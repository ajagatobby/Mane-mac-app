//
//  Document.swift
//  ManeAI
//
//  Document model for ingested files with multimodal support
//

import Foundation
import SwiftData

@Model
final class Document {
    var id: String
    var fileName: String
    var filePath: String
    var fileExtension: String
    var fileSize: Int64
    var mediaType: String // "text", "image", "audio", "video"
    var thumbnailPath: String?
    var ingestedAt: Date
    var metadata: [String: String]
    
    init(
        id: String,
        fileName: String,
        filePath: String,
        fileExtension: String = "",
        fileSize: Int64 = 0,
        mediaType: String = "text",
        thumbnailPath: String? = nil,
        ingestedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.mediaType = mediaType
        self.thumbnailPath = thumbnailPath
        self.ingestedAt = ingestedAt
        self.metadata = metadata
    }
    
    var icon: String {
        // First check media type
        switch mediaType {
        case "image":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        default:
            // Fall back to extension-based icons for text
            switch fileExtension.lowercased() {
            case "txt", "md", "markdown":
                return "doc.text"
            case "pdf":
                return "doc.richtext"
            case "swift", "ts", "js", "py", "java", "cpp", "c", "h":
                return "chevron.left.forwardslash.chevron.right"
            case "json", "xml", "yaml", "yml":
                return "curlybraces"
            case "html", "css":
                return "globe"
            case "csv":
                return "tablecells"
            default:
                return "doc"
            }
        }
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: ingestedAt, relativeTo: Date())
    }
    
    var isMediaFile: Bool {
        mediaType == "image" || mediaType == "audio" || mediaType == "video"
    }
}
