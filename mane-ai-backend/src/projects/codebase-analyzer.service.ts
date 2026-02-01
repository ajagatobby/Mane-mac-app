import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import {
  ProjectManifest,
  CodebaseStructure,
  CodebaseAnalysis,
} from './dto/project.dto';

interface ManifestDetection {
  type: string;
  file: string;
  techStack: string[];
}

const MANIFEST_FILES: Record<string, ManifestDetection> = {
  'package.json': {
    type: 'nodejs',
    file: 'package.json',
    techStack: ['Node.js', 'JavaScript'],
  },
  'Cargo.toml': {
    type: 'rust',
    file: 'Cargo.toml',
    techStack: ['Rust'],
  },
  'pyproject.toml': {
    type: 'python',
    file: 'pyproject.toml',
    techStack: ['Python'],
  },
  'setup.py': {
    type: 'python',
    file: 'setup.py',
    techStack: ['Python'],
  },
  'requirements.txt': {
    type: 'python',
    file: 'requirements.txt',
    techStack: ['Python'],
  },
  'go.mod': {
    type: 'go',
    file: 'go.mod',
    techStack: ['Go'],
  },
  'pom.xml': {
    type: 'java',
    file: 'pom.xml',
    techStack: ['Java', 'Maven'],
  },
  'build.gradle': {
    type: 'java',
    file: 'build.gradle',
    techStack: ['Java', 'Gradle'],
  },
  'build.gradle.kts': {
    type: 'kotlin',
    file: 'build.gradle.kts',
    techStack: ['Kotlin', 'Gradle'],
  },
  'Package.swift': {
    type: 'swift',
    file: 'Package.swift',
    techStack: ['Swift'],
  },
  'pubspec.yaml': {
    type: 'dart',
    file: 'pubspec.yaml',
    techStack: ['Dart', 'Flutter'],
  },
  'Gemfile': {
    type: 'ruby',
    file: 'Gemfile',
    techStack: ['Ruby'],
  },
  'composer.json': {
    type: 'php',
    file: 'composer.json',
    techStack: ['PHP'],
  },
  'CMakeLists.txt': {
    type: 'cpp',
    file: 'CMakeLists.txt',
    techStack: ['C++', 'CMake'],
  },
  'Makefile': {
    type: 'make',
    file: 'Makefile',
    techStack: ['Make'],
  },
};

const IGNORED_DIRECTORIES = new Set([
  'node_modules',
  '.git',
  '.svn',
  '.hg',
  '__pycache__',
  '.pytest_cache',
  '.mypy_cache',
  'venv',
  '.venv',
  'env',
  '.env',
  'dist',
  'build',
  'target',
  '.next',
  '.nuxt',
  'coverage',
  '.idea',
  '.vscode',
  '.DS_Store',
  'vendor',
  'Pods',
  '.gradle',
  'bin',
  'obj',
]);

const CODE_EXTENSIONS = new Set([
  '.ts',
  '.tsx',
  '.js',
  '.jsx',
  '.py',
  '.rs',
  '.go',
  '.java',
  '.kt',
  '.swift',
  '.rb',
  '.php',
  '.c',
  '.cpp',
  '.h',
  '.hpp',
  '.cs',
  '.dart',
  '.vue',
  '.svelte',
]);

const CONFIG_FILES = new Set([
  'tsconfig.json',
  'jsconfig.json',
  '.eslintrc',
  '.eslintrc.js',
  '.eslintrc.json',
  '.prettierrc',
  '.prettierrc.js',
  '.prettierrc.json',
  'babel.config.js',
  'webpack.config.js',
  'vite.config.ts',
  'vite.config.js',
  'next.config.js',
  'next.config.mjs',
  'nuxt.config.ts',
  'tailwind.config.js',
  'tailwind.config.ts',
  'jest.config.js',
  'vitest.config.ts',
  '.env.example',
  'docker-compose.yml',
  'Dockerfile',
  '.dockerignore',
  '.gitignore',
  'Makefile',
]);

const ENTRY_POINT_PATTERNS = [
  'main.ts',
  'main.js',
  'index.ts',
  'index.js',
  'app.ts',
  'app.js',
  'server.ts',
  'server.js',
  'main.py',
  'app.py',
  '__main__.py',
  'main.go',
  'main.rs',
  'lib.rs',
  'Main.java',
  'App.java',
  'main.swift',
  'AppDelegate.swift',
  'main.dart',
  'main.c',
  'main.cpp',
];

export interface DiscoveredCodebase {
  path: string;
  name: string;
  type: string;
  techStack: string[];
}

@Injectable()
export class CodebaseAnalyzerService {
  private readonly logger = new Logger(CodebaseAnalyzerService.name);

  /**
   * Scan a directory recursively to find all codebases
   * @param rootPath - The root directory to scan
   * @param maxDepth - Maximum depth to search (default: 3)
   * @returns Array of discovered codebases
   */
  discoverCodebases(rootPath: string, maxDepth: number = 3): DiscoveredCodebase[] {
    const codebases: DiscoveredCodebase[] = [];
    
    if (!fs.existsSync(rootPath)) {
      return codebases;
    }

    const stats = fs.statSync(rootPath);
    if (!stats.isDirectory()) {
      return codebases;
    }

    this.scanForCodebases(rootPath, rootPath, codebases, 0, maxDepth);
    
    this.logger.log(`Discovered ${codebases.length} codebases in ${rootPath}`);
    return codebases;
  }

  private scanForCodebases(
    rootPath: string,
    currentPath: string,
    codebases: DiscoveredCodebase[],
    depth: number,
    maxDepth: number,
  ): void {
    if (depth > maxDepth) return;

    // Check if current directory is a codebase
    const detection = this.detectCodebase(currentPath);
    if (detection) {
      codebases.push({
        path: currentPath,
        name: path.basename(currentPath),
        type: detection.type,
        techStack: detection.techStack,
      });
      // Don't recurse into detected codebases (they're already found)
      return;
    }

    // Scan subdirectories
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(currentPath, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      
      // Skip ignored directories
      if (IGNORED_DIRECTORIES.has(entry.name)) continue;
      
      // Skip hidden directories
      if (entry.name.startsWith('.')) continue;

      const fullPath = path.join(currentPath, entry.name);
      this.scanForCodebases(rootPath, fullPath, codebases, depth + 1, maxDepth);
    }
  }

  /**
   * Detect if a folder contains a codebase by looking for manifest files
   */
  detectCodebase(folderPath: string): ManifestDetection | null {
    if (!fs.existsSync(folderPath)) {
      return null;
    }

    const stats = fs.statSync(folderPath);
    if (!stats.isDirectory()) {
      return null;
    }

    // Check for manifest files
    for (const [filename, detection] of Object.entries(MANIFEST_FILES)) {
      const manifestPath = path.join(folderPath, filename);
      if (fs.existsSync(manifestPath)) {
        this.logger.log(`Detected ${detection.type} project via ${filename}`);
        return detection;
      }
    }

    // Check if it's a git repository
    const gitPath = path.join(folderPath, '.git');
    if (fs.existsSync(gitPath)) {
      this.logger.log('Detected git repository');
      return {
        type: 'git',
        file: '.git',
        techStack: [],
      };
    }

    return null;
  }

  /**
   * Parse manifest file to extract project metadata
   */
  parseManifest(folderPath: string, detection: ManifestDetection): ProjectManifest | null {
    const manifestPath = path.join(folderPath, detection.file);
    
    if (!fs.existsSync(manifestPath)) {
      return null;
    }

    try {
      const content = fs.readFileSync(manifestPath, 'utf-8');

      if (detection.file === 'package.json') {
        return this.parsePackageJson(content);
      } else if (detection.file === 'Cargo.toml') {
        return this.parseCargoToml(content);
      } else if (detection.file === 'pyproject.toml') {
        return this.parsePyprojectToml(content);
      } else if (detection.file === 'go.mod') {
        return this.parseGoMod(content);
      } else if (detection.file === 'pubspec.yaml') {
        return this.parsePubspecYaml(content);
      }

      // For other manifest types, return basic info
      return {
        type: detection.type,
        raw: content.substring(0, 2000), // First 2000 chars for context
      };
    } catch (error) {
      this.logger.warn(`Failed to parse manifest: ${error}`);
      return null;
    }
  }

  private parsePackageJson(content: string): ProjectManifest {
    const pkg = JSON.parse(content);
    return {
      type: 'nodejs',
      name: pkg.name,
      version: pkg.version,
      description: pkg.description,
      dependencies: pkg.dependencies || {},
      devDependencies: pkg.devDependencies || {},
      scripts: pkg.scripts || {},
    };
  }

  private parseCargoToml(content: string): ProjectManifest {
    // Simple TOML parsing for Cargo.toml
    const lines = content.split('\n');
    const manifest: ProjectManifest = { type: 'rust' };
    
    let currentSection = '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        currentSection = trimmed.replace(/[\[\]]/g, '');
      } else if (trimmed.includes('=') && currentSection === 'package') {
        const [key, ...valueParts] = trimmed.split('=');
        const value = valueParts.join('=').trim().replace(/^["']|["']$/g, '');
        if (key.trim() === 'name') manifest.name = value;
        if (key.trim() === 'version') manifest.version = value;
        if (key.trim() === 'description') manifest.description = value;
      }
    }
    
    return manifest;
  }

  private parsePyprojectToml(content: string): ProjectManifest {
    // Simple parsing for pyproject.toml
    const lines = content.split('\n');
    const manifest: ProjectManifest = { type: 'python' };
    
    let currentSection = '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        currentSection = trimmed.replace(/[\[\]]/g, '');
      } else if (trimmed.includes('=') && 
                 (currentSection === 'project' || currentSection === 'tool.poetry')) {
        const [key, ...valueParts] = trimmed.split('=');
        const value = valueParts.join('=').trim().replace(/^["']|["']$/g, '');
        if (key.trim() === 'name') manifest.name = value;
        if (key.trim() === 'version') manifest.version = value;
        if (key.trim() === 'description') manifest.description = value;
      }
    }
    
    return manifest;
  }

  private parseGoMod(content: string): ProjectManifest {
    const lines = content.split('\n');
    const manifest: ProjectManifest = { type: 'go' };
    
    for (const line of lines) {
      if (line.startsWith('module ')) {
        manifest.name = line.replace('module ', '').trim();
        break;
      }
    }
    
    return manifest;
  }

  private parsePubspecYaml(content: string): ProjectManifest {
    // Simple YAML parsing
    const lines = content.split('\n');
    const manifest: ProjectManifest = { type: 'dart' };
    
    for (const line of lines) {
      if (line.startsWith('name:')) {
        manifest.name = line.split(':')[1].trim();
      } else if (line.startsWith('version:')) {
        manifest.version = line.split(':')[1].trim();
      } else if (line.startsWith('description:')) {
        manifest.description = line.split(':')[1].trim();
      }
    }
    
    return manifest;
  }

  /**
   * Scan the codebase structure
   * @param maxDepth - Maximum directory depth to scan (default: 4)
   * @param maxFiles - Maximum files to count before stopping detailed scan (default: 5000)
   */
  scanStructure(folderPath: string, maxDepth: number = 4, maxFiles: number = 5000): CodebaseStructure {
    const structure: CodebaseStructure = {
      totalFiles: 0,
      totalDirectories: 0,
      filesByExtension: {},
      keyDirectories: [],
      entryPoints: [],
      configFiles: [],
      hasTests: false,
      hasDocumentation: false,
    };

    this.walkDirectory(folderPath, folderPath, structure, 0, maxDepth, maxFiles);

    return structure;
  }

  private walkDirectory(
    rootPath: string,
    currentPath: string,
    structure: CodebaseStructure,
    depth: number,
    maxDepth: number,
    maxFiles: number = 5000,
  ): boolean {
    // Stop if we've hit the file limit (return false to signal early exit)
    if (structure.totalFiles >= maxFiles) return false;
    if (depth > maxDepth) return true;

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(currentPath, { withFileTypes: true });
    } catch {
      return true;
    }

    for (const entry of entries) {
      // Check file limit
      if (structure.totalFiles >= maxFiles) return false;
      
      const fullPath = path.join(currentPath, entry.name);
      const relativePath = path.relative(rootPath, fullPath);

      if (entry.isDirectory()) {
        // Skip ignored directories
        if (IGNORED_DIRECTORIES.has(entry.name)) continue;

        structure.totalDirectories++;

        // Identify key directories (only at shallow depth)
        if (depth <= 2) {
          const lowerName = entry.name.toLowerCase();
          if (['src', 'lib', 'app', 'components', 'services', 'utils', 'api', 'core', 'modules'].includes(lowerName)) {
            structure.keyDirectories.push(relativePath);
          }

          // Check for tests/docs
          if (['test', 'tests', '__tests__', 'spec', 'specs'].includes(lowerName)) {
            structure.hasTests = true;
          }
          if (['docs', 'documentation', 'doc'].includes(lowerName)) {
            structure.hasDocumentation = true;
          }
        }

        // Recurse
        const shouldContinue = this.walkDirectory(rootPath, fullPath, structure, depth + 1, maxDepth, maxFiles);
        if (!shouldContinue) return false;
      } else {
        structure.totalFiles++;

        // Count by extension
        const ext = path.extname(entry.name).toLowerCase();
        if (ext) {
          structure.filesByExtension[ext] = (structure.filesByExtension[ext] || 0) + 1;
        }

        // Check for entry points (only at root or shallow depth)
        if (depth <= 2 && ENTRY_POINT_PATTERNS.includes(entry.name)) {
          structure.entryPoints.push(relativePath);
        }

        // Check for config files (only at root)
        if (depth === 0 && CONFIG_FILES.has(entry.name)) {
          structure.configFiles.push(relativePath);
        }

        // Check for documentation
        if (entry.name.toLowerCase() === 'readme.md' || entry.name.toLowerCase() === 'readme.txt') {
          structure.hasDocumentation = true;
        }
      }
    }
    
    return true;
  }

  /**
   * Read sample files for LLM analysis (README, entry points, configs)
   */
  readSampleFiles(folderPath: string, structure: CodebaseStructure): Record<string, string> {
    const samples: Record<string, string> = {};
    const maxFileSize = 5000; // Max chars per file

    // Read README
    const readmeNames = ['README.md', 'README.txt', 'readme.md', 'Readme.md'];
    for (const name of readmeNames) {
      const readmePath = path.join(folderPath, name);
      if (fs.existsSync(readmePath)) {
        try {
          const content = fs.readFileSync(readmePath, 'utf-8');
          samples['README'] = content.substring(0, maxFileSize);
        } catch {
          // Ignore read errors
        }
        break;
      }
    }

    // Read entry points (first 2)
    for (const entryPoint of structure.entryPoints.slice(0, 2)) {
      const entryPath = path.join(folderPath, entryPoint);
      try {
        const content = fs.readFileSync(entryPath, 'utf-8');
        samples[entryPoint] = content.substring(0, maxFileSize);
      } catch {
        // Ignore read errors
      }
    }

    // Read key config files (first 3)
    const importantConfigs = ['tsconfig.json', 'package.json', 'Cargo.toml', 'pyproject.toml', 'go.mod'];
    let configCount = 0;
    for (const config of structure.configFiles) {
      if (configCount >= 3) break;
      const configName = path.basename(config);
      if (importantConfigs.some(ic => configName === ic)) {
        const configPath = path.join(folderPath, config);
        try {
          const content = fs.readFileSync(configPath, 'utf-8');
          samples[config] = content.substring(0, maxFileSize);
          configCount++;
        } catch {
          // Ignore read errors
        }
      }
    }

    return samples;
  }

  /**
   * Infer tech stack from structure and manifest
   */
  inferTechStack(
    detection: ManifestDetection,
    manifest: ProjectManifest | null,
    structure: CodebaseStructure,
  ): string[] {
    const techStack = new Set<string>(detection.techStack);

    // Infer from file extensions
    const extToTech: Record<string, string[]> = {
      '.ts': ['TypeScript'],
      '.tsx': ['TypeScript', 'React'],
      '.jsx': ['React'],
      '.vue': ['Vue.js'],
      '.svelte': ['Svelte'],
      '.py': ['Python'],
      '.rs': ['Rust'],
      '.go': ['Go'],
      '.java': ['Java'],
      '.kt': ['Kotlin'],
      '.swift': ['Swift'],
      '.dart': ['Dart'],
      '.rb': ['Ruby'],
      '.php': ['PHP'],
    };

    for (const [ext, count] of Object.entries(structure.filesByExtension)) {
      if (count > 0 && extToTech[ext]) {
        for (const tech of extToTech[ext]) {
          techStack.add(tech);
        }
      }
    }

    // Infer from dependencies (for Node.js projects)
    if (manifest && manifest.dependencies) {
      const deps = { ...manifest.dependencies, ...manifest.devDependencies };
      
      if (deps['react']) techStack.add('React');
      if (deps['vue']) techStack.add('Vue.js');
      if (deps['svelte']) techStack.add('Svelte');
      if (deps['@angular/core']) techStack.add('Angular');
      if (deps['next']) techStack.add('Next.js');
      if (deps['nuxt']) techStack.add('Nuxt');
      if (deps['express']) techStack.add('Express');
      if (deps['fastify']) techStack.add('Fastify');
      if (deps['@nestjs/core']) techStack.add('NestJS');
      if (deps['prisma'] || deps['@prisma/client']) techStack.add('Prisma');
      if (deps['typeorm']) techStack.add('TypeORM');
      if (deps['mongoose']) techStack.add('MongoDB');
      if (deps['pg'] || deps['postgres']) techStack.add('PostgreSQL');
      if (deps['mysql'] || deps['mysql2']) techStack.add('MySQL');
      if (deps['redis'] || deps['ioredis']) techStack.add('Redis');
      if (deps['tailwindcss']) techStack.add('Tailwind CSS');
      if (deps['jest']) techStack.add('Jest');
      if (deps['vitest']) techStack.add('Vitest');
      if (deps['webpack']) techStack.add('Webpack');
      if (deps['vite']) techStack.add('Vite');
      if (deps['docker-compose']) techStack.add('Docker');
    }

    // Check for Docker
    if (structure.configFiles.some(f => f.includes('Dockerfile') || f.includes('docker-compose'))) {
      techStack.add('Docker');
    }

    return Array.from(techStack);
  }

  /**
   * Generate tags from analysis
   */
  generateTags(
    detection: ManifestDetection,
    manifest: ProjectManifest | null,
    structure: CodebaseStructure,
    techStack: string[],
  ): string[] {
    const tags = new Set<string>();

    // Add tech stack as tags
    for (const tech of techStack) {
      tags.add(tech.toLowerCase().replace(/[^a-z0-9]/g, '-'));
    }

    // Add project type
    tags.add(detection.type);

    // Add characteristics
    if (structure.hasTests) tags.add('tested');
    if (structure.hasDocumentation) tags.add('documented');
    if (structure.configFiles.some(f => f.includes('docker'))) tags.add('containerized');
    if (structure.totalFiles > 100) tags.add('large-project');
    else if (structure.totalFiles > 20) tags.add('medium-project');
    else tags.add('small-project');

    // Infer purpose from key directories
    if (structure.keyDirectories.some(d => d.includes('api') || d.includes('routes'))) {
      tags.add('api');
      tags.add('backend');
    }
    if (structure.keyDirectories.some(d => d.includes('components') || d.includes('views'))) {
      tags.add('frontend');
      tags.add('ui');
    }
    if (structure.keyDirectories.some(d => d.includes('cli') || d.includes('commands'))) {
      tags.add('cli');
    }

    return Array.from(tags);
  }
}
