import { Module } from '@nestjs/common';
import { IngestController } from './ingest.controller';
import { IngestService } from './ingest.service';
import { LanceDBModule } from '../lancedb';
import { MultimodalModule } from '../multimodal';
import { ImageCaptioningModule } from '../image-captioning';

@Module({
  imports: [LanceDBModule, MultimodalModule, ImageCaptioningModule],
  controllers: [IngestController],
  providers: [IngestService],
  exports: [IngestService],
})
export class IngestModule {}
