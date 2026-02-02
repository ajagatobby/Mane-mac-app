import { IsString, IsOptional, IsBoolean, IsArray } from 'class-validator';

export type MediaType = 'text' | 'image' | 'audio';

export class ChatQueryDto {
  @IsString()
  query: string;

  @IsOptional()
  @IsBoolean()
  stream?: boolean;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  documentIds?: string[];
}

export class ChatResponseDto {
  answer: string;
  sources: Array<{
    fileName: string;
    filePath: string;
    mediaType: MediaType;
    thumbnailPath?: string;
    relevance: number;
  }>;
}

export class SearchQueryDto {
  @IsString()
  query: string;

  @IsOptional()
  limit?: number;
}

export class SearchResponseDto {
  results: Array<{
    id: string;
    content: string;
    fileName: string;
    filePath: string;
    mediaType: MediaType;
    thumbnailPath?: string;
    score: number;
  }>;
}
