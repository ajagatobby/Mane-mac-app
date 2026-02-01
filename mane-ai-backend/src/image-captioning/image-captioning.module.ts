import { Module } from '@nestjs/common';
import { ImageCaptioningService } from './image-captioning.service';
import { ConfigModule } from '../config';

@Module({
  imports: [ConfigModule],
  providers: [ImageCaptioningService],
  exports: [ImageCaptioningService],
})
export class ImageCaptioningModule {}
