import {
  Controller,
  Post,
  Get,
  Body,
  Res,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { Response } from 'express';
import { ChatService } from './chat.service';
import {
  ChatQueryDto,
  ChatResponseDto,
  SearchQueryDto,
  SearchResponseDto,
} from './dto/chat.dto';

@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async chat(
    @Body() dto: ChatQueryDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<ChatResponseDto | void> {
    if (dto.stream) {
      // Set headers for Server-Sent Events
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no');

      try {
        for await (const chunk of this.chatService.chatStream(dto)) {
          if (chunk.done) {
            // Include sources in the final message
            res.write(`data: ${JSON.stringify({ done: true, sources: chunk.sources || [] })}\n\n`);
          } else {
            res.write(
              `data: ${JSON.stringify({ content: chunk.content })}\n\n`,
            );
          }
        }
      } catch (error: any) {
        res.write(
          `data: ${JSON.stringify({ error: error.message, done: true })}\n\n`,
        );
      }

      res.end();
      return;
    }

    // Non-streaming response
    return this.chatService.chat(dto);
  }

  @Post('search')
  @HttpCode(HttpStatus.OK)
  async search(@Body() dto: SearchQueryDto): Promise<SearchResponseDto> {
    return this.chatService.search(dto);
  }

  @Get('status')
  @HttpCode(HttpStatus.OK)
  getStatus(): { available: boolean; model: string; url: string } {
    return this.chatService.getOllamaStatus();
  }
}
