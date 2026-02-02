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
  ): AsyncGenerator<{ content: string; done: boolean; sources?: Array<{ fileName: string; filePath: string; mediaType: string }> }, void, unknown> {
    this.logger.log(
      `Processing streaming chat query: ${dto.query.substring(0, 50)}...`,
    );
    if (dto.documentIds?.length) {
      this.logger.log(`Filtering to documents: ${dto.documentIds.join(', ')}`);
    }
    yield* this.ollamaService.chatStream(dto.query, dto.documentIds);
  }

  async search(dto: SearchQueryDto): Promise<SearchResponseDto> {
    this.logger.log(
      `Processing search query: ${dto.query.substring(0, 50)}...`,
    );
    
    // Use limit from DTO, default to 5. A value of 0 means return all results.
    const limit = dto.limit === undefined ? 5 : dto.limit;
    
    const results = await this.lanceDBService.hybridSearch(
      dto.query,
      limit,
    );

    return {
      results: results.map((r) => ({
        id: r.id,
        content:
          r.mediaType === 'text' || r.mediaType === 'audio'
            ? r.content.substring(0, 500)
            : r.content, // Don't truncate file paths
        fileName: r.fileName,
        filePath: r.filePath,
        mediaType: (r.mediaType as any) || 'text',
        thumbnailPath: r.thumbnailPath,
        score: r.score,
      })),
    };
  }

  getOllamaStatus(): { available: boolean; model: string; url: string } {
    return this.ollamaService.getStatus();
  }
}
