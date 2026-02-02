import {
  Controller,
  Delete,
  Get,
  Param,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { IngestService } from './ingest.service';
import { DocumentListResponseDto } from './dto/ingest.dto';

@Controller('documents')
export class DocumentsController {
  constructor(private readonly ingestService: IngestService) {}

  @Get()
  @HttpCode(HttpStatus.OK)
  async listDocuments(): Promise<DocumentListResponseDto> {
    return this.ingestService.listDocuments();
  }

  @Delete('all')
  @HttpCode(HttpStatus.OK)
  async deleteAllDocuments(): Promise<{ success: boolean; message: string }> {
    return this.ingestService.deleteAllDocuments();
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  async deleteDocument(
    @Param('id') id: string,
  ): Promise<{ success: boolean; message: string }> {
    return this.ingestService.deleteDocument(id);
  }
}
