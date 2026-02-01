//
//  ChatView.swift
//  ManeAI
//
//  AI Chat interface with streaming responses
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var sidecarManager: SidecarManager
    @Environment(\.modelContext) private var modelContext
    
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var messages: [ChatMessage] = []
    @State private var streamingMessage: ChatMessage?
    @State private var ollamaStatus: OllamaStatus?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            // Messages
            messagesView
            
            // Input
            inputView
        }
        .navigationTitle("AI Chat")
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await checkOllamaStatus()
        }
    }
    
    private var statusBar: some View {
        HStack {
            if let status = ollamaStatus {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.available ? .green : .red)
                        .frame(width: 8, height: 8)
                    
                    Text(status.available ? "Ollama: \(status.model)" : "Ollama: Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !messages.isEmpty {
                Button("Clear Chat") {
                    messages.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty && streamingMessage == nil {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if let streaming = streamingMessage {
                            MessageBubble(message: streaming)
                                .id(streaming.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingMessage?.content) { _, _ in
                if let streaming = streamingMessage {
                    withAnimation {
                        proxy.scrollTo(streaming.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Ask me anything about your files")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                SuggestionButton(text: "What files do I have?") {
                    inputText = "What files do I have in my knowledge base?"
                }
                
                SuggestionButton(text: "Summarize my documents") {
                    inputText = "Can you give me a summary of my documents?"
                }
                
                SuggestionButton(text: "Find related content") {
                    inputText = "Find files related to "
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var inputView: some View {
        HStack(spacing: 12) {
            TextField("Ask about your files...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    if !inputText.isEmpty && !isLoading {
                        Task {
                            await sendMessage()
                        }
                    }
                }
            
            Button {
                Task {
                    await sendMessage()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
            .foregroundColor(inputText.isEmpty ? .secondary : .blue)
        }
        .padding()
        .background(.bar)
    }
    
    private func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let query = inputText
        inputText = ""
        
        // Add user message
        let userMessage = ChatMessage(content: query, isUser: true)
        messages.append(userMessage)
        
        // Create streaming message placeholder
        let assistantMessage = ChatMessage(content: "", isUser: false, isStreaming: true)
        streamingMessage = assistantMessage
        
        isLoading = true
        
        do {
            var fullResponse = ""
            
            for try await chunk in apiService.chatStream(query: query) {
                fullResponse += chunk
                streamingMessage?.content = fullResponse
            }
            
            // Finalize the message
            let finalMessage = ChatMessage(
                content: fullResponse,
                isUser: false,
                isStreaming: false
            )
            messages.append(finalMessage)
            streamingMessage = nil
            
        } catch {
            // If streaming fails, try non-streaming
            do {
                let response = try await apiService.chat(query: query)
                let finalMessage = ChatMessage(
                    content: response.answer,
                    isUser: false,
                    sources: response.sources.map { $0.filePath }
                )
                messages.append(finalMessage)
                streamingMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                streamingMessage = nil
            }
        }
        
        isLoading = false
    }
    
    private func checkOllamaStatus() async {
        do {
            ollamaStatus = try await apiService.getOllamaStatus()
        } catch {
            ollamaStatus = OllamaStatus(available: false, model: "unknown", url: "")
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if !message.isUser {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                    }
                    
                    Text(message.isUser ? "You" : "ManeAI")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    if message.isUser {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(.controlBackgroundColor))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Generating...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !message.sources.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("\(message.sources.count) source(s)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct SuggestionButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChatView()
        .environmentObject(APIService())
        .environmentObject(SidecarManager())
}
