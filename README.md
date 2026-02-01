# ManeAI - Local AI File Organizer

A native macOS application that helps you organize and understand your files using local AI. Built with SwiftUI for the frontend and NestJS (TypeScript) for the AI backend.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS App (SwiftUI)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Sidebar   │  │  Documents  │  │    Chat / Detail    │  │
│  │  Navigation │  │    List     │  │       View          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                            │                                 │
│                    HTTP (localhost:3000)                     │
└────────────────────────────┼────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────┐
│                    NestJS Sidecar                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Ingest    │  │    Chat     │  │    LanceDB          │  │
│  │  Controller │  │  Controller │  │    (Vector DB)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                            │                                 │
│                    LangChain + Ollama                        │
└────────────────────────────┼────────────────────────────────┘
                             │
                      ┌──────┴──────┐
                      │   Ollama    │
                      │  (qwen2.5)  │
                      └─────────────┘
```

## Features

- **Document Ingestion**: Import text files into a vector database for semantic search
- **AI Chat**: Ask questions about your files using RAG (Retrieval Augmented Generation)
- **Local Processing**: All AI processing happens locally using Ollama
- **Native macOS UI**: Beautiful SwiftUI interface with 3-pane navigation

## Prerequisites

### 1. Install Ollama

```bash
brew install ollama
```

### 2. Pull the Qwen model

```bash
ollama pull qwen2.5
```

### 3. Start Ollama

```bash
ollama serve
```

### 4. Install Node.js (for development)

```bash
brew install node
```

## Project Structure

```
mane-ai/
├── ManeAI/                    # SwiftUI macOS App
│   └── ManeAI/
│       ├── Services/
│       │   ├── SidecarManager.swift   # Process lifecycle
│       │   └── APIService.swift       # HTTP client
│       ├── Views/
│       │   ├── ContentView.swift      # Main layout
│       │   ├── SidebarView.swift      # Navigation
│       │   ├── DocumentsView.swift    # File management
│       │   ├── ChatView.swift         # AI chat
│       │   └── SettingsView.swift     # Settings
│       ├── Models/
│       │   ├── Document.swift
│       │   └── ChatMessage.swift
│       └── Utilities/
│           └── SecurityBookmarks.swift
│
└── mane-ai-backend/           # NestJS Backend
    └── src/
        ├── config/            # CLI argument parsing
        ├── lancedb/           # Vector DB + embeddings
        ├── ollama/            # LangChain + Ollama
        ├── ingest/            # /ingest endpoint
        └── chat/              # /chat endpoint
```

## Development Setup

### Backend (NestJS)

```bash
cd mane-ai-backend

# Install dependencies
pnpm install

# Run in development mode
pnpm start:dev
```

The backend will start on `http://localhost:3000`.

### Frontend (SwiftUI)

1. Open `ManeAI/ManeAI.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (Cmd+R)

### Building for Production

```bash
cd mane-ai-backend

# Build the sidecar package
pnpm run build:sidecar
```

This creates a `sidecar/` folder containing:
- Compiled JavaScript
- Required node_modules
- Launch script

## API Endpoints

### Health Check
```
GET /health
Response: { status: "healthy", timestamp: "...", uptime: 123 }
```

### Ingest Document
```
POST /ingest
Body: { content: "...", filePath: "/path/to/file.txt", metadata: {} }
Response: { id: "doc_...", fileName: "file.txt", success: true }
```

### Chat
```
POST /chat
Body: { query: "What files do I have?", stream: true }
Response: SSE stream or { answer: "...", sources: [...] }
```

### Search
```
POST /chat/search
Body: { query: "find documents about...", limit: 5 }
Response: { results: [...] }
```

## Bundling the Sidecar in the App

For distribution, you need to bundle the sidecar with the macOS app:

1. Build the sidecar: `pnpm run build:sidecar`
2. In Xcode, add the `sidecar/` folder to your project
3. Add it to "Copy Bundle Resources" build phase
4. Bundle Node.js runtime (or require users to install it)

### Alternative: Use a Pre-built Node.js

For simplicity during development, the app checks if Node.js is available at `/usr/local/bin/node`. For production distribution, you should bundle a Node.js runtime.

## Entitlements

The app requires these entitlements for sandboxed operation:

- `com.apple.security.app-sandbox`: Enable sandbox
- `com.apple.security.files.user-selected.read-write`: Access user files
- `com.apple.security.network.client`: Connect to localhost
- `com.apple.security.cs.allow-unsigned-executable-memory`: Run Node.js

## Troubleshooting

### Backend not starting
- Check if port 3000 is available
- Ensure Node.js is installed
- Check the logs in Settings > View Logs

### Ollama not available
- Run `ollama serve` in terminal
- Check if model is downloaded: `ollama list`
- Pull the model: `ollama pull qwen2.5`

### File import fails
- Ensure the file is a supported type (txt, md, swift, etc.)
- Check file permissions
- The app needs read access to the file

## License

MIT
