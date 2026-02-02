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

// Concurrency settings for parallel processing
const DEFAULT_CONCURRENCY = 10; // Process 10 files in parallel
const MAX_CONCURRENCY = 50; // Maximum parallel operations

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
   * Batch ingest multiple files (legacy sequential - use batchIngestConcurrent for speed)
   */
  async batchIngest(
    files: IngestDocumentDto[],
  ): Promise<{
    success: number;
    failed: number;
    results: IngestResponseDto[];
  }> {
    // Use concurrent processing by default for better performance
    return this.batchIngestConcurrent(files);
  }

  /**
   * Concurrent batch ingest - processes multiple files in parallel
   * This is significantly faster than sequential processing (up to 100x for large batches)
   */
  async batchIngestConcurrent(
    files: IngestDocumentDto[],
    concurrency: number = DEFAULT_CONCURRENCY,
  ): Promise<{
    success: number;
    failed: number;
    results: IngestResponseDto[];
    elapsedMs: number;
  }> {
    const startTime = Date.now();
    const effectiveConcurrency = Math.min(
      Math.max(1, concurrency),
      MAX_CONCURRENCY,
    );

    this.logger.log(
      `Starting concurrent batch ingest: ${files.length} files with concurrency ${effectiveConcurrency}`,
    );

    // Separate files by type for optimized processing
    const textFiles: IngestDocumentDto[] = [];
    const audioFiles: IngestDocumentDto[] = [];
    const imageFiles: IngestDocumentDto[] = [];

    for (const file of files) {
      const mediaType =
        file.mediaType || this.multimodalService.getMediaType(file.filePath);
      if (mediaType === 'audio') {
        audioFiles.push(file);
      } else if (mediaType === 'image') {
        imageFiles.push(file);
      } else {
        textFiles.push(file);
      }
    }

    // Process all types concurrently
    const [textResults, audioResults, imageResults] = await Promise.all([
      this.processTextFilesConcurrent(textFiles, effectiveConcurrency),
      this.processMediaFilesConcurrent(audioFiles, 'audio', Math.max(1, Math.floor(effectiveConcurrency / 2))), // Audio is CPU-intensive
      this.processMediaFilesConcurrent(imageFiles, 'image', Math.max(1, Math.floor(effectiveConcurrency / 2))), // Image captioning is GPU-intensive
    ]);

    // Combine results
    const results = [...textResults, ...audioResults, ...imageResults];
    const success = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success).length;
    const elapsedMs = Date.now() - startTime;

    this.logger.log(
      `Concurrent batch ingest complete: ${success} success, ${failed} failed in ${elapsedMs}ms (${(elapsedMs / files.length).toFixed(1)}ms/file avg)`,
    );

    return { success, failed, results, elapsedMs };
  }

  /**
   * Process text files concurrently with batch embedding optimization
   */
  private async processTextFilesConcurrent(
    files: IngestDocumentDto[],
    concurrency: number,
  ): Promise<IngestResponseDto[]> {
    if (files.length === 0) return [];

    this.logger.log(`Processing ${files.length} text files concurrently...`);

    // First, extract content from all files in parallel
    const contentExtractions = await this.runWithConcurrency(
      files,
      async (file) => this.extractTextContent(file),
      concurrency,
    );

    // Collect all chunks for batch embedding
    const allChunks: Array<{
      content: string;
      filePath: string;
      metadata: Record<string, unknown>;
      fileIndex: number;
      chunkIndex: number;
    }> = [];

    const fileChunkRanges: Array<{ start: number; end: number }> = [];

    for (let i = 0; i < contentExtractions.length; i++) {
      const extraction = contentExtractions[i];
      if (!extraction.success || !extraction.content) continue;

      const content = extraction.content;
      const shouldChunk = content.length >= MIN_CONTENT_FOR_CHUNKING;
      const chunks = shouldChunk ? this.chunkText(content) : [content];

      const ext = path
        .extname(files[i].filePath)
        .toLowerCase()
        .replace('.', '') || 'text';
      const docType =
        ext === 'pdf'
          ? 'pdf'
          : ext === 'docx'
            ? 'word'
            : ext === 'xlsx' || ext === 'xls'
              ? 'spreadsheet'
              : 'text';

      const startIdx = allChunks.length;
      for (let j = 0; j < chunks.length; j++) {
        allChunks.push({
          content: this.enrichContent(chunks[j], files[i].filePath, docType),
          filePath: files[i].filePath,
          metadata: {
            ...files[i].metadata,
            ...(chunks.length > 1 && {
              chunkIndex: j,
              totalChunks: chunks.length,
            }),
          },
          fileIndex: i,
          chunkIndex: j,
        });
      }
      fileChunkRanges[i] = { start: startIdx, end: allChunks.length };
    }

    // Batch insert all chunks at once
    let ids: string[] = [];
    if (allChunks.length > 0) {
      ids = await this.lanceDBService.addTextDocumentsBatch(
        allChunks.map((c) => ({
          content: c.content,
          filePath: c.filePath,
          metadata: c.metadata,
        })),
      );
    }

    // Build results
    const results: IngestResponseDto[] = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const fileName = path.basename(file.filePath);
      const extraction = contentExtractions[i];

      if (!extraction.success) {
        results.push({
          id: '',
          fileName,
          filePath: file.filePath,
          mediaType: 'text',
          success: false,
          message: extraction.error || 'Failed to extract content',
        });
        continue;
      }

      const range = fileChunkRanges[i];
      if (!range) {
        results.push({
          id: '',
          fileName,
          filePath: file.filePath,
          mediaType: 'text',
          success: false,
          message: 'No content to index',
        });
        continue;
      }

      const fileIds = ids.slice(range.start, range.end);
      const chunkCount = range.end - range.start;

      results.push({
        id: fileIds[0],
        fileName,
        filePath: file.filePath,
        mediaType: 'text',
        success: true,
        message:
          chunkCount > 1
            ? `Indexed as ${chunkCount} chunks`
            : 'Ingested successfully',
      });
    }

    return results;
  }

  /**
   * Extract text content from a file
   */
  private async extractTextContent(
    dto: IngestDocumentDto,
  ): Promise<{ success: boolean; content?: string; error?: string }> {
    try {
      // Check file size
      if (fs.existsSync(dto.filePath)) {
        const stats = fs.statSync(dto.filePath);
        if (stats.size > MAX_FILE_SIZE_BYTES) {
          return {
            success: false,
            error: `File exceeds size limit of ${MAX_FILE_SIZE_BYTES / 1024 / 1024}MB`,
          };
        }
      }

      let content = dto.content;

      if (!content && fs.existsSync(dto.filePath)) {
        const ext = path.extname(dto.filePath).toLowerCase();

        if (ext === '.pdf') {
          const parser = new PDFParse({ url: dto.filePath });
          const pdfData = await parser.getText();
          content = pdfData.text;
        } else if (ext === '.docx') {
          const result = await mammoth.extractRawText({ path: dto.filePath });
          content = result.value;
        } else if (ext === '.xlsx' || ext === '.xls') {
          const workbook = XLSX.readFile(dto.filePath);
          const sheets: string[] = [];
          for (const sheetName of workbook.SheetNames) {
            const sheet = workbook.Sheets[sheetName];
            const csv = XLSX.utils.sheet_to_csv(sheet);
            sheets.push(`[Sheet: ${sheetName}]\n${csv}`);
          }
          content = sheets.join('\n\n');
        } else if (ext === '.pptx') {
          const fileName = path.basename(dto.filePath);
          content = `[document, file, presentation, slides, pptx format] PowerPoint presentation: ${fileName}. Contains slides and visual content.`;
        } else if (ext === '.doc' || ext === '.ppt' || ext === '.rtf') {
          const fileName = path.basename(dto.filePath);
          content = `[document, file, ${ext.replace('.', '')} format] Document file: ${fileName}. Legacy document format.`;
        } else {
          content = await fs.promises.readFile(dto.filePath, 'utf-8');
        }
      }

      if (!content) {
        return { success: false, error: 'No content found' };
      }

      return { success: true, content };
    } catch (error: any) {
      return { success: false, error: error.message };
    }
  }

  /**
   * Process media files (audio/image) concurrently
   */
  private async processMediaFilesConcurrent(
    files: IngestDocumentDto[],
    mediaType: 'audio' | 'image',
    concurrency: number,
  ): Promise<IngestResponseDto[]> {
    if (files.length === 0) return [];

    this.logger.log(
      `Processing ${files.length} ${mediaType} files concurrently...`,
    );

    return this.runWithConcurrency(
      files,
      async (file) => {
        try {
          const result = await this.ingestDocument({
            ...file,
            mediaType,
          });
          return result;
        } catch (error: any) {
          return {
            id: '',
            fileName: path.basename(file.filePath),
            filePath: file.filePath,
            mediaType,
            success: false,
            message: error.message,
          };
        }
      },
      concurrency,
    );
  }

  /**
   * Run async operations with controlled concurrency (semaphore pattern)
   */
  private async runWithConcurrency<T, R>(
    items: T[],
    fn: (item: T) => Promise<R>,
    concurrency: number,
  ): Promise<R[]> {
    const results: R[] = new Array(items.length);
    let currentIndex = 0;

    const workers = Array(Math.min(concurrency, items.length))
      .fill(null)
      .map(async () => {
        while (currentIndex < items.length) {
          const index = currentIndex++;
          if (index >= items.length) break;
          results[index] = await fn(items[index]);
        }
      });

    await Promise.all(workers);
    return results;
  }
}
