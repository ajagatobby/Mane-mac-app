import { Injectable, Logger, OnModuleInit, Inject, forwardRef } from '@nestjs/common';
import { ConfigService } from '../config';
import { LanceDBService } from '../lancedb';
import { MultimodalService } from '../multimodal';
import { ChatOllama } from '@langchain/ollama';
import { HumanMessage, SystemMessage } from '@langchain/core/messages';

type MediaType = 'text' | 'image' | 'audio';

interface ChatResponse {
  answer: string;
  sources: Array<{
    fileName: string;
    filePath: string;
    mediaType: MediaType;
    thumbnailPath?: string;
    relevance: number;
  }>;
}

interface StreamChunk {
  content: string;
  done: boolean;
}

@Injectable()
export class OllamaService implements OnModuleInit {
  private readonly logger = new Logger(OllamaService.name);
  private chatModel: ChatOllama | null = null;
  private isOllamaAvailable = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly lanceDBService: LanceDBService,
    @Inject(forwardRef(() => MultimodalService))
    private readonly multimodalService: MultimodalService,
  ) {}

  async onModuleInit() {
    await this.initialize();
  }

  private async initialize(): Promise<void> {
    const ollamaUrl = this.configService.getOllamaUrl();
    const ollamaModel = this.configService.getOllamaModel();

    this.chatModel = new ChatOllama({
      baseUrl: ollamaUrl,
      model: ollamaModel,
      temperature: 0.7,
    });

    // Check if Ollama is available
    await this.checkOllamaHealth();
  }

  async checkOllamaHealth(): Promise<boolean> {
    try {
      const ollamaUrl = this.configService.getOllamaUrl();
      const response = await fetch(`${ollamaUrl}/api/tags`);
      this.isOllamaAvailable = response.ok;

      if (this.isOllamaAvailable) {
        this.logger.log('Ollama is available and ready');
      } else {
        this.logger.warn('Ollama is not responding properly');
      }

      return this.isOllamaAvailable;
    } catch (error) {
      this.logger.warn(
        'Ollama is not available. Please ensure Ollama is running.',
      );
      this.isOllamaAvailable = false;
      return false;
    }
  }

  async chat(query: string): Promise<ChatResponse> {
    if (!this.chatModel) {
      throw new Error('Chat model not initialized');
    }

    // Check Ollama availability
    if (!this.isOllamaAvailable) {
      await this.checkOllamaHealth();
      if (!this.isOllamaAvailable) {
        throw new Error(
          'Ollama is not available. Please ensure Ollama is running with: ollama serve',
        );
      }
    }

    // Search for relevant documents (text + media)
    this.logger.log('Searching for relevant context...');
    const searchResults = await this.searchAllDocuments(query, 5);

    // Build context from search results
    const context = this.buildContext(searchResults);
    const sources = searchResults.map((r) => ({
      fileName: r.fileName,
      filePath: r.filePath,
      mediaType: (r.mediaType as MediaType) || 'text',
      thumbnailPath: r.thumbnailPath,
      relevance: r.score,
    }));

    // Create the RAG prompt
    const systemPrompt = this.createSystemPrompt(context);

    this.logger.log('Sending query to Ollama...');
    const messages = [new SystemMessage(systemPrompt), new HumanMessage(query)];

    try {
      const response = await this.chatModel.invoke(messages);
      const answer =
        typeof response.content === 'string'
          ? response.content
          : JSON.stringify(response.content);

      this.logger.log('Response received from Ollama');

      return {
        answer,
        sources,
      };
    } catch (error: any) {
      this.logger.error('Error calling Ollama:', error.message);
      this.isOllamaAvailable = false;
      throw new Error(`Failed to get response from Ollama: ${error.message}`);
    }
  }

  async *chatStream(query: string): AsyncGenerator<StreamChunk, void, unknown> {
    if (!this.chatModel) {
      throw new Error('Chat model not initialized');
    }

    // Check Ollama availability
    if (!this.isOllamaAvailable) {
      await this.checkOllamaHealth();
      if (!this.isOllamaAvailable) {
        throw new Error(
          'Ollama is not available. Please ensure Ollama is running with: ollama serve',
        );
      }
    }

    // Search for relevant documents (text + media)
    this.logger.log('Searching for relevant context...');
    const searchResults = await this.searchAllDocuments(query, 5);

    // Build context from search results
    const context = this.buildContext(searchResults);

    // Create the RAG prompt
    const systemPrompt = this.createSystemPrompt(context);

    this.logger.log('Starting streaming response from Ollama...');
    const messages = [new SystemMessage(systemPrompt), new HumanMessage(query)];

    try {
      const stream = await this.chatModel.stream(messages);

      for await (const chunk of stream) {
        const content =
          typeof chunk.content === 'string'
            ? chunk.content
            : JSON.stringify(chunk.content);

        yield { content, done: false };
      }

      yield { content: '', done: true };
      this.logger.log('Streaming completed');
    } catch (error: any) {
      this.logger.error('Error streaming from Ollama:', error.message);
      this.isOllamaAvailable = false;
      throw new Error(`Failed to stream from Ollama: ${error.message}`);
    }
  }

  /**
   * Search documents using MiniLM (384-dim) for text/audio/image captions
   */
  private async searchAllDocuments(
    query: string,
    limit: number,
  ): Promise<
    Array<{
      id: string;
      content: string;
      filePath: string;
      fileName: string;
      mediaType: string;
      thumbnailPath?: string;
      metadata: Record<string, unknown>;
      score: number;
    }>
  > {
    this.logger.log('Searching documents with MiniLM...');

    try {
      const results = await this.lanceDBService.hybridSearch(query, limit);
      this.logger.log(`Found ${results.length} results`);
      return results;
    } catch (err: any) {
      this.logger.warn(`Search failed: ${err.message}`);
      return [];
    }
  }

  private buildContext(
    searchResults: Array<{
      fileName: string;
      content: string;
      mediaType?: string;
      score: number;
    }>,
  ): string {
    if (searchResults.length === 0) {
      return 'No relevant documents found in the knowledge base.';
    }

    const contextParts = searchResults.map((result, index) => {
      const mediaType = result.mediaType || 'text';

      // For media files, describe them instead of showing content
      if (mediaType === 'image') {
        return `[Image ${index + 1}: ${result.fileName}]\nThis is an image file located at: ${result.content}`;
      } else if (mediaType === 'audio') {
        // Audio has transcript in content
        const maxLength = 1000;
        const content =
          result.content.length > maxLength
            ? result.content.substring(0, maxLength) + '...'
            : result.content;
        return `[Audio ${index + 1}: ${result.fileName}]\nTranscript: ${content}`;
      }

      // Text documents
      const maxLength = 1000;
      const content =
        result.content.length > maxLength
          ? result.content.substring(0, maxLength) + '...'
          : result.content;

      return `[Document ${index + 1}: ${result.fileName}]\n${content}`;
    });

    return contextParts.join('\n\n---\n\n');
  }

  private createSystemPrompt(context: string): string {
    return `You are a helpful AI assistant that helps users organize and understand their files. 
You have access to the user's document library and can answer questions based on the content of their files.

CONTEXT FROM USER'S DOCUMENTS:
${context}

INSTRUCTIONS:
1. Answer the user's question based primarily on the context provided above.
2. If the context contains relevant information, cite which document(s) you're referencing.
3. If the context doesn't contain enough information to fully answer the question, say so clearly.
4. Be concise but thorough in your responses.
5. If asked about file organization, provide practical suggestions based on the documents you see.

Remember: You're helping the user understand and organize THEIR files, so be specific and actionable.`;
  }

  getStatus(): { available: boolean; model: string; url: string } {
    return {
      available: this.isOllamaAvailable,
      model: this.configService.getOllamaModel(),
      url: this.configService.getOllamaUrl(),
    };
  }
}
