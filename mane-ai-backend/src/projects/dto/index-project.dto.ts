import { IsString, IsOptional, IsBoolean, IsNumber, IsArray, Min, Max } from 'class-validator';

export class IndexProjectDto {
  @IsString()
  path: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(10)
  maxDepth?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(2000)
  maxFiles?: number;

  @IsOptional()
  @IsBoolean()
  skipSkeletons?: boolean;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreDirs?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreFiles?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreExtensions?: string[];

  @IsOptional()
  @IsBoolean()
  includeTests?: boolean;
}

export class ReindexProjectDto {
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(10)
  maxDepth?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(2000)
  maxFiles?: number;

  @IsOptional()
  @IsBoolean()
  skipSkeletons?: boolean;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreDirs?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreFiles?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  customIgnoreExtensions?: string[];

  @IsOptional()
  @IsBoolean()
  includeTests?: boolean;
}
