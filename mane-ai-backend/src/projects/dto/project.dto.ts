import {
  IsString,
  IsOptional,
  IsArray,
  IsNumber,
  IsBoolean,
} from 'class-validator';

export class IndexProjectDto {
  @IsString()
  folderPath: string;

  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsBoolean()
  quickMode?: boolean; // Skip LLM analysis for faster indexing
}

export class SearchProjectsDto {
  @IsString()
  query: string;

  @IsOptional()
  @IsNumber()
  limit?: number;
}

export interface ProjectManifest {
  type: string;
  name?: string;
  version?: string;
  description?: string;
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
  scripts?: Record<string, string>;
  [key: string]: unknown;
}

export interface CodebaseStructure {
  totalFiles: number;
  totalDirectories: number;
  filesByExtension: Record<string, number>;
  keyDirectories: string[];
  entryPoints: string[];
  configFiles: string[];
  hasTests: boolean;
  hasDocumentation: boolean;
}

export interface CodebaseAnalysis {
  projectName: string;
  projectPath: string;
  projectType: string;
  techStack: string[];
  manifest: ProjectManifest | null;
  structure: CodebaseStructure;
  knowledgeDocument: string;
  tags: string[];
}

export interface ProjectResponseDto {
  id: string;
  name: string;
  path: string;
  description: string;
  techStack: string[];
  tags: string[];
  fileCount: number;
  knowledgeDocument?: string;
  createdAt: string;
}

export interface ProjectListResponseDto {
  projects: ProjectResponseDto[];
  total: number;
}

export interface IndexProjectResponseDto {
  success: boolean;
  message: string;
  project?: ProjectResponseDto;
}

export class ScanDirectoryDto {
  @IsString()
  folderPath: string;

  @IsOptional()
  @IsNumber()
  maxDepth?: number; // Maximum depth to search (default: 3)
}

export interface DiscoveredCodebaseDto {
  path: string;
  name: string;
  type: string;
  techStack: string[];
}

export interface ScanDirectoryResponseDto {
  success: boolean;
  message: string;
  codebases: DiscoveredCodebaseDto[];
  total: number;
}

export interface BatchIndexResponseDto {
  success: boolean;
  message: string;
  indexed: number;
  failed: number;
  projects: ProjectResponseDto[];
  errors: Array<{ path: string; error: string }>;
}
