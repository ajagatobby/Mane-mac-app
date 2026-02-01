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
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { PDFParse } = require('pdf-parse');
import * as mammoth from 'mammoth';
import * as XLSX from 'xlsx';

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
          const ext = path.extname(dto.filePath).toLowerCase();
          
          if (ext === '.pdf') {
            // Extract text from PDF
            const parser = new PDFParse({ url: dto.filePath });
            const pdfData = await parser.getText();
            content = pdfData.text;
            this.logger.log(`Extracted ${content.length} chars from PDF: ${fileName}`);
          } else if (ext === '.docx') {
            // Extract text from Word (.docx)
            const result = await mammoth.extractRawText({ path: dto.filePath });
            content = result.value;
            this.logger.log(`Extracted ${content.length} chars from DOCX: ${fileName}`);
          } else if (ext === '.xlsx' || ext === '.xls') {
            // Extract text from Excel
            const workbook = XLSX.readFile(dto.filePath);
            const sheets: string[] = [];
            for (const sheetName of workbook.SheetNames) {
              const sheet = workbook.Sheets[sheetName];
              const csv = XLSX.utils.sheet_to_csv(sheet);
              sheets.push(`[Sheet: ${sheetName}]\n${csv}`);
            }
            content = sheets.join('\n\n');
            this.logger.log(`Extracted ${content.length} chars from Excel: ${fileName}`);
          } else if (ext === '.pptx') {
            // PowerPoint - extract as XML text (basic)
            const dataBuffer = await fs.promises.readFile(dto.filePath);
            content = `PowerPoint file: ${fileName} (${dataBuffer.length} bytes)`;
            this.logger.log(`Indexed PowerPoint: ${fileName}`);
          } else if (ext === '.doc' || ext === '.ppt' || ext === '.rtf') {
            // Legacy formats - index filename only
            content = `Document file: ${fileName} (legacy format)`;
            this.logger.log(`Indexed legacy document: ${fileName}`);
          } else {
            content = await fs.promises.readFile(dto.filePath, 'utf-8');
          }
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
