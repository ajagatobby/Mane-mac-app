import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import { ConfigService } from '../config';
import * as lancedb from '@lancedb/lancedb';
import * as fs from 'fs';
import * as path from 'path';

// Types for LanceDB
interface TextDocumentRecord {
  id: string;
  content: string;
  filePath: string;
  fileName: string;
  mediaType: string;
  metadata: string; // JSON string
  vector: number[];
  createdAt: string;
  [key: string]: unknown;
}

// Project record for codebase indexing
export interface ProjectRecord {
  id: string;
  name: string;
  path: string;
  description: string;
  techStack: string; // JSON array string
  tags: string; // JSON array string
  manifest: string; // JSON string
  fileCount: number;
  vector: number[];
  createdAt: string;
  [key: string]: unknown;
}

// Code skeleton record for function/class signatures
export interface CodeSkeletonRecord {
  id: string;
  projectId: string;
  filePath: string;
  fileName: string;
  content: string; // Extracted signatures
  language: string;
  vector: number[];
  createdAt: string;
  [key: string]: unknown;
}

export interface SearchResult {
  id: string;
  content: string;
  filePath: string;
  fileName: string;
  mediaType: string;
  thumbnailPath?: string;
  metadata: Record<string, unknown>;
  score: number;
}

export interface ProjectSearchResult {
  id: string;
  name: string;
  path: string;
  description: string;
  techStack: string[];
  tags: string[];
  fileCount: number;
  createdAt: string;
  score: number;
}

export interface SkeletonSearchResult {
  id: string;
  projectId: string;
  filePath: string;
  fileName: string;
  content: string;
  language: string;
  score: number;
}

export type MediaType = 'text' | 'image' | 'audio';

@Injectable()
export class LanceDBService implements OnModuleInit {
  private readonly logger = new Logger(LanceDBService.name);
  private db: lancedb.Connection | null = null;
  private textTable: lancedb.Table | null = null;
  private projectsTable: lancedb.Table | null = null;
  private skeletonsTable: lancedb.Table | null = null;
  private embedder: any = null;

  private readonly textTableName = 'documents_text';
  private readonly projectsTableName = 'projects';
  private readonly skeletonsTableName = 'code_skeletons';

  // Embedding dimensions
  readonly TEXT_DIMENSION = 384; // all-MiniLM-L6-v2

  constructor(private readonly configService: ConfigService) {}

  async onModuleInit() {
    await this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      // Initialize the embedding model for text (backward compatibility)
      this.logger.log('Loading embedding model (all-MiniLM-L6-v2)...');
      const { pipeline } = await import('@huggingface/transformers');
      this.embedder = await pipeline(
        'feature-extraction',
        'Xenova/all-MiniLM-L6-v2',
      );
      this.logger.log('Embedding model loaded successfully');

      // Ensure the database directory exists
      const dbPath = this.configService.getDbPath();
      if (!fs.existsSync(dbPath)) {
        fs.mkdirSync(dbPath, { recursive: true });
        this.logger.log(`Created database directory: ${dbPath}`);
      }

      // Connect to LanceDB
      this.logger.log(`Connecting to LanceDB at: ${dbPath}`);
      this.db = await lancedb.connect(dbPath);

      // Initialize tables
      await this.initializeTables();

      this.logger.log('LanceDB initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize LanceDB:', error);
      throw error;
    }
  }

  private async initializeTables(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const tableNames = await this.db.tableNames();

    // Initialize text table
    if (tableNames.includes(this.textTableName)) {
      this.textTable = await this.db.openTable(this.textTableName);
      this.logger.log(`Opened existing table: ${this.textTableName}`);
    } else {
      await this.createTextTable();
    }

    // Initialize projects table
    if (tableNames.includes(this.projectsTableName)) {
      this.projectsTable = await this.db.openTable(this.projectsTableName);
      this.logger.log(`Opened existing table: ${this.projectsTableName}`);
    } else {
      await this.createProjectsTable();
    }

    // Initialize code skeletons table
    if (tableNames.includes(this.skeletonsTableName)) {
      this.skeletonsTable = await this.db.openTable(this.skeletonsTableName);
      this.logger.log(`Opened existing table: ${this.skeletonsTableName}`);
    } else {
      await this.createSkeletonsTable();
    }
  }

  private async createTextTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sampleRecord: TextDocumentRecord = {
      id: 'init',
      content: '',
      filePath: '',
      fileName: '',
      mediaType: 'text',
      metadata: '{}',
      vector: new Array(this.TEXT_DIMENSION).fill(0),
      createdAt: new Date().toISOString(),
    };

    this.textTable = await this.db.createTable(this.textTableName, [
      sampleRecord,
    ]);
    await this.textTable.delete('id = "init"');
    this.logger.log(`Created new table: ${this.textTableName}`);
  }

  private async createProjectsTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sampleRecord: ProjectRecord = {
      id: 'init',
      name: '',
      path: '',
      description: '',
      techStack: '[]',
      tags: '[]',
      manifest: '{}',
      fileCount: 0,
      vector: new Array(this.TEXT_DIMENSION).fill(0),
      createdAt: new Date().toISOString(),
    };

    this.projectsTable = await this.db.createTable(this.projectsTableName, [
      sampleRecord,
    ]);
    await this.projectsTable.delete('id = "init"');
    this.logger.log(`Created new table: ${this.projectsTableName}`);
  }

  private async createSkeletonsTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sampleRecord: CodeSkeletonRecord = {
      id: 'init',
      projectId: '',
      filePath: '',
      fileName: '',
      content: '',
      language: '',
      vector: new Array(this.TEXT_DIMENSION).fill(0),
      createdAt: new Date().toISOString(),
    };

    this.skeletonsTable = await this.db.createTable(this.skeletonsTableName, [
      sampleRecord,
    ]);
    await this.skeletonsTable.delete('id = "init"');
    this.logger.log(`Created new table: ${this.skeletonsTableName}`);
  }

  /**
   * Generate text embedding (for backward compatibility)
   */
  async generateEmbedding(text: string): Promise<number[]> {
    if (!this.embedder) {
      throw new Error('Embedding model not initialized');
    }

    const output = await this.embedder(text, {
      pooling: 'mean',
      normalize: true,
    });

    return Array.from(output.data);
  }

  /**
   * Add a text document (also used for audio transcripts)
   */
  async addTextDocument(
    content: string,
    filePath: string,
    metadata: Record<string, unknown> = {},
    vector?: number[],
  ): Promise<string> {
    if (!this.textTable) {
      throw new Error('Text table not initialized');
    }

    // Validate pre-computed vector dimension if provided
    if (vector && vector.length !== this.TEXT_DIMENSION) {
      throw new Error(
        `Vector dimension mismatch: expected ${this.TEXT_DIMENSION}, got ${vector.length}. ` +
        `Text table requires MiniLM embeddings (384-dim).`
      );
    }

    const id = this.generateId();
    const fileName = path.basename(filePath);

    // Extract mediaType from metadata (for audio) or default to 'text'
    const mediaType = (metadata.mediaType as string) || 'text';
    
    // Remove mediaType from metadata to avoid duplication
    const { mediaType: _, ...cleanMetadata } = metadata;

    this.logger.log(`Adding ${mediaType} document: ${fileName}`);
    const docVector = vector || (await this.generateEmbedding(content));

    const record: TextDocumentRecord = {
      id,
      content,
      filePath,
      fileName,
      mediaType,
      metadata: JSON.stringify(cleanMetadata),
      vector: docVector,
      createdAt: new Date().toISOString(),
    };

    await this.textTable.add([record]);
    this.logger.log(`${mediaType.charAt(0).toUpperCase() + mediaType.slice(1)} document added: ${id} (${fileName})`);

    return id;
  }

  /**
   * Legacy method for backward compatibility
   */
  async addDocument(
    content: string,
    filePath: string,
    metadata: Record<string, unknown> = {},
  ): Promise<string> {
    return this.addTextDocument(content, filePath, metadata);
  }

  /**
   * Search text documents
   */
  async searchText(query: string, limit: number = 5): Promise<SearchResult[]> {
    if (!this.textTable) {
      throw new Error('Text table not initialized');
    }

    const queryVector = await this.generateEmbedding(query);
    const results = await this.textTable
      .vectorSearch(queryVector)
      .limit(limit)
      .toArray();

    return results.map((row: any) => ({
      id: row.id,
      content: row.content,
      filePath: row.filePath,
      fileName: row.fileName,
      mediaType: row.mediaType || 'text',
      metadata: this.parseMetadata(row.metadata),
      score: row._distance ? 1 - row._distance : 0,
    }));
  }

  /**
   * Legacy search method (text only)
   */
  async search(query: string, limit: number = 5): Promise<SearchResult[]> {
    return this.searchText(query, limit);
  }

  /**
   * Hybrid search across text documents
   * Combines vector search (semantic) with keyword matching (exact)
   */
  async hybridSearch(query: string, limit: number = 5): Promise<SearchResult[]> {
    if (!this.textTable) {
      throw new Error('Text table not initialized');
    }

    // Run vector search
    const vectorResults = await this.searchText(query, limit * 2);

    // Extract keywords for boosting exact matches
    const keywords = query
      .toLowerCase()
      .split(/\s+/)
      .filter((k) => k.length > 2);

    // Score results with keyword boost
    const scoredResults = vectorResults.map((result) => {
      let keywordScore = 0;
      const contentLower = result.content.toLowerCase();
      const fileNameLower = result.fileName.toLowerCase();

      for (const keyword of keywords) {
        // Exact keyword matches in content
        if (contentLower.includes(keyword)) {
          keywordScore += 0.1;
        }
        // Filename matches are more valuable
        if (fileNameLower.includes(keyword)) {
          keywordScore += 0.2;
        }
        // Boost for exact word boundaries
        const wordBoundaryRegex = new RegExp(`\\b${keyword}\\b`, 'i');
        if (wordBoundaryRegex.test(result.content)) {
          keywordScore += 0.15;
        }
      }

      return {
        ...result,
        score: Math.min(result.score + keywordScore, 1.0), // Cap at 1.0
      };
    });

    return scoredResults.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  /**
   * Delete a document by ID
   */
  async deleteDocument(id: string): Promise<void> {
    if (this.textTable) {
      try {
        await this.textTable.delete(`id = "${id}"`);
        this.logger.log(`Document deleted: ${id}`);
      } catch (e) {
        this.logger.warn(`Failed to delete document ${id}: ${e}`);
      }
    }
  }

  /**
   * Get total document count
   */
  async getDocumentCount(): Promise<number> {
    if (this.textTable) {
      return await this.textTable.countRows();
    }
    return 0;
  }

  /**
   * Get all documents
   */
  async getAllDocuments(): Promise<SearchResult[]> {
    if (!this.textTable) {
      return [];
    }

    const textDocs = await this.textTable.query().limit(1000).toArray();
    return textDocs.map((row: any) => ({
      id: row.id,
      content: row.content,
      filePath: row.filePath,
      fileName: row.fileName,
      mediaType: row.mediaType || 'text',
      metadata: this.parseMetadata(row.metadata),
      score: 1,
    }));
  }

  // ==================== PROJECT METHODS ====================

  /**
   * Add a new project
   */
  async addProject(
    name: string,
    projectPath: string,
    description: string,
    techStack: string[],
    tags: string[],
    manifest: Record<string, unknown>,
    fileCount: number,
  ): Promise<string> {
    if (!this.projectsTable) {
      throw new Error('Projects table not initialized');
    }

    const id = this.generateProjectId();
    
    // Generate embedding from description + tech stack + tags
    const embeddingText = `${name} ${description} ${techStack.join(' ')} ${tags.join(' ')}`;
    const vector = await this.generateEmbedding(embeddingText);

    const record: ProjectRecord = {
      id,
      name,
      path: projectPath,
      description,
      techStack: JSON.stringify(techStack),
      tags: JSON.stringify(tags),
      manifest: JSON.stringify(manifest),
      fileCount,
      vector,
      createdAt: new Date().toISOString(),
    };

    await this.projectsTable.add([record]);
    this.logger.log(`Project added: ${id} (${name})`);

    return id;
  }

  /**
   * Get all projects
   */
  async getAllProjects(): Promise<ProjectSearchResult[]> {
    if (!this.projectsTable) {
      return [];
    }

    const projects = await this.projectsTable.query().limit(1000).toArray();
    return projects.map((row: any) => ({
      id: row.id,
      name: row.name,
      path: row.path,
      description: row.description,
      techStack: this.parseJsonArray(row.techStack),
      tags: this.parseJsonArray(row.tags),
      fileCount: row.fileCount,
      createdAt: row.createdAt,
      score: 1,
    }));
  }

  /**
   * Get project by ID
   */
  async getProject(id: string): Promise<ProjectSearchResult | null> {
    if (!this.projectsTable) {
      return null;
    }

    const results = await this.projectsTable
      .query()
      .where(`id = "${id}"`)
      .limit(1)
      .toArray();

    if (results.length === 0) {
      return null;
    }

    const row = results[0] as any;
    return {
      id: row.id,
      name: row.name,
      path: row.path,
      description: row.description,
      techStack: this.parseJsonArray(row.techStack),
      tags: this.parseJsonArray(row.tags),
      fileCount: row.fileCount,
      createdAt: row.createdAt,
      score: 1,
    };
  }

  /**
   * Get project by path
   */
  async getProjectByPath(projectPath: string): Promise<ProjectSearchResult | null> {
    if (!this.projectsTable) {
      return null;
    }

    const results = await this.projectsTable
      .query()
      .where(`path = "${projectPath}"`)
      .limit(1)
      .toArray();

    if (results.length === 0) {
      return null;
    }

    const row = results[0] as any;
    return {
      id: row.id,
      name: row.name,
      path: row.path,
      description: row.description,
      techStack: this.parseJsonArray(row.techStack),
      tags: this.parseJsonArray(row.tags),
      fileCount: row.fileCount,
      createdAt: row.createdAt,
      score: 1,
    };
  }

  /**
   * Search projects by query (hybrid search)
   */
  async searchProjects(query: string, limit: number = 10): Promise<ProjectSearchResult[]> {
    if (!this.projectsTable) {
      return [];
    }

    const queryVector = await this.generateEmbedding(query);
    const results = await this.projectsTable
      .vectorSearch(queryVector)
      .limit(limit * 2)
      .toArray();

    // Extract keywords for boosting
    const keywords = query.toLowerCase().split(/\s+/).filter((k) => k.length > 2);

    const scoredResults = results.map((row: any) => {
      let keywordScore = 0;
      const nameLower = row.name.toLowerCase();
      const descLower = row.description.toLowerCase();
      const techStack = this.parseJsonArray(row.techStack);
      const tags = this.parseJsonArray(row.tags);

      for (const keyword of keywords) {
        // Name matches are most valuable
        if (nameLower.includes(keyword)) keywordScore += 0.3;
        // Tech stack exact matches
        if (techStack.some((t: string) => t.toLowerCase() === keyword)) keywordScore += 0.4;
        // Tag matches
        if (tags.some((t: string) => t.toLowerCase().includes(keyword))) keywordScore += 0.3;
        // Description matches
        if (descLower.includes(keyword)) keywordScore += 0.1;
      }

      const baseScore = row._distance ? 1 - row._distance : 0;
      return {
        id: row.id,
        name: row.name,
        path: row.path,
        description: row.description,
        techStack,
        tags,
        fileCount: row.fileCount,
        createdAt: row.createdAt,
        score: Math.min(baseScore + keywordScore, 1.0),
      };
    });

    return scoredResults.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  /**
   * Delete a project and its skeletons
   */
  async deleteProject(id: string): Promise<void> {
    if (this.projectsTable) {
      try {
        await this.projectsTable.delete(`id = "${id}"`);
        this.logger.log(`Project deleted: ${id}`);
      } catch (e) {
        this.logger.warn(`Failed to delete project ${id}: ${e}`);
      }
    }

    // Also delete associated skeletons
    await this.deleteSkeletonsByProject(id);
  }

  // ==================== CODE SKELETON METHODS ====================

  /**
   * Add code skeletons for a file
   */
  async addCodeSkeleton(
    projectId: string,
    filePath: string,
    content: string,
    language: string,
  ): Promise<string> {
    if (!this.skeletonsTable) {
      throw new Error('Skeletons table not initialized');
    }

    const id = this.generateSkeletonId();
    const fileName = path.basename(filePath);
    const vector = await this.generateEmbedding(content);

    const record: CodeSkeletonRecord = {
      id,
      projectId,
      filePath,
      fileName,
      content,
      language,
      vector,
      createdAt: new Date().toISOString(),
    };

    await this.skeletonsTable.add([record]);
    this.logger.log(`Code skeleton added: ${id} (${fileName})`);

    return id;
  }

  /**
   * Add multiple code skeletons in batch
   */
  async addCodeSkeletonsBatch(
    skeletons: Array<{
      projectId: string;
      filePath: string;
      content: string;
      language: string;
    }>,
  ): Promise<string[]> {
    if (!this.skeletonsTable || skeletons.length === 0) {
      return [];
    }

    const records: CodeSkeletonRecord[] = [];
    const ids: string[] = [];

    for (const skeleton of skeletons) {
      const id = this.generateSkeletonId();
      const fileName = path.basename(skeleton.filePath);
      const vector = await this.generateEmbedding(skeleton.content);

      records.push({
        id,
        projectId: skeleton.projectId,
        filePath: skeleton.filePath,
        fileName,
        content: skeleton.content,
        language: skeleton.language,
        vector,
        createdAt: new Date().toISOString(),
      });
      ids.push(id);
    }

    await this.skeletonsTable.add(records);
    this.logger.log(`Added ${records.length} code skeletons in batch`);

    return ids;
  }

  /**
   * Search code skeletons
   */
  async searchSkeletons(
    query: string,
    limit: number = 10,
    projectId?: string,
  ): Promise<SkeletonSearchResult[]> {
    if (!this.skeletonsTable) {
      return [];
    }

    const queryVector = await this.generateEmbedding(query);
    let searchQuery = this.skeletonsTable.vectorSearch(queryVector);

    // Note: LanceDB doesn't support WHERE with vectorSearch directly
    // We'll filter after the search
    const results = await searchQuery.limit(limit * 3).toArray();

    let filteredResults = results;
    if (projectId) {
      filteredResults = results.filter((row: any) => row.projectId === projectId);
    }

    return filteredResults.slice(0, limit).map((row: any) => ({
      id: row.id,
      projectId: row.projectId,
      filePath: row.filePath,
      fileName: row.fileName,
      content: row.content,
      language: row.language,
      score: row._distance ? 1 - row._distance : 0,
    }));
  }

  /**
   * Get skeletons for a project
   */
  async getSkeletonsByProject(projectId: string): Promise<SkeletonSearchResult[]> {
    if (!this.skeletonsTable) {
      return [];
    }

    const results = await this.skeletonsTable
      .query()
      .where(`projectId = "${projectId}"`)
      .limit(1000)
      .toArray();

    return results.map((row: any) => ({
      id: row.id,
      projectId: row.projectId,
      filePath: row.filePath,
      fileName: row.fileName,
      content: row.content,
      language: row.language,
      score: 1,
    }));
  }

  /**
   * Delete skeletons for a project
   */
  async deleteSkeletonsByProject(projectId: string): Promise<void> {
    if (this.skeletonsTable) {
      try {
        await this.skeletonsTable.delete(`projectId = "${projectId}"`);
        this.logger.log(`Deleted skeletons for project: ${projectId}`);
      } catch (e) {
        this.logger.warn(`Failed to delete skeletons for project ${projectId}: ${e}`);
      }
    }
  }

  /**
   * Get project count
   */
  async getProjectCount(): Promise<number> {
    if (this.projectsTable) {
      return await this.projectsTable.countRows();
    }
    return 0;
  }

  // ==================== HELPER METHODS ====================

  private parseMetadata(
    metadata: string | Record<string, unknown>,
  ): Record<string, unknown> {
    if (typeof metadata === 'string') {
      try {
        return JSON.parse(metadata);
      } catch {
        return {};
      }
    }
    return metadata || {};
  }

  private parseJsonArray(jsonStr: string | string[]): string[] {
    if (Array.isArray(jsonStr)) {
      return jsonStr;
    }
    if (typeof jsonStr === 'string') {
      try {
        return JSON.parse(jsonStr);
      } catch {
        return [];
      }
    }
    return [];
  }

  private generateId(): string {
    return `doc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private generateProjectId(): string {
    return `proj_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private generateSkeletonId(): string {
    return `skel_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}
