import { IsString, IsOptional, IsNumber, Min, Max } from 'class-validator';

export class SearchProjectsDto {
  @IsString()
  query: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(50)
  limit?: number;
}

export class SearchCodeDto {
  @IsString()
  query: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @IsString()
  projectId?: string;
}

export class UnifiedSearchDto {
  @IsString()
  query: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(20)
  projectLimit?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(50)
  codeLimit?: number;

  @IsOptional()
  @IsString()
  projectId?: string;
}
