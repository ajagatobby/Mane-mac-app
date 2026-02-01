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

interface MediaDocumentRecord {
  id: string;
  content: string; // File path for media, transcript for audio
  filePath: string;
  fileName: string;
  mediaType: string;
  thumbnailPath: string;
  metadata: string; // JSON string
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

export type MediaType = 'text' | 'image' | 'audio' | 'video';

@Injectable()
export class LanceDBService implements OnModuleInit {
  private readonly logger = new Logger(LanceDBService.name);
  private db: lancedb.Connection | null = null;
  private textTable: lancedb.Table | null = null;
  private mediaTable: lancedb.Table | null = null;
  private embedder: any = null;

  private readonly textTableName = 'documents_text';
  private readonly mediaTableName = 'documents_media';

  // Embedding dimensions
  readonly TEXT_DIMENSION = 384; // all-MiniLM-L6-v2
  readonly MEDIA_DIMENSION = 512; // CLIP

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

    // Initialize media table
    if (tableNames.includes(this.mediaTableName)) {
      this.mediaTable = await this.db.openTable(this.mediaTableName);
      this.logger.log(`Opened existing table: ${this.mediaTableName}`);
    } else {
      await this.createMediaTable();
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

  private async createMediaTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sampleRecord: MediaDocumentRecord = {
      id: 'init',
      content: '',
      filePath: '',
      fileName: '',
      mediaType: 'image',
      thumbnailPath: '',
      metadata: '{}',
      vector: new Array(this.MEDIA_DIMENSION).fill(0),
      createdAt: new Date().toISOString(),
    };

    this.mediaTable = await this.db.createTable(this.mediaTableName, [
      sampleRecord,
    ]);
    await this.mediaTable.delete('id = "init"');
    this.logger.log(`Created new table: ${this.mediaTableName}`);
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
   * Add a text document
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

    const id = this.generateId();
    const fileName = path.basename(filePath);

    this.logger.log(`Adding text document: ${fileName}`);
    const docVector = vector || (await this.generateEmbedding(content));

    const record: TextDocumentRecord = {
      id,
      content,
      filePath,
      fileName,
      mediaType: 'text',
      metadata: JSON.stringify(metadata),
      vector: docVector,
      createdAt: new Date().toISOString(),
    };

    await this.textTable.add([record]);
    this.logger.log(`Text document added: ${id} (${fileName})`);

    return id;
  }

  /**
   * Add a media document (image, audio, video)
   */
  async addMediaDocument(
    content: string,
    filePath: string,
    mediaType: MediaType,
    vector: number[],
    thumbnailPath?: string,
    metadata: Record<string, unknown> = {},
  ): Promise<string> {
    if (!this.mediaTable) {
      throw new Error('Media table not initialized');
    }

    const id = this.generateId();
    const fileName = path.basename(filePath);

    this.logger.log(`Adding ${mediaType} document: ${fileName}`);

    const record: MediaDocumentRecord = {
      id,
      content,
      filePath,
      fileName,
      mediaType,
      thumbnailPath: thumbnailPath || '',
      metadata: JSON.stringify(metadata),
      vector,
      createdAt: new Date().toISOString(),
    };

    await this.mediaTable.add([record]);
    this.logger.log(`Media document added: ${id} (${fileName})`);

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
   * Search media documents with provided vector
   */
  async searchMedia(
    queryVector: number[],
    limit: number = 5,
  ): Promise<SearchResult[]> {
    if (!this.mediaTable) {
      throw new Error('Media table not initialized');
    }

    const results = await this.mediaTable
      .vectorSearch(queryVector)
      .limit(limit)
      .toArray();

    return results.map((row: any) => ({
      id: row.id,
      content: row.content,
      filePath: row.filePath,
      fileName: row.fileName,
      mediaType: row.mediaType,
      thumbnailPath: row.thumbnailPath,
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
   */
  async hybridSearch(query: string, limit: number = 5): Promise<SearchResult[]> {
    if (!this.textTable) {
      throw new Error('Text table not initialized');
    }

    const vectorResults = await this.searchText(query, limit * 2);

    // Simple keyword filtering to boost relevance
    const keywords = query
      .toLowerCase()
      .split(/\s+/)
      .filter((k) => k.length > 2);

    const scoredResults = vectorResults.map((result) => {
      let keywordScore = 0;
      const contentLower = result.content.toLowerCase();
      const fileNameLower = result.fileName.toLowerCase();

      for (const keyword of keywords) {
        if (contentLower.includes(keyword)) {
          keywordScore += 0.1;
        }
        if (fileNameLower.includes(keyword)) {
          keywordScore += 0.2;
        }
      }

      return {
        ...result,
        score: result.score + keywordScore,
      };
    });

    return scoredResults.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  /**
   * Search all documents (text + media)
   */
  async searchAll(
    textQuery: string,
    mediaVector?: number[],
    limit: number = 5,
  ): Promise<SearchResult[]> {
    const results: SearchResult[] = [];

    // Search text
    const textResults = await this.searchText(textQuery, limit);
    results.push(...textResults);

    // Search media if vector provided
    if (mediaVector && this.mediaTable) {
      const mediaResults = await this.searchMedia(mediaVector, limit);
      results.push(...mediaResults);
    }

    // Sort by score and return top results
    return results.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  /**
   * Delete a document by ID
   */
  async deleteDocument(id: string): Promise<void> {
    // Try to delete from both tables
    if (this.textTable) {
      try {
        await this.textTable.delete(`id = "${id}"`);
      } catch (e) {
        // Ignore if not found in this table
      }
    }

    if (this.mediaTable) {
      try {
        await this.mediaTable.delete(`id = "${id}"`);
      } catch (e) {
        // Ignore if not found in this table
      }
    }

    this.logger.log(`Document deleted: ${id}`);
  }

  /**
   * Get total document count
   */
  async getDocumentCount(): Promise<number> {
    let count = 0;

    if (this.textTable) {
      count += await this.textTable.countRows();
    }

    if (this.mediaTable) {
      count += await this.mediaTable.countRows();
    }

    return count;
  }

  /**
   * Get all documents
   */
  async getAllDocuments(): Promise<SearchResult[]> {
    const results: SearchResult[] = [];

    if (this.textTable) {
      const textDocs = await this.textTable.query().limit(1000).toArray();
      results.push(
        ...textDocs.map((row: any) => ({
          id: row.id,
          content: row.content,
          filePath: row.filePath,
          fileName: row.fileName,
          mediaType: row.mediaType || 'text',
          metadata: this.parseMetadata(row.metadata),
          score: 1,
        })),
      );
    }

    if (this.mediaTable) {
      const mediaDocs = await this.mediaTable.query().limit(1000).toArray();
      results.push(
        ...mediaDocs.map((row: any) => ({
          id: row.id,
          content: row.content,
          filePath: row.filePath,
          fileName: row.fileName,
          mediaType: row.mediaType,
          thumbnailPath: row.thumbnailPath,
          metadata: this.parseMetadata(row.metadata),
          score: 1,
        })),
      );
    }

    return results;
  }

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

  private generateId(): string {
    return `doc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}
