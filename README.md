<p align="center">
  <img src="assets/app-icon.png" alt="Mane AI Logo" width="128" height="128">
</p>

<h1 align="center">Mane AI</h1>

<p align="center">
  <strong>Your Private AI Knowledge Base for macOS</strong>
</p>

<p align="center">
  Index documents, code, images, and audio — then chat with your data using local AI.
  <br>
  <em>100% private. Everything runs on your machine.</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#usage">Usage</a> •
  <a href="#architecture">Architecture</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Node.js-20+-green?style=flat-square&logo=node.js" alt="Node.js">
  <img src="https://img.shields.io/badge/Ollama-Local%20AI-purple?style=flat-square" alt="Ollama">
  <img src="https://img.shields.io/github/license/ajagatobby/Mane-mac-app?style=flat-square" alt="License">
</p>

---

## Why Mane AI?

Most AI tools send your data to the cloud. **Mane AI is different** — it's a native macOS app that keeps everything local:

- **Your documents stay on your Mac** — no cloud uploads, no data harvesting
- **Powered by Ollama** — run powerful LLMs locally
- **Semantic search** — find files by meaning, not just keywords
- **Multimodal** — understands text, code, images, and audio

---

## Features

<table>
<tr>
<td width="50%">

### 📚 Unified Knowledge Base

Import folders and files to build your personal knowledge base. Mane AI automatically detects code projects and indexes them intelligently.

</td>
<td width="50%">

### 💬 RAG-Powered Chat

Ask questions about your documents and get AI responses with source citations. The AI retrieves relevant context before answering.

</td>
</tr>
<tr>
<td width="50%">

### 🔍 Semantic Search

Find files by what they mean, not just exact keywords. Search across documents, code, and even image descriptions.

</td>
<td width="50%">

### 🎨 Multimodal Support

Index images (with AI captions) and audio files (with transcription). Ask questions about visual and audio content.

</td>
</tr>
<tr>
<td width="50%">

### 🛡️ 100% Private

No telemetry, no cloud, no accounts. Your data never leaves your machine. Period.

</td>
<td width="50%">

### ⚡ Native Performance

Built with SwiftUI for a fast, responsive experience. Metal-accelerated animations and efficient resource usage.

</td>
</tr>
</table>

---

## Installation

### Prerequisites

Before installing Mane AI, you need:

| Requirement     | Installation          |
| --------------- | --------------------- |
| **macOS 14+**   | Sonoma or later       |
| **Ollama**      | `brew install ollama` |
| **Node.js 20+** | `brew install node`   |
| **pnpm**        | `npm install -g pnpm` |

### Step 1: Install Ollama and Pull Model

```bash
# Install Ollama
brew install ollama

# Start Ollama service
ollama serve

# In a new terminal, pull the AI model
ollama pull qwen2.5
```

### Step 2: Download Mane AI

Download the latest release from the [Releases](https://github.com/ajagatobby/Mane-mac-app/releases) page.

Or build from source:

```bash
# Clone the repository
git clone https://github.com/ajagatobby/Mane-mac-app.git
cd Mane-mac-app

# Install backend dependencies
cd mane-ai-backend
pnpm install

# Open in Xcode
open ../ManeAI/ManePaw.xcodeproj
```

---

## Quick Start

### 1. Start Ollama

Make sure Ollama is running:

```bash
ollama serve
```

### 2. Start the Backend (Development)

```bash
cd mane-ai-backend
pnpm start:dev
```

### 3. Run the App

Open `ManeAI/ManePaw.xcodeproj` in Xcode and press `Cmd + R`.

---

## Usage

### Importing Content

Click **Import** to add files or folders to your knowledge base:

| Content Type      | How It's Processed                                                                                   |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| **Code Projects** | Detected by manifest files (package.json, Cargo.toml, etc.). Indexed with function/class signatures. |
| **Documents**     | Text files are chunked and embedded for semantic search.                                             |
| **Images**        | AI generates captions describing the visual content.                                                 |
| **Audio**         | Automatically transcribed to searchable text.                                                        |

### Supported File Types

| Category   | Extensions                                                  |
| ---------- | ----------------------------------------------------------- |
| **Text**   | `.txt` `.md` `.json` `.yaml` `.xml` `.html` `.css` `.csv`   |
| **Code**   | `.swift` `.ts` `.js` `.py` `.rs` `.go` `.java` `.rb` `.php` |
| **Images** | `.png` `.jpg` `.jpeg` `.gif` `.webp` `.heic`                |
| **Audio**  | `.mp3` `.wav` `.m4a` `.aiff` `.flac` `.ogg`                 |

### Project Detection

Mane AI automatically detects projects by these manifest files:

| Manifest                              | Language/Framework   |
| ------------------------------------- | -------------------- |
| `package.json`                        | Node.js / TypeScript |
| `Cargo.toml`                          | Rust                 |
| `pyproject.toml` / `requirements.txt` | Python               |
| `go.mod`                              | Go                   |
| `Package.swift`                       | Swift                |
| `pom.xml` / `build.gradle`            | Java                 |
| `pubspec.yaml`                        | Flutter              |

### Chat Examples

Ask natural questions about your indexed content:

> "What files do I have about authentication?"

> "Summarize my Python projects"

> "Find code that handles database connections"

> "What images contain landscapes?"

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Mane AI (SwiftUI)                           │
│  ┌─────────────┐  ┌─────────────────┐  ┌───────────────────┐   │
│  │   Sidebar   │  │  Knowledge Base │  │     AI Chat       │   │
│  │ Navigation  │  │  Documents/Code │  │   RAG Interface   │   │
│  └─────────────┘  └─────────────────┘  └───────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP (localhost:3000)
┌────────────────────────────┴────────────────────────────────────┐
│                     NestJS Backend                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │  Ingest  │  │   Chat   │  │  Search  │  │   Projects   │    │
│  │   API    │  │   API    │  │   API    │  │     API      │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
│                             │                                   │
│  ┌──────────────────────────┴────────────────────────────┐     │
│  │              LanceDB (Vector Database)                 │     │
│  │        Embeddings • Semantic Search • RAG              │     │
│  └───────────────────────────────────────────────────────┘     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │     Ollama      │
                    │   Local LLMs    │
                    │   (qwen2.5)     │
                    └─────────────────┘
```

---

## Project Structure

```
mane-ai/
├── ManeAI/                          # SwiftUI macOS App
│   └── ManePaw/
│       ├── Views/                   # UI Components
│       ├── Services/                # API & Sidecar Management
│       ├── Models/                  # Data Models
│       └── Theme/                   # Metal Shaders & Styling
│
├── mane-ai-backend/                 # NestJS Backend
│   └── src/
│       ├── chat/                    # RAG Chat API
│       ├── ingest/                  # Document Ingestion
│       ├── projects/                # Project Indexing
│       ├── lancedb/                 # Vector Database
│       └── ollama/                  # LLM Integration
│
└── scripts/                         # Build & Distribution
```

---

## API Reference

<details>
<summary><strong>Documents API</strong></summary>

| Endpoint         | Method | Description             |
| ---------------- | ------ | ----------------------- |
| `/ingest`        | POST   | Ingest a text document  |
| `/ingest/media`  | POST   | Ingest image/audio file |
| `/documents`     | GET    | List all documents      |
| `/documents/:id` | DELETE | Delete a document       |

</details>

<details>
<summary><strong>Chat API</strong></summary>

| Endpoint       | Method | Description           |
| -------------- | ------ | --------------------- |
| `/chat`        | POST   | Chat with RAG context |
| `/chat/search` | POST   | Semantic search       |
| `/chat/status` | GET    | Check Ollama status   |

</details>

<details>
<summary><strong>Projects API</strong></summary>

| Endpoint                | Method | Description            |
| ----------------------- | ------ | ---------------------- |
| `/projects/index`       | POST   | Index a code project   |
| `/projects`             | GET    | List all projects      |
| `/projects/:id`         | GET    | Get project details    |
| `/projects/:id`         | DELETE | Delete a project       |
| `/projects/search`      | POST   | Search projects        |
| `/projects/search/code` | POST   | Search code signatures |

</details>

---

## Troubleshooting

<details>
<summary><strong>Ollama not connecting</strong></summary>

1. Make sure Ollama is running:

   ```bash
   ollama serve
   ```

2. Check if the model is downloaded:

   ```bash
   ollama list
   ```

3. Pull the model if needed:
   ```bash
   ollama pull qwen2.5
   ```

</details>

<details>
<summary><strong>Backend won't start</strong></summary>

1. Check if port 3000 is available
2. Ensure Node.js 20+ is installed: `node --version`
3. Reinstall dependencies: `pnpm install`

</details>

<details>
<summary><strong>Reset the database</strong></summary>

```bash
rm -rf ~/Library/Application\ Support/ManePaw/lancedb
```

Then restart the app.

</details>

---

## Distribution

For information on building and distributing the app, see [DISTRIBUTION.md](./DISTRIBUTION.md).

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## License

MIT License — see [LICENSE](./LICENSE) for details.

---

## Hire Me

I'm available for freelance and contract work! If you need help building:

- Native macOS/iOS apps with SwiftUI
- AI-powered applications with RAG and LLMs
- Full-stack web applications

**Let's connect:**

<p align="center">
  <a href="https://twitter.com/ajagatobby"><img src="https://img.shields.io/badge/Twitter-@ajagatobby?style=flat-square&logo=twitter&logoColor=white" alt="Twitter"></a>
  <a href="https://github.com/ajagatobby"><img src="https://img.shields.io/badge/GitHub-ajagatobby-181717?style=flat-square&logo=github" alt="GitHub"></a>
  <a href="mailto:ajagatobby@gmail.com"><img src="https://img.shields.io/badge/Email-Contact%20Me-red?style=flat-square&logo=gmail&logoColor=white" alt="Email"></a>
</p>

---

<p align="center">
  <sub>Built with ❤️ using SwiftUI, NestJS, LanceDB, and Ollama</sub>
</p>
