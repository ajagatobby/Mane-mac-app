import { IsString, IsOptional } from 'class-validator';

export class TranscribeDto {
  @IsString()
  filePath: string;
}

export class TranscribeResponseDto {
  transcription: string;
  fileName: string;
  filePath: string;
  durationSeconds?: number;
  success: boolean;
  message?: string;
}
