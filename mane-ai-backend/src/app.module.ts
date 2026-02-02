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
import { ProjectsModule } from './projects';
import { TranscribeModule } from './transcribe';

@Module({
  imports: [
    ConfigModule,
    LanceDBModule,
    OllamaModule,
    MultimodalModule,
    ImageCaptioningModule,
    IngestModule,
    ChatModule,
    ProjectsModule,
    TranscribeModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
