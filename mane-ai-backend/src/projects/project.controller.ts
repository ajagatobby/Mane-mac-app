import {
  Controller,
  Post,
  Get,
  Delete,
  Body,
  Param,
  Query,
  HttpStatus,
  HttpException,
} from '@nestjs/common';
import { ProjectService } from './project.service';
import {
  IndexProjectDto,
  ReindexProjectDto,
  SearchProjectsDto,
  SearchCodeDto,
  UnifiedSearchDto,
} from './dto';

@Controller('projects')
export class ProjectController {
  constructor(private readonly projectService: ProjectService) {}

  /**
   * Index a new project
   */
  @Post('index')
  async indexProject(@Body() dto: IndexProjectDto) {
    try {
      const project = await this.projectService.indexProject(dto.path, {
        maxDepth: dto.maxDepth,
        maxFiles: dto.maxFiles,
        skipSkeletons: dto.skipSkeletons,
        customIgnoreDirs: dto.customIgnoreDirs,
        customIgnoreFiles: dto.customIgnoreFiles,
        customIgnoreExtensions: dto.customIgnoreExtensions,
        includeTests: dto.includeTests,
      });

      return {
        success: true,
        project,
        message: `Project "${project.name}" indexed successfully`,
      };
    } catch (error: any) {
      throw new HttpException(
        `Failed to index project: ${error.message}`,
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * Re-index an existing project
   */
  @Post(':id/reindex')
  async reindexProject(
    @Param('id') id: string,
    @Body() dto: ReindexProjectDto,
  ) {
    try {
      const project = await this.projectService.reindexProject(id, {
        maxDepth: dto.maxDepth,
        maxFiles: dto.maxFiles,
        skipSkeletons: dto.skipSkeletons,
        customIgnoreDirs: dto.customIgnoreDirs,
        customIgnoreFiles: dto.customIgnoreFiles,
        customIgnoreExtensions: dto.customIgnoreExtensions,
        includeTests: dto.includeTests,
      });

      return {
        success: true,
        project,
        message: `Project "${project.name}" re-indexed successfully`,
      };
    } catch (error: any) {
      throw new HttpException(
        `Failed to re-index project: ${error.message}`,
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * List all indexed projects
   */
  @Get()
  async listProjects() {
    const projects = await this.projectService.listProjects();

    return {
      success: true,
      count: projects.length,
      projects,
    };
  }

  /**
   * Get project by ID
   */
  @Get(':id')
  async getProject(@Param('id') id: string) {
    const project = await this.projectService.getProject(id);

    if (!project) {
      throw new HttpException('Project not found', HttpStatus.NOT_FOUND);
    }

    return {
      success: true,
      project,
    };
  }

  /**
   * Delete a project
   */
  @Delete(':id')
  async deleteProject(@Param('id') id: string) {
    const project = await this.projectService.getProject(id);

    if (!project) {
      throw new HttpException('Project not found', HttpStatus.NOT_FOUND);
    }

    await this.projectService.deleteProject(id);

    return {
      success: true,
      message: `Project "${project.name}" deleted`,
    };
  }

  /**
   * Search projects
   */
  @Post('search')
  async searchProjects(@Body() dto: SearchProjectsDto) {
    const projects = await this.projectService.searchProjects(
      dto.query,
      dto.limit || 10,
    );

    return {
      success: true,
      query: dto.query,
      count: projects.length,
      projects,
    };
  }

  /**
   * Search code skeletons
   */
  @Post('search/code')
  async searchCode(@Body() dto: SearchCodeDto) {
    const skeletons = await this.projectService.searchCode(
      dto.query,
      dto.limit || 10,
      dto.projectId,
    );

    return {
      success: true,
      query: dto.query,
      count: skeletons.length,
      skeletons,
    };
  }

  /**
   * Unified search across projects and code
   */
  @Post('search/unified')
  async unifiedSearch(@Body() dto: UnifiedSearchDto) {
    const results = await this.projectService.unifiedSearch(dto.query, {
      projectLimit: dto.projectLimit,
      codeLimit: dto.codeLimit,
      projectId: dto.projectId,
    });

    return {
      success: true,
      query: dto.query,
      results,
    };
  }

  /**
   * Get skeletons for a specific project
   */
  @Get(':id/skeletons')
  async getProjectSkeletons(
    @Param('id') id: string,
    @Query('limit') limit?: string,
  ) {
    const project = await this.projectService.getProject(id);

    if (!project) {
      throw new HttpException('Project not found', HttpStatus.NOT_FOUND);
    }

    const skeletons = await this.projectService.getProjectSkeletons(id);
    const limitNum = limit ? parseInt(limit, 10) : undefined;

    return {
      success: true,
      projectId: id,
      projectName: project.name,
      count: skeletons.length,
      skeletons: limitNum ? skeletons.slice(0, limitNum) : skeletons,
    };
  }

  /**
   * Get project statistics
   */
  @Get('stats/overview')
  async getStats() {
    const stats = await this.projectService.getStats();

    return {
      success: true,
      stats,
    };
  }

  /**
   * Get default ignore patterns
   */
  @Get('ignore-patterns')
  async getIgnorePatterns() {
    const patterns = this.projectService.getDefaultIgnorePatterns();

    return {
      success: true,
      patterns,
    };
  }
}
