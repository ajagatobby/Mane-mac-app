import { Injectable } from '@nestjs/common';
import * as path from 'path';
import * as os from 'os';

@Injectable()
export class ConfigService {
  private readonly dbPath: string;
  private readonly ollamaUrl: string;
  private readonly ollamaModel: string;
  private readonly port: number;

  constructor() {
    // Parse command line arguments
    const args = process.argv.slice(2);
    const dbPathIndex = args.indexOf('--db-path');
    const ollamaUrlIndex = args.indexOf('--ollama-url');
    const ollamaModelIndex = args.indexOf('--ollama-model');
    const portIndex = args.indexOf('--port');

    // Default to user's home directory if no path provided
    const defaultDbPath = path.join(
      os.homedir(),
      'Library',
      'Application Support',
      'ManeAI',
      'lancedb',
    );

    this.dbPath =
      dbPathIndex !== -1 && args[dbPathIndex + 1]
        ? args[dbPathIndex + 1]
        : defaultDbPath;

    this.ollamaUrl =
      ollamaUrlIndex !== -1 && args[ollamaUrlIndex + 1]
        ? args[ollamaUrlIndex + 1]
        : 'http://localhost:11434';

    this.ollamaModel =
      ollamaModelIndex !== -1 && args[ollamaModelIndex + 1]
        ? args[ollamaModelIndex + 1]
        : 'qwen2.5';

    this.port =
      portIndex !== -1 && args[portIndex + 1]
        ? parseInt(args[portIndex + 1], 10)
        : 3000;

    console.log(`[ConfigService] Database path: ${this.dbPath}`);
    console.log(`[ConfigService] Ollama URL: ${this.ollamaUrl}`);
    console.log(`[ConfigService] Ollama Model: ${this.ollamaModel}`);
    console.log(`[ConfigService] Port: ${this.port}`);
  }

  getDbPath(): string {
    return this.dbPath;
  }

  getOllamaUrl(): string {
    return this.ollamaUrl;
  }

  getOllamaModel(): string {
    return this.ollamaModel;
  }

  getPort(): number {
    return this.port;
  }
}
