//
//  DocumentIndexingService.swift
//  ManeAI
//
//  Smart document indexing service with deduplication
//

import Foundation
import SwiftData
import Combine

/// Result of an indexing operation
enum IndexingResult {
    case indexed(id: String, fileName: String)
    case alreadyIndexed(id: String, fileName: String)
    case failed(error: Error)
    
    var isSuccess: Bool {
        switch self {
        case .indexed, .alreadyIndexed: return true
        case .failed: return false
        }
    }
    
    var documentId: String? {
        switch self {
        case .indexed(let id, _), .alreadyIndexed(let id, _): return id
        case .failed: return nil
        }
    }
    
    var fileName: String? {
        switch self {
        case .indexed(_, let name), .alreadyIndexed(_, let name): return name
        case .failed: return nil
        }
    }
    
    var wasNewlyIndexed: Bool {
        if case .indexed = self { return true }
        return false
    }
}

/// Service for smart document indexing with caching and deduplication
@MainActor
class DocumentIndexingService: ObservableObject {
    private let apiService: APIService
    private let modelContext: ModelContext?
    
    @Published var isIndexing = false
    @Published var indexingProgress: String = ""
    @Published var lastIndexedFile: String?
    
    init(apiService: APIService, modelContext: ModelContext?) {
        self.apiService = apiService
        self.modelContext = modelContext
    }
    
    // MARK: - Smart Indexing
    
    /// Index a file if it hasn't been indexed or has changed
    /// - Parameters:
    ///   - url: URL of the file to index
    ///   - forceReindex: If true, reindex even if file hasn't changed
    /// - Returns: IndexingResult indicating success/skip/failure
    func indexFileIfNeeded(_ url: URL, forceReindex: Bool = false) async -> IndexingResult {
        isIndexing = true
        indexingProgress = "Checking file..."
        
        defer {
            isIndexing = false
            indexingProgress = ""
        }
        
        let fileName = url.lastPathComponent
        let filePath = url.path
        
        // Get file attributes
        guard let attrs = FileHasher.attributes(fileAt: url) else {
            return .failed(error: IndexingError.fileNotAccessible)
        }
        
        // Compute content hash
        indexingProgress = "Computing hash..."
        guard let contentHash = FileHasher.hash(fileAt: url) else {
            return .failed(error: IndexingError.hashComputationFailed)
        }
        
        // Check if already indexed with same hash
        if !forceReindex, let existingFile = findIndexedFile(path: filePath, hash: contentHash) {
            print("📚 File already indexed: \(fileName) (hash match)")
            lastIndexedFile = fileName
            return .alreadyIndexed(id: existingFile.id, fileName: existingFile.fileName)
        }
        
        // Determine media type
        let mediaType = determineMediaType(for: url)
        
        // Index the file
        indexingProgress = "Indexing \(fileName)..."
        
        do {
            let response: IngestResponse
            
            if mediaType == .text {
                // Read text content
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    return .failed(error: IndexingError.contentReadFailed)
                }
                response = try await apiService.ingestDocument(
                    content: content,
                    filePath: filePath,
                    mediaType: mediaType
                )
            } else {
                // Index media file
                response = try await apiService.ingestMediaFile(
                    filePath: filePath,
                    mediaType: mediaType
                )
            }
            
            // Store in local database
            saveIndexedFile(
                id: response.id,
                filePath: filePath,
                contentHash: contentHash,
                fileSize: attrs.size,
                fileModifiedAt: attrs.modified,
                mediaType: mediaType.rawValue,
                fileName: response.fileName
            )
            
            print("✅ Indexed new file: \(fileName)")
            lastIndexedFile = fileName
            return .indexed(id: response.id, fileName: response.fileName)
            
        } catch {
            print("❌ Failed to index \(fileName): \(error)")
            return .failed(error: error)
        }
    }
    
    /// Index multiple files, skipping already-indexed ones
    func indexFilesIfNeeded(_ urls: [URL]) async -> [IndexingResult] {
        var results: [IndexingResult] = []
        
        for (index, url) in urls.enumerated() {
            indexingProgress = "Processing \(index + 1)/\(urls.count)..."
            let result = await indexFileIfNeeded(url)
            results.append(result)
        }
        
        return results
    }
    
    /// Check if a file needs indexing (changed or not indexed)
    func needsIndexing(_ url: URL) -> Bool {
        guard let contentHash = FileHasher.hash(fileAt: url) else {
            return true // Assume needs indexing if can't read
        }
        return findIndexedFile(path: url.path, hash: contentHash) == nil
    }
    
    /// Get the document ID for an already-indexed file
    func getIndexedFileId(for url: URL) -> String? {
        guard let contentHash = FileHasher.hash(fileAt: url) else { return nil }
        return findIndexedFile(path: url.path, hash: contentHash)?.id
    }
    
    // MARK: - Private Helpers
    
    private func findIndexedFile(path: String, hash: String) -> IndexedFile? {
        guard let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { file in
                file.filePath == path && file.contentHash == hash
            }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    private func findIndexedFileByPath(_ path: String) -> IndexedFile? {
        guard let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { file in
                file.filePath == path
            }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    private func saveIndexedFile(
        id: String,
        filePath: String,
        contentHash: String,
        fileSize: Int64,
        fileModifiedAt: Date,
        mediaType: String,
        fileName: String
    ) {
        guard let context = modelContext else { return }
        
        // Remove any existing record for this path
        if let existing = findIndexedFileByPath(filePath) {
            context.delete(existing)
        }
        
        // Create new record
        let indexedFile = IndexedFile(
            id: id,
            filePath: filePath,
            contentHash: contentHash,
            fileSize: fileSize,
            fileModifiedAt: fileModifiedAt,
            mediaType: mediaType,
            fileName: fileName
        )
        
        context.insert(indexedFile)
        try? context.save()
    }
    
    private func determineMediaType(for url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        
        // Image types
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"]
        if imageExtensions.contains(ext) {
            return .image
        }
        
        // Audio types
        let audioExtensions = ["mp3", "wav", "m4a", "aac", "ogg", "flac", "aiff", "wma"]
        if audioExtensions.contains(ext) {
            return .audio
        }
        
        // Default to text
        return .text
    }
}

// MARK: - Indexing Errors

enum IndexingError: LocalizedError {
    case fileNotAccessible
    case hashComputationFailed
    case contentReadFailed
    case alreadyIndexing
    
    var errorDescription: String? {
        switch self {
        case .fileNotAccessible:
            return "Cannot access the file"
        case .hashComputationFailed:
            return "Failed to compute file hash"
        case .contentReadFailed:
            return "Failed to read file content"
        case .alreadyIndexing:
            return "Already indexing a file"
        }
    }
}
