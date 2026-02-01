//
//  DocumentsView.swift
//  ManeAI
//
//  Document list and management view
//

import SwiftUI
import SwiftData

struct DocumentsView: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.ingestedAt, order: .reverse) private var documents: [Document]
    
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var selectedDocument: Document?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter { doc in
            doc.fileName.localizedCaseInsensitiveContains(searchText) ||
            doc.filePath.localizedCaseInsensitiveContains(searchText)
        }
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
            allowedTypes: ["txt", "md", "swift", "ts", "js", "py", "json", "yaml", "yml", "xml", "html", "css"],
            allowMultiple: true,
            message: "Select files to import into your knowledge base"
        )
        
        guard !urls.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        for url in urls {
            do {
                let content = try SecurityBookmarks.shared.readFile(at: url)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                let response = try await apiService.ingestDocument(
                    content: content,
                    filePath: url.path,
                    metadata: [
                        "extension": url.pathExtension,
                        "importedAt": ISO8601DateFormatter().string(from: Date())
                    ]
                )
                
                // Save to local SwiftData
                let document = Document(
                    id: response.id,
                    fileName: response.fileName,
                    filePath: response.filePath,
                    fileExtension: url.pathExtension,
                    fileSize: fileSize
                )
                modelContext.insert(document)
                
            } catch {
                errorMessage = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        
        try? modelContext.save()
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
                    fileExtension: URL(fileURLWithPath: doc.filePath).pathExtension
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
            Image(systemName: document.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
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
                // Header
                HStack(spacing: 16) {
                    Image(systemName: document.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.fileName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(document.filePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Divider()
                
                // Details
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    DetailItem(title: "Size", value: document.formattedSize)
                    DetailItem(title: "Type", value: document.fileExtension.uppercased())
                    DetailItem(title: "Ingested", value: document.formattedDate)
                    DetailItem(title: "ID", value: String(document.id.prefix(12)) + "...")
                }
                
                Spacer()
            }
            .padding()
        }
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
