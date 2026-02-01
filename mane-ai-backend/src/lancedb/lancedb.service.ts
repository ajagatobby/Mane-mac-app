import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import { ConfigService } from '../config';
import * as lancedb from '@lancedb/lancedb';
import * as fs from 'fs';
import * as path from 'path';

// Types for LanceDB
interface DocumentRecord {
  id: string;
  content: string;
  filePath: string;
  fileName: string;
  metadata: string; // JSON string to avoid schema issues
  vector: number[];
  createdAt: string;
  [key: string]: unknown; // Index signature for LanceDB compatibility
}

interface SearchResult {
  id: string;
  content: string;
  filePath: string;
  fileName: string;
  metadata: Record<string, unknown>; // Parsed from JSON string
  score: number;
}

@Injectable()
export class LanceDBService implements OnModuleInit {
  private readonly logger = new Logger(LanceDBService.name);
  private db: lancedb.Connection | null = null;
  private table: lancedb.Table | null = null;
  private embedder: any = null;
  private readonly tableName = 'documents';
  private readonly embeddingDimension = 384; // all-MiniLM-L6-v2 dimension

  constructor(private readonly configService: ConfigService) {}

  async onModuleInit() {
    await this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      // Initialize the embedding model
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

      // Check if table exists, create if not
      const tableNames = await this.db.tableNames();
      if (tableNames.includes(this.tableName)) {
        this.table = await this.db.openTable(this.tableName);
        this.logger.log(`Opened existing table: ${this.tableName}`);
      } else {
        // Create table with initial schema
        await this.createTable();
      }

      this.logger.log('LanceDB initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize LanceDB:', error);
      throw error;
    }
  }

  private async createTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    // Create table with a sample record to establish schema
    const sampleRecord: DocumentRecord = {
      id: 'init',
      content: '',
      filePath: '',
      fileName: '',
      metadata: '{}', // JSON string
      vector: new Array(this.embeddingDimension).fill(0),
      createdAt: new Date().toISOString(),
    };

    this.table = await this.db.createTable(this.tableName, [sampleRecord]);

    // Delete the sample record
    await this.table.delete('id = "init"');

    this.logger.log(`Created new table: ${this.tableName}`);
  }

  async generateEmbedding(text: string): Promise<number[]> {
    if (!this.embedder) {
      throw new Error('Embedding model not initialized');
    }

    const output = await this.embedder(text, {
      pooling: 'mean',
      normalize: true,
    });

    // Convert tensor to array
    return Array.from(output.data);
  }

  async addDocument(
    content: string,
    filePath: string,
    metadata: Record<string, unknown> = {},
  ): Promise<string> {
    if (!this.table) {
      throw new Error('Table not initialized');
    }

    const id = this.generateId();
    const fileName = path.basename(filePath);

    this.logger.log(`Generating embedding for document: ${fileName}`);
    const vector = await this.generateEmbedding(content);

    const record: DocumentRecord = {
      id,
      content,
      filePath,
      fileName,
      metadata: JSON.stringify(metadata), // Serialize to JSON string
      vector,
      createdAt: new Date().toISOString(),
    };

    await this.table.add([record]);
    this.logger.log(`Document added: ${id} (${fileName})`);

    return id;
  }

  async search(query: string, limit: number = 5): Promise<SearchResult[]> {
    if (!this.table) {
      throw new Error('Table not initialized');
    }

    this.logger.log(`Searching for: "${query.substring(0, 50)}..."`);
    const queryVector = await this.generateEmbedding(query);

    const results = await this.table
      .vectorSearch(queryVector)
      .limit(limit)
      .toArray();

    return results.map((row: any) => ({
      id: row.id,
      content: row.content,
      filePath: row.filePath,
      fileName: row.fileName,
      metadata: this.parseMetadata(row.metadata),
      score: row._distance ? 1 - row._distance : 0,
    }));
  }

  async hybridSearch(
    query: string,
    limit: number = 5,
  ): Promise<SearchResult[]> {
    if (!this.table) {
      throw new Error('Table not initialized');
    }

    // First, do vector search
    const vectorResults = await this.search(query, limit * 2);

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

    // Sort by combined score and return top results
    return scoredResults.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  async deleteDocument(id: string): Promise<void> {
    if (!this.table) {
      throw new Error('Table not initialized');
    }

    await this.table.delete(`id = "${id}"`);
    this.logger.log(`Document deleted: ${id}`);
  }

  async getDocumentCount(): Promise<number> {
    if (!this.table) {
      return 0;
    }

    const results = await this.table.countRows();
    return results;
  }

  async getAllDocuments(): Promise<SearchResult[]> {
    if (!this.table) {
      return [];
    }

    const results = await this.table.query().limit(1000).toArray();
    return results.map((row: any) => ({
      id: row.id,
      content: row.content,
      filePath: row.filePath,
      fileName: row.fileName,
      metadata: this.parseMetadata(row.metadata),
      score: 1,
    }));
  }

  private parseMetadata(metadata: string | Record<string, unknown>): Record<string, unknown> {
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
