/**
 * Build script for creating the ManeAI sidecar package
 * 
 * This creates a distributable sidecar folder containing:
 * - Compiled JavaScript
 * - Required node_modules (for native dependencies)
 * - A shell script wrapper
 * 
 * The Swift app will bundle this folder and run it with a bundled Node.js runtime.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT_DIR = path.join(__dirname, '..');
const DIST_DIR = path.join(ROOT_DIR, 'dist');
const SIDECAR_DIR = path.join(ROOT_DIR, 'sidecar');

// Native modules that need to be copied
const NATIVE_MODULES = [
  '@lancedb',
  'onnxruntime-node',
  'apache-arrow',
  '@huggingface',
  'sharp', // if used
];

// All production dependencies
const COPY_MODULES = [
  '@nestjs',
  '@langchain',
  'reflect-metadata',
  'rxjs',
  'class-validator',
  'class-transformer',
  'express',
  'body-parser',
  'cookie-parser',
  'cors',
  'uuid',
  'long',
  'flatbuffers',
  'iterator.prototype',
  'es-abstract',
  // Add more as needed
];

async function build() {
  console.log('🚀 Building ManeAI Sidecar...\n');

  // Clean previous build
  if (fs.existsSync(SIDECAR_DIR)) {
    console.log('Cleaning previous sidecar build...');
    fs.rmSync(SIDECAR_DIR, { recursive: true });
  }

  // Create sidecar directory structure
  fs.mkdirSync(SIDECAR_DIR, { recursive: true });
  fs.mkdirSync(path.join(SIDECAR_DIR, 'node_modules'), { recursive: true });

  // Copy compiled JavaScript
  console.log('Copying compiled JavaScript...');
  copyDir(DIST_DIR, path.join(SIDECAR_DIR, 'dist'));

  // Copy required node_modules
  console.log('Copying native modules and dependencies...');
  const nodeModulesDir = path.join(ROOT_DIR, 'node_modules');
  const targetNodeModules = path.join(SIDECAR_DIR, 'node_modules');

  // Get all dependencies from package.json
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(ROOT_DIR, 'package.json'), 'utf8')
  );
  const dependencies = Object.keys(packageJson.dependencies || {});

  // Copy each dependency and its sub-dependencies
  for (const dep of dependencies) {
    copyModuleWithDeps(dep, nodeModulesDir, targetNodeModules);
  }

  // Create package.json for sidecar
  const sidecarPackageJson = {
    name: 'mane-ai-sidecar',
    version: packageJson.version,
    main: 'dist/main.js',
    scripts: {
      start: 'node dist/main.js',
    },
  };

  fs.writeFileSync(
    path.join(SIDECAR_DIR, 'package.json'),
    JSON.stringify(sidecarPackageJson, null, 2)
  );

  // Create launcher script
  const launcherScript = `#!/bin/bash
# ManeAI Sidecar Launcher
# This script is called by the Swift app

SCRIPT_DIR="$( cd "$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
NODE_PATH="\${SCRIPT_DIR}/node_modules"

# Pass all arguments to the Node.js app
exec "\${NODE_EXEC:-node}" "\${SCRIPT_DIR}/dist/main.js" "$@"
`;

  fs.writeFileSync(path.join(SIDECAR_DIR, 'launch.sh'), launcherScript);
  fs.chmodSync(path.join(SIDECAR_DIR, 'launch.sh'), '755');

  // Calculate size
  const size = getDirectorySize(SIDECAR_DIR);
  console.log(`\n✅ Sidecar built successfully!`);
  console.log(`📦 Output: ${SIDECAR_DIR}`);
  console.log(`📏 Size: ${(size / 1024 / 1024).toFixed(2)} MB`);
  console.log(`\nTo test: cd sidecar && node dist/main.js --db-path ./test-db`);
}

function copyDir(src, dest) {
  if (!fs.existsSync(src)) return;
  
  fs.mkdirSync(dest, { recursive: true });
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function copyModuleWithDeps(moduleName, nodeModulesDir, targetDir) {
  const modulePath = path.join(nodeModulesDir, moduleName);
  const targetPath = path.join(targetDir, moduleName);

  if (!fs.existsSync(modulePath)) {
    // Try scoped module
    if (moduleName.startsWith('@')) {
      const [scope, name] = moduleName.split('/');
      const scopedPath = path.join(nodeModulesDir, scope, name);
      if (fs.existsSync(scopedPath)) {
        fs.mkdirSync(path.join(targetDir, scope), { recursive: true });
        copyDir(scopedPath, path.join(targetDir, scope, name));
      }
    }
    return;
  }

  if (fs.existsSync(targetPath)) return; // Already copied

  copyDir(modulePath, targetPath);

  // Copy peer dependencies
  const pkgJsonPath = path.join(modulePath, 'package.json');
  if (fs.existsSync(pkgJsonPath)) {
    try {
      const pkgJson = JSON.parse(fs.readFileSync(pkgJsonPath, 'utf8'));
      const deps = {
        ...(pkgJson.dependencies || {}),
        ...(pkgJson.peerDependencies || {}),
      };

      for (const dep of Object.keys(deps)) {
        copyModuleWithDeps(dep, nodeModulesDir, targetDir);
      }
    } catch (e) {
      // Ignore parse errors
    }
  }
}

function getDirectorySize(dirPath) {
  let size = 0;
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });

  for (const entry of entries) {
    const entryPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      size += getDirectorySize(entryPath);
    } else {
      size += fs.statSync(entryPath).size;
    }
  }

  return size;
}

build().catch(console.error);
