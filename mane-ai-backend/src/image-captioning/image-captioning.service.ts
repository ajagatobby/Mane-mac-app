import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '../config';
import { Ollama } from 'ollama';
import * as fs from 'fs';
import * as path from 'path';
import * as sharp from 'sharp';

const MAX_IMAGE_DIMENSION = 768;
const MAX_IMAGE_BYTES = 25 * 1024 * 1024; // 25MB
const RETRY_ATTEMPTS = 2;
const RETRY_DELAY_MS = 2000;
const RECOVERY_COOLDOWN_MS = 60000; // Re-check Moondream after 1 min

@Injectable()
export class ImageCaptioningService implements OnModuleInit {
  private readonly logger = new Logger(ImageCaptioningService.name);
  private ollama: Ollama;
  private isMoondreamAvailable = false;
  private lastMoondreamFailureTime = 0;
  private readonly modelName = 'moondream';

  constructor(private readonly configService: ConfigService) {
    const ollamaUrl = this.configService.getOllamaUrl();
    this.ollama = new Ollama({ host: ollamaUrl });
  }

  async onModuleInit() {
    await this.checkMoondreamHealth();
  }

  /**
   * Check if Ollama is running and moondream model is available
   */
  async checkMoondreamHealth(): Promise<boolean> {
    try {
      const ollamaUrl = this.configService.getOllamaUrl();
      
      // First check if Ollama is running
      const response = await fetch(`${ollamaUrl}/api/tags`);
      if (!response.ok) {
        this.logger.warn('Ollama is not responding');
        this.isMoondreamAvailable = false;
        return false;
      }

      // Check if moondream model is available
      const data = await response.json();
      const models = data.models || [];
      const hasMoondream = models.some(
        (model: { name: string }) =>
          model.name.toLowerCase().includes(this.modelName),
      );

      if (hasMoondream) {
        this.logger.log('Moondream model is available');
        this.isMoondreamAvailable = true;
      } else {
        this.logger.warn(
          `Moondream model not found. Please run: ollama pull ${this.modelName}`,
        );
        this.isMoondreamAvailable = false;
      }

      return this.isMoondreamAvailable;
    } catch (error: any) {
      this.logger.warn(
        `Failed to check Moondream health: ${error.message}. Please ensure Ollama is running.`,
      );
      this.isMoondreamAvailable = false;
      return false;
    }
  }

  /**
   * Generate a detailed caption for an image using Moondream
   * @param imagePath - Path to the image file
   * @returns Detailed text description of the image
   */
  async generateCaption(imagePath: string): Promise<string> {
    // Verify file exists
    if (!fs.existsSync(imagePath)) {
      throw new Error(`Image file not found: ${imagePath}`);
    }

    // Re-check health if previously failed and cooldown has passed
    if (
      !this.isMoondreamAvailable &&
      Date.now() - this.lastMoondreamFailureTime > RECOVERY_COOLDOWN_MS
    ) {
      await this.checkMoondreamHealth();
    }

    // Check health if not already available
    if (!this.isMoondreamAvailable) {
      await this.checkMoondreamHealth();
    }

    // If still not available, use fallback
    if (!this.isMoondreamAvailable) {
      this.logger.warn(
        `Moondream not available, using filename fallback for: ${imagePath}`,
      );
      return this.getFallbackCaption(imagePath);
    }

    try {
      // Read and optionally resize image to reduce memory pressure on Ollama
      const imageBuffer = await this.prepareImageForCaptioning(imagePath);
      const base64Image = imageBuffer.toString('base64');

      this.logger.log(`Generating caption for: ${path.basename(imagePath)}`);

      let lastError: Error | null = null;
      for (let attempt = 0; attempt <= RETRY_ATTEMPTS; attempt++) {
        try {
          const response = await this.ollama.chat({
            model: this.modelName,
            messages: [
              {
                role: 'user',
                content:
                  'Describe this image in extreme detail for search indexing. Include: (1) people or humans if present, (2) any animations, motion, or dynamic elements, (3) document type if it shows text/screenshots/files, (4) main objects, clothing, colors, backgrounds, actions, (5) file or image type. Use specific searchable terms: humans, people, characters, animations, document, file, image, picture. Be exhaustive—list everything a user might search for. No filler words.',
                images: [base64Image],
              },
            ],
          });

          const rawCaption = response.message.content.trim();
          const fileName = path.basename(imagePath);
          const ext = path.extname(imagePath).toLowerCase().replace('.', '');
          const searchablePrefix = `[image, picture, file, ${ext} format, ${fileName}] `;
          const caption = searchablePrefix + rawCaption;
          this.logger.log(
            `Generated caption (${caption.length} chars): ${caption.substring(0, 100)}...`,
          );

          return caption;
        } catch (err: any) {
          lastError = err;
          if (attempt < RETRY_ATTEMPTS) {
            this.logger.warn(
              `Moondream attempt ${attempt + 1} failed (${err.message}), retrying in ${RETRY_DELAY_MS}ms...`,
            );
            await this.sleep(RETRY_DELAY_MS);
          }
        }
      }

      throw lastError ?? new Error('Captioning failed');
    } catch (error: any) {
      this.logger.warn(
        `Moondream captioning failed, using fallback: ${error.message}`,
      );

      this.isMoondreamAvailable = false;
      this.lastMoondreamFailureTime = Date.now();

      return this.getFallbackCaption(imagePath);
    }
  }

  /**
   * Prepare image for captioning - resize and convert to JPEG to avoid Ollama OOM.
   * WebP/PNG can cause memory issues; JPEG is more reliable for Ollama.
   */
  private async prepareImageForCaptioning(imagePath: string): Promise<Buffer> {
    const imageBuffer = await fs.promises.readFile(imagePath);
    const ext = path.extname(imagePath).toLowerCase();

    try {
      const metadata = await sharp(imageBuffer).metadata();
      const width = metadata.width ?? 0;
      const height = metadata.height ?? 0;

      // Always convert WebP/PNG to JPEG - more reliable for Ollama, reduces memory
      const needsConvert = ['.webp', '.png', '.gif'].includes(ext);
      const needsResize =
        width > MAX_IMAGE_DIMENSION ||
        height > MAX_IMAGE_DIMENSION ||
        imageBuffer.length > MAX_IMAGE_BYTES;

      if (!needsConvert && !needsResize) {
        return imageBuffer;
      }

      let pipeline = sharp(imageBuffer);

      if (needsResize) {
        pipeline = pipeline.resize(MAX_IMAGE_DIMENSION, MAX_IMAGE_DIMENSION, {
          fit: 'inside',
          withoutEnlargement: true,
        });
      }

      const processed = await pipeline
        .jpeg({ quality: 80 })
        .toBuffer();

      this.logger.log(
        `Prepared image for captioning: ${imageBuffer.length} -> ${processed.length} bytes`,
      );
      return processed;
    } catch (err: any) {
      this.logger.warn(`Image prepare failed, using original: ${err.message}`);
      return imageBuffer;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Fallback caption when Moondream is unavailable.
   * Extracts searchable terms from filename (e.g. "beautiful-brown-horse" -> horse, brown, beautiful).
   */
  private getFallbackCaption(imagePath: string): string {
    const fileName = path.basename(imagePath);
    const ext = path.extname(imagePath).toLowerCase().replace('.', '');
    const nameWithoutExt = path.basename(fileName, ext ? `.${ext}` : '');

    // Extract hyphen/underscore-separated words as searchable terms (skip numbers)
    const words = nameWithoutExt
      .split(/[-_\s.]+/)
      .filter((w) => w.length > 2 && !/^\d+$/.test(w))
      .map((w) => w.toLowerCase());

    const searchTerms =
      words.length > 0 ? ` Search terms: ${[...new Set(words)].join(', ')}.` : '';

    return `[image, picture, file, ${ext} format, ${fileName}] Image file: ${fileName}.${searchTerms}`;
  }

  /**
   * Get the current status of the service
   */
  getStatus(): { available: boolean; model: string } {
    return {
      available: this.isMoondreamAvailable,
      model: this.modelName,
    };
  }
}
