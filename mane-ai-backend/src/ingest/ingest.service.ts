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

const CHUNK_WORD_COUNT = 280;
const CHUNK_OVERLAP_WORDS = 50;
const MIN_CONTENT_FOR_CHUNKING = 800;

// Max file size for ingest (1GB) - applies to text, audio, and image files
const MAX_FILE_SIZE_BYTES = 1024 * 1024 * 1024;

@Injectable()
export class IngestService {
  private readonly logger = new Logger(IngestService.name);

  private enrichContent(
    content: string,
    filePath: string,
    docType: string,
  ): string {
    const fileName = path.basename(filePath);
    const ext = path.extname(filePath).toLowerCase().replace('.', '') || 'text';
    const prefix = `[document, file, ${docType}, ${ext} format, ${fileName}] `;
    return prefix + content;
  }

  private chunkText(text: string): string[] {
    const words = text.split(/\s+/).filter((w) => w.length > 0);
    if (words.length <= CHUNK_WORD_COUNT) return [text];

    const chunks: string[] = [];
    let start = 0;
    while (start < words.length) {
      const end = Math.min(start + CHUNK_WORD_COUNT, words.length);
      const chunkWords = words.slice(start, end);
      chunks.push(chunkWords.join(' '));
      start = end - CHUNK_OVERLAP_WORDS;
      if (start >= words.length) break;
    }
    return chunks;
  }

  constructor(
    private readonly lanceDBService: LanceDBService,
    private readonly multimodalService: MultimodalService,
    private readonly imageCaptioningService: ImageCaptioningService,
  ) {}

  async ingestDocument(dto: IngestDocumentDto): Promise<IngestResponseDto> {
    try {
      this.logger.log(`Ingesting document: ${dto.filePath}`);

      // Check file size limit for all media types
      if (fs.existsSync(dto.filePath)) {
        const stats = fs.statSync(dto.filePath);
        if (stats.size > MAX_FILE_SIZE_BYTES) {
          throw new Error(
            `File exceeds size limit of ${MAX_FILE_SIZE_BYTES / 1024 / 1024}MB (file: ${(stats.size / 1024 / 1024).toFixed(1)}MB)`,
          );
        }
      }

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
            this.logger.log(
              `Extracted ${content.length} chars from PDF: ${fileName}`,
            );
          } else if (ext === '.docx') {
            // Extract text from Word (.docx)
            const result = await mammoth.extractRawText({ path: dto.filePath });
            content = result.value;
            this.logger.log(
              `Extracted ${content.length} chars from DOCX: ${fileName}`,
            );
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
            this.logger.log(
              `Extracted ${content.length} chars from Excel: ${fileName}`,
            );
          } else if (ext === '.pptx') {
            // PowerPoint - extract as XML text (basic)
            const dataBuffer = await fs.promises.readFile(dto.filePath);
            content = `[document, file, presentation, slides, pptx format] PowerPoint presentation: ${fileName}. Contains slides and visual content.`;
            this.logger.log(`Indexed PowerPoint: ${fileName}`);
          } else if (ext === '.doc' || ext === '.ppt' || ext === '.rtf') {
            // Legacy formats - index filename with searchable terms
            content = `[document, file, ${ext.replace('.', '')} format] Document file: ${fileName}. Legacy document format.`;
            this.logger.log(`Indexed legacy document: ${fileName}`);
          } else {
            content = await fs.promises.readFile(dto.filePath, 'utf-8');
          }
        }

        if (!content) {
          throw new Error('Content is required for text documents');
        }

        const ext =
          path.extname(dto.filePath).toLowerCase().replace('.', '') || 'text';
        const docType =
          ext === 'pdf'
            ? 'pdf'
            : ext === 'docx'
              ? 'word'
              : ext === 'xlsx' || ext === 'xls'
                ? 'spreadsheet'
                : 'text';

        const shouldChunk = content.length >= MIN_CONTENT_FOR_CHUNKING;
        const chunks = shouldChunk ? this.chunkText(content) : [content];

        const ids: string[] = [];
        for (let i = 0; i < chunks.length; i++) {
          const chunkContent = this.enrichContent(
            chunks[i],
            dto.filePath,
            docType,
          );
          const chunkMetadata = {
            ...dto.metadata,
            ...(chunks.length > 1 && {
              chunkIndex: i,
              totalChunks: chunks.length,
            }),
          };
          const chunkId = await this.lanceDBService.addTextDocument(
            chunkContent,
            dto.filePath,
            chunkMetadata,
          );
          ids.push(chunkId);
        }
        id = ids[0];
        if (chunks.length > 1) {
          this.logger.log(
            `Indexed ${fileName} as ${chunks.length} chunks for better search`,
          );
        }
      } else if (mediaType === 'audio') {
        // Audio file - transcribe with Whisper, embed with MiniLM (384-dim)
        // Store in text table since it uses text embeddings
        if (!fs.existsSync(dto.filePath)) {
          throw new Error(`File not found: ${dto.filePath}`);
        }

        const processed = await this.multimodalService.processFile(
          dto.filePath,
        );
        const enrichedContent = this.enrichContent(
          processed.content,
          dto.filePath,
          'audio transcript',
        );

        // Store in text table with pre-computed vector and audio metadata
        id = await this.lanceDBService.addTextDocument(
          enrichedContent,
          dto.filePath,
          { ...dto.metadata, mediaType: 'audio' },
          undefined, // Re-embed with enriched content for better search
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
        id = await this.lanceDBService.addTextDocument(caption, dto.filePath, {
          ...dto.metadata,
          mediaType: 'image',
        });
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

  async deleteAllDocuments(): Promise<{ success: boolean; message: string }> {
    try {
      this.logger.log('Deleting all documents');
      await this.lanceDBService.deleteAllDocuments();

      return {
        success: true,
        message: 'All documents deleted successfully',
      };
    } catch (error: any) {
      this.logger.error(`Failed to delete all documents: ${error.message}`);
      throw error;
    }
  }

  async listDocuments(): Promise<DocumentListResponseDto> {
    try {
      const documents = await this.lanceDBService.getUniqueDocuments();
      const total = documents.length;

      return {
        documents: documents.map((doc) => ({
          id: doc.id,
          fileName: doc.fileName,
          filePath: doc.filePath,
          mediaType: (doc.mediaType as MediaType) || 'text',
          thumbnailPath: doc.thumbnailPath,
          metadata: doc.metadata,
          chunkIds: doc.chunkIds,
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
  ): Promise<{
    success: number;
    failed: number;
    results: IngestResponseDto[];
  }> {
    const results: IngestResponseDto[] = [];
    let success = 0;
    let failed = 0;

    for (const file of files) {
      try {
        const result = await this.ingestDocument(file);
        results.push(result);
        success++;
      } catch (error: any) {
        this.logger.error(
          `Failed to ingest ${file.filePath}: ${error.message}`,
        );
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
