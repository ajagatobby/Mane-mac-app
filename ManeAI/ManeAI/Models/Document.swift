//
//  Document.swift
//  ManeAI
//
//  Document model for ingested files
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
    var ingestedAt: Date
    var metadata: [String: String]
    
    init(
        id: String,
        fileName: String,
        filePath: String,
        fileExtension: String = "",
        fileSize: Int64 = 0,
        ingestedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.ingestedAt = ingestedAt
        self.metadata = metadata
    }
    
    var icon: String {
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
        default:
            return "doc"
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
}
