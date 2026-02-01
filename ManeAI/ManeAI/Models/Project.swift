//
//  Project.swift
//  ManeAI
//
//  Project model for indexed codebases
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
    var skeletonCount: Int
    var indexedAt: Date
    
    init(
        id: String,
        name: String,
        path: String,
        projectDescription: String = "",
        techStack: [String] = [],
        tags: [String] = [],
        fileCount: Int = 0,
        skeletonCount: Int = 0,
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.projectDescription = projectDescription
        self.techStack = techStack
        self.tags = tags
        self.fileCount = fileCount
        self.skeletonCount = skeletonCount
        self.indexedAt = indexedAt
    }
    
    /// Icon based on primary tech stack
    var icon: String {
        let primaryTech = techStack.first?.lowercased() ?? ""
        
        switch primaryTech {
        case "react", "nextjs":
            return "atom"
        case "vue", "nuxtjs":
            return "v.square"
        case "angular":
            return "a.square"
        case "svelte":
            return "s.square"
        case "typescript":
            return "t.square.fill"
        case "javascript", "nodejs":
            return "j.square.fill"
        case "python":
            return "p.square.fill"
        case "rust":
            return "r.square.fill"
        case "go", "golang":
            return "g.square.fill"
        case "swift":
            return "swift"
        case "java":
            return "cup.and.saucer"
        default:
            return "folder.fill"
        }
    }
    
    /// Color based on primary language
    var color: String {
        let primaryTech = techStack.first?.lowercased() ?? ""
        
        switch primaryTech {
        case "react", "nextjs":
            return "blue"
        case "vue", "nuxtjs":
            return "green"
        case "angular":
            return "red"
        case "svelte":
            return "orange"
        case "typescript":
            return "blue"
        case "javascript", "nodejs":
            return "yellow"
        case "python":
            return "blue"
        case "rust":
            return "orange"
        case "go", "golang":
            return "cyan"
        case "swift":
            return "orange"
        default:
            return "gray"
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
        tags.prefix(3).joined(separator: ", ")
    }
}

// MARK: - API Response Models

/// Project response from API
struct ProjectResponse: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    let description: String
    let techStack: [String]
    let tags: [String]
    let fileCount: Int
    let createdAt: String
    let score: Double?
    let skeletonCount: Int?
    let manifest: ProjectManifest?
}

struct ProjectManifest: Codable {
    let language: String?
    let framework: String?
    let version: String?
    let dependencies: [String]?
}

/// Index project request
struct IndexProjectRequest: Codable {
    let path: String
    let maxDepth: Int?
    let maxFiles: Int?
    let skipSkeletons: Bool?
}

/// Index project response
struct IndexProjectResponse: Codable {
    let success: Bool
    let project: ProjectResponse
    let message: String
}

/// List projects response
struct ListProjectsResponse: Codable {
    let success: Bool
    let count: Int
    let projects: [ProjectResponse]
}

/// Single project response
struct GetProjectResponse: Codable {
    let success: Bool
    let project: ProjectResponse
}

/// Delete project response
struct DeleteProjectResponse: Codable {
    let success: Bool
    let message: String
}

/// Search projects request
struct SearchProjectsRequest: Codable {
    let query: String
    let limit: Int?
}

/// Search projects response
struct SearchProjectsResponse: Codable {
    let success: Bool
    let query: String
    let count: Int
    let projects: [ProjectResponse]
}

/// Code skeleton response
struct CodeSkeletonResponse: Codable, Identifiable {
    let id: String
    let projectId: String
    let filePath: String
    let fileName: String
    let content: String
    let language: String
    let score: Double?
    let projectName: String?
}

/// Search code request
struct SearchCodeRequest: Codable {
    let query: String
    let limit: Int?
    let projectId: String?
}

/// Search code response
struct SearchCodeResponse: Codable {
    let success: Bool
    let query: String
    let count: Int
    let skeletons: [CodeSkeletonResponse]
}

/// Unified search request
struct UnifiedSearchRequest: Codable {
    let query: String
    let projectLimit: Int?
    let codeLimit: Int?
    let projectId: String?
}

/// Unified search results
struct UnifiedSearchResults: Codable {
    let projects: [ProjectResponse]
    let skeletons: [CodeSkeletonResponse]
}

/// Unified search response
struct UnifiedSearchResponse: Codable {
    let success: Bool
    let query: String
    let results: UnifiedSearchResults
}

/// Project skeletons response
struct ProjectSkeletonsResponse: Codable {
    let success: Bool
    let projectId: String
    let projectName: String
    let count: Int
    let skeletons: [CodeSkeletonResponse]
}

/// Project stats
struct ProjectStats: Codable {
    let projectCount: Int
    let totalFileCount: Int
    let languages: [String: Int]
    let techStack: [String: Int]
}

/// Project stats response
struct ProjectStatsResponse: Codable {
    let success: Bool
    let stats: ProjectStats
}
