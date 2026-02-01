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

export type MediaType = 'text' | 'image' | 'audio';

@Injectable()
export class LanceDBService implements OnModuleInit {
  private readonly logger = new Logger(LanceDBService.name);
  private db: lancedb.Connection | null = null;
  private textTable: lancedb.Table | null = null;
  private embedder: any = null;

  private readonly textTableName = 'documents_text';

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
