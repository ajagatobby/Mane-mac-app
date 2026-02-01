import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';

// Types for pipelines
type Pipeline = any;

interface TranscriptionResult {
  text: string;
}

export type MediaType = 'text' | 'image' | 'audio';

export interface ProcessedMedia {
  mediaType: MediaType;
  vector: number[];
  content: string; // Text content or transcript
}

@Injectable()
export class MultimodalService implements OnModuleInit {
  private readonly logger = new Logger(MultimodalService.name);

  // Lazy-loaded pipelines (Singleton pattern)
  private whisperPipeline: Pipeline = null;
  private textPipeline: Pipeline = null;

  // Embedding dimensions
  readonly TEXT_DIMENSION = 384; // all-MiniLM-L6-v2

  // Supported file extensions
  private readonly imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
  private readonly audioExtensions = ['.mp3', '.wav', '.m4a', '.flac', '.ogg'];
  private readonly textExtensions = [
    '.txt',
    '.md',
    '.csv',
    '.pdf',
    '.docx',
    '.doc',
    '.xlsx',
    '.xls',
    '.pptx',
    '.ppt',
    '.rtf',
  ];

  async onModuleInit() {
    // Pre-load text pipeline on startup (most commonly used)
    this.logger.log('Pre-loading text embedding pipeline...');
    await this.getTextPipeline();
  }

  /**
   * Determine media type from file extension
   */
  getMediaType(filePath: string): MediaType {
    const ext = path.extname(filePath).toLowerCase();

    if (this.imageExtensions.includes(ext)) return 'image';
    if (this.audioExtensions.includes(ext)) return 'audio';
    return 'text';
  }

  /**
   * Process any file and return embeddings
   */
  async processFile(
    filePath: string,
    content?: string,
  ): Promise<ProcessedMedia> {
    const mediaType = this.getMediaType(filePath);

    this.logger.log(`Processing ${mediaType} file: ${path.basename(filePath)}`);

    switch (mediaType) {
      case 'audio':
        return this.processAudio(filePath);
      default:
        return this.processText(filePath, content);
    }
  }

  /**
   * Process text content
   */
  async processText(
    filePath: string,
    content?: string,
  ): Promise<ProcessedMedia> {
    const textContent =
      content || (await fs.promises.readFile(filePath, 'utf-8'));

    const vector = await this.embedText(textContent);

    return {
      mediaType: 'text',
      vector,
      content: textContent,
    };
  }

  /**
   * Process audio file using Whisper for transcription
   */
  async processAudio(filePath: string): Promise<ProcessedMedia> {
    try {
      // Transcribe audio to text
      const transcript = await this.transcribeAudio(filePath);

      // Embed the transcript
      const vector = await this.embedText(transcript);

      return {
        mediaType: 'audio',
        vector,
        content: transcript,
      };
    } catch (error: any) {
      this.logger.error(`Failed to process audio: ${error.message}`);
      throw error;
    }
  }

  /**
   * Get or initialize Whisper pipeline for audio transcription
   */
  private async getWhisperPipeline(): Promise<Pipeline> {
    if (!this.whisperPipeline) {
      this.logger.log('Loading Whisper pipeline (Xenova/whisper-tiny)...');
      const { pipeline } = await import('@huggingface/transformers');
      this.whisperPipeline = await pipeline(
        'automatic-speech-recognition',
        'Xenova/whisper-tiny',
      );
      this.logger.log('Whisper pipeline loaded successfully');
    }
    return this.whisperPipeline;
  }

  /**
   * Get or initialize text embedding pipeline
   */
  private async getTextPipeline(): Promise<Pipeline> {
    if (!this.textPipeline) {
      this.logger.log('Loading text pipeline (Xenova/all-MiniLM-L6-v2)...');
      const { pipeline } = await import('@huggingface/transformers');
      this.textPipeline = await pipeline(
        'feature-extraction',
        'Xenova/all-MiniLM-L6-v2',
      );
      this.logger.log('Text pipeline loaded successfully');
    }
    return this.textPipeline;
  }

  /**
   * Generate text embedding using text model (384-dim)
   */
  async embedText(text: string): Promise<number[]> {
    const pipe = await this.getTextPipeline();

    const output = await pipe(text, {
      pooling: 'mean',
      normalize: true,
    });

    return Array.from(output.data);
  }

  /**
   * Transcribe audio using Whisper
   */
  async transcribeAudio(audioPath: string): Promise<string> {
    const pipe = await this.getWhisperPipeline();

    try {
      const result = (await pipe(audioPath)) as TranscriptionResult;
      return result.text || '';
    } catch (error: any) {
      this.logger.warn(`Whisper transcription failed: ${error.message}`);
      // Return filename as fallback
      return `Audio file: ${path.basename(audioPath)}`;
    }
  }

  /**
   * Check if a file is a supported media type
   */
  isSupported(filePath: string): boolean {
    const ext = path.extname(filePath).toLowerCase();
    return (
      this.imageExtensions.includes(ext) ||
      this.audioExtensions.includes(ext) ||
      this.textExtensions.includes(ext)
    );
  }

  /**
   * Get the embedding dimension for a media type
   */
  getEmbeddingDimension(): number {
    return this.TEXT_DIMENSION;
  }
}
