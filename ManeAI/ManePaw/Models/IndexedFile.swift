//
//  IndexedFile.swift
//  ManeAI
//
//  Tracks indexed files with content hash for deduplication
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class IndexedFile {
    /// Unique identifier from backend
    var id: String
    
    /// Original file path
    var filePath: String
    
    /// SHA256 hash of file content for change detection
    var contentHash: String
    
    /// File size at time of indexing
    var fileSize: Int64
    
    /// Last modified date of the file when indexed
    var fileModifiedAt: Date
    
    /// When this file was indexed
    var indexedAt: Date
    
    /// Media type (text, image, audio)
    var mediaType: String
    
    /// File name for display
    var fileName: String
    
    init(
        id: String,
        filePath: String,
        contentHash: String,
        fileSize: Int64,
        fileModifiedAt: Date,
        indexedAt: Date = Date(),
        mediaType: String = "text",
        fileName: String
    ) {
        self.id = id
        self.filePath = filePath
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.fileModifiedAt = fileModifiedAt
        self.indexedAt = indexedAt
        self.mediaType = mediaType
        self.fileName = fileName
    }
}

// MARK: - File Attributes

struct FileAttributes {
    let size: Int64
    let modified: Date
    let created: Date
}

// MARK: - File Hashing Utility

enum FileHasher {
    /// Compute SHA256 hash of file content
    /// Uses chunked reading for memory efficiency with large files
    static func hash(fileAt url: URL) -> String? {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            var hasher = SHA256()
            let chunkSize = 1024 * 1024 // 1MB chunks
            
            while autoreleasepool(invoking: {
                let data = fileHandle.readData(ofLength: chunkSize)
                if data.isEmpty {
                    return false
                }
                hasher.update(data: data)
                return true
            }) {}
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            print("❌ Failed to hash file: \(error)")
            return nil
        }
    }
    
    /// Get file attributes (size, modification date, creation date)
    static func attributes(fileAt url: URL) -> FileAttributes? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey
            ])
            
            let size = Int64(resourceValues.fileSize ?? 0)
            let modified = resourceValues.contentModificationDate ?? Date()
            let created = resourceValues.creationDate ?? Date()
            
            return FileAttributes(size: size, modified: modified, created: created)
        } catch {
            print("❌ Failed to get file attributes: \(error)")
            return nil
        }
    }
}
