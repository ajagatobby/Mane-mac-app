import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ConfigModule } from './config';
import { LanceDBModule } from './lancedb';
import { OllamaModule } from './ollama';
import { IngestModule } from './ingest';
import { ChatModule } from './chat';
import { MultimodalModule } from './multimodal';

@Module({
  imports: [
    ConfigModule,
    LanceDBModule,
    OllamaModule,
    MultimodalModule,
    IngestModule,
    ChatModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
