import { IsString, IsOptional, IsObject, IsEnum } from 'class-validator';

export type MediaType = 'text' | 'image' | 'audio';

export class IngestDocumentDto {
  @IsOptional()
  @IsString()
  content?: string; // Optional for media files

  @IsString()
  filePath: string;

  @IsOptional()
  @IsEnum(['text', 'image', 'audio'])
  mediaType?: MediaType; // Auto-detected if not provided

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class IngestResponseDto {
  id: string;
  fileName: string;
  filePath: string;
  mediaType: MediaType;
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
    mediaType: MediaType;
    thumbnailPath?: string;
    metadata: Record<string, unknown>;
    /** All chunk IDs for this file (when chunked). Use these for search filtering. */
    chunkIds?: string[];
  }>;
  total: number;
}
