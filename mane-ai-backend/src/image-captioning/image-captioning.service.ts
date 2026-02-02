import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '../config';
import { Ollama } from 'ollama';
import * as fs from 'fs';
import * as path from 'path';

@Injectable()
export class ImageCaptioningService implements OnModuleInit {
  private readonly logger = new Logger(ImageCaptioningService.name);
  private ollama: Ollama;
  private isMoondreamAvailable = false;
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
      // Read image as base64
      const imageBuffer = await fs.promises.readFile(imagePath);
      const base64Image = imageBuffer.toString('base64');

      this.logger.log(`Generating caption for: ${path.basename(imagePath)}`);

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
    } catch (error: any) {
      this.logger.error(`Moondream captioning failed: ${error.message}`);
      
      // Mark as unavailable so we don't keep retrying
      this.isMoondreamAvailable = false;
      
      // Return fallback caption
      return this.getFallbackCaption(imagePath);
    }
  }

  /**
   * Fallback caption when Moondream is unavailable
   */
  private getFallbackCaption(imagePath: string): string {
    const fileName = path.basename(imagePath);
    const ext = path.extname(imagePath).toLowerCase().replace('.', '');
    return `[image, picture, file, document, ${ext} format] Image file: ${fileName}`;
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
