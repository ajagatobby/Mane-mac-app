import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Detected project manifest information
 */
export interface ProjectManifest {
  name: string;
  description: string;
  techStack: string[];
  tags: string[];
  dependencies: string[];
  devDependencies: string[];
  scripts: Record<string, string>;
  version?: string;
  language: string;
  framework?: string;
}

/**
 * Mapping of dependencies to tech stack tags
 */
const DEPENDENCY_TO_TECH: Record<string, string[]> = {
  // Frontend frameworks
  react: ['react', 'frontend'],
  vue: ['vue', 'frontend'],
  angular: ['angular', 'frontend'],
  svelte: ['svelte', 'frontend'],
  'next': ['nextjs', 'react', 'frontend', 'fullstack'],
  'nuxt': ['nuxtjs', 'vue', 'frontend', 'fullstack'],
  gatsby: ['gatsby', 'react', 'frontend'],
  
  // Backend frameworks
  express: ['express', 'nodejs', 'backend', 'api'],
  fastify: ['fastify', 'nodejs', 'backend', 'api'],
  'nestjs': ['nestjs', 'nodejs', 'backend', 'api'],
  '@nestjs/core': ['nestjs', 'nodejs', 'backend', 'api'],
  koa: ['koa', 'nodejs', 'backend', 'api'],
  hapi: ['hapi', 'nodejs', 'backend', 'api'],
  
  // Databases
  mongoose: ['mongodb', 'database'],
  mongodb: ['mongodb', 'database'],
  pg: ['postgresql', 'database'],
  mysql: ['mysql', 'database'],
  mysql2: ['mysql', 'database'],
  prisma: ['prisma', 'database', 'orm'],
  '@prisma/client': ['prisma', 'database', 'orm'],
  typeorm: ['typeorm', 'database', 'orm'],
  sequelize: ['sequelize', 'database', 'orm'],
  sqlite3: ['sqlite', 'database'],
  redis: ['redis', 'database', 'cache'],
  ioredis: ['redis', 'database', 'cache'],
  
  // Payment/Ecommerce
  stripe: ['stripe', 'payments', 'ecommerce'],
  '@stripe/stripe-js': ['stripe', 'payments', 'ecommerce'],
  paypal: ['paypal', 'payments', 'ecommerce'],
  shopify: ['shopify', 'ecommerce'],
  '@shopify/shopify-api': ['shopify', 'ecommerce'],
  
  // Authentication
  passport: ['passport', 'auth'],
  jsonwebtoken: ['jwt', 'auth'],
  'next-auth': ['nextauth', 'auth'],
  '@auth0/auth0-react': ['auth0', 'auth'],
  firebase: ['firebase', 'auth', 'baas'],
  
  // Testing
  jest: ['jest', 'testing'],
  mocha: ['mocha', 'testing'],
  vitest: ['vitest', 'testing'],
  cypress: ['cypress', 'testing', 'e2e'],
  playwright: ['playwright', 'testing', 'e2e'],
  
  // UI Libraries
  '@mui/material': ['material-ui', 'ui'],
  'tailwindcss': ['tailwind', 'css', 'ui'],
  'styled-components': ['styled-components', 'css'],
  '@emotion/react': ['emotion', 'css'],
  chakra: ['chakra-ui', 'ui'],
  '@chakra-ui/react': ['chakra-ui', 'ui'],
  
  // State Management
  redux: ['redux', 'state-management'],
  '@reduxjs/toolkit': ['redux', 'state-management'],
  mobx: ['mobx', 'state-management'],
  zustand: ['zustand', 'state-management'],
  recoil: ['recoil', 'state-management'],
  
  // GraphQL
  graphql: ['graphql', 'api'],
  '@apollo/client': ['apollo', 'graphql', 'api'],
  'apollo-server': ['apollo', 'graphql', 'api'],
  
  // Build tools
  webpack: ['webpack', 'bundler'],
  vite: ['vite', 'bundler'],
  esbuild: ['esbuild', 'bundler'],
  rollup: ['rollup', 'bundler'],
  
  // Mobile
  'react-native': ['react-native', 'mobile'],
  expo: ['expo', 'react-native', 'mobile'],
  
  // AI/ML
  openai: ['openai', 'ai', 'llm'],
  langchain: ['langchain', 'ai', 'llm'],
  '@langchain/core': ['langchain', 'ai', 'llm'],
  tensorflow: ['tensorflow', 'ai', 'ml'],
  '@tensorflow/tfjs': ['tensorflow', 'ai', 'ml'],
  
  // Python packages (for requirements.txt)
  django: ['django', 'python', 'backend', 'fullstack'],
  flask: ['flask', 'python', 'backend', 'api'],
  fastapi: ['fastapi', 'python', 'backend', 'api'],
  numpy: ['numpy', 'python', 'data-science'],
  pandas: ['pandas', 'python', 'data-science'],
  scikit: ['scikit-learn', 'python', 'ml'],
  torch: ['pytorch', 'python', 'ai', 'ml'],
  transformers: ['transformers', 'python', 'ai', 'llm'],
};

/**
 * ManifestScanner Service
 * Detects project type and extracts metadata from configuration files
 */
@Injectable()
export class ManifestScannerService {
  private readonly logger = new Logger(ManifestScannerService.name);

  /**
   * Scan a project directory for manifest files and extract metadata
   */
  async scanProject(projectPath: string): Promise<ProjectManifest> {
    this.logger.log(`Scanning project: ${projectPath}`);

    const manifest: ProjectManifest = {
      name: path.basename(projectPath),
      description: '',
      techStack: [],
      tags: [],
      dependencies: [],
      devDependencies: [],
      scripts: {},
      language: 'unknown',
    };

    // Check for various manifest files
    await Promise.all([
      this.scanPackageJson(projectPath, manifest),
      this.scanReadme(projectPath, manifest),
      this.scanPythonProject(projectPath, manifest),
      this.scanRustProject(projectPath, manifest),
      this.scanGoProject(projectPath, manifest),
    ]);

    // Deduplicate tech stack and tags
    manifest.techStack = [...new Set(manifest.techStack)];
    manifest.tags = [...new Set(manifest.tags)];

    // Infer additional tags from tech stack
    this.inferTags(manifest);

    this.logger.log(`Detected tech stack: ${manifest.techStack.join(', ')}`);
    this.logger.log(`Detected tags: ${manifest.tags.join(', ')}`);

    return manifest;
  }

  /**
   * Scan package.json for Node.js projects
   */
  private async scanPackageJson(
    projectPath: string,
    manifest: ProjectManifest,
  ): Promise<void> {
    const packageJsonPath = path.join(projectPath, 'package.json');

    if (!fs.existsSync(packageJsonPath)) {
      return;
    }

    try {
      const content = fs.readFileSync(packageJsonPath, 'utf-8');
      const pkg = JSON.parse(content);

      manifest.name = pkg.name || manifest.name;
      manifest.description = pkg.description || '';
      manifest.version = pkg.version;
      manifest.language = 'javascript';
      manifest.scripts = pkg.scripts || {};

      // Check for TypeScript
      const allDeps = {
        ...(pkg.dependencies || {}),
        ...(pkg.devDependencies || {}),
      };

      if (allDeps.typescript || fs.existsSync(path.join(projectPath, 'tsconfig.json'))) {
        manifest.language = 'typescript';
        manifest.techStack.push('typescript');
      }

      manifest.techStack.push('nodejs');

      // Extract dependencies
      manifest.dependencies = Object.keys(pkg.dependencies || {});
      manifest.devDependencies = Object.keys(pkg.devDependencies || {});

      // Map dependencies to tech stack
      for (const dep of [...manifest.dependencies, ...manifest.devDependencies]) {
        const depLower = dep.toLowerCase();
        for (const [key, tags] of Object.entries(DEPENDENCY_TO_TECH)) {
          if (depLower.includes(key.toLowerCase()) || depLower === key.toLowerCase()) {
            manifest.techStack.push(...tags);
          }
        }
      }

      // Detect framework
      if (allDeps['next']) manifest.framework = 'nextjs';
      else if (allDeps['nuxt']) manifest.framework = 'nuxtjs';
      else if (allDeps.react) manifest.framework = 'react';
      else if (allDeps.vue) manifest.framework = 'vue';
      else if (allDeps.angular) manifest.framework = 'angular';
      else if (allDeps['@nestjs/core']) manifest.framework = 'nestjs';
      else if (allDeps.express) manifest.framework = 'express';

    } catch (error) {
      this.logger.warn(`Failed to parse package.json: ${error}`);
    }
  }

  /**
   * Scan README.md for project description
   */
  private async scanReadme(
    projectPath: string,
    manifest: ProjectManifest,
  ): Promise<void> {
    const readmeNames = ['README.md', 'readme.md', 'README', 'readme.txt'];

    for (const readmeName of readmeNames) {
      const readmePath = path.join(projectPath, readmeName);

      if (fs.existsSync(readmePath)) {
        try {
          const content = fs.readFileSync(readmePath, 'utf-8');
          
          // Take first 2KB for description
          const truncated = content.substring(0, 2000);
          
          // Extract first paragraph or meaningful content
          const lines = truncated.split('\n').filter((l) => l.trim());
          
          // Skip title lines (starting with #)
          let descriptionLines: string[] = [];
          let foundContent = false;
          
          for (const line of lines) {
            if (line.startsWith('#')) {
              if (foundContent) break; // Stop at next heading
              continue;
            }
            if (line.trim()) {
              foundContent = true;
              descriptionLines.push(line.trim());
              if (descriptionLines.join(' ').length > 300) break;
            }
          }

          if (descriptionLines.length > 0 && !manifest.description) {
            manifest.description = descriptionLines.join(' ').substring(0, 500);
          }

          // Look for badges/keywords
          const badges = content.match(/\[!\[([^\]]+)\]/g) || [];
          for (const badge of badges) {
            const badgeLower = badge.toLowerCase();
            if (badgeLower.includes('react')) manifest.techStack.push('react');
            if (badgeLower.includes('typescript')) manifest.techStack.push('typescript');
            if (badgeLower.includes('python')) manifest.techStack.push('python');
            if (badgeLower.includes('docker')) manifest.tags.push('docker');
          }

        } catch (error) {
          this.logger.warn(`Failed to read README: ${error}`);
        }
        break;
      }
    }
  }

  /**
   * Scan Python project files
   */
  private async scanPythonProject(
    projectPath: string,
    manifest: ProjectManifest,
  ): Promise<void> {
    // Check for requirements.txt
    const requirementsPath = path.join(projectPath, 'requirements.txt');
    if (fs.existsSync(requirementsPath)) {
      manifest.language = 'python';
      manifest.techStack.push('python');

      try {
        const content = fs.readFileSync(requirementsPath, 'utf-8');
        const lines = content.split('\n');

        for (const line of lines) {
          const pkg = line.split('==')[0].split('>=')[0].split('<=')[0].trim().toLowerCase();
          if (pkg && !pkg.startsWith('#')) {
            manifest.dependencies.push(pkg);
            
            for (const [key, tags] of Object.entries(DEPENDENCY_TO_TECH)) {
              if (pkg.includes(key.toLowerCase())) {
                manifest.techStack.push(...tags);
              }
            }
          }
        }
      } catch (error) {
        this.logger.warn(`Failed to parse requirements.txt: ${error}`);
      }
    }

    // Check for pyproject.toml
    const pyprojectPath = path.join(projectPath, 'pyproject.toml');
    if (fs.existsSync(pyprojectPath)) {
      manifest.language = 'python';
      manifest.techStack.push('python');

      try {
        const content = fs.readFileSync(pyprojectPath, 'utf-8');
        
        // Basic TOML parsing for name and description
        const nameMatch = content.match(/name\s*=\s*"([^"]+)"/);
        if (nameMatch) manifest.name = nameMatch[1];
        
        const descMatch = content.match(/description\s*=\s*"([^"]+)"/);
        if (descMatch && !manifest.description) manifest.description = descMatch[1];

      } catch (error) {
        this.logger.warn(`Failed to parse pyproject.toml: ${error}`);
      }
    }
  }

  /**
   * Scan Rust project (Cargo.toml)
   */
  private async scanRustProject(
    projectPath: string,
    manifest: ProjectManifest,
  ): Promise<void> {
    const cargoPath = path.join(projectPath, 'Cargo.toml');

    if (!fs.existsSync(cargoPath)) {
      return;
    }

    manifest.language = 'rust';
    manifest.techStack.push('rust');

    try {
      const content = fs.readFileSync(cargoPath, 'utf-8');
      
      const nameMatch = content.match(/name\s*=\s*"([^"]+)"/);
      if (nameMatch) manifest.name = nameMatch[1];
      
      const descMatch = content.match(/description\s*=\s*"([^"]+)"/);
      if (descMatch && !manifest.description) manifest.description = descMatch[1];

      // Check for common Rust crates
      if (content.includes('tokio')) manifest.techStack.push('async', 'tokio');
      if (content.includes('actix')) manifest.techStack.push('actix', 'backend', 'api');
      if (content.includes('axum')) manifest.techStack.push('axum', 'backend', 'api');
      if (content.includes('rocket')) manifest.techStack.push('rocket', 'backend', 'api');
      if (content.includes('diesel')) manifest.techStack.push('diesel', 'database', 'orm');
      if (content.includes('sqlx')) manifest.techStack.push('sqlx', 'database');
      if (content.includes('wasm')) manifest.techStack.push('wasm', 'webassembly');

    } catch (error) {
      this.logger.warn(`Failed to parse Cargo.toml: ${error}`);
    }
  }

  /**
   * Scan Go project (go.mod)
   */
  private async scanGoProject(
    projectPath: string,
    manifest: ProjectManifest,
  ): Promise<void> {
    const goModPath = path.join(projectPath, 'go.mod');

    if (!fs.existsSync(goModPath)) {
      return;
    }

    manifest.language = 'go';
    manifest.techStack.push('go', 'golang');

    try {
      const content = fs.readFileSync(goModPath, 'utf-8');
      
      const moduleMatch = content.match(/module\s+(\S+)/);
      if (moduleMatch) {
        const moduleName = moduleMatch[1].split('/').pop() || manifest.name;
        manifest.name = moduleName;
      }

      // Check for common Go packages
      if (content.includes('gin-gonic')) manifest.techStack.push('gin', 'backend', 'api');
      if (content.includes('echo')) manifest.techStack.push('echo', 'backend', 'api');
      if (content.includes('fiber')) manifest.techStack.push('fiber', 'backend', 'api');
      if (content.includes('gorm')) manifest.techStack.push('gorm', 'database', 'orm');
      if (content.includes('sqlx')) manifest.techStack.push('sqlx', 'database');
      if (content.includes('grpc')) manifest.techStack.push('grpc', 'api');

    } catch (error) {
      this.logger.warn(`Failed to parse go.mod: ${error}`);
    }
  }

  /**
   * Infer additional tags from tech stack
   */
  private inferTags(manifest: ProjectManifest): void {
    const techLower = manifest.techStack.map((t) => t.toLowerCase());

    // Infer project type
    if (techLower.some((t) => ['react', 'vue', 'angular', 'svelte'].includes(t))) {
      manifest.tags.push('frontend');
    }

    if (techLower.some((t) => ['express', 'fastify', 'nestjs', 'django', 'flask', 'fastapi'].includes(t))) {
      manifest.tags.push('backend');
    }

    if (techLower.includes('fullstack') || (manifest.tags.includes('frontend') && manifest.tags.includes('backend'))) {
      manifest.tags.push('fullstack');
    }

    if (techLower.some((t) => ['api', 'graphql', 'rest'].includes(t))) {
      manifest.tags.push('api');
    }

    if (techLower.some((t) => ['stripe', 'paypal', 'shopify', 'ecommerce'].includes(t))) {
      manifest.tags.push('ecommerce');
    }

    if (techLower.some((t) => ['openai', 'langchain', 'llm', 'tensorflow', 'pytorch'].includes(t))) {
      manifest.tags.push('ai');
    }

    if (techLower.some((t) => ['react-native', 'expo'].includes(t))) {
      manifest.tags.push('mobile');
    }

    if (techLower.some((t) => ['jest', 'mocha', 'vitest', 'cypress', 'playwright'].includes(t))) {
      manifest.tags.push('tested');
    }

    // Check for monorepo indicators
    if (fs.existsSync(path.join(manifest.name, 'lerna.json')) ||
        fs.existsSync(path.join(manifest.name, 'pnpm-workspace.yaml')) ||
        fs.existsSync(path.join(manifest.name, 'turbo.json'))) {
      manifest.tags.push('monorepo');
    }
  }

  /**
   * Get file count for supported code files
   */
  async getCodeFileCount(projectPath: string, maxDepth: number = 5): Promise<number> {
    const codeExtensions = [
      '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
      '.py', '.pyw',
      '.rs',
      '.go',
      '.java', '.kt', '.scala',
      '.rb',
      '.php',
      '.swift',
      '.c', '.cpp', '.h', '.hpp',
      '.cs',
      '.vue', '.svelte',
    ];

    let count = 0;

    const scanDir = (dir: string, depth: number) => {
      if (depth > maxDepth) return;

      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          // Skip common non-code directories
          if (entry.isDirectory()) {
            const skipDirs = ['node_modules', '.git', 'dist', 'build', '__pycache__', 'target', 'vendor', '.next', '.nuxt'];
            if (!skipDirs.includes(entry.name)) {
              scanDir(path.join(dir, entry.name), depth + 1);
            }
          } else if (entry.isFile()) {
            const ext = path.extname(entry.name).toLowerCase();
            if (codeExtensions.includes(ext)) {
              count++;
            }
          }
        }
      } catch (error) {
        // Ignore permission errors
      }
    };

    scanDir(projectPath, 0);
    return count;
  }
}
