# ManeAI - Local AI Knowledge Base

A native macOS application for building a personal knowledge base with AI-powered search and chat. Index documents, code projects, images, and audio files - then ask questions using RAG (Retrieval Augmented Generation). All processing happens locally.

## Features

### 🗂️ Unified Knowledge Base
- **Auto-detect Projects**: Import folders and ManeAI automatically detects code projects
- **Smart Indexing**: Code projects are indexed with function/class signatures for semantic search
- **Multimodal Support**: Import text, images, and audio files
- **Semantic Search**: Find files by meaning, not just keywords

### 💬 RAG Chat
- **Ask Questions**: Chat about your indexed documents and code
- **Source Citations**: See which files informed the AI's response
- **Streaming Responses**: Real-time streaming for a fluid chat experience

### 🔒 Privacy First
- **100% Local**: No data leaves your machine
- **Ollama Powered**: Uses local LLMs (qwen2.5)
- **Vector DB**: LanceDB stores embeddings locally

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   macOS App (SwiftUI)                       │
│  ┌───────────┐  ┌───────────────┐  ┌───────────────────┐   │
│  │  Sidebar  │  │ Knowledge Base│  │    AI Chat        │   │
│  │    Nav    │  │  (Docs+Proj)  │  │                   │   │
│  └───────────┘  └───────────────┘  └───────────────────┘   │
│                          │                                  │
│                  HTTP (localhost:3000)                      │
└──────────────────────────┼──────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────┐
│                   NestJS Backend                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────────────┐    │
│  │ Ingest  │ │  Chat   │ │ Search  │ │    Projects    │    │
│  │   API   │ │   API   │ │   API   │ │      API       │    │
│  └─────────┘ └─────────┘ └─────────┘ └────────────────┘    │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────┐     │
│  │              LanceDB (Vector Database)             │     │
│  │   documents | projects | code_skeletons            │     │
│  └───────────────────────────────────────────────────┘     │
│                          │                                  │
│                  LangChain + Ollama                         │
└──────────────────────────┼──────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │   Ollama    │
                    │  (Local AI) │
                    └─────────────┘
```

## Quick Start

### Prerequisites

1. **Install Ollama**
   ```bash
   brew install ollama
   ```

2. **Pull the AI model**
   ```bash
   ollama pull qwen2.5
   ```

3. **Start Ollama**
   ```bash
   ollama serve
   ```

4. **Install Node.js**
   ```bash
   brew install node pnpm
   ```

### Running the App

#### Backend
```bash
cd mane-ai-backend
pnpm install
pnpm start:dev
```

#### Frontend
1. Open `ManeAI/ManeAI.xcodeproj` in Xcode
2. Build and run (Cmd+R)

## Usage

### Importing Content

Click **Import** in the Knowledge Base to add files or folders:

| Content Type | What Happens |
|--------------|--------------|
| **Code Project** (has package.json, Cargo.toml, etc.) | Indexed as a Project with code signatures |
| **Folder** (no manifest) | All supported files imported as Documents |
| **Individual Files** | Imported as Documents |

### Supported File Types

- **Text**: txt, md, swift, ts, js, py, json, yaml, xml, html, css, csv
- **Images**: png, jpg, jpeg, gif, webp, heic (with AI-generated captions)
- **Audio**: mp3, wav, m4a, aiff, flac, ogg (with transcription)

### Project Detection

Projects are auto-detected by these manifest files:

| File | Language/Framework |
|------|-------------------|
| `package.json` | Node.js / JavaScript / TypeScript |
| `Cargo.toml` | Rust |
| `pyproject.toml`, `setup.py`, `requirements.txt` | Python |
| `go.mod` | Go |
| `pom.xml`, `build.gradle` | Java |
| `Gemfile` | Ruby |
| `composer.json` | PHP |
| `Package.swift` | Swift |
| `pubspec.yaml` | Dart/Flutter |
| `.git` | Any Git repository |

### Chat

Use the AI Chat to ask questions about your indexed content:

- "What files do I have about authentication?"
- "Summarize my Python projects"
- "Find code that handles database connections"
- "What images contain landscapes?"

## Project Structure

```
mane-ai/
├── ManeAI/                        # SwiftUI macOS App
│   └── ManeAI/
│       ├── Services/
│       │   ├── SidecarManager.swift    # Backend lifecycle
│       │   └── APIService.swift        # HTTP client
│       ├── Views/
│       │   ├── ContentView.swift       # Main layout
│       │   ├── SidebarView.swift       # Navigation
│       │   ├── DocumentsView.swift     # Knowledge Base
│       │   ├── ChatView.swift          # AI chat
│       │   └── SettingsView.swift      # Settings
│       ├── Models/
│       │   ├── Document.swift          # Document model
│       │   ├── Project.swift           # Project model
│       │   └── ChatMessage.swift       # Chat model
│       └── Utilities/
│           └── SecurityBookmarks.swift # Sandbox access
│
└── mane-ai-backend/               # NestJS Backend
    └── src/
        ├── config/                # Configuration
        ├── lancedb/               # Vector DB service
        ├── ollama/                # LangChain + Ollama
        ├── multimodal/            # Image/audio processing
        ├── ingest/                # Document ingestion
        ├── chat/                  # RAG chat
        └── projects/              # Project indexing
```

## API Reference

### Documents

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ingest` | POST | Ingest a text document |
| `/ingest/media` | POST | Ingest image/audio |
| `/documents` | GET | List all documents |
| `/documents/:id` | DELETE | Delete a document |

### Chat

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/chat` | POST | Chat with RAG |
| `/chat/search` | POST | Semantic search |
| `/chat/status` | GET | Get Ollama status |

### Projects

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/projects/index` | POST | Index a project |
| `/projects` | GET | List all projects |
| `/projects/:id` | GET | Get project details |
| `/projects/:id` | DELETE | Delete a project |
| `/projects/search` | POST | Search projects |
| `/projects/search/code` | POST | Search code signatures |

## Configuration

### Backend CLI Arguments

```bash
pnpm start:dev -- \
  --port 3000 \
  --ollama-url http://localhost:11434 \
  --ollama-model qwen2.5 \
  --db-path ~/Library/Application\ Support/ManeAI/lancedb
```

## Troubleshooting

### Backend not starting
- Check if port 3000 is available
- Ensure Node.js 18+ is installed
- Check logs in Settings > View Logs

### Ollama not available
- Run `ollama serve` in terminal
- Check if model is downloaded: `ollama list`
- Pull the model: `ollama pull qwen2.5`

### File import fails
- Ensure the file is a supported type
- Check file permissions
- The app needs read access via Security-Scoped Bookmarks

### Clear vector database
```bash
rm -rf ~/Library/Application\ Support/ManeAI/lancedb
```
Then restart the backend.

## License

MIT
