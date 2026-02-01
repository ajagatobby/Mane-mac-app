import { Injectable, Logger } from '@nestjs/common';
import { OllamaService } from '../ollama';
import { LanceDBService } from '../lancedb';
import {
  ChatQueryDto,
  ChatResponseDto,
  SearchQueryDto,
  SearchResponseDto,
} from './dto/chat.dto';

@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);

  constructor(
    private readonly ollamaService: OllamaService,
    private readonly lanceDBService: LanceDBService,
  ) {}

  async chat(dto: ChatQueryDto): Promise<ChatResponseDto> {
    this.logger.log(`Processing chat query: ${dto.query.substring(0, 50)}...`);
    return this.ollamaService.chat(dto.query);
  }

  async *chatStream(
    dto: ChatQueryDto,
  ): AsyncGenerator<{ content: string; done: boolean }, void, unknown> {
    this.logger.log(
      `Processing streaming chat query: ${dto.query.substring(0, 50)}...`,
    );
    yield* this.ollamaService.chatStream(dto.query);
  }

  async search(dto: SearchQueryDto): Promise<SearchResponseDto> {
    this.logger.log(
      `Processing search query: ${dto.query.substring(0, 50)}...`,
    );
    const results = await this.lanceDBService.hybridSearch(
      dto.query,
      dto.limit || 5,
    );

    return {
      results: results.map((r) => ({
        id: r.id,
        content: r.content.substring(0, 500), // Truncate for response
        fileName: r.fileName,
        filePath: r.filePath,
        score: r.score,
      })),
    };
  }

  getOllamaStatus(): { available: boolean; model: string; url: string } {
    return this.ollamaService.getStatus();
  }
}
