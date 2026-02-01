//
//  FileOperations.swift
//  ManeAI
//
//  Handles file system operations with security-scoped bookmark support
//

import Foundation
import AppKit
import Combine

/// Errors that can occur during file operations
enum FileOperationError: LocalizedError {
    case accessDenied(String)
    case fileNotFound(String)
    case destinationExists(String)
    case operationFailed(String)
    case invalidPath(String)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "Access denied to: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .destinationExists(let path):
            return "Destination already exists: \(path)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}

/// Result of a file operation
struct FileOperationResult {
    let success: Bool
    let actionId: String
    let error: String?
}

/// Handles file system operations with security-scoped access
@MainActor
class FileOperations: ObservableObject {
    
    static let shared = FileOperations()
    
    private let fileManager = FileManager.default
    private let bookmarks = SecurityBookmarks.shared
    
    private init() {}
    
    // MARK: - Move File
    
    /// Move a file from source to destination
    /// If destination is a folder, the file keeps its original name
    func moveFile(from sourcePath: String, to destinationPath: String) async throws {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        var destinationURL = URL(fileURLWithPath: destinationPath)
        
        // If destination is a folder, append the source filename
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue {
            destinationURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        } else if destinationURL.pathExtension.isEmpty && !sourceURL.pathExtension.isEmpty {
            // Destination looks like a folder path (no extension) but doesn't exist yet
            // If source has an extension, treat destination as a folder
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            destinationURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        }
        
        // Ensure we have access to both source and destination
        try await ensureAccess(to: sourceURL)
        try await ensureAccess(to: destinationURL.deletingLastPathComponent())
        
        // Check source exists
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw FileOperationError.fileNotFound(sourcePath)
        }
        
        // Check destination doesn't exist
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw FileOperationError.destinationExists(destinationURL.path)
        }
        
        // Perform the move with security-scoped access
        try await withSecurityScopedAccess(source: sourceURL, destination: destinationURL) {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }
    
    // MARK: - Copy File
    
    /// Copy a file from source to destination
    /// If destination is a folder, the file keeps its original name
    func copyFile(from sourcePath: String, to destinationPath: String) async throws {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        var destinationURL = URL(fileURLWithPath: destinationPath)
        
        // If destination is a folder, append the source filename
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue {
            destinationURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        } else if destinationURL.pathExtension.isEmpty && !sourceURL.pathExtension.isEmpty {
            // Destination looks like a folder path (no extension) but doesn't exist yet
            // If source has an extension, treat destination as a folder
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            destinationURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        }
        
        try await ensureAccess(to: sourceURL)
        try await ensureAccess(to: destinationURL.deletingLastPathComponent())
        
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw FileOperationError.fileNotFound(sourcePath)
        }
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw FileOperationError.destinationExists(destinationURL.path)
        }
        
        try await withSecurityScopedAccess(source: sourceURL, destination: destinationURL) {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
    
    // MARK: - Rename File
    
    /// Rename a file (same as move within same directory)
    func renameFile(at filePath: String, to newName: String) async throws {
        let sourceURL = URL(fileURLWithPath: filePath)
        let directory = sourceURL.deletingLastPathComponent()
        let destinationURL = directory.appendingPathComponent(newName)
        
        try await moveFile(from: filePath, to: destinationURL.path)
    }
    
    // MARK: - Delete File
    
    /// Delete a file permanently
    func deleteFile(at filePath: String) async throws {
        let url = URL(fileURLWithPath: filePath)
        
        try await ensureAccess(to: url)
        
        guard fileManager.fileExists(atPath: filePath) else {
            throw FileOperationError.fileNotFound(filePath)
        }
        
        // Use security-scoped access for deletion
        let accessGranted = bookmarks.startAccessing(url)
        defer {
            if accessGranted {
                bookmarks.stopAccessing(url)
            }
        }
        
        // Try to resolve bookmark if direct access fails
        if !accessGranted {
            if let resolvedURL = bookmarks.resolveBookmark(for: filePath) {
                let resolved = bookmarks.startAccessing(resolvedURL)
                defer {
                    if resolved {
                        bookmarks.stopAccessing(resolvedURL)
                    }
                }
                try fileManager.removeItem(at: resolvedURL)
                return
            }
            throw FileOperationError.accessDenied(filePath)
        }
        
        try fileManager.removeItem(at: url)
    }
    
    // MARK: - Create Folder
    
    /// Create a new folder at the specified path
    func createFolder(at folderPath: String) async throws {
        let url = URL(fileURLWithPath: folderPath)
        let parentURL = url.deletingLastPathComponent()
        
        try await ensureAccess(to: parentURL)
        
        // Check if folder already exists
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // Folder already exists, that's fine
                return
            } else {
                throw FileOperationError.destinationExists(folderPath)
            }
        }
        
        // Use security-scoped access
        let accessGranted = bookmarks.startAccessing(parentURL)
        defer {
            if accessGranted {
                bookmarks.stopAccessing(parentURL)
            }
        }
        
        if !accessGranted {
            if let resolvedURL = bookmarks.resolveBookmark(for: parentURL.path) {
                let resolved = bookmarks.startAccessing(resolvedURL)
                defer {
                    if resolved {
                        bookmarks.stopAccessing(resolvedURL)
                    }
                }
                let newFolderURL = resolvedURL.appendingPathComponent(url.lastPathComponent)
                try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
                return
            }
            throw FileOperationError.accessDenied(parentURL.path)
        }
        
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    // MARK: - Delete Folder
    
    /// Delete an empty folder
    func deleteFolder(at folderPath: String) async throws {
        let url = URL(fileURLWithPath: folderPath)
        let parentURL = url.deletingLastPathComponent()
        
        try await ensureAccess(to: parentURL)
        
        // Check if folder exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileOperationError.fileNotFound(folderPath)
        }
        
        // Check if folder is empty
        let contents = try fileManager.contentsOfDirectory(atPath: folderPath)
        if !contents.isEmpty {
            throw FileOperationError.operationFailed("Folder is not empty")
        }
        
        // Use security-scoped access
        let accessGranted = bookmarks.startAccessing(parentURL)
        defer {
            if accessGranted {
                bookmarks.stopAccessing(parentURL)
            }
        }
        
        if !accessGranted {
            if let resolvedURL = bookmarks.resolveBookmark(for: parentURL.path) {
                let resolved = bookmarks.startAccessing(resolvedURL)
                defer {
                    if resolved {
                        bookmarks.stopAccessing(resolvedURL)
                    }
                }
                let folderURL = resolvedURL.appendingPathComponent(url.lastPathComponent)
                try fileManager.removeItem(at: folderURL)
                return
            }
            throw FileOperationError.accessDenied(parentURL.path)
        }
        
        try fileManager.removeItem(at: url)
    }
    
    // MARK: - Check Access
    
    /// Check if we have access to a path
    func hasAccess(to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // Try direct access
        if bookmarks.startAccessing(url) {
            bookmarks.stopAccessing(url)
            return true
        }
        
        // Try resolved bookmark
        if let resolvedURL = bookmarks.resolveBookmark(for: path) {
            if bookmarks.startAccessing(resolvedURL) {
                bookmarks.stopAccessing(resolvedURL)
                return true
            }
        }
        
        return false
    }
    
    /// Request access to a folder
    func requestFolderAccess(message: String = "Select a folder to grant access") async -> URL? {
        return await bookmarks.selectDirectory(message: message)
    }
    
    // MARK: - Private Helpers
    
    /// Ensure we have access to a URL, requesting if necessary
    private func ensureAccess(to url: URL) async throws {
        // First check if we have access
        if hasAccess(to: url.path) {
            return
        }
        
        // Check if parent directory has access
        let parent = url.deletingLastPathComponent()
        if hasAccess(to: parent.path) {
            return
        }
        
        // We need to request access - this will be handled by ActionHandler
        throw FileOperationError.accessDenied(url.path)
    }
    
    /// Execute operation with security-scoped access to both source and destination
    private func withSecurityScopedAccess(
        source: URL,
        destination: URL,
        operation: () throws -> Void
    ) async throws {
        var sourceAccess = false
        var destAccess = false
        var resolvedSource: URL?
        var resolvedDest: URL?
        
        // Get source access
        sourceAccess = bookmarks.startAccessing(source)
        if !sourceAccess {
            resolvedSource = bookmarks.resolveBookmark(for: source.path)
            if let resolved = resolvedSource {
                sourceAccess = bookmarks.startAccessing(resolved)
            }
        }
        
        // Get destination folder access
        let destFolder = destination.deletingLastPathComponent()
        destAccess = bookmarks.startAccessing(destFolder)
        if !destAccess {
            resolvedDest = bookmarks.resolveBookmark(for: destFolder.path)
            if let resolved = resolvedDest {
                destAccess = bookmarks.startAccessing(resolved)
            }
        }
        
        defer {
            if sourceAccess {
                bookmarks.stopAccessing(resolvedSource ?? source)
            }
            if destAccess {
                bookmarks.stopAccessing(resolvedDest ?? destFolder)
            }
        }
        
        if !sourceAccess {
            throw FileOperationError.accessDenied(source.path)
        }
        
        if !destAccess {
            throw FileOperationError.accessDenied(destFolder.path)
        }
        
        try operation()
    }
}
