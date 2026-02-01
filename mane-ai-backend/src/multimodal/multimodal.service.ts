import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';

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
   * For longer videos (>60s), extracts multiple keyframes
   */
  async processVideo(filePath: string): Promise<ProcessedMedia> {
    try {
      // Get video duration first
      const duration = await this.getVideoDuration(filePath);
      this.logger.log(`Video duration: ${duration}s`);

      // Extract thumbnail(s) based on duration
      let thumbnailPath: string;
      let vector: number[];

      if (duration > 60) {
        // For long videos, extract multiple keyframes and use the best one
        this.logger.log('Long video detected, extracting multiple keyframes...');
        const keyframes = await this.extractMultipleKeyframes(filePath, duration);
        
        // Use the first keyframe as primary (usually most representative)
        thumbnailPath = keyframes[0];
        vector = await this.embedImage(thumbnailPath);
      } else {
        // For short videos, single thumbnail at 50%
        thumbnailPath = await this.extractVideoThumbnail(filePath);
        vector = await this.embedImage(thumbnailPath);
      }

      return {
        mediaType: 'video',
        vector,
        content: filePath,
        thumbnailPath,
      };
    } catch (error: any) {
      this.logger.error(`Failed to process video: ${error.message}`);
      throw error;
    }
  }

  /**
   * Get video duration in seconds
   */
  private async getVideoDuration(videoPath: string): Promise<number> {
    const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
    const ffmpeg = require('fluent-ffmpeg');
    ffmpeg.setFfmpegPath(ffmpegPath);

    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(videoPath, (err: Error, metadata: any) => {
        if (err) {
          this.logger.warn(`Could not get video duration: ${err.message}`);
          resolve(30); // Default to 30s if probe fails
        } else {
          resolve(metadata.format.duration || 30);
        }
      });
    });
  }

  /**
   * Extract multiple keyframes from a long video
   * Extracts at 10%, 50%, and 90% of the video
   */
  private async extractMultipleKeyframes(
    videoPath: string,
    duration: number,
  ): Promise<string[]> {
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

    await fs.promises.mkdir(thumbnailDir, { recursive: true });

    const baseName = path.basename(videoPath, path.extname(videoPath));
    const timestamps = [
      Math.floor(duration * 0.1),  // 10%
      Math.floor(duration * 0.5),  // 50%
      Math.floor(duration * 0.9),  // 90%
    ];

    const keyframePaths: string[] = [];

    for (let i = 0; i < timestamps.length; i++) {
      const timestamp = timestamps[i];
      const keyframePath = path.join(
        thumbnailDir,
        `${baseName}_keyframe_${i}.jpg`,
      );

      try {
        await new Promise<void>((resolve, reject) => {
          ffmpeg(videoPath)
            .screenshots({
              timestamps: [timestamp],
              filename: `${baseName}_keyframe_${i}.jpg`,
              folder: thumbnailDir,
              size: '224x224',
            })
            .on('end', () => resolve())
            .on('error', (err: Error) => reject(err));
        });
        keyframePaths.push(keyframePath);
      } catch (err: any) {
        this.logger.warn(`Failed to extract keyframe at ${timestamp}s: ${err.message}`);
      }
    }

    // If no keyframes extracted, fall back to single thumbnail
    if (keyframePaths.length === 0) {
      const fallback = await this.extractVideoThumbnail(videoPath);
      return [fallback];
    }

    this.logger.log(`Extracted ${keyframePaths.length} keyframes`);
    return keyframePaths;
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
   * Generate text embedding using CLIP text encoder (512-dim)
   * This is used for cross-modal search (text query → image results)
   */
  async embedTextWithClip(text: string): Promise<number[]> {
    const { AutoTokenizer, CLIPTextModelWithProjection } = await import(
      '@huggingface/transformers'
    );

    // Load CLIP text model if not cached
    if (!this.clipTextModel) {
      this.logger.log('Loading CLIP text model for cross-modal search...');
      this.clipTextModel = await CLIPTextModelWithProjection.from_pretrained(
        'Xenova/clip-vit-base-patch32',
      );
      this.clipTokenizer = await AutoTokenizer.from_pretrained(
        'Xenova/clip-vit-base-patch32',
      );
      this.logger.log('CLIP text model loaded successfully');
    }

    // Tokenize and encode
    const inputs = await this.clipTokenizer(text, {
      padding: true,
      truncation: true,
    });

    const output = await this.clipTextModel(inputs);

    // Get text embeddings and normalize
    const vector = Array.from(output.text_embeds.data) as number[];
    const magnitude = Math.sqrt(
      vector.reduce((sum, val) => sum + val * val, 0),
    );
    return vector.map((v) => v / magnitude);
  }

  // CLIP text model cache
  private clipTextModel: any = null;
  private clipTokenizer: any = null;

  /**
   * Generate image embedding using CLIP
   * Note: The CLIP pipeline handles image preprocessing internally when given a file path
   */
  async embedImage(imagePath: string): Promise<number[]> {
    const pipe = await this.getClipPipeline();

    // CLIP pipeline handles preprocessing (resize, normalize, etc.) internally
    const output = await pipe(imagePath);

    // Extract and normalize the output vector to unit length
    const vector = Array.from(output.data) as number[];
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
