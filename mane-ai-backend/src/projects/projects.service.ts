import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService } from '../lancedb';
import { ConfigService } from '../config';
import { CodebaseAnalyzerService } from './codebase-analyzer.service';
import {
  IndexProjectDto,
  CodebaseAnalysis,
  ProjectResponseDto,
  ProjectListResponseDto,
  IndexProjectResponseDto,
} from './dto/project.dto';
import * as path from 'path';
import { ChatOllama } from '@langchain/ollama';
import { HumanMessage, SystemMessage } from '@langchain/core/messages';

@Injectable()
export class ProjectsService {
  private readonly logger = new Logger(ProjectsService.name);
  private chatModel: ChatOllama | null = null;

  constructor(
    private readonly lanceDBService: LanceDBService,
    private readonly configService: ConfigService,
    private readonly codebaseAnalyzer: CodebaseAnalyzerService,
  ) {
    this.initializeChatModel();
  }

  private async initializeChatModel(): Promise<void> {
    const ollamaUrl = this.configService.getOllamaUrl();
    const ollamaModel = this.configService.getOllamaModel();

    this.chatModel = new ChatOllama({
      baseUrl: ollamaUrl,
      model: ollamaModel,
      temperature: 0.3, // Lower temperature for more factual analysis
    });
  }

  /**
   * Index a folder as a project
   * @param dto.quickMode - If true, skip LLM analysis for faster indexing (default: true)
   */
  async indexProject(dto: IndexProjectDto): Promise<IndexProjectResponseDto> {
    const startTime = Date.now();
    const quickMode = dto.quickMode !== false; // Default to quick mode
    
    try {
      this.logger.log(`Indexing project at: ${dto.folderPath} (quickMode: ${quickMode})`);

      // Step 1: Detect if it's a codebase
      const detection = this.codebaseAnalyzer.detectCodebase(dto.folderPath);
      if (!detection) {
        return {
          success: false,
          message: 'No codebase detected in the specified folder. Looking for manifest files like package.json, Cargo.toml, etc.',
        };
      }

      // Step 2: Check if project already exists
      const existingProject = await this.lanceDBService.getProjectByPath(dto.folderPath);
      if (existingProject) {
        this.logger.log(`Re-indexing existing project: ${existingProject.id}`);
        await this.lanceDBService.deleteProject(existingProject.id);
      }

      // Step 3: Parse manifest
      const manifest = this.codebaseAnalyzer.parseManifest(dto.folderPath, detection);

      // Step 4: Scan structure (limit depth for large projects)
      this.logger.log('Scanning codebase structure...');
      const structure = this.codebaseAnalyzer.scanStructure(dto.folderPath, 4); // Reduced depth

      // Step 5: Infer tech stack (fast operation)
      const techStack = this.codebaseAnalyzer.inferTechStack(detection, manifest, structure);

      // Step 6: Generate tags (fast operation)
      const tags = this.codebaseAnalyzer.generateTags(detection, manifest, structure, techStack);

      // Step 7: Determine project name
      const projectName = dto.name || manifest?.name || path.basename(dto.folderPath);

      // Step 8: Generate knowledge document
      let knowledgeDocument: string;
      
      if (quickMode) {
        // Fast: Use template-based document (no LLM)
        this.logger.log('Generating knowledge document (quick mode)...');
        knowledgeDocument = this.generateBasicKnowledgeDocument(
          projectName,
          detection.type,
          manifest,
          structure,
          techStack,
        );
      } else {
        // Slow: Use LLM analysis
        this.logger.log('Generating knowledge document with LLM (this may take a moment)...');
        const samples = this.codebaseAnalyzer.readSampleFiles(dto.folderPath, structure);
        knowledgeDocument = await this.generateKnowledgeDocument(
          projectName,
          detection.type,
          manifest,
          structure,
          techStack,
          samples,
        );
      }

      // Step 9: Store in LanceDB
      this.logger.log('Storing project in database...');
      const projectId = await this.lanceDBService.addProject(
        projectName,
        dto.folderPath,
        knowledgeDocument,
        techStack,
        tags,
        manifest || {},
        structure.totalFiles,
      );

      // Also store the knowledge document as a searchable text document
      await this.lanceDBService.addTextDocument(
        knowledgeDocument,
        dto.folderPath,
        {
          mediaType: 'text',
          documentType: 'knowledge',
          projectId,
          projectName,
        },
      );

      const elapsed = Date.now() - startTime;
      const project: ProjectResponseDto = {
        id: projectId,
        name: projectName,
        path: dto.folderPath,
        description: knowledgeDocument,
        techStack,
        tags,
        fileCount: structure.totalFiles,
        knowledgeDocument,
        createdAt: new Date().toISOString(),
      };

      this.logger.log(`Project indexed successfully in ${elapsed}ms: ${projectId}`);

      return {
        success: true,
        message: `Project "${projectName}" indexed successfully with ${structure.totalFiles} files (${elapsed}ms)`,
        project,
      };
    } catch (error: any) {
      this.logger.error(`Failed to index project: ${error.message}`);
      return {
        success: false,
        message: `Failed to index project: ${error.message}`,
      };
    }
  }

  /**
   * Enhanced indexing with LLM analysis (slower but more detailed)
   */
  async indexProjectWithAnalysis(dto: IndexProjectDto): Promise<IndexProjectResponseDto> {
    return this.indexProject({ ...dto, quickMode: false });
  }

  /**
   * Generate knowledge document using LLM
   */
  private async generateKnowledgeDocument(
    projectName: string,
    projectType: string,
    manifest: any,
    structure: any,
    techStack: string[],
    samples: Record<string, string>,
  ): Promise<string> {
    if (!this.chatModel) {
      // Fallback to basic template if no LLM available
      return this.generateBasicKnowledgeDocument(
        projectName,
        projectType,
        manifest,
        structure,
        techStack,
      );
    }

    try {
      const prompt = this.buildAnalysisPrompt(
        projectName,
        projectType,
        manifest,
        structure,
        techStack,
        samples,
      );

      const systemMessage = new SystemMessage(`You are an expert software architect analyzing a codebase.
Your task is to generate a concise knowledge document about the project.
Focus on:
1. What the project does (purpose)
2. Architecture and design patterns
3. Key components and their roles
4. Technology stack and dependencies
5. Project structure insights

Be factual and concise. Use markdown formatting.
Do NOT make up information - only report what you can infer from the provided context.`);

      const humanMessage = new HumanMessage(prompt);

      const response = await this.chatModel.invoke([systemMessage, humanMessage]);
      const content = typeof response.content === 'string' 
        ? response.content 
        : JSON.stringify(response.content);

      return content;
    } catch (error: any) {
      this.logger.warn(`LLM analysis failed, using basic template: ${error.message}`);
      return this.generateBasicKnowledgeDocument(
        projectName,
        projectType,
        manifest,
        structure,
        techStack,
      );
    }
  }

  private buildAnalysisPrompt(
    projectName: string,
    projectType: string,
    manifest: any,
    structure: any,
    techStack: string[],
    samples: Record<string, string>,
  ): string {
    let prompt = `Analyze this ${projectType} project named "${projectName}" and generate a knowledge document.\n\n`;

    // Add structure info
    prompt += `## Project Structure\n`;
    prompt += `- Total files: ${structure.totalFiles}\n`;
    prompt += `- Total directories: ${structure.totalDirectories}\n`;
    prompt += `- Has tests: ${structure.hasTests}\n`;
    prompt += `- Has documentation: ${structure.hasDocumentation}\n`;
    
    if (structure.keyDirectories.length > 0) {
      prompt += `- Key directories: ${structure.keyDirectories.join(', ')}\n`;
    }
    
    if (structure.entryPoints.length > 0) {
      prompt += `- Entry points: ${structure.entryPoints.join(', ')}\n`;
    }

    // Add file distribution
    prompt += `\n## File Distribution\n`;
    const sortedExtensions = Object.entries(structure.filesByExtension)
      .sort((a, b) => (b[1] as number) - (a[1] as number))
      .slice(0, 10);
    for (const [ext, count] of sortedExtensions) {
      prompt += `- ${ext}: ${count} files\n`;
    }

    // Add tech stack
    prompt += `\n## Detected Tech Stack\n`;
    prompt += techStack.join(', ') + '\n';

    // Add manifest info
    if (manifest) {
      prompt += `\n## Manifest Information\n`;
      if (manifest.name) prompt += `- Name: ${manifest.name}\n`;
      if (manifest.version) prompt += `- Version: ${manifest.version}\n`;
      if (manifest.description) prompt += `- Description: ${manifest.description}\n`;
      
      if (manifest.dependencies) {
        const depCount = Object.keys(manifest.dependencies).length;
        const topDeps = Object.keys(manifest.dependencies).slice(0, 10);
        prompt += `- Dependencies (${depCount} total): ${topDeps.join(', ')}${depCount > 10 ? '...' : ''}\n`;
      }
      
      if (manifest.devDependencies) {
        const devDepCount = Object.keys(manifest.devDependencies).length;
        const topDevDeps = Object.keys(manifest.devDependencies).slice(0, 5);
        prompt += `- Dev dependencies (${devDepCount} total): ${topDevDeps.join(', ')}${devDepCount > 5 ? '...' : ''}\n`;
      }
      
      if (manifest.scripts) {
        prompt += `- Available scripts: ${Object.keys(manifest.scripts).join(', ')}\n`;
      }
    }

    // Add sample file contents
    if (Object.keys(samples).length > 0) {
      prompt += `\n## Sample Files\n`;
      for (const [filename, content] of Object.entries(samples)) {
        prompt += `\n### ${filename}\n\`\`\`\n${content.substring(0, 2000)}\n\`\`\`\n`;
      }
    }

    prompt += `\n---\nGenerate a comprehensive knowledge document in markdown format.`;

    return prompt;
  }

  private generateBasicKnowledgeDocument(
    projectName: string,
    projectType: string,
    manifest: any,
    structure: any,
    techStack: string[],
  ): string {
    let doc = `# ${projectName}\n\n`;
    
    doc += `## Overview\n`;
    doc += `A ${projectType} project`;
    if (manifest?.description) {
      doc += `: ${manifest.description}`;
    }
    doc += `.\n\n`;

    doc += `## Tech Stack\n`;
    doc += techStack.map(t => `- ${t}`).join('\n') + '\n\n';

    doc += `## Project Structure\n`;
    doc += `- **Total Files**: ${structure.totalFiles}\n`;
    doc += `- **Total Directories**: ${structure.totalDirectories}\n`;
    doc += `- **Has Tests**: ${structure.hasTests ? 'Yes' : 'No'}\n`;
    doc += `- **Has Documentation**: ${structure.hasDocumentation ? 'Yes' : 'No'}\n\n`;

    if (structure.keyDirectories.length > 0) {
      doc += `## Key Directories\n`;
      doc += structure.keyDirectories.map((d: string) => `- ${d}`).join('\n') + '\n\n';
    }

    if (structure.entryPoints.length > 0) {
      doc += `## Entry Points\n`;
      doc += structure.entryPoints.map((e: string) => `- ${e}`).join('\n') + '\n\n';
    }

    // File distribution
    doc += `## File Distribution\n`;
    const sortedExtensions = Object.entries(structure.filesByExtension)
      .sort((a, b) => (b[1] as number) - (a[1] as number))
      .slice(0, 10);
    for (const [ext, count] of sortedExtensions) {
      doc += `- ${ext}: ${count} files\n`;
    }

    // Dependencies summary
    if (manifest?.dependencies) {
      const depCount = Object.keys(manifest.dependencies).length;
      doc += `\n## Dependencies\n`;
      doc += `Total: ${depCount} production dependencies\n`;
      if (manifest.devDependencies) {
        const devDepCount = Object.keys(manifest.devDependencies).length;
        doc += `Dev: ${devDepCount} development dependencies\n`;
      }
    }

    return doc;
  }

  /**
   * List all projects
   */
  async listProjects(): Promise<ProjectListResponseDto> {
    const projects = await this.lanceDBService.getAllProjects();
    const total = await this.lanceDBService.getProjectCount();

    return {
      projects: projects.map(p => ({
        id: p.id,
        name: p.name,
        path: p.path,
        description: p.description,
        techStack: p.techStack,
        tags: p.tags,
        fileCount: p.fileCount,
        createdAt: p.createdAt,
      })),
      total,
    };
  }

  /**
   * Get project by ID
   */
  async getProject(id: string): Promise<ProjectResponseDto | null> {
    const project = await this.lanceDBService.getProject(id);
    if (!project) {
      return null;
    }

    return {
      id: project.id,
      name: project.name,
      path: project.path,
      description: project.description,
      techStack: project.techStack,
      tags: project.tags,
      fileCount: project.fileCount,
      knowledgeDocument: project.description,
      createdAt: project.createdAt,
    };
  }

  /**
   * Delete a project
   */
  async deleteProject(id: string): Promise<{ success: boolean; message: string }> {
    try {
      await this.lanceDBService.deleteProject(id);
      return {
        success: true,
        message: `Project ${id} deleted successfully`,
      };
    } catch (error: any) {
      return {
        success: false,
        message: `Failed to delete project: ${error.message}`,
      };
    }
  }

  /**
   * Search projects
   */
  async searchProjects(query: string, limit: number = 10): Promise<ProjectResponseDto[]> {
    const results = await this.lanceDBService.searchProjects(query, limit);
    
    return results.map(p => ({
      id: p.id,
      name: p.name,
      path: p.path,
      description: p.description,
      techStack: p.techStack,
      tags: p.tags,
      fileCount: p.fileCount,
      createdAt: p.createdAt,
    }));
  }

  /**
   * Detect if a folder contains a codebase
   */
  detectCodebase(folderPath: string): { isCodebase: boolean; type?: string; techStack?: string[] } {
    const detection = this.codebaseAnalyzer.detectCodebase(folderPath);
    
    if (!detection) {
      return { isCodebase: false };
    }

    return {
      isCodebase: true,
      type: detection.type,
      techStack: detection.techStack,
    };
  }
}
