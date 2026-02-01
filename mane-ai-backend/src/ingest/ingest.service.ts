import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService } from '../lancedb';
import {
  IngestDocumentDto,
  IngestResponseDto,
  DocumentListResponseDto,
} from './dto/ingest.dto';
import * as path from 'path';

@Injectable()
export class IngestService {
  private readonly logger = new Logger(IngestService.name);

  constructor(private readonly lanceDBService: LanceDBService) {}

  async ingestDocument(dto: IngestDocumentDto): Promise<IngestResponseDto> {
    try {
      this.logger.log(`Ingesting document: ${dto.filePath}`);

      const id = await this.lanceDBService.addDocument(
        dto.content,
        dto.filePath,
        dto.metadata || {},
      );

      const fileName = path.basename(dto.filePath);

      return {
        id,
        fileName,
        filePath: dto.filePath,
        success: true,
        message: `Document "${fileName}" ingested successfully`,
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
}
