import { Module, forwardRef } from '@nestjs/common';
import { OllamaService } from './ollama.service';
import { LanceDBModule } from '../lancedb';
import { MultimodalModule } from '../multimodal';

@Module({
  imports: [LanceDBModule, forwardRef(() => MultimodalModule)],
  providers: [OllamaService],
  exports: [OllamaService],
})
export class OllamaModule {}
