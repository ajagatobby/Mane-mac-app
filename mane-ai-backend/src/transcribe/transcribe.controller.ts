import {
  Controller,
  Post,
  Get,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { TranscribeService } from './transcribe.service';
import { TranscribeDto, TranscribeResponseDto } from './dto/transcribe.dto';

@Controller('transcribe')
export class TranscribeController {
  constructor(private readonly transcribeService: TranscribeService) {}

  /**
   * Transcribe an audio file directly using Whisper
   * Returns raw transcription text without LLM processing
   */
  @Post()
  @HttpCode(HttpStatus.OK)
  async transcribe(@Body() dto: TranscribeDto): Promise<TranscribeResponseDto> {
    return this.transcribeService.transcribe(dto);
  }

  /**
   * Get list of supported audio formats
   */
  @Get('formats')
  @HttpCode(HttpStatus.OK)
  getSupportedFormats(): { formats: string[] } {
    return {
      formats: this.transcribeService.getSupportedExtensions(),
    };
  }
}
