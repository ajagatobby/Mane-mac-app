import { Module } from '@nestjs/common';
import { ProjectsController } from './projects.controller';
import { ProjectsService } from './projects.service';
import { CodebaseAnalyzerService } from './codebase-analyzer.service';
import { LanceDBModule } from '../lancedb';
import { ConfigModule } from '../config';

@Module({
  imports: [LanceDBModule, ConfigModule],
  controllers: [ProjectsController],
  providers: [ProjectsService, CodebaseAnalyzerService],
  exports: [ProjectsService, CodebaseAnalyzerService],
})
export class ProjectsModule {}
