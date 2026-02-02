import {
  Injectable,
  Logger,
  OnModuleInit,
  Inject,
  forwardRef,
} from '@nestjs/common';
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

    // Get document stats for count queries
    const stats = await this.getDocumentStats();

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

    // Create the RAG prompt with stats
    const systemPrompt = this.createSystemPrompt(context, stats);

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

  async *chatStream(
    query: string,
    documentIds?: string[],
  ): AsyncGenerator<
    StreamChunk & {
      sources?: Array<{
        fileName: string;
        filePath: string;
        mediaType: string;
      }>;
    },
    void,
    unknown
  > {
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

    // Get document stats for count queries
    const stats = await this.getDocumentStats();

    // Search for relevant documents (text + media)
    // If documentIds are provided, filter to only those documents
    this.logger.log('Searching for relevant context...');
    const searchResults = await this.searchAllDocuments(query, 5, documentIds);

    // Build context from search results
    const context = this.buildContext(searchResults);

    // Extract only high-confidence sources (score >= 0.3) - important for quality
    // Deduplicate by filePath and limit to top 5
    const MIN_CONFIDENCE_SCORE = 0.3;
    const MAX_SOURCES = 5;

    const seenPaths = new Set<string>();
    const sources = searchResults
      .filter((r) => r.score >= MIN_CONFIDENCE_SCORE)
      .filter((r) => {
        if (seenPaths.has(r.filePath)) return false;
        seenPaths.add(r.filePath);
        return true;
      })
      .slice(0, MAX_SOURCES)
      .map((r) => ({
        fileName: r.fileName,
        filePath: r.filePath,
        mediaType: r.mediaType || 'text',
      }));

    // Create the RAG prompt with stats (adjust for filtered search)
    const systemPrompt = documentIds?.length
      ? this.createDocumentFocusedPrompt(context)
      : this.createSystemPrompt(context, stats);

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

      // Send sources with the final done message
      yield { content: '', done: true, sources };
      this.logger.log('Streaming completed');
    } catch (error: any) {
      this.logger.error('Error streaming from Ollama:', error.message);
      this.isOllamaAvailable = false;
      throw new Error(`Failed to stream from Ollama: ${error.message}`);
    }
  }

  /**
   * Search documents using MiniLM (384-dim) for text/audio/image captions
   * @param query - The search query
   * @param limit - Maximum number of results
   * @param documentIds - Optional array of document IDs to filter to
   */
  private async searchAllDocuments(
    query: string,
    limit: number,
    documentIds?: string[],
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
      const results = await this.lanceDBService.hybridSearch(
        query,
        limit,
        documentIds,
      );
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

  /**
   * Get document statistics from the database
   */
  private async getDocumentStats(): Promise<{
    total: number;
    byType: { text: number; image: number; audio: number };
  }> {
    try {
      const documents = await this.lanceDBService.getUniqueDocuments();
      const stats = {
        total: documents.length,
        byType: { text: 0, image: 0, audio: 0 },
      };

      for (const doc of documents) {
        const type = (doc.mediaType as 'text' | 'image' | 'audio') || 'text';
        if (type in stats.byType) {
          stats.byType[type]++;
        }
      }

      return stats;
    } catch (error) {
      return { total: 0, byType: { text: 0, image: 0, audio: 0 } };
    }
  }

  private createSystemPrompt(
    context: string,
    stats: {
      total: number;
      byType: { text: number; image: number; audio: number };
    },
  ): string {
    return `You are a helpful AI assistant that answers questions about the user's files.

KNOWLEDGE BASE STATISTICS:
- Total documents: ${stats.total}
- Text documents: ${stats.byType.text}
- Images: ${stats.byType.image}
- Audio files: ${stats.byType.audio}

RELEVANT DOCUMENTS (showing up to 5 most relevant):
${context}

INSTRUCTIONS:
1. Answer the user's question directly based on the context above.
2. When asked "how many files/documents" use the KNOWLEDGE BASE STATISTICS above.
3. Cite which document(s) you're referencing when relevant.
4. If the context doesn't contain enough information, say so.
5. Be concise. Do NOT suggest how to organize files.`;
  }

  /**
   * Create a system prompt focused on a specific document
   * Used when documentIds filter is provided (tool mode)
   */
  private createDocumentFocusedPrompt(context: string): string {
    return `You are a helpful AI assistant. You MUST ONLY answer based on the document content provided below.

DOCUMENT CONTENT:
${context}

CRITICAL INSTRUCTIONS:
1. ONLY use information from the document above to answer.
2. Do NOT use any external knowledge or information from other documents.
3. If the user's question cannot be answered from this document alone, say so clearly.
4. When summarizing, cover all main points from the document.
5. Be thorough and accurate in your response.`;
  }

  getStatus(): { available: boolean; model: string; url: string } {
    return {
      available: this.isOllamaAvailable,
      model: this.configService.getOllamaModel(),
      url: this.configService.getOllamaUrl(),
    };
  }
}
