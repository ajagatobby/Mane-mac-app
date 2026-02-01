//
//  ChatMessage.swift
//  ManeAI
//
//  Chat message model
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var content: String
    var isUser: Bool
    var timestamp: Date
    var sources: [String] // File paths of sources used
    var isStreaming: Bool
    
    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        sources: [String] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.sources = sources
        self.isStreaming = isStreaming
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Chat Conversation

@Model
final class ChatConversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]
    
    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
    
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
    }
    
    var lastMessage: ChatMessage? {
        messages.sorted { $0.timestamp < $1.timestamp }.last
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
