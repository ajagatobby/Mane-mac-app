//
//  DocumentsView.swift
//  ManeAI
//
//  Document list and management view with multimodal support
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.ingestedAt, order: .reverse) private var documents: [Document]
    
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var selectedDocument: Document?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterMediaType: MediaType? = nil
    @State private var importProgress: (current: Int, total: Int)? = nil
    @State private var showDeleteAllConfirmation = false
    @State private var showCodebaseAlert = false
    @State private var detectedCodebasePath: String? = nil
    @State private var detectedCodebaseType: String? = nil
    
    // Supported file types for multimodal ingestion
    private let supportedTypes: [UTType] = [
        // Text
        .plainText, .utf8PlainText, .sourceCode, .json, .xml, .yaml,
        // Images
        .png, .jpeg, .gif, .webP, .heic,
        // Audio
        .mp3, .wav, .aiff, .mpeg4Audio
    ]
    
    var filteredDocuments: [Document] {
        var result = documents
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { doc in
                doc.fileName.localizedCaseInsensitiveContains(searchText) ||
                doc.filePath.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by media type
        if let mediaType = filterMediaType {
            result = result.filter { $0.mediaType == mediaType.rawValue }
        }
        
        return result
    }
    
    var body: some View {
        NavigationSplitView {
            documentList
        } detail: {
            if let document = selectedDocument {
                DocumentDetailView(document: document)
            } else {
                ContentUnavailableView(
                    "Select a Document",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the list to view details")
                )
            }
        }
        .navigationTitle("Documents")
        .searchable(text: $searchText, prompt: "Search documents")
        .toolbar {
            ToolbarItemGroup {
                // Media type filter
                Menu {
                    Button("All Types") {
                        filterMediaType = nil
                    }
                    Divider()
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Button {
                            filterMediaType = type
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    Label(
                        filterMediaType?.displayName ?? "Filter",
                        systemImage: filterMediaType?.icon ?? "line.3.horizontal.decrease.circle"
                    )
                }
                
                Menu {
                    Button {
                        Task {
                            await importFiles()
                        }
                    } label: {
                        Label("Import Files...", systemImage: "doc.badge.plus")
                    }
                    
                    Button {
                        Task {
                            await importFolder()
                        }
                    } label: {
                        Label("Import Folder...", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .help("Import files or folder to your knowledge base")
                
                // Delete all button
                if !documents.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .help("Delete all documents")
                }
                
                if isLoading {
                    if let progress = importProgress {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("\(progress.current)/\(progress.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete All Documents",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All (\(documents.count) documents)", role: .destructive) {
                Task {
                    await deleteAllDocuments()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(documents.count) documents from your knowledge base. This action cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .alert("Codebase Detected", isPresented: $showCodebaseAlert) {
            Button("Index as Project") {
                Task {
                    await indexAsProject()
                }
            }
            Button("Import Files Only") {
                Task {
                    if let path = detectedCodebasePath {
                        await importFolderContents(URL(fileURLWithPath: path))
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                detectedCodebasePath = nil
                detectedCodebaseType = nil
            }
        } message: {
            Text("This folder appears to be a \(detectedCodebaseType ?? "code") project. Would you like to analyze it with smart indexing or just import the files?")
        }
        .task {
            await refreshDocuments()
        }
    }
    
    private var documentList: some View {
        List(selection: $selectedDocument) {
            if filteredDocuments.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Import files or a folder to build your knowledge base")
                } actions: {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await importFiles()
                            }
                        } label: {
                            Label("Import Files", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            Task {
                                await importFolder()
                            }
                        } label: {
                            Label("Import Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ForEach(filteredDocuments) { document in
                    DocumentRow(document: document)
                        .tag(document)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await deleteDocument(document)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await deleteDocument(filteredDocuments[index])
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
    
    // Supported file extensions for import
    private static let supportedExtensions = [
        // Text files
        "txt", "md", "csv",
        // Documents
        "pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "rtf",
        // Images
        "png", "jpg", "jpeg", "gif", "webp", "heic",
        // Audio
        "mp3", "wav", "m4a", "aiff", "flac", "ogg"
    ]
    
    private func importFiles() async {
        let urls = await SecurityBookmarks.shared.selectFiles(
            allowedTypes: Self.supportedExtensions,
            allowMultiple: true,
            message: "Select files to import (text, images, audio)"
        )
        
        guard !urls.isEmpty else { return }
        
        await importURLs(urls)
    }
    
    private func importFolder() async {
        guard let folderURL = await SecurityBookmarks.shared.selectDirectory(
            message: "Select a folder to import all supported files"
        ) else { return }
        
        isLoading = true
        
        // Check if it's a codebase
        do {
            let detection = try await apiService.detectCodebase(folderPath: folderURL.path)
            if detection.isCodebase {
                isLoading = false
                detectedCodebasePath = folderURL.path
                detectedCodebaseType = detection.type
                showCodebaseAlert = true
                return
            }
        } catch {
            // Detection failed, proceed with normal import
        }
        
        await importFolderContents(folderURL)
    }
    
    private func importFolderContents(_ folderURL: URL) async {
        isLoading = true
        
        do {
            // Get all supported files recursively
            let urls = try SecurityBookmarks.shared.listFilesRecursively(
                in: folderURL,
                extensions: Self.supportedExtensions
            )
            
            if urls.isEmpty {
                errorMessage = "No supported files found in the selected folder"
                isLoading = false
                return
            }
            
            await importURLs(urls)
        } catch {
            errorMessage = "Failed to read folder: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func indexAsProject() async {
        guard let path = detectedCodebasePath else { return }
        
        isLoading = true
        
        do {
            let response = try await apiService.indexProject(folderPath: path)
            
            if response.success {
                // Show success message
                errorMessage = response.message
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = "Failed to index project: \(error.localizedDescription)"
        }
        
        isLoading = false
        detectedCodebasePath = nil
        detectedCodebaseType = nil
    }
    
    private func importURLs(_ urls: [URL]) async {
        isLoading = true
        importProgress = (current: 0, total: urls.count)
        defer { 
            isLoading = false 
            importProgress = nil
        }
        
        var importedCount = 0
        var failedCount = 0
        
        for (index, url) in urls.enumerated() {
            importProgress = (current: index + 1, total: urls.count)
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let mediaType = getMediaType(for: url)
                
                let response: IngestResponse
                
                if mediaType == .text && !isBinaryDocument(url) {
                    // Plain text files - read content directly
                    let content = try SecurityBookmarks.shared.readFile(at: url)
                    response = try await apiService.ingestDocument(
                        content: content,
                        filePath: url.path,
                        mediaType: mediaType,
                        metadata: [
                            "extension": url.pathExtension,
                            "importedAt": ISO8601DateFormatter().string(from: Date())
                        ]
                    )
                } else {
                    // Media files and binary docs (PDF, Word, Excel) - backend handles extraction
                    response = try await apiService.ingestMediaFile(
                        filePath: url.path,
                        mediaType: mediaType,
                        metadata: [
                            "extension": url.pathExtension,
                            "importedAt": ISO8601DateFormatter().string(from: Date())
                        ]
                    )
                }
                
                // Save to local SwiftData
                let document = Document(
                    id: response.id,
                    fileName: response.fileName,
                    filePath: response.filePath,
                    fileExtension: url.pathExtension,
                    fileSize: fileSize,
                    mediaType: response.mediaType.rawValue
                )
                modelContext.insert(document)
                importedCount += 1
                
            } catch {
                failedCount += 1
                print("Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        try? modelContext.save()
        
        // Show summary for folder imports
        if urls.count > 1 {
            if failedCount > 0 {
                errorMessage = "Imported \(importedCount) files, \(failedCount) failed"
            }
        }
    }
    
    private func getMediaType(for url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
        let audioExtensions = ["mp3", "wav", "m4a", "aiff", "flac", "ogg"]
        
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        return .text
    }
    
    private func isBinaryDocument(_ url: URL) -> Bool {
        let binaryDocs = ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "rtf"]
        return binaryDocs.contains(url.pathExtension.lowercased())
    }
    
    private func deleteDocument(_ document: Document) async {
        // Try to delete from backend, ignore 404 (already deleted)
        do {
            try await apiService.deleteDocument(id: document.id)
        } catch {
            print("Backend delete skipped: \(error.localizedDescription)")
        }
        
        // Always delete from local SwiftData
        modelContext.delete(document)
        try? modelContext.save()
        
        if selectedDocument == document {
            selectedDocument = nil
        }
    }
    
    private func deleteAllDocuments() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await apiService.deleteAllDocuments()
            PanelManager.shared.clearIndexedDocumentsCache()
        } catch {
            print("Failed to delete all documents: \(error.localizedDescription)")
        }
        selectedDocument = nil
    }
    
    private func refreshDocuments() async {
        // Sync with backend
        do {
            let response = try await apiService.listDocuments()
            
            // Update local database
            let existingIds = Set(documents.map { $0.id })
            let remoteIds = Set(response.documents.map { $0.id })
            
            // Add missing documents
            for doc in response.documents where !existingIds.contains(doc.id) {
                let document = Document(
                    id: doc.id,
                    fileName: doc.fileName,
                    filePath: doc.filePath,
                    fileExtension: URL(fileURLWithPath: doc.filePath).pathExtension,
                    mediaType: doc.mediaType?.rawValue ?? "text",
                    thumbnailPath: doc.thumbnailPath
                )
                modelContext.insert(document)
            }
            
            // Remove documents that no longer exist on backend
            for document in documents where !remoteIds.contains(document.id) {
                modelContext.delete(document)
            }
            
            try? modelContext.save()
        } catch {
            // Silently fail - documents might just not be synced yet
        }
    }
}

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        HStack(spacing: 12) {
            // Media type icon or thumbnail
            Group {
                if document.mediaType == "image", FileManager.default.fileExists(atPath: document.filePath) {
                    AsyncImage(url: URL(fileURLWithPath: document.filePath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: document.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Media type badge
                    if let mediaType = MediaType(rawValue: document.mediaType) {
                        Label(mediaType.displayName, systemImage: mediaType.icon)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    Text(document.formattedSize)
                    Text("•")
                    Text(document.formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DocumentDetailView: View {
    let document: Document
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with preview
                mediaPreview
                
                Divider()
                
                // Details
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    DetailItem(title: "Size", value: document.formattedSize)
                    DetailItem(title: "Type", value: MediaType(rawValue: document.mediaType)?.displayName ?? document.fileExtension.uppercased())
                    DetailItem(title: "Ingested", value: document.formattedDate)
                    DetailItem(title: "ID", value: String(document.id.prefix(12)) + "...")
                }
                
                // File path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(document.filePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var mediaPreview: some View {
        HStack(spacing: 16) {
            // Preview based on media type
            Group {
                switch document.mediaType {
                case "image":
                    if FileManager.default.fileExists(atPath: document.filePath) {
                        AsyncImage(url: URL(fileURLWithPath: document.filePath)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        placeholderIcon
                    }
                    
                case "audio":
                    VStack {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.purple)
                        Text("Audio File")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100, height: 100)
                    
                default:
                    placeholderIcon
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.fileName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let mediaType = MediaType(rawValue: document.mediaType) {
                    Label(mediaType.displayName, systemImage: mediaType.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    private var placeholderIcon: some View {
        Image(systemName: document.icon)
            .font(.system(size: 48))
            .foregroundStyle(.blue)
            .frame(width: 80, height: 80)
    }
}

struct DetailItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DocumentsView()
        .environmentObject(APIService())
}
