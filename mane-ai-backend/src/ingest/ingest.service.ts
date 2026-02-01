import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService } from '../lancedb';
import { MultimodalService, MediaType } from '../multimodal';
import { ImageCaptioningService } from '../image-captioning';
import {
  IngestDocumentDto,
  IngestResponseDto,
  DocumentListResponseDto,
} from './dto/ingest.dto';
import * as path from 'path';
import * as fs from 'fs';

@Injectable()
export class IngestService {
  private readonly logger = new Logger(IngestService.name);

  constructor(
    private readonly lanceDBService: LanceDBService,
    private readonly multimodalService: MultimodalService,
    private readonly imageCaptioningService: ImageCaptioningService,
  ) {}

  async ingestDocument(dto: IngestDocumentDto): Promise<IngestResponseDto> {
    try {
      this.logger.log(`Ingesting document: ${dto.filePath}`);

      // Determine media type
      const mediaType =
        dto.mediaType || this.multimodalService.getMediaType(dto.filePath);
      const fileName = path.basename(dto.filePath);

      let id: string;

      if (mediaType === 'text') {
        // Text document - use content if provided, otherwise read from file
        let content = dto.content;
        if (!content && fs.existsSync(dto.filePath)) {
          content = await fs.promises.readFile(dto.filePath, 'utf-8');
        }

        if (!content) {
          throw new Error('Content is required for text documents');
        }

        id = await this.lanceDBService.addTextDocument(
          content,
          dto.filePath,
          dto.metadata || {},
        );
      } else if (mediaType === 'audio') {
        // Audio file - transcribe with Whisper, embed with MiniLM (384-dim)
        // Store in text table since it uses text embeddings
        if (!fs.existsSync(dto.filePath)) {
          throw new Error(`File not found: ${dto.filePath}`);
        }

        const processed = await this.multimodalService.processFile(dto.filePath);

        // Store in text table with pre-computed vector and audio metadata
        id = await this.lanceDBService.addTextDocument(
          processed.content, // transcript
          dto.filePath,
          { ...dto.metadata, mediaType: 'audio' },
          processed.vector, // 384-dim MiniLM vector
        );
      } else if (mediaType === 'image') {
        // Image files - caption with Moondream, embed with MiniLM (384-dim)
        // Store in text table for unified text search
        if (!fs.existsSync(dto.filePath)) {
          throw new Error(`File not found: ${dto.filePath}`);
        }

        // Generate detailed caption using Moondream vision model
        const caption = await this.imageCaptioningService.generateCaption(
          dto.filePath,
        );
        this.logger.log(
          `Generated caption for ${fileName}: ${caption.substring(0, 100)}...`,
        );

        // Store caption in text table (will be embedded with MiniLM)
        id = await this.lanceDBService.addTextDocument(
          caption,
          dto.filePath,
          { ...dto.metadata, mediaType: 'image' },
        );
      } else {
        throw new Error(`Unsupported media type: ${mediaType}`);
      }

      return {
        id,
        fileName,
        filePath: dto.filePath,
        mediaType,
        success: true,
        message: `${mediaType.charAt(0).toUpperCase() + mediaType.slice(1)} "${fileName}" ingested successfully`,
      };
    } catch (error: any) {
      this.logger.error(`Failed to ingest document: ${error.message}`);
      throw error;
    }
  }

  async deleteDocument(
    id: string,
  ): Promise<{ success: boolean; message: string }> {
    try {
      this.logger.log(`Deleting document: ${id}`);
      await this.lanceDBService.deleteDocument(id);

      return {
        success: true,
        message: `Document "${id}" deleted successfully`,
      };
    } catch (error: any) {
      this.logger.error(`Failed to delete document: ${error.message}`);
      throw error;
    }
  }

  async listDocuments(): Promise<DocumentListResponseDto> {
    try {
      const documents = await this.lanceDBService.getAllDocuments();
      const total = await this.lanceDBService.getDocumentCount();

      return {
        documents: documents.map((doc) => ({
          id: doc.id,
          fileName: doc.fileName,
          filePath: doc.filePath,
          mediaType: (doc.mediaType as MediaType) || 'text',
          thumbnailPath: doc.thumbnailPath,
          metadata: doc.metadata,
        })),
        total,
      };
    } catch (error: any) {
      this.logger.error(`Failed to list documents: ${error.message}`);
      throw error;
    }
  }

  async getDocumentCount(): Promise<{ count: number }> {
    const count = await this.lanceDBService.getDocumentCount();
    return { count };
  }

  /**
   * Batch ingest multiple files
   */
  async batchIngest(
    files: IngestDocumentDto[],
  ): Promise<{ success: number; failed: number; results: IngestResponseDto[] }> {
    const results: IngestResponseDto[] = [];
    let success = 0;
    let failed = 0;

    for (const file of files) {
      try {
        const result = await this.ingestDocument(file);
        results.push(result);
        success++;
      } catch (error: any) {
        this.logger.error(`Failed to ingest ${file.filePath}: ${error.message}`);
        results.push({
          id: '',
          fileName: path.basename(file.filePath),
          filePath: file.filePath,
          mediaType: 'text',
          success: false,
          message: error.message,
        });
        failed++;
      }
    }

    return { success, failed, results };
  }
}
