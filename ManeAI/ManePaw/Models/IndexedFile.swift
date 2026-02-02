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

// MARK: - File Hashing Utility

enum FileHasher {
    /// Compute SHA256 hash of file content
    static func hash(fileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Get file attributes (size, modification date)
    static func attributes(fileAt url: URL) -> (size: Int64, modified: Date)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attrs[.size] as? Int64) ?? 0
        let modified = (attrs[.modificationDate] as? Date) ?? Date()
        return (size, modified)
    }
}
