import { Module } from '@nestjs/common';
import { TranscribeController } from './transcribe.controller';
import { TranscribeService } from './transcribe.service';
import { MultimodalModule } from '../multimodal';

@Module({
  imports: [MultimodalModule],
  controllers: [TranscribeController],
  providers: [TranscribeService],
  exports: [TranscribeService],
})
export class TranscribeModule {}
