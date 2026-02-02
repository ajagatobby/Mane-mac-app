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
    
    /// Index multiple files, skipping already-indexed ones (legacy sequential)
    func indexFilesIfNeeded(_ urls: [URL]) async -> [IndexingResult] {
        // Use concurrent processing by default for better performance
        return await indexFilesIfNeededConcurrent(urls)
    }
    
    /// Index multiple files concurrently using TaskGroup (up to 100x faster)
    /// - Parameters:
    ///   - urls: Files to index
    ///   - maxConcurrency: Maximum parallel operations (default: 10)
    /// - Returns: Array of IndexingResult for each file
    func indexFilesIfNeededConcurrent(_ urls: [URL], maxConcurrency: Int = 10) async -> [IndexingResult] {
        guard !urls.isEmpty else { return [] }
        
        isIndexing = true
        indexingProgress = "Preparing \(urls.count) files..."
        
        defer {
            isIndexing = false
            indexingProgress = ""
        }
        
        // First pass: Check which files need indexing (parallel hash computation)
        var filesToIndex: [(index: Int, url: URL, content: String?, mediaType: MediaType)] = []
        var cachedResults: [(index: Int, result: IndexingResult)] = []
        
        // Compute hashes and check cache in parallel
        await withTaskGroup(of: (Int, URL, String?, IndexingResult?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let filePath = url.path
                    
                    // Compute hash
                    guard let contentHash = FileHasher.hash(fileAt: url) else {
                        return (index, url, nil, .failed(error: IndexingError.hashComputationFailed))
                    }
                    
                    // Check if already indexed
                    if let existingFile = await self.findIndexedFile(path: filePath, hash: contentHash) {
                        return (index, url, contentHash, .alreadyIndexed(id: existingFile.id, fileName: existingFile.fileName))
                    }
                    
                    return (index, url, contentHash, nil)
                }
            }
            
            for await (index, url, hash, cachedResult) in group {
                if let result = cachedResult {
                    cachedResults.append((index, result))
                } else if hash != nil {
                    let mediaType = determineMediaType(for: url)
                    
                    // Read text content if needed
                    var content: String? = nil
                    if mediaType == .text {
                        content = try? String(contentsOf: url, encoding: .utf8)
                    }
                    
                    filesToIndex.append((index, url, content, mediaType))
                }
            }
        }
        
        // If all files are cached, return early
        if filesToIndex.isEmpty {
            indexingProgress = "All files already indexed"
            return cachedResults.sorted(by: { $0.index < $1.index }).map(\.result)
        }
        
        indexingProgress = "Indexing \(filesToIndex.count) new files..."
        
        // Separate by media type for batch processing
        let textFiles = filesToIndex.filter { $0.mediaType == .text && $0.content != nil }
        let mediaFiles = filesToIndex.filter { $0.mediaType != .text || $0.content == nil }
        
        var indexedResults: [(index: Int, result: IndexingResult)] = []
        
        // Batch process text files using the batch API
        if !textFiles.isEmpty {
            do {
                let requests = textFiles.map { file in
                    IngestRequest(
                        content: file.content,
                        filePath: file.url.path,
                        mediaType: .text,
                        metadata: nil
                    )
                }
                
                let batchResponse = try await apiService.batchIngest(files: requests, concurrency: maxConcurrency)
                
                for (i, response) in batchResponse.results.enumerated() {
                    let fileInfo = textFiles[i]
                    if response.success {
                        // Save to local cache
                        if let attrs = FileHasher.attributes(fileAt: fileInfo.url),
                           let hash = FileHasher.hash(fileAt: fileInfo.url) {
                            saveIndexedFile(
                                id: response.id,
                                filePath: fileInfo.url.path,
                                contentHash: hash,
                                fileSize: attrs.size,
                                fileModifiedAt: attrs.modified,
                                mediaType: fileInfo.mediaType.rawValue,
                                fileName: response.fileName
                            )
                        }
                        indexedResults.append((fileInfo.index, .indexed(id: response.id, fileName: response.fileName)))
                    } else {
                        indexedResults.append((fileInfo.index, .failed(error: APIError.serverError(500, response.message))))
                    }
                }
                
                print("✅ Batch indexed \(batchResponse.success) text files in \(batchResponse.elapsedMs)ms")
            } catch {
                // Fallback to individual processing if batch fails
                print("⚠️ Batch API failed, falling back to sequential: \(error)")
                for file in textFiles {
                    let result = await indexSingleFile(file.url, content: file.content, mediaType: file.mediaType)
                    indexedResults.append((file.index, result))
                }
            }
        }
        
        // Process media files concurrently (audio/image need individual processing)
        if !mediaFiles.isEmpty {
            await withTaskGroup(of: (Int, IndexingResult).self) { group in
                // Use semaphore pattern for controlled concurrency
                let semaphore = AsyncSemaphore(limit: maxConcurrency)
                
                for file in mediaFiles {
                    group.addTask {
                        await semaphore.wait()
                        
                        let result = await self.indexSingleFile(file.url, content: file.content, mediaType: file.mediaType)
                        
                        await semaphore.signal()
                        return (file.index, result)
                    }
                }
                
                for await (index, result) in group {
                    indexedResults.append((index, result))
                }
            }
        }
        
        // Combine and sort results
        let allResults = (cachedResults + indexedResults).sorted(by: { $0.index < $1.index })
        
        let newlyIndexed = indexedResults.filter { $0.result.wasNewlyIndexed }.count
        indexingProgress = "Done! Indexed \(newlyIndexed) new files"
        
        return allResults.map(\.result)
    }
    
    /// Index a single file (used for media files that need individual processing)
    private func indexSingleFile(_ url: URL, content: String?, mediaType: MediaType) async -> IndexingResult {
        let fileName = url.lastPathComponent
        let filePath = url.path
        
        do {
            let response: IngestResponse
            
            if mediaType == .text, let textContent = content {
                response = try await apiService.ingestDocument(
                    content: textContent,
                    filePath: filePath,
                    mediaType: mediaType
                )
            } else {
                response = try await apiService.ingestMediaFile(
                    filePath: filePath,
                    mediaType: mediaType
                )
            }
            
            // Save to local cache
            if let attrs = FileHasher.attributes(fileAt: url),
               let hash = FileHasher.hash(fileAt: url) {
                saveIndexedFile(
                    id: response.id,
                    filePath: filePath,
                    contentHash: hash,
                    fileSize: attrs.size,
                    fileModifiedAt: attrs.modified,
                    mediaType: mediaType.rawValue,
                    fileName: response.fileName
                )
            }
            
            return .indexed(id: response.id, fileName: response.fileName)
        } catch {
            print("❌ Failed to index \(fileName): \(error)")
            return .failed(error: error)
        }
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

// MARK: - Async Semaphore for Controlled Concurrency

/// A simple async semaphore for limiting concurrent operations
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(limit: Int) {
        self.count = limit
    }
    
    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}
