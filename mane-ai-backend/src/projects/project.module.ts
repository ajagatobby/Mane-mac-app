import { Module } from '@nestjs/common';
import { ProjectController } from './project.controller';
import { ProjectService } from './project.service';
import { ManifestScannerService } from './services/manifest-scanner.service';
import { SkeletonExtractorService } from './services/skeleton-extractor.service';
import { LanceDBModule } from '../lancedb';
import { ConfigModule } from '../config';

@Module({
  imports: [ConfigModule, LanceDBModule],
  controllers: [ProjectController],
  providers: [
    ProjectService,
    ManifestScannerService,
    SkeletonExtractorService,
  ],
  exports: [ProjectService],
})
export class ProjectModule {}
