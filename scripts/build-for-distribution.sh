#!/bin/bash
#
# ManeAI Distribution Build Script
# 
# This script prepares the sidecar for distribution by:
# 1. Downloading Node.js runtime (if not present)
# 2. Building the NestJS sidecar
# 3. Signing all executables and native modules
#
# Usage: ./scripts/build-for-distribution.sh [--sign "Developer ID Application: Your Name (TEAM_ID)"]
#

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
BACKEND_DIR="$ROOT_DIR/mane-ai-backend"
RESOURCES_DIR="$ROOT_DIR/ManeAI/ManePaw/Resources"
NODE_VERSION="20.11.0"  # LTS version
NODE_ARCH="arm64"       # Change to "x64" for Intel Macs

# Parse arguments
SIGNING_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --arch)
            NODE_ARCH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "============================================"
echo "🦁 ManeAI Distribution Build"
echo "============================================"
echo ""

# Create Resources directory
mkdir -p "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR/node"
mkdir -p "$RESOURCES_DIR/sidecar"

# ============================================
# Step 1: Download Node.js
# ============================================
NODE_DIR="$RESOURCES_DIR/node"
NODE_BINARY="$NODE_DIR/node"

if [ ! -f "$NODE_BINARY" ]; then
    echo "📥 Downloading Node.js v$NODE_VERSION ($NODE_ARCH)..."
    
    NODE_URL="https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
    TEMP_DIR=$(mktemp -d)
    
    curl -L "$NODE_URL" -o "$TEMP_DIR/node.tar.gz"
    tar -xzf "$TEMP_DIR/node.tar.gz" -C "$TEMP_DIR"
    
    # Copy only the node binary (not the entire runtime)
    cp "$TEMP_DIR/node-v$NODE_VERSION-darwin-$NODE_ARCH/bin/node" "$NODE_BINARY"
    chmod +x "$NODE_BINARY"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo "✅ Node.js downloaded to $NODE_BINARY"
else
    echo "✅ Node.js already present at $NODE_BINARY"
fi

# ============================================
# Step 2: Build the sidecar
# ============================================
echo ""
echo "🔨 Building NestJS sidecar..."

cd "$BACKEND_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    pnpm install
fi

# Build the sidecar
pnpm run build:sidecar

# Copy sidecar to Resources
echo "📦 Copying sidecar to Resources..."
rm -rf "$RESOURCES_DIR/sidecar"
cp -R "$BACKEND_DIR/sidecar/"* "$RESOURCES_DIR/sidecar/"

echo "✅ Sidecar built and copied"

# ============================================
# Step 3: Sign executables (if identity provided)
# ============================================
if [ -n "$SIGNING_IDENTITY" ]; then
    echo ""
    echo "🔏 Signing executables with: $SIGNING_IDENTITY"
    
    # Sign Node.js binary
    echo "  Signing Node.js..."
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$NODE_BINARY"
    
    # Sign native modules in node_modules
    echo "  Signing native modules..."
    
    # Find and sign all .node files (native modules)
    find "$RESOURCES_DIR/sidecar/node_modules" -name "*.node" -type f 2>/dev/null | while read -r module; do
        echo "    Signing: $(basename "$module")"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$module"
    done
    
    # Find and sign any dylib files
    find "$RESOURCES_DIR/sidecar/node_modules" -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
        echo "    Signing: $(basename "$dylib")"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$dylib"
    done
    
    # Sign any embedded executables
    find "$RESOURCES_DIR/sidecar/node_modules" -type f -perm +111 -name "*.bin" 2>/dev/null | while read -r bin; do
        echo "    Signing: $(basename "$bin")"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$bin"
    done
    
    echo "✅ All executables signed"
else
    echo ""
    echo "⚠️  No signing identity provided. Skipping code signing."
    echo "   For distribution, run with: --sign \"Developer ID Application: Your Name (TEAM_ID)\""
fi

# ============================================
# Step 4: Verify structure
# ============================================
echo ""
echo "📁 Resources structure:"
echo ""
find "$RESOURCES_DIR" -maxdepth 3 -type f | head -20
echo "..."

# Calculate total size
TOTAL_SIZE=$(du -sh "$RESOURCES_DIR" | cut -f1)
echo ""
echo "📏 Total Resources size: $TOTAL_SIZE"

# ============================================
# Done
# ============================================
echo ""
echo "============================================"
echo "✅ Distribution build complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Open Xcode and add the Resources folder to your project"
echo "2. Ensure 'Copy Bundle Resources' includes:"
echo "   - Resources/node/"
echo "   - Resources/sidecar/"
echo "3. Archive and distribute via Xcode"
echo ""
