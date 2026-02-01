import { Injectable, Logger } from '@nestjs/common';
import { AgentTool, ToolParameter, ToolResult } from './tool.interface';
import { LanceDBService, SearchResult } from '../../lancedb';

/**
 * FindFiles Tool
 * Performs semantic search across indexed documents
 */
@Injectable()
export class FindFilesTool implements AgentTool {
  private readonly logger = new Logger(FindFilesTool.name);

  readonly name = 'findFiles';

  readonly description =
    'Search for files based on their content or description. ' +
    'Use this to find files containing specific topics, objects, or text. ' +
    'For images, searches through their AI-generated descriptions. ' +
    'Returns matching file paths with relevance scores.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'query',
      type: 'string',
      description:
        'Semantic search query describing what to find (e.g., "images of cats", "tax documents from 2023", "vacation photos")',
      required: true,
    },
    {
      name: 'limit',
      type: 'number',
      description: 'Maximum number of results to return (default: 10)',
      required: false,
    },
    {
      name: 'mediaType',
      type: 'string',
      description:
        'Filter by media type: "text", "image", "audio", or "all" (default: "all")',
      required: false,
    },
  ];

  constructor(private readonly lanceDBService: LanceDBService) {}

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const query = params.query as string;
    const limit = (params.limit as number) || 10;
    const mediaType = (params.mediaType as string) || 'all';

    if (!query) {
      return {
        success: false,
        error: 'Query parameter is required',
      };
    }

    try {
      this.logger.log(`Searching for: "${query}" (limit: ${limit}, type: ${mediaType})`);

      // Perform hybrid search
      const results = await this.lanceDBService.hybridSearch(query, limit * 2);

      // Filter by media type if specified
      let filteredResults: SearchResult[] = results;
      if (mediaType !== 'all') {
        filteredResults = results.filter((r) => r.mediaType === mediaType);
      }

      // Limit results
      filteredResults = filteredResults.slice(0, limit);

      this.logger.log(`Found ${filteredResults.length} matching files`);

      // Format results for the agent
      const formattedResults = filteredResults.map((r) => ({
        filePath: r.filePath,
        fileName: r.fileName,
        mediaType: r.mediaType,
        relevance: Math.round(r.score * 100) / 100,
        preview:
          r.content.length > 200
            ? r.content.substring(0, 200) + '...'
            : r.content,
      }));

      return {
        success: true,
        data: {
          query,
          totalFound: filteredResults.length,
          files: formattedResults,
        },
      };
    } catch (error: any) {
      this.logger.error(`Search failed: ${error.message}`);
      return {
        success: false,
        error: `Search failed: ${error.message}`,
      };
    }
  }
}
