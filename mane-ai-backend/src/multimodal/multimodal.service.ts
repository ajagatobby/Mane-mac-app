import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import * as sharp from 'sharp';

// Types for pipelines
type Pipeline = any;

interface TranscriptionResult {
  text: string;
}

export type MediaType = 'text' | 'image' | 'audio' | 'video';

export interface ProcessedMedia {
  mediaType: MediaType;
  vector: number[];
  content: string; // Text content or transcript
  thumbnailPath?: string; // For video thumbnails
}

@Injectable()
export class MultimodalService implements OnModuleInit {
  private readonly logger = new Logger(MultimodalService.name);

  // Lazy-loaded pipelines (Singleton pattern)
  private clipPipeline: Pipeline = null;
  private whisperPipeline: Pipeline = null;
  private textPipeline: Pipeline = null;

  // Embedding dimensions
  readonly CLIP_DIMENSION = 512;
  readonly TEXT_DIMENSION = 384; // all-MiniLM-L6-v2

  // Supported file extensions
  private readonly imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
  private readonly audioExtensions = ['.mp3', '.wav', '.m4a', '.flac', '.ogg'];
  private readonly videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
  private readonly textExtensions = [
    '.txt',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.css',
    '.js',
    '.ts',
    '.swift',
    '.py',
    '.java',
    '.c',
    '.cpp',
    '.h',
    '.csv',
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
    if (this.videoExtensions.includes(ext)) return 'video';
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
      case 'image':
        return this.processImage(filePath);
      case 'audio':
        return this.processAudio(filePath);
      case 'video':
        return this.processVideo(filePath);
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
   * Process image file using CLIP
   */
  async processImage(filePath: string): Promise<ProcessedMedia> {
    try {
      const vector = await this.embedImage(filePath);

      return {
        mediaType: 'image',
        vector,
        content: filePath, // Store path as content for images
      };
    } catch (error: any) {
      this.logger.error(`Failed to process image: ${error.message}`);
      throw error;
    }
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
   * Process video file - extract thumbnail and embed
   */
  async processVideo(filePath: string): Promise<ProcessedMedia> {
    try {
      // Extract thumbnail from video
      const thumbnailPath = await this.extractVideoThumbnail(filePath);

      // Embed thumbnail using CLIP
      const vector = await this.embedImage(thumbnailPath);

      return {
        mediaType: 'video',
        vector,
        content: filePath, // Store original path
        thumbnailPath,
      };
    } catch (error: any) {
      this.logger.error(`Failed to process video: ${error.message}`);
      throw error;
    }
  }

  /**
   * Get or initialize CLIP pipeline for image embeddings
   */
  private async getClipPipeline(): Promise<Pipeline> {
    if (!this.clipPipeline) {
      this.logger.log('Loading CLIP pipeline (Xenova/clip-vit-base-patch32)...');
      const { pipeline } = await import('@huggingface/transformers');
      this.clipPipeline = await pipeline(
        'image-feature-extraction',
        'Xenova/clip-vit-base-patch32',
      );
      this.logger.log('CLIP pipeline loaded successfully');
    }
    return this.clipPipeline;
  }

  /**
   * Get or initialize Whisper pipeline for audio transcription
   */
  private async getWhisperPipeline(): Promise<Pipeline> {
    if (!this.whisperPipeline) {
      this.logger.log(
        'Loading Whisper pipeline (Xenova/whisper-tiny)...',
      );
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
      this.logger.log(
        'Loading text pipeline (Xenova/all-MiniLM-L6-v2)...',
      );
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
   * Generate text embedding
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
   * Generate image embedding using CLIP
   */
  async embedImage(imagePath: string): Promise<number[]> {
    const pipe = await this.getClipPipeline();

    // Read and preprocess image
    const imageBuffer = await fs.promises.readFile(imagePath);

    // Convert to RGB format that CLIP expects
    const processedImage = await sharp(imageBuffer)
      .resize(224, 224, { fit: 'cover' })
      .removeAlpha()
      .raw()
      .toBuffer();

    // Create image data for the pipeline
    const output = await pipe(imagePath);

    // Normalize the output
    const vector = Array.from(output.data) as number[];

    // Normalize to unit length
    const magnitude = Math.sqrt(
      vector.reduce((sum, val) => sum + val * val, 0),
    );
    return vector.map((v) => v / magnitude);
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
   * Extract thumbnail from video using ffmpeg
   */
  async extractVideoThumbnail(videoPath: string): Promise<string> {
    const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
    const ffmpeg = require('fluent-ffmpeg');
    ffmpeg.setFfmpegPath(ffmpegPath);

    const thumbnailDir = path.join(
      process.env.HOME || '/tmp',
      'Library',
      'Application Support',
      'ManeAI',
      'thumbnails',
    );

    // Ensure thumbnail directory exists
    await fs.promises.mkdir(thumbnailDir, { recursive: true });

    const thumbnailPath = path.join(
      thumbnailDir,
      `${path.basename(videoPath, path.extname(videoPath))}_thumb.jpg`,
    );

    return new Promise((resolve, reject) => {
      ffmpeg(videoPath)
        .screenshots({
          timestamps: ['50%'], // Extract from middle of video
          filename: path.basename(thumbnailPath),
          folder: thumbnailDir,
          size: '224x224',
        })
        .on('end', () => {
          this.logger.log(`Thumbnail extracted: ${thumbnailPath}`);
          resolve(thumbnailPath);
        })
        .on('error', (err: Error) => {
          this.logger.error(`FFmpeg error: ${err.message}`);
          reject(err);
        });
    });
  }

  /**
   * Check if a file is a supported media type
   */
  isSupported(filePath: string): boolean {
    const ext = path.extname(filePath).toLowerCase();
    return (
      this.imageExtensions.includes(ext) ||
      this.audioExtensions.includes(ext) ||
      this.videoExtensions.includes(ext) ||
      this.textExtensions.includes(ext)
    );
  }

  /**
   * Get the embedding dimension for a media type
   */
  getEmbeddingDimension(mediaType: MediaType): number {
    if (mediaType === 'image' || mediaType === 'video') {
      return this.CLIP_DIMENSION;
    }
    return this.TEXT_DIMENSION;
  }
}
