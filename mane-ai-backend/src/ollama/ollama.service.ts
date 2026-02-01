import { Injectable, Logger, OnModuleInit, Inject, forwardRef } from '@nestjs/common';
import { ConfigService } from '../config';
import { LanceDBService } from '../lancedb';
import { MultimodalService } from '../multimodal';
import { ChatOllama } from '@langchain/ollama';
import { HumanMessage, SystemMessage } from '@langchain/core/messages';

type MediaType = 'text' | 'image' | 'audio' | 'video';

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
   * Search both text and media documents using PARALLEL inference
   * 
   * This runs two embedding models in parallel:
   * 1. MiniLM (384-dim) for text/audio transcripts in documents_text
   * 2. CLIP Text Encoder (512-dim) for images/videos in documents_media
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
    type SearchResult = {
      id: string;
      content: string;
      filePath: string;
      fileName: string;
      mediaType: string;
      thumbnailPath?: string;
      metadata: Record<string, unknown>;
      score: number;
    };

    // Run BOTH embedding models in PARALLEL
    this.logger.log('Running parallel search (MiniLM + CLIP)...');

    const hasMedia = await this.lanceDBService.hasMediaDocuments();

    // Prepare parallel tasks
    const searchTasks: Promise<SearchResult[]>[] = [];

    // Task 1: Text search with MiniLM (384-dim)
    searchTasks.push(
      this.lanceDBService.hybridSearch(query, limit).catch((err) => {
        this.logger.warn(`Text search failed: ${err.message}`);
        return [] as SearchResult[];
      }),
    );

    // Task 2: Media search with CLIP (512-dim) - only if media exists
    if (hasMedia) {
      searchTasks.push(
        (async () => {
          try {
            this.logger.log('Embedding query with CLIP for media search...');
            const clipTextVector =
              await this.multimodalService.embedTextWithClip(query);
            return await this.lanceDBService.searchMedia(clipTextVector, limit);
          } catch (err: any) {
            this.logger.warn(`Media search failed: ${err.message}`);
            return [] as SearchResult[];
          }
        })(),
      );
    }

    // Execute both searches in parallel
    const results = await Promise.all(searchTasks);

    // Flatten results
    const textResults = results[0] || [];
    const mediaResults = results[1] || [];

    this.logger.log(
      `Found ${textResults.length} text + ${mediaResults.length} media results`,
    );

    // Merge and normalize scores
    // CLIP and MiniLM use different score scales, so we normalize
    const allResults: SearchResult[] = [];

    // Add text results (MiniLM scores are typically 0-1)
    for (const r of textResults) {
      allResults.push({
        ...r,
        score: r.score, // Already normalized
      });
    }

    // Add media results (CLIP cosine similarity can be -1 to 1)
    for (const r of mediaResults) {
      allResults.push({
        ...r,
        // Normalize CLIP scores to 0-1 range: (score + 1) / 2
        score: (r.score + 1) / 2,
      });
    }

    // Sort by normalized score and return top results
    return allResults.sort((a, b) => b.score - a.score).slice(0, limit);
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
      } else if (mediaType === 'video') {
        return `[Video ${index + 1}: ${result.fileName}]\nThis is a video file located at: ${result.content}`;
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
