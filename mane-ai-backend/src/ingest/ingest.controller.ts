import {
  Controller,
  Post,
  Delete,
  Get,
  Body,
  Param,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { IngestService } from './ingest.service';
import {
  IngestDocumentDto,
  IngestResponseDto,
  DocumentListResponseDto,
} from './dto/ingest.dto';

@Controller('ingest')
export class IngestController {
  constructor(private readonly ingestService: IngestService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async ingestDocument(
    @Body() dto: IngestDocumentDto,
  ): Promise<IngestResponseDto> {
    return this.ingestService.ingestDocument(dto);
  }

  @Post('media')
  @HttpCode(HttpStatus.CREATED)
  async ingestMedia(
    @Body() dto: IngestDocumentDto,
  ): Promise<IngestResponseDto> {
    // Same as ingestDocument - handles images, audio, etc.
    return this.ingestService.ingestDocument(dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  async deleteDocument(
    @Param('id') id: string,
  ): Promise<{ success: boolean; message: string }> {
    return this.ingestService.deleteDocument(id);
  }

  @Get()
  @HttpCode(HttpStatus.OK)
  async listDocuments(): Promise<DocumentListResponseDto> {
    return this.ingestService.listDocuments();
  }

  @Get('count')
  @HttpCode(HttpStatus.OK)
  async getDocumentCount(): Promise<{ count: number }> {
    return this.ingestService.getDocumentCount();
  }
}
