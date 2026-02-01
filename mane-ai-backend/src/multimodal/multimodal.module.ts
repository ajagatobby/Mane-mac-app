import { Module } from '@nestjs/common';
import { MultimodalService } from './multimodal.service';

@Module({
  providers: [MultimodalService],
  exports: [MultimodalService],
})
export class MultimodalModule {}
