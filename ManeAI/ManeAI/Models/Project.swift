//
//  Project.swift
//  ManeAI
//
//  Project model for indexed codebases with smart analysis
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: String
    var name: String
    var path: String
    var projectDescription: String
    var techStack: [String]
    var tags: [String]
    var fileCount: Int
    var knowledgeDocument: String?
    var indexedAt: Date
    
    init(
        id: String,
        name: String,
        path: String,
        projectDescription: String = "",
        techStack: [String] = [],
        tags: [String] = [],
        fileCount: Int = 0,
        knowledgeDocument: String? = nil,
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.projectDescription = projectDescription
        self.techStack = techStack
        self.tags = tags
        self.fileCount = fileCount
        self.knowledgeDocument = knowledgeDocument
        self.indexedAt = indexedAt
    }
    
    var icon: String {
        // Determine icon based on primary tech
        let primaryTech = techStack.first?.lowercased() ?? ""
        
        switch primaryTech {
        case let tech where tech.contains("swift"):
            return "swift"
        case let tech where tech.contains("typescript") || tech.contains("javascript"):
            return "curlybraces"
        case let tech where tech.contains("python"):
            return "chevron.left.forwardslash.chevron.right"
        case let tech where tech.contains("rust"):
            return "gearshape.2"
        case let tech where tech.contains("go"):
            return "square.stack.3d.up"
        case let tech where tech.contains("java") || tech.contains("kotlin"):
            return "cup.and.saucer"
        case let tech where tech.contains("ruby"):
            return "diamond"
        case let tech where tech.contains("php"):
            return "ellipsis.curlybraces"
        default:
            return "folder.badge.gearshape"
        }
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: indexedAt, relativeTo: Date())
    }
    
    var techStackDisplay: String {
        techStack.prefix(3).joined(separator: ", ")
    }
    
    var tagsDisplay: String {
        tags.prefix(5).joined(separator: ", ")
    }
    
    /// Short description (first paragraph)
    var shortDescription: String {
        let lines = projectDescription.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip headers and empty lines
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("-") && !trimmed.hasPrefix("*") {
                return String(trimmed.prefix(200))
            }
        }
        return name
    }
}
