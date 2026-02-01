import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ConfigModule } from './config';
import { LanceDBModule } from './lancedb';
import { OllamaModule } from './ollama';
import { IngestModule } from './ingest';
import { ChatModule } from './chat';
import { MultimodalModule } from './multimodal';
import { ImageCaptioningModule } from './image-captioning';
import { ProjectModule } from './projects';

@Module({
  imports: [
    ConfigModule,
    LanceDBModule,
    OllamaModule,
    MultimodalModule,
    ImageCaptioningModule,
    IngestModule,
    ChatModule,
    ProjectModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
