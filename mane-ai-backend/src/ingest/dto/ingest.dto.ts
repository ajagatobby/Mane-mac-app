import { IsString, IsOptional, IsObject } from 'class-validator';

export class IngestDocumentDto {
  @IsString()
  content: string;

  @IsString()
  filePath: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class IngestResponseDto {
  id: string;
  fileName: string;
  filePath: string;
  success: boolean;
  message: string;
}

export class DeleteDocumentDto {
  @IsString()
  id: string;
}

export class DocumentListResponseDto {
  documents: Array<{
    id: string;
    fileName: string;
    filePath: string;
    metadata: Record<string, unknown>;
  }>;
  total: number;
}
