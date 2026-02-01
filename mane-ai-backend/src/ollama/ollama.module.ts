import { Module } from '@nestjs/common';
import { OllamaService } from './ollama.service';
import { LanceDBModule } from '../lancedb';

@Module({
  imports: [LanceDBModule],
  providers: [OllamaService],
  exports: [OllamaService],
})
export class OllamaModule {}
