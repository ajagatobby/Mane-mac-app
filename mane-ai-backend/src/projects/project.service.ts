import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService, ProjectSearchResult, SkeletonSearchResult } from '../lancedb';
import { ManifestScannerService, ProjectManifest } from './services/manifest-scanner.service';
import { SkeletonExtractorService, CodeSkeleton, DEFAULT_IGNORE_PATTERNS } from './services/skeleton-extractor.service';

/**
 * Project indexing options
 */
export interface IndexProjectOptions {
  /** Maximum directory depth to scan */
  maxDepth?: number;
  /** Maximum number of files to index */
  maxFiles?: number;
  /** Skip skeleton extraction (faster indexing) */
  skipSkeletons?: boolean;
  /** Custom directories to ignore */
  customIgnoreDirs?: string[];
  /** Custom files to ignore */
  customIgnoreFiles?: string[];
  /** Custom file extensions to ignore */
  customIgnoreExtensions?: string[];
  /** Include test files in indexing */
  includeTests?: boolean;
}

/**
 * Full project details including skeletons
 */
export interface ProjectDetails extends ProjectSearchResult {
  manifest: Record<string, unknown>;
  skeletonCount: number;
}

/**
 * Search results combining projects and code
 */
export interface UnifiedSearchResult {
  projects: ProjectSearchResult[];
  skeletons: Array<SkeletonSearchResult & { projectName?: string }>;
}

/**
 * ProjectService
 * Orchestrates project indexing, searching, and management
 */
@Injectable()
export class ProjectService {
  private readonly logger = new Logger(ProjectService.name);

  constructor(
    private readonly lanceDBService: LanceDBService,
    private readonly manifestScanner: ManifestScannerService,
    private readonly skeletonExtractor: SkeletonExtractorService,
  ) {}

  /**
   * Index a project directory
   */
  async indexProject(
    projectPath: string,
    options: IndexProjectOptions = {},
  ): Promise<ProjectDetails> {
    const { 
      maxDepth = 5, 
      maxFiles = 500, 
      skipSkeletons = false,
      customIgnoreDirs,
      customIgnoreFiles,
      customIgnoreExtensions,
      includeTests = false,
    } = options;

    this.logger.log(`Indexing project: ${projectPath}`);

    // Check if project already exists
    const existing = await this.lanceDBService.getProjectByPath(projectPath);
    if (existing) {
      this.logger.log(`Project already indexed, re-indexing: ${projectPath}`);
      await this.deleteProject(existing.id);
    }

    // Step 1: Scan manifest files
    this.logger.log('Scanning manifest files...');
    const manifest = await this.manifestScanner.scanProject(projectPath);

    // Step 2: Get file count
    const fileCount = await this.manifestScanner.getCodeFileCount(projectPath, maxDepth);
    this.logger.log(`Found ${fileCount} code files`);

    // Step 3: Add project to database
    const projectId = await this.lanceDBService.addProject(
      manifest.name,
      projectPath,
      manifest.description,
      manifest.techStack,
      manifest.tags,
      {
        language: manifest.language,
        framework: manifest.framework,
        version: manifest.version,
        dependencies: manifest.dependencies.slice(0, 50), // Limit stored deps
        scripts: manifest.scripts,
      },
      fileCount,
    );

    this.logger.log(`Project added with ID: ${projectId}`);

    // Step 4: Extract and store code skeletons
    let skeletonCount = 0;
    if (!skipSkeletons && fileCount > 0) {
      this.logger.log('Extracting code skeletons...');
      const skeletons = await this.skeletonExtractor.extractProjectSkeletons(
        projectPath,
        maxDepth,
        maxFiles,
        {
          customIgnoreDirs,
          customIgnoreFiles,
          customIgnoreExtensions,
          includeTests,
        },
      );

      if (skeletons.length > 0) {
        // Batch add skeletons
        const skeletonRecords = skeletons.map((s) => ({
          projectId,
          filePath: s.filePath,
          content: s.content,
          language: s.language,
        }));

        await this.lanceDBService.addCodeSkeletonsBatch(skeletonRecords);
        skeletonCount = skeletons.length;
        this.logger.log(`Added ${skeletonCount} code skeletons`);
      }
    }

    // Return project details
    const project = await this.lanceDBService.getProject(projectId);
    if (!project) {
      throw new Error('Failed to retrieve indexed project');
    }

    return {
      ...project,
      manifest: {
        language: manifest.language,
        framework: manifest.framework,
        version: manifest.version,
        dependencies: manifest.dependencies.slice(0, 20),
      },
      skeletonCount,
    };
  }

  /**
   * Re-index an existing project
   */
  async reindexProject(
    projectId: string,
    options: IndexProjectOptions = {},
  ): Promise<ProjectDetails> {
    const project = await this.lanceDBService.getProject(projectId);
    if (!project) {
      throw new Error(`Project not found: ${projectId}`);
    }

    return this.indexProject(project.path, options);
  }

  /**
   * Get all indexed projects
   */
  async listProjects(): Promise<ProjectSearchResult[]> {
    return this.lanceDBService.getAllProjects();
  }

  /**
   * Get project by ID
   */
  async getProject(projectId: string): Promise<ProjectDetails | null> {
    const project = await this.lanceDBService.getProject(projectId);
    if (!project) {
      return null;
    }

    const skeletons = await this.lanceDBService.getSkeletonsByProject(projectId);

    return {
      ...project,
      manifest: {},
      skeletonCount: skeletons.length,
    };
  }

  /**
   * Search projects by query
   */
  async searchProjects(
    query: string,
    limit: number = 10,
  ): Promise<ProjectSearchResult[]> {
    return this.lanceDBService.searchProjects(query, limit);
  }

  /**
   * Search code skeletons
   */
  async searchCode(
    query: string,
    limit: number = 10,
    projectId?: string,
  ): Promise<SkeletonSearchResult[]> {
    return this.lanceDBService.searchSkeletons(query, limit, projectId);
  }

  /**
   * Unified search across projects and code
   */
  async unifiedSearch(
    query: string,
    options: {
      projectLimit?: number;
      codeLimit?: number;
      projectId?: string;
    } = {},
  ): Promise<UnifiedSearchResult> {
    const { projectLimit = 5, codeLimit = 10, projectId } = options;

    // Search projects
    const projects = projectId
      ? []
      : await this.searchProjects(query, projectLimit);

    // Search code skeletons
    const skeletons = await this.searchCode(query, codeLimit, projectId);

    // Enrich skeletons with project names
    const enrichedSkeletons = await Promise.all(
      skeletons.map(async (skeleton) => {
        const project = await this.lanceDBService.getProject(skeleton.projectId);
        return {
          ...skeleton,
          projectName: project?.name,
        };
      }),
    );

    return {
      projects,
      skeletons: enrichedSkeletons,
    };
  }

  /**
   * Get skeletons for a project
   */
  async getProjectSkeletons(projectId: string): Promise<SkeletonSearchResult[]> {
    return this.lanceDBService.getSkeletonsByProject(projectId);
  }

  /**
   * Delete a project and its skeletons
   */
  async deleteProject(projectId: string): Promise<void> {
    this.logger.log(`Deleting project: ${projectId}`);
    await this.lanceDBService.deleteProject(projectId);
  }

  /**
   * Get project statistics
   */
  async getStats(): Promise<{
    projectCount: number;
    totalFileCount: number;
    languages: Record<string, number>;
    techStack: Record<string, number>;
  }> {
    const projects = await this.listProjects();

    const languages: Record<string, number> = {};
    const techStack: Record<string, number> = {};
    let totalFileCount = 0;

    for (const project of projects) {
      totalFileCount += project.fileCount;

      for (const tech of project.techStack) {
        techStack[tech] = (techStack[tech] || 0) + 1;
      }
    }

    return {
      projectCount: projects.length,
      totalFileCount,
      languages,
      techStack,
    };
  }

  /**
   * Get the default ignore patterns
   */
  getDefaultIgnorePatterns(): typeof DEFAULT_IGNORE_PATTERNS {
    return DEFAULT_IGNORE_PATTERNS;
  }
}
