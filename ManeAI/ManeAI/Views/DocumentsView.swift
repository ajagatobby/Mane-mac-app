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
                
                Button {
                    Task {
                        await importFiles()
                    }
                } label: {
                    Label("Import Files", systemImage: "plus")
                }
                .help("Import files to your knowledge base")
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
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
                    Text("Import files to build your knowledge base")
                } actions: {
                    Button("Import Files") {
                        Task {
                            await importFiles()
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
    
    private func importFiles() async {
        let urls = await SecurityBookmarks.shared.selectFiles(
            allowedTypes: [
                // Text files
                "txt", "md", "swift", "ts", "js", "py", "json", "yaml", "yml", "xml", "html", "css", "csv",
                // Images
                "png", "jpg", "jpeg", "gif", "webp", "heic",
                // Audio
                "mp3", "wav", "m4a", "aiff", "flac", "ogg"
            ],
            allowMultiple: true,
            message: "Select files to import (text, images, audio)"
        )
        
        guard !urls.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        for url in urls {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let mediaType = getMediaType(for: url)
                
                let response: IngestResponse
                
                if mediaType == .text {
                    // Text files - read content
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
                    // Media files - just pass the path
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
                
            } catch {
                errorMessage = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        
        try? modelContext.save()
    }
    
    private func getMediaType(for url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
        let audioExtensions = ["mp3", "wav", "m4a", "aiff", "flac", "ogg"]
        
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        return .text
    }
    
    private func deleteDocument(_ document: Document) async {
        do {
            try await apiService.deleteDocument(id: document.id)
            modelContext.delete(document)
            try? modelContext.save()
            
            if selectedDocument == document {
                selectedDocument = nil
            }
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
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
