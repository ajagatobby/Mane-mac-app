import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Extracted code skeleton
 */
export interface CodeSkeleton {
  filePath: string;
  language: string;
  content: string; // Extracted signatures
}

/**
 * Language detection result
 */
interface LanguageInfo {
  language: string;
  extractor: (content: string) => string;
}

/**
 * Default ignore patterns for common irrelevant files/directories
 */
export const DEFAULT_IGNORE_PATTERNS = {
  // Package managers and dependencies
  directories: [
    'node_modules',
    'bower_components',
    'jspm_packages',
    'vendor',
    'packages',
    '.pnpm',

    // Version control
    '.git',
    '.svn',
    '.hg',
    '.bzr',

    // Build outputs
    'dist',
    'build',
    'out',
    'output',
    '_build',
    'target',
    'bin',
    'obj',

    // Cache directories
    '.cache',
    '.parcel-cache',
    '.turbo',
    '.nx',
    '__pycache__',
    '.pytest_cache',
    '.mypy_cache',
    '.ruff_cache',
    '.tox',

    // Framework specific
    '.next',
    '.nuxt',
    '.svelte-kit',
    '.vercel',
    '.netlify',
    '.serverless',

    // IDE/Editor
    '.vscode',
    '.idea',
    '.vs',
    '.eclipse',

    // Virtual environments
    'venv',
    'env',
    '.env',
    '.venv',
    'virtualenv',
    'conda-env',

    // Test coverage
    'coverage',
    '.nyc_output',
    'htmlcov',

    // Documentation
    'docs',
    '_docs',
    'documentation',

    // Logs
    'logs',
    'log',

    // Temporary
    'tmp',
    'temp',
    '.tmp',

    // OS specific
    '.DS_Store',
    'Thumbs.db',
  ],

  // File patterns to ignore
  files: [
    // Lock files
    'package-lock.json',
    'yarn.lock',
    'pnpm-lock.yaml',
    'Gemfile.lock',
    'Cargo.lock',
    'poetry.lock',
    'composer.lock',

    // Config files (usually not useful for code search)
    '.gitignore',
    '.gitattributes',
    '.npmrc',
    '.yarnrc',
    '.editorconfig',
    '.prettierrc',
    '.eslintrc',
    '.stylelintrc',
    'tsconfig.json',
    'jsconfig.json',
    'babel.config.js',
    'webpack.config.js',
    'rollup.config.js',
    'vite.config.js',
    'jest.config.js',
    'vitest.config.js',

    // Environment files
    '.env',
    '.env.local',
    '.env.development',
    '.env.production',
    '.env.test',

    // Minified/bundled files
    '*.min.js',
    '*.min.css',
    '*.bundle.js',
    '*.chunk.js',

    // Source maps
    '*.map',
    '*.js.map',
    '*.css.map',

    // Generated files
    '*.generated.ts',
    '*.generated.js',
    '*.d.ts',

    // Test files (optional - sometimes useful)
    '*.test.ts',
    '*.test.js',
    '*.spec.ts',
    '*.spec.js',
    '__tests__',
    '__mocks__',
  ],

  // File extensions to ignore
  extensions: [
    '.lock',
    '.log',
    '.map',
    '.min.js',
    '.min.css',
    '.svg',
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.ico',
    '.woff',
    '.woff2',
    '.ttf',
    '.eot',
    '.mp3',
    '.mp4',
    '.webm',
    '.pdf',
    '.zip',
    '.tar',
    '.gz',
    '.rar',
  ],
};

/**
 * SkeletonExtractor Service
 * Extracts function/class/interface signatures from code files
 * without including implementation details
 */
@Injectable()
export class SkeletonExtractorService {
  private readonly logger = new Logger(SkeletonExtractorService.name);

  // File extensions to language mapping
  private readonly extensionMap: Record<string, LanguageInfo> = {
    '.ts': {
      language: 'typescript',
      extractor: this.extractTypeScript.bind(this),
    },
    '.tsx': {
      language: 'typescript',
      extractor: this.extractTypeScript.bind(this),
    },
    '.js': {
      language: 'javascript',
      extractor: this.extractJavaScript.bind(this),
    },
    '.jsx': {
      language: 'javascript',
      extractor: this.extractJavaScript.bind(this),
    },
    '.mjs': {
      language: 'javascript',
      extractor: this.extractJavaScript.bind(this),
    },
    '.py': { language: 'python', extractor: this.extractPython.bind(this) },
    '.rs': { language: 'rust', extractor: this.extractRust.bind(this) },
    '.go': { language: 'go', extractor: this.extractGo.bind(this) },
    '.java': { language: 'java', extractor: this.extractJava.bind(this) },
    '.swift': { language: 'swift', extractor: this.extractSwift.bind(this) },
    '.rb': { language: 'ruby', extractor: this.extractRuby.bind(this) },
    '.php': { language: 'php', extractor: this.extractPHP.bind(this) },
  };

  // Default directories to skip (uses DEFAULT_IGNORE_PATTERNS)
  private skipDirs = new Set(DEFAULT_IGNORE_PATTERNS.directories);

  // Default files to skip
  private skipFiles = new Set(DEFAULT_IGNORE_PATTERNS.files);

  // Default extensions to skip
  private skipExtensions = new Set(DEFAULT_IGNORE_PATTERNS.extensions);

  /**
   * Extract skeletons from all code files in a project
   */
  async extractProjectSkeletons(
    projectPath: string,
    maxDepth: number = 5,
    maxFiles: number = 500,
    options: {
      customIgnoreDirs?: string[];
      customIgnoreFiles?: string[];
      customIgnoreExtensions?: string[];
      includeTests?: boolean;
    } = {},
  ): Promise<CodeSkeleton[]> {
    this.logger.log(`Extracting skeletons from: ${projectPath}`);
    const skeletons: CodeSkeleton[] = [];
    let fileCount = 0;

    // Build ignore sets with custom patterns
    const ignoreDirs = new Set([
      ...this.skipDirs,
      ...(options.customIgnoreDirs || []),
    ]);
    
    const ignoreFiles = new Set([
      ...this.skipFiles,
      ...(options.customIgnoreFiles || []),
    ]);
    
    const ignoreExtensions = new Set([
      ...this.skipExtensions,
      ...(options.customIgnoreExtensions || []),
    ]);

    // Optionally include test files
    if (options.includeTests) {
      ignoreFiles.delete('*.test.ts');
      ignoreFiles.delete('*.test.js');
      ignoreFiles.delete('*.spec.ts');
      ignoreFiles.delete('*.spec.js');
      ignoreFiles.delete('__tests__');
      ignoreFiles.delete('__mocks__');
    }

    const processDir = async (dir: string, depth: number) => {
      if (depth > maxDepth || fileCount >= maxFiles) return;

      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          if (fileCount >= maxFiles) break;

          const fullPath = path.join(dir, entry.name);

          if (entry.isDirectory()) {
            // Skip ignored directories
            if (!ignoreDirs.has(entry.name) && !entry.name.startsWith('.')) {
              await processDir(fullPath, depth + 1);
            }
          } else if (entry.isFile()) {
            // Skip ignored files
            if (this.shouldSkipFile(entry.name, ignoreFiles, ignoreExtensions)) {
              continue;
            }
            
            const skeleton = await this.extractFileSkeleton(fullPath);
            if (skeleton && skeleton.content.trim()) {
              skeletons.push(skeleton);
              fileCount++;
            }
          }
        }
      } catch (error) {
        // Ignore permission errors
      }
    };

    await processDir(projectPath, 0);
    this.logger.log(
      `Extracted ${skeletons.length} skeletons from ${fileCount} files`,
    );

    return skeletons;
  }

  /**
   * Check if a file should be skipped based on ignore patterns
   */
  private shouldSkipFile(
    fileName: string,
    ignoreFiles: Set<string>,
    ignoreExtensions: Set<string>,
  ): boolean {
    // Check exact file name match
    if (ignoreFiles.has(fileName)) {
      return true;
    }

    // Check extension
    const ext = path.extname(fileName).toLowerCase();
    if (ignoreExtensions.has(ext)) {
      return true;
    }

    // Check wildcard patterns (e.g., *.min.js)
    for (const pattern of ignoreFiles) {
      if (pattern.startsWith('*')) {
        const suffix = pattern.slice(1);
        if (fileName.endsWith(suffix)) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * Get the default ignore patterns (useful for UI display)
   */
  getDefaultIgnorePatterns(): typeof DEFAULT_IGNORE_PATTERNS {
    return DEFAULT_IGNORE_PATTERNS;
  }

  /**
   * Extract skeleton from a single file
   */
  async extractFileSkeleton(filePath: string): Promise<CodeSkeleton | null> {
    const ext = path.extname(filePath).toLowerCase();
    const langInfo = this.extensionMap[ext];

    if (!langInfo) {
      return null;
    }

    try {
      const content = fs.readFileSync(filePath, 'utf-8');

      // Skip very large files
      if (content.length > 100000) {
        this.logger.debug(`Skipping large file: ${filePath}`);
        return null;
      }

      const skeleton = langInfo.extractor(content);

      if (!skeleton.trim()) {
        return null;
      }

      return {
        filePath,
        language: langInfo.language,
        content: `// File: ${path.basename(filePath)}\n${skeleton}`,
      };
    } catch (error) {
      this.logger.debug(
        `Failed to extract skeleton from ${filePath}: ${error}`,
      );
      return null;
    }
  }

  /**
   * Extract TypeScript/JavaScript signatures
   */
  private extractTypeScript(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Export statements
      /^export\s+(?:default\s+)?(?:async\s+)?(?:function|class|interface|type|enum|const|let|var)\s+[\w<>,\s]+/gm,
      // Class declarations
      /^(?:export\s+)?(?:abstract\s+)?class\s+\w+(?:\s+extends\s+[\w<>,\s]+)?(?:\s+implements\s+[\w<>,\s]+)?\s*\{/gm,
      // Interface declarations
      /^(?:export\s+)?interface\s+\w+(?:\s+extends\s+[\w<>,\s]+)?\s*\{/gm,
      // Type declarations
      /^(?:export\s+)?type\s+\w+(?:<[^>]+>)?\s*=/gm,
      // Function declarations
      /^(?:export\s+)?(?:async\s+)?function\s+\w+\s*(?:<[^>]+>)?\s*\([^)]*\)(?:\s*:\s*[\w<>\[\]|&\s]+)?/gm,
      // Arrow functions (exported)
      /^(?:export\s+)?(?:const|let|var)\s+\w+\s*(?::\s*[\w<>\[\]|&\s]+)?\s*=\s*(?:async\s+)?\([^)]*\)\s*(?::\s*[\w<>\[\]|&\s]+)?\s*=>/gm,
      // Method signatures (inside classes)
      /^\s+(?:public|private|protected|static|async|readonly|\s)*\w+\s*(?:<[^>]+>)?\s*\([^)]*\)(?:\s*:\s*[\w<>\[\]|&\s]+)?/gm,
      // Decorators (for NestJS, Angular, etc.)
      /^@\w+\([^)]*\)/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    // Also extract JSDoc comments for context
    const jsdocPattern =
      /\/\*\*[\s\S]*?\*\/\s*(?=export|class|interface|function|const|async)/g;
    const jsdocs = content.match(jsdocPattern);
    if (jsdocs) {
      for (const doc of jsdocs.slice(0, 10)) {
        // Limit to 10 JSDoc comments
        const firstLine = doc
          .split('\n')
          .find((l) => l.includes('@') || l.includes('*'))
          ?.trim();
        if (firstLine && firstLine.length < 200) {
          // Don't add, but note these exist
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract JavaScript signatures (similar to TypeScript but without types)
   */
  private extractJavaScript(content: string): string {
    return this.extractTypeScript(content);
  }

  /**
   * Extract Python signatures
   */
  private extractPython(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Class declarations with docstrings
      /^class\s+\w+(?:\([^)]*\))?:/gm,
      // Function declarations with docstrings
      /^(?:async\s+)?def\s+\w+\s*\([^)]*\)(?:\s*->\s*[\w\[\],\s]+)?:/gm,
      // Method declarations (indented)
      /^\s+(?:async\s+)?def\s+\w+\s*\([^)]*\)(?:\s*->\s*[\w\[\],\s]+)?:/gm,
      // Decorators
      /^@\w+(?:\([^)]*\))?/gm,
      // Import statements (for context)
      /^from\s+[\w.]+\s+import\s+[\w,\s*]+/gm,
      /^import\s+[\w.]+(?:\s+as\s+\w+)?/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    // Extract docstrings
    const docstringPattern = /"""[\s\S]*?"""/g;
    const docstrings = content.match(docstringPattern);
    if (docstrings) {
      for (const doc of docstrings.slice(0, 5)) {
        const firstLine = doc.split('\n')[0].replace(/"""/g, '').trim();
        if (
          firstLine &&
          firstLine.length < 100 &&
          !lines.includes(`# ${firstLine}`)
        ) {
          lines.push(`# ${firstLine}`);
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract Rust signatures
   */
  private extractRust(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Struct declarations
      /^(?:pub\s+)?struct\s+\w+(?:<[^>]+>)?(?:\s+where[^{]+)?\s*\{?/gm,
      // Enum declarations
      /^(?:pub\s+)?enum\s+\w+(?:<[^>]+>)?\s*\{/gm,
      // Trait declarations
      /^(?:pub\s+)?trait\s+\w+(?:<[^>]+>)?(?:\s*:\s*[\w\s+<>]+)?\s*\{/gm,
      // Impl blocks
      /^impl(?:<[^>]+>)?\s+(?:\w+(?:<[^>]+>)?\s+for\s+)?\w+(?:<[^>]+>)?\s*\{/gm,
      // Function declarations
      /^(?:pub\s+)?(?:async\s+)?fn\s+\w+(?:<[^>]+>)?\s*\([^)]*\)(?:\s*->\s*[\w<>&\[\]']+)?/gm,
      // Use statements
      /^use\s+[\w:{}*,\s]+;/gm,
      // Mod declarations
      /^(?:pub\s+)?mod\s+\w+;?/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract Go signatures
   */
  private extractGo(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Package declaration
      /^package\s+\w+/gm,
      // Struct declarations
      /^type\s+\w+\s+struct\s*\{/gm,
      // Interface declarations
      /^type\s+\w+\s+interface\s*\{/gm,
      // Function declarations
      /^func\s+(?:\([^)]+\)\s+)?\w+\s*\([^)]*\)(?:\s*\([^)]*\)|\s*[\w*\[\]]+)?/gm,
      // Import statements
      /^import\s+(?:\([^)]+\)|"[^"]+"|[\w.]+)/gm,
      // Const/var blocks
      /^(?:const|var)\s+(?:\([^)]+\)|\w+(?:\s+[\w*\[\]]+)?(?:\s*=)?)/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract Java signatures
   */
  private extractJava(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Package declaration
      /^package\s+[\w.]+;/gm,
      // Import statements
      /^import\s+(?:static\s+)?[\w.*]+;/gm,
      // Class declarations
      /^(?:public|private|protected)?\s*(?:abstract|final)?\s*class\s+\w+(?:<[^>]+>)?(?:\s+extends\s+[\w<>,]+)?(?:\s+implements\s+[\w<>,\s]+)?\s*\{/gm,
      // Interface declarations
      /^(?:public|private|protected)?\s*interface\s+\w+(?:<[^>]+>)?(?:\s+extends\s+[\w<>,\s]+)?\s*\{/gm,
      // Enum declarations
      /^(?:public|private|protected)?\s*enum\s+\w+(?:\s+implements\s+[\w<>,\s]+)?\s*\{/gm,
      // Method declarations
      /^\s*(?:public|private|protected)?\s*(?:static|final|abstract|synchronized)?\s*(?:<[^>]+>\s+)?[\w<>\[\]]+\s+\w+\s*\([^)]*\)(?:\s+throws\s+[\w,\s]+)?/gm,
      // Annotations
      /^@\w+(?:\([^)]*\))?/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract Swift signatures
   */
  private extractSwift(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Import statements
      /^import\s+\w+/gm,
      // Class declarations
      /^(?:public|private|internal|fileprivate|open)?\s*(?:final)?\s*class\s+\w+(?:<[^>]+>)?(?:\s*:\s*[\w<>,\s]+)?\s*\{/gm,
      // Struct declarations
      /^(?:public|private|internal|fileprivate)?\s*struct\s+\w+(?:<[^>]+>)?(?:\s*:\s*[\w<>,\s]+)?\s*\{/gm,
      // Enum declarations
      /^(?:public|private|internal|fileprivate)?\s*enum\s+\w+(?:<[^>]+>)?(?:\s*:\s*[\w<>,\s]+)?\s*\{/gm,
      // Protocol declarations
      /^(?:public|private|internal|fileprivate)?\s*protocol\s+\w+(?:\s*:\s*[\w<>,\s]+)?\s*\{/gm,
      // Function declarations
      /^(?:@\w+\s+)*(?:public|private|internal|fileprivate|open)?\s*(?:static|class|override|mutating|async)?\s*func\s+\w+(?:<[^>]+>)?\s*\([^)]*\)(?:\s*(?:throws|rethrows))?\s*(?:->\s*[\w<>\[\]?!]+)?/gm,
      // Property declarations
      /^\s*(?:public|private|internal|fileprivate)?\s*(?:static|class|lazy|weak|unowned)?\s*(?:let|var)\s+\w+\s*:\s*[\w<>\[\]?!]+/gm,
      // Property wrappers
      /^@\w+(?:\([^)]*\))?/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract Ruby signatures
   */
  private extractRuby(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Class declarations
      /^class\s+\w+(?:\s*<\s*[\w:]+)?/gm,
      // Module declarations
      /^module\s+\w+/gm,
      // Method definitions
      /^\s*def\s+(?:self\.)?\w+(?:\([^)]*\))?/gm,
      // Attr accessors
      /^\s*attr_(?:reader|writer|accessor)\s+[\w:,\s]+/gm,
      // Include/extend
      /^\s*(?:include|extend|prepend)\s+[\w:]+/gm,
      // Require statements
      /^require(?:_relative)?\s+['"][\w\/]+['"]/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }

  /**
   * Extract PHP signatures
   */
  private extractPHP(content: string): string {
    const lines: string[] = [];
    const patterns = [
      // Namespace declaration
      /^namespace\s+[\w\\]+;/gm,
      // Use statements
      /^use\s+[\w\\]+(?:\s+as\s+\w+)?;/gm,
      // Class declarations
      /^(?:abstract|final)?\s*class\s+\w+(?:\s+extends\s+[\w\\]+)?(?:\s+implements\s+[\w\\,\s]+)?\s*\{/gm,
      // Interface declarations
      /^interface\s+\w+(?:\s+extends\s+[\w\\,\s]+)?\s*\{/gm,
      // Trait declarations
      /^trait\s+\w+\s*\{/gm,
      // Function declarations
      /^(?:public|private|protected)?\s*(?:static)?\s*function\s+\w+\s*\([^)]*\)(?:\s*:\s*\??\w+)?/gm,
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          const cleaned = match.trim();
          if (cleaned && !lines.includes(cleaned)) {
            lines.push(cleaned);
          }
        }
      }
    }

    return lines.slice(0, 100).join('\n');
  }
}
