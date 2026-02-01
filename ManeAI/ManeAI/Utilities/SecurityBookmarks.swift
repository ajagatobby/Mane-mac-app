//
//  SecurityBookmarks.swift
//  ManeAI
//
//  Handles Security-Scoped Bookmarks for sandboxed file access
//

import Foundation
import AppKit

/// Manages security-scoped bookmarks for persistent file access
class SecurityBookmarks {
    
    static let shared = SecurityBookmarks()
    
    private let bookmarksKey = "ManeAI.SecurityBookmarks"
    private var activeAccessURLs: Set<URL> = []
    
    private init() {}
    
    // MARK: - Create Bookmark
    
    /// Create and store a security-scoped bookmark for a URL
    func createBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        var bookmarks = loadBookmarks()
        bookmarks[url.path] = bookmarkData
        saveBookmarks(bookmarks)
    }
    
    // MARK: - Resolve Bookmark
    
    /// Resolve a stored bookmark and return the URL with access
    func resolveBookmark(for path: String) -> URL? {
        let bookmarks = loadBookmarks()
        guard let bookmarkData = bookmarks[path] else {
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark is stale, try to refresh it
                try createBookmark(for: url)
            }
            
            return url
        } catch {
            print("Failed to resolve bookmark for \(path): \(error)")
            // Remove invalid bookmark
            var bookmarks = loadBookmarks()
            bookmarks.removeValue(forKey: path)
            saveBookmarks(bookmarks)
            return nil
        }
    }
    
    // MARK: - Start/Stop Access
    
    /// Start accessing a security-scoped resource
    func startAccessing(_ url: URL) -> Bool {
        guard !activeAccessURLs.contains(url) else {
            return true // Already accessing
        }
        
        if url.startAccessingSecurityScopedResource() {
            activeAccessURLs.insert(url)
            return true
        }
        return false
    }
    
    /// Stop accessing a security-scoped resource
    func stopAccessing(_ url: URL) {
        if activeAccessURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeAccessURLs.remove(url)
        }
    }
    
    /// Stop accessing all resources
    func stopAccessingAll() {
        for url in activeAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccessURLs.removeAll()
    }
    
    // MARK: - Read File with Bookmark
    
    /// Read file contents using a security-scoped bookmark
    func readFile(at url: URL) throws -> String {
        // First, try to access directly
        if startAccessing(url) {
            defer { stopAccessing(url) }
            return try String(contentsOf: url, encoding: .utf8)
        }
        
        // Try to resolve from stored bookmark
        if let resolvedURL = resolveBookmark(for: url.path) {
            if startAccessing(resolvedURL) {
                defer { stopAccessing(resolvedURL) }
                return try String(contentsOf: resolvedURL, encoding: .utf8)
            }
        }
        
        throw SecurityBookmarkError.accessDenied(url.path)
    }
    
    /// Read binary file contents
    func readData(at url: URL) throws -> Data {
        if startAccessing(url) {
            defer { stopAccessing(url) }
            return try Data(contentsOf: url)
        }
        
        if let resolvedURL = resolveBookmark(for: url.path) {
            if startAccessing(resolvedURL) {
                defer { stopAccessing(resolvedURL) }
                return try Data(contentsOf: resolvedURL)
            }
        }
        
        throw SecurityBookmarkError.accessDenied(url.path)
    }
    
    // MARK: - File Picker
    
    /// Show open panel and create bookmark for selected files
    func selectFiles(
        allowedTypes: [String]? = nil,
        allowMultiple: Bool = true,
        message: String = "Select files to import"
    ) async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.message = message
                panel.allowsMultipleSelection = allowMultiple
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.canCreateDirectories = false
                
                if let types = allowedTypes {
                    panel.allowedContentTypes = types.compactMap { 
                        UTType(filenameExtension: $0) 
                    }
                }
                
                panel.begin { response in
                    if response == .OK {
                        let urls = panel.urls
                        
                        // Create bookmarks for all selected files
                        for url in urls {
                            try? self.createBookmark(for: url)
                        }
                        
                        continuation.resume(returning: urls)
                    } else {
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }
    
    /// Show open panel for selecting a directory
    func selectDirectory(message: String = "Select a folder") async -> URL? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.message = message
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        try? self.createBookmark(for: url)
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    // MARK: - List Files in Directory
    
    /// List files in a directory with bookmark access
    func listFiles(in directoryURL: URL, extensions: [String]? = nil) throws -> [URL] {
        guard startAccessing(directoryURL) else {
            if let resolvedURL = resolveBookmark(for: directoryURL.path) {
                guard startAccessing(resolvedURL) else {
                    throw SecurityBookmarkError.accessDenied(directoryURL.path)
                }
                defer { stopAccessing(resolvedURL) }
                return try listFilesInternal(in: resolvedURL, extensions: extensions)
            }
            throw SecurityBookmarkError.accessDenied(directoryURL.path)
        }
        
        defer { stopAccessing(directoryURL) }
        return try listFilesInternal(in: directoryURL, extensions: extensions)
    }
    
    private func listFilesInternal(in directory: URL, extensions: [String]?) throws -> [URL] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        if let extensions = extensions {
            return contents.filter { url in
                extensions.contains(url.pathExtension.lowercased())
            }
        }
        
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
    
    /// List all files recursively in a directory with bookmark access
    func listFilesRecursively(in directoryURL: URL, extensions: [String]? = nil) throws -> [URL] {
        guard startAccessing(directoryURL) else {
            if let resolvedURL = resolveBookmark(for: directoryURL.path) {
                guard startAccessing(resolvedURL) else {
                    throw SecurityBookmarkError.accessDenied(directoryURL.path)
                }
                defer { stopAccessing(resolvedURL) }
                return try listFilesRecursivelyInternal(in: resolvedURL, extensions: extensions)
            }
            throw SecurityBookmarkError.accessDenied(directoryURL.path)
        }
        
        defer { stopAccessing(directoryURL) }
        return try listFilesRecursivelyInternal(in: directoryURL, extensions: extensions)
    }
    
    private func listFilesRecursivelyInternal(in directory: URL, extensions: [String]?) throws -> [URL] {
        let fileManager = FileManager.default
        var results: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }
        
        for case let url as URL in enumerator {
            // Skip directories
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            // Filter by extension if specified
            if let extensions = extensions {
                if extensions.contains(url.pathExtension.lowercased()) {
                    results.append(url)
                }
            } else {
                results.append(url)
            }
        }
        
        return results
    }
    
    // MARK: - Write Operations
    
    /// Write data to a file with bookmark access
    func writeData(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        
        // Try direct access first
        if startAccessing(directory) {
            defer { stopAccessing(directory) }
            try data.write(to: url)
            return
        }
        
        // Try resolved bookmark
        if let resolvedDir = resolveBookmark(for: directory.path) {
            if startAccessing(resolvedDir) {
                defer { stopAccessing(resolvedDir) }
                let resolvedURL = resolvedDir.appendingPathComponent(url.lastPathComponent)
                try data.write(to: resolvedURL)
                return
            }
        }
        
        throw SecurityBookmarkError.accessDenied(url.path)
    }
    
    /// Write string to a file with bookmark access
    func writeFile(_ content: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard let data = content.data(using: encoding) else {
            throw SecurityBookmarkError.accessDenied("Failed to encode content")
        }
        try writeData(data, to: url)
    }
    
    /// Check if we have write access to a path
    func hasWriteAccess(to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        
        // Try direct access
        if startAccessing(directory) {
            stopAccessing(directory)
            return FileManager.default.isWritableFile(atPath: directory.path)
        }
        
        // Try resolved bookmark
        if let resolvedDir = resolveBookmark(for: directory.path) {
            if startAccessing(resolvedDir) {
                stopAccessing(resolvedDir)
                return FileManager.default.isWritableFile(atPath: resolvedDir.path)
            }
        }
        
        return false
    }
    
    /// Check if we have any access (read or write) to a path
    func hasAccess(to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // Try direct access
        if startAccessing(url) {
            stopAccessing(url)
            return true
        }
        
        // Try parent directory
        let parent = url.deletingLastPathComponent()
        if startAccessing(parent) {
            stopAccessing(parent)
            return true
        }
        
        // Try resolved bookmark for path
        if let resolved = resolveBookmark(for: path) {
            if startAccessing(resolved) {
                stopAccessing(resolved)
                return true
            }
        }
        
        // Try resolved bookmark for parent
        if let resolvedParent = resolveBookmark(for: parent.path) {
            if startAccessing(resolvedParent) {
                stopAccessing(resolvedParent)
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Bookmark Storage
    
    private func loadBookmarks() -> [String: Data] {
        return UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
    
    private func saveBookmarks(_ bookmarks: [String: Data]) {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
    
    /// Get all stored bookmark paths
    func getStoredPaths() -> [String] {
        return Array(loadBookmarks().keys)
    }
    
    /// Remove a stored bookmark
    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        saveBookmarks(bookmarks)
    }
    
    /// Clear all stored bookmarks
    func clearAllBookmarks() {
        stopAccessingAll()
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }
}

// MARK: - Errors

enum SecurityBookmarkError: LocalizedError {
    case accessDenied(String)
    case bookmarkCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "Access denied to file: \(path)"
        case .bookmarkCreationFailed(let path):
            return "Failed to create bookmark for: \(path)"
        }
    }
}

// MARK: - UTType Extension

import UniformTypeIdentifiers

extension UTType {
    static let textTypes: [UTType] = [.plainText, .utf8PlainText, .sourceCode]
    static let documentTypes: [UTType] = [.pdf, .rtf, .rtfd]
}
