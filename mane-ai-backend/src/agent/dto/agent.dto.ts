import { IsString, IsBoolean, IsOptional, IsArray } from 'class-validator';

/**
 * DTO for executing an agent command
 */
export class ExecuteAgentDto {
  @IsString()
  command: string;

  @IsBoolean()
  @IsOptional()
  stream?: boolean;
}

/**
 * DTO for confirming pending actions
 */
export class ConfirmActionsDto {
  @IsString()
  sessionId: string;
}

/**
 * DTO for reporting action execution results
 */
export class ActionResultDto {
  @IsString()
  actionId: string;

  @IsBoolean()
  success: boolean;

  @IsString()
  @IsOptional()
  error?: string;
}

/**
 * DTO for reporting multiple action results
 */
export class ActionResultsDto {
  @IsString()
  sessionId: string;

  @IsArray()
  results: ActionResultDto[];
}

/**
 * DTO for auto-organize request
 */
export class OrganizeDto {
  @IsString()
  @IsOptional()
  targetFolder?: string;

  @IsBoolean()
  @IsOptional()
  preview?: boolean;
}

/**
 * DTO for duplicate detection options
 */
export class FindDuplicatesDto {
  @IsString()
  @IsOptional()
  mediaType?: 'text' | 'image' | 'audio' | 'all';

  @IsOptional()
  threshold?: number;
}
