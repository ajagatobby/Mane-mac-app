//
//  ActionHandler.swift
//  ManeAI
//
//  Handles execution of file actions from the agent
//

import Foundation
import SwiftUI
import Combine

/// Types of file actions from the agent
enum FileActionType: String, Codable {
    case move
    case copy
    case rename
    case delete
    case createFolder
    case deleteFolder
}

/// A file action from the agent
struct FileAction: Codable, Identifiable {
    let id: String
    let type: FileActionType
    let sourcePath: String?
    let destinationPath: String?
    let requiresPermission: String?
    let description: String
}

/// Result of executing a single action
struct ActionResult: Codable {
    let actionId: String
    let success: Bool
    let error: String?
}

/// Pending actions waiting for confirmation
struct PendingActionsState: Identifiable {
    let id: String // sessionId
    let actions: [FileAction]
    let createdAt: Date
}

/// Handles execution of agent file actions
@MainActor
class ActionHandler: ObservableObject {
    
    static let shared = ActionHandler()
    
    @Published var pendingActions: PendingActionsState?
    @Published var isExecuting = false
    @Published var executionProgress: Double = 0
    @Published var lastResults: [ActionResult] = []
    
    private let fileOps = FileOperations.shared
    private let bookmarks = SecurityBookmarks.shared
    
    private init() {}
    
    // MARK: - Permission Checking
    
    /// Check which folders need permission for a set of actions
    func checkPermissions(for actions: [FileAction]) -> [String] {
        var needPermission: Set<String> = []
        
        for action in actions {
            if let permPath = action.requiresPermission {
                if !fileOps.hasAccess(to: permPath) {
                    needPermission.insert(permPath)
                }
            }
            
            // Also check source paths
            if let source = action.sourcePath {
                let sourceDir = URL(fileURLWithPath: source).deletingLastPathComponent().path
                if !fileOps.hasAccess(to: sourceDir) {
                    needPermission.insert(sourceDir)
                }
            }
        }
        
        return Array(needPermission).sorted()
    }
    
    /// Request access to required folders
    func requestAccess(for folders: [String]) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        for folder in folders {
            let message = "Grant access to: \(folder)"
            if let url = await bookmarks.selectDirectory(message: message) {
                results[folder] = (url.path == folder || url.path.hasPrefix(folder) || folder.hasPrefix(url.path))
            } else {
                results[folder] = false
            }
        }
        
        return results
    }
    
    // MARK: - Action Execution
    
    /// Set pending actions from agent response
    func setPendingActions(sessionId: String, actions: [FileAction]) {
        pendingActions = PendingActionsState(
            id: sessionId,
            actions: actions,
            createdAt: Date()
        )
    }
    
    /// Clear pending actions
    func clearPendingActions() {
        pendingActions = nil
    }
    
    /// Execute all pending actions
    func executePendingActions() async -> [ActionResult] {
        guard let pending = pendingActions else {
            return []
        }
        
        return await executeActions(pending.actions)
    }
    
    /// Execute a list of actions
    func executeActions(_ actions: [FileAction]) async -> [ActionResult] {
        isExecuting = true
        executionProgress = 0
        lastResults = []
        
        var results: [ActionResult] = []
        let total = Double(actions.count)
        
        for (index, action) in actions.enumerated() {
            let result = await executeAction(action)
            results.append(result)
            
            executionProgress = Double(index + 1) / total
        }
        
        lastResults = results
        isExecuting = false
        pendingActions = nil
        
        return results
    }
    
    /// Execute a single action
    func executeAction(_ action: FileAction) async -> ActionResult {
        do {
            switch action.type {
            case .move:
                guard let source = action.sourcePath, let dest = action.destinationPath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing source or destination path"
                    )
                }
                try await fileOps.moveFile(from: source, to: dest)
                
            case .copy:
                guard let source = action.sourcePath, let dest = action.destinationPath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing source or destination path"
                    )
                }
                try await fileOps.copyFile(from: source, to: dest)
                
            case .rename:
                guard let source = action.sourcePath, let dest = action.destinationPath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing source or destination path"
                    )
                }
                let newName = URL(fileURLWithPath: dest).lastPathComponent
                try await fileOps.renameFile(at: source, to: newName)
                
            case .delete:
                guard let source = action.sourcePath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing file path"
                    )
                }
                try await fileOps.deleteFile(at: source)
                
            case .createFolder:
                guard let dest = action.destinationPath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing folder path"
                    )
                }
                try await fileOps.createFolder(at: dest)
                
            case .deleteFolder:
                guard let source = action.sourcePath else {
                    return ActionResult(
                        actionId: action.id,
                        success: false,
                        error: "Missing folder path"
                    )
                }
                try await fileOps.deleteFolder(at: source)
            }
            
            return ActionResult(actionId: action.id, success: true, error: nil)
            
        } catch {
            return ActionResult(
                actionId: action.id,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Summary
    
    /// Get a summary of actions
    func getActionsSummary(_ actions: [FileAction]) -> String {
        var summary: [String] = []
        
        let createCount = actions.filter { $0.type == .createFolder }.count
        let moveCount = actions.filter { $0.type == .move }.count
        let copyCount = actions.filter { $0.type == .copy }.count
        let renameCount = actions.filter { $0.type == .rename }.count
        let deleteCount = actions.filter { $0.type == .delete }.count
        
        if createCount > 0 { summary.append("\(createCount) folder(s) to create") }
        if moveCount > 0 { summary.append("\(moveCount) file(s) to move") }
        if copyCount > 0 { summary.append("\(copyCount) file(s) to copy") }
        if renameCount > 0 { summary.append("\(renameCount) file(s) to rename") }
        if deleteCount > 0 { summary.append("\(deleteCount) file(s) to delete") }
        
        return summary.joined(separator: ", ")
    }
    
    /// Get results summary
    func getResultsSummary(_ results: [ActionResult]) -> (succeeded: Int, failed: Int) {
        let succeeded = results.filter { $0.success }.count
        let failed = results.count - succeeded
        return (succeeded, failed)
    }
}
