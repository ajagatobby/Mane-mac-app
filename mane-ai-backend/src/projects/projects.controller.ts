import {
  Controller,
  Post,
  Get,
  Delete,
  Body,
  Param,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { ProjectsService } from './projects.service';
import {
  IndexProjectDto,
  SearchProjectsDto,
  ScanDirectoryDto,
  ProjectResponseDto,
  ProjectListResponseDto,
  IndexProjectResponseDto,
  ScanDirectoryResponseDto,
  BatchIndexResponseDto,
} from './dto/project.dto';

@Controller('projects')
export class ProjectsController {
  private readonly logger = new Logger(ProjectsController.name);

  constructor(private readonly projectsService: ProjectsService) {}

  /**
   * Index a folder as a project (quick mode by default)
   * POST /projects/index
   * Set quickMode: false for LLM-powered analysis (slower but more detailed)
   */
  @Post('index')
  async indexProject(@Body() dto: IndexProjectDto): Promise<IndexProjectResponseDto> {
    this.logger.log(`Index project request: ${dto.folderPath} (quickMode: ${dto.quickMode !== false})`);
    return this.projectsService.indexProject(dto);
  }

  /**
   * Index a folder with full LLM analysis (slower but more detailed)
   * POST /projects/analyze
   */
  @Post('analyze')
  async analyzeProject(@Body() dto: IndexProjectDto): Promise<IndexProjectResponseDto> {
    this.logger.log(`Analyze project request: ${dto.folderPath}`);
    return this.projectsService.indexProjectWithAnalysis(dto);
  }

  /**
   * Detect if a folder contains a codebase
   * POST /projects/detect
   */
  @Post('detect')
  async detectCodebase(
    @Body() body: { folderPath: string },
  ): Promise<{ isCodebase: boolean; type?: string; techStack?: string[] }> {
    this.logger.log(`Detect codebase request: ${body.folderPath}`);
    return this.projectsService.detectCodebase(body.folderPath);
  }

  /**
   * List all projects
   * GET /projects
   */
  @Get()
  async listProjects(): Promise<ProjectListResponseDto> {
    return this.projectsService.listProjects();
  }

  /**
   * Get project by ID
   * GET /projects/:id
   */
  @Get(':id')
  async getProject(@Param('id') id: string): Promise<ProjectResponseDto> {
    const project = await this.projectsService.getProject(id);
    if (!project) {
      throw new HttpException('Project not found', HttpStatus.NOT_FOUND);
    }
    return project;
  }

  /**
   * Delete a project
   * DELETE /projects/:id
   */
  @Delete(':id')
  async deleteProject(
    @Param('id') id: string,
  ): Promise<{ success: boolean; message: string }> {
    return this.projectsService.deleteProject(id);
  }

  /**
   * Search projects
   * POST /projects/search
   */
  @Post('search')
  async searchProjects(@Body() dto: SearchProjectsDto): Promise<ProjectResponseDto[]> {
    return this.projectsService.searchProjects(dto.query, dto.limit);
  }

  /**
   * Scan a directory to discover all codebases
   * POST /projects/scan
   */
  @Post('scan')
  async scanDirectory(@Body() dto: ScanDirectoryDto): Promise<ScanDirectoryResponseDto> {
    this.logger.log(`Scan directory request: ${dto.folderPath}`);
    return this.projectsService.scanDirectory(dto.folderPath, dto.maxDepth);
  }

  /**
   * Scan a directory and index all discovered codebases
   * POST /projects/scan-and-index
   */
  @Post('scan-and-index')
  async scanAndIndexAll(
    @Body() body: { folderPath: string; maxDepth?: number; quickMode?: boolean },
  ): Promise<BatchIndexResponseDto> {
    this.logger.log(`Scan and index request: ${body.folderPath}`);
    return this.projectsService.scanAndIndexAll(
      body.folderPath,
      body.maxDepth ?? 3,
      body.quickMode !== false,
    );
  }
}
