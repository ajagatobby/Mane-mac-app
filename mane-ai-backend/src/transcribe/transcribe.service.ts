import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { MultimodalService } from '../multimodal';
import { TranscribeDto, TranscribeResponseDto } from './dto/transcribe.dto';
import * as path from 'path';
import * as fs from 'fs';

// Supported audio extensions
const AUDIO_EXTENSIONS = ['.mp3', '.wav', '.m4a', '.flac', '.ogg', '.aac'];

@Injectable()
export class TranscribeService {
  private readonly logger = new Logger(TranscribeService.name);

  constructor(private readonly multimodalService: MultimodalService) {}

  /**
   * Transcribe an audio file directly using Whisper
   * Returns raw transcription without LLM processing
   */
  async transcribe(dto: TranscribeDto): Promise<TranscribeResponseDto> {
    const { filePath } = dto;
    const fileName = path.basename(filePath);
    const ext = path.extname(filePath).toLowerCase();

    this.logger.log(`Transcribe request for: ${fileName}`);

    // Validate file exists
    if (!fs.existsSync(filePath)) {
      throw new BadRequestException(`File not found: ${filePath}`);
    }

    // Validate audio file type
    if (!AUDIO_EXTENSIONS.includes(ext)) {
      throw new BadRequestException(
        `Invalid file type: ${ext}. Transcription only supports audio files: ${AUDIO_EXTENSIONS.join(', ')}`,
      );
    }

    try {
      // Get file stats for duration estimation
      const stats = fs.statSync(filePath);
      const fileSizeBytes = stats.size;

      this.logger.log(`Starting Whisper transcription for: ${fileName}`);
      const startTime = Date.now();

      // Call Whisper directly via MultimodalService
      const transcription =
        await this.multimodalService.transcribeAudio(filePath);

      const elapsedMs = Date.now() - startTime;
      this.logger.log(
        `Transcription complete for ${fileName}: ${transcription.length} chars in ${elapsedMs}ms`,
      );

      return {
        transcription,
        fileName,
        filePath,
        success: true,
        message: `Successfully transcribed "${fileName}"`,
      };
    } catch (error: any) {
      this.logger.error(`Transcription failed for ${fileName}: ${error.message}`);
      throw new BadRequestException(
        `Failed to transcribe audio: ${error.message}`,
      );
    }
  }

  /**
   * Check if a file is a supported audio type
   */
  isAudioFile(filePath: string): boolean {
    const ext = path.extname(filePath).toLowerCase();
    return AUDIO_EXTENSIONS.includes(ext);
  }

  /**
   * Get list of supported audio extensions
   */
  getSupportedExtensions(): string[] {
    return [...AUDIO_EXTENSIONS];
  }
}
