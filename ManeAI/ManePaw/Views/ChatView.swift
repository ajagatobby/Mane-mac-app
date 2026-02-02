//
//  ChatView.swift
//  ManeAI
//
//  AI Chat interface with RAG-powered responses
//  Updated with Raycast/iOS 26-inspired design
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
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            // Messages
            messagesView
            
            // Input
            inputView
        }
        .background(ManeTheme.Colors.background)
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
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            if let status = ollamaStatus {
                HStack(spacing: ManeTheme.Spacing.sm) {
                    Circle()
                        .fill(status.available ? ManeTheme.Colors.statusSuccess : ManeTheme.Colors.statusError)
                        .frame(width: 8, height: 8)
                    
                    Text(status.available ? "Ollama: \(status.model)" : "Ollama: Offline")
                        .font(ManeTheme.Typography.caption)
                        .foregroundStyle(ManeTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            if !messages.isEmpty {
                Button("Clear") {
                    withAnimation(ManeTheme.Animation.normal) {
                        messages.removeAll()
                    }
                }
                .buttonStyle(.plain)
                .font(ManeTheme.Typography.caption)
                .foregroundStyle(ManeTheme.Colors.textSecondary)
                .padding(.horizontal, ManeTheme.Spacing.sm)
                .padding(.vertical, ManeTheme.Spacing.xs)
                .background {
                    Capsule()
                        .fill(ManeTheme.Colors.hover)
                }
            }
        }
        .padding(.horizontal, ManeTheme.Spacing.lg)
        .padding(.vertical, ManeTheme.Spacing.sm)
        .background {
            ManeTheme.Colors.backgroundSecondary
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ManeTheme.Colors.divider)
                        .frame(height: 1)
                }
        }
    }
    
    // MARK: - Messages View
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ManeTheme.Spacing.lg) {
                    if messages.isEmpty && streamingMessage == nil {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            ThemedMessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if let streaming = streamingMessage {
                            ThemedMessageBubble(message: streaming)
                                .id(streaming.id)
                        }
                    }
                }
                .padding(ManeTheme.Spacing.lg)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation(ManeTheme.Animation.normal) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingMessage?.content) { _, _ in
                if let streaming = streamingMessage {
                    withAnimation(ManeTheme.Animation.fast) {
                        proxy.scrollTo(streaming.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: ManeTheme.Spacing.xl) {
            // Icon
            ZStack {
                Circle()
                    .fill(ManeTheme.Colors.accentPurple.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(ManeTheme.Colors.accentPurple)
            }
            
            VStack(spacing: ManeTheme.Spacing.sm) {
                Text("Ask me anything about your files")
                    .font(ManeTheme.Typography.title3)
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
                
                Text("I can search, summarize, and answer questions about your knowledge base")
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Suggestion chips
            VStack(alignment: .leading, spacing: ManeTheme.Spacing.sm) {
                ThemedSuggestionButton(
                    text: "What files do I have?",
                    icon: "folder"
                ) {
                    inputText = "What files do I have in my knowledge base?"
                }
                
                ThemedSuggestionButton(
                    text: "Summarize my documents",
                    icon: "doc.text.magnifyingglass"
                ) {
                    inputText = "Can you give me a summary of my documents?"
                }
                
                ThemedSuggestionButton(
                    text: "Find related content",
                    icon: "link"
                ) {
                    inputText = "Find files related to "
                }
                
                ThemedSuggestionButton(
                    text: "Search for code",
                    icon: "chevron.left.forwardslash.chevron.right"
                ) {
                    inputText = "Find code that handles "
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ManeTheme.Spacing.xxl)
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        HStack(spacing: ManeTheme.Spacing.md) {
            // Text input
            TextField("Ask about your files...", text: $inputText, axis: .vertical)
                .font(ManeTheme.Typography.body)
                .foregroundStyle(ManeTheme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    if !inputText.isEmpty && !isLoading {
                        Task {
                            await sendMessage()
                        }
                    }
                }
            
            // Send button
            Button {
                Task {
                    await sendMessage()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(inputText.isEmpty ? ManeTheme.Colors.backgroundTertiary : ManeTheme.Colors.accentPrimary)
                        .frame(width: 32, height: 32)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(ManeTheme.Colors.textInverse)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(inputText.isEmpty ? ManeTheme.Colors.textTertiary : ManeTheme.Colors.textInverse)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding(ManeTheme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                        .strokeBorder(
                            isInputFocused ? ManeTheme.Colors.accentPrimary.opacity(0.5) : ManeTheme.Colors.border,
                            lineWidth: isInputFocused ? 2 : 1
                        )
                }
                .shadow(color: ManeTheme.Colors.shadowLight, radius: 4, x: 0, y: 2)
        }
        .padding(ManeTheme.Spacing.lg)
        .background(ManeTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Actions
    
    private func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let query = inputText
        inputText = ""
        
        // Add user message
        let userMessage = ChatMessage(content: query, isUser: true)
        withAnimation(ManeTheme.Animation.springFast) {
            messages.append(userMessage)
        }
        
        isLoading = true
        await sendChatMessage(query)
        isLoading = false
    }
    
    private func sendChatMessage(_ query: String) async {
        // Create streaming message placeholder
        let assistantMessage = ChatMessage(content: "", isUser: false, isStreaming: true)
        streamingMessage = assistantMessage
        
        do {
            var fullResponse = ""
            var sources: [String] = []
            
            for try await chunk in apiService.chatStream(query: query) {
                switch chunk {
                case .content(let text):
                    fullResponse += text
                    streamingMessage?.content = fullResponse
                case .sources(let streamSources):
                    sources = streamSources.map { $0.filePath }
                }
            }
            
            // Finalize the message
            let finalMessage = ChatMessage(
                content: fullResponse,
                isUser: false,
                sources: sources,
                isStreaming: false
            )
            withAnimation(ManeTheme.Animation.springFast) {
                messages.append(finalMessage)
            }
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
                withAnimation(ManeTheme.Animation.springFast) {
                    messages.append(finalMessage)
                }
                streamingMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                streamingMessage = nil
            }
        }
    }
    
    private func checkOllamaStatus() async {
        do {
            ollamaStatus = try await apiService.getOllamaStatus()
        } catch {
            ollamaStatus = OllamaStatus(available: false, model: "unknown", url: "")
        }
    }
}

// MARK: - Themed Message Bubble

struct ThemedMessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: ManeTheme.Spacing.md) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                // AI Avatar
                ZStack {
                    Circle()
                        .fill(ManeTheme.Colors.accentPurple.opacity(0.12))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ManeTheme.Colors.accentPurple)
                }
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: ManeTheme.Spacing.xs) {
                // Sender name
                Text(message.isUser ? "You" : "Mane-paw")
                    .font(ManeTheme.Typography.captionMedium)
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
                
                // Message content
                Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(message.isUser ? ManeTheme.Colors.textInverse : ManeTheme.Colors.textPrimary)
                    .padding(ManeTheme.Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.md)
                            .fill(message.isUser ? ManeTheme.Colors.accentPrimary : Color.white)
                            .shadow(color: ManeTheme.Colors.shadowLight, radius: 2, x: 0, y: 1)
                    }
                
                // Streaming indicator
                if message.isStreaming {
                    HStack(spacing: ManeTheme.Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Generating...")
                            .font(ManeTheme.Typography.caption)
                            .foregroundStyle(ManeTheme.Colors.textTertiary)
                    }
                }
                
                // Sources
                if !message.sources.isEmpty {
                    HStack(spacing: ManeTheme.Spacing.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text("\(message.sources.count) source(s)")
                            .font(ManeTheme.Typography.caption)
                    }
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
                    .padding(.horizontal, ManeTheme.Spacing.sm)
                    .padding(.vertical, ManeTheme.Spacing.xxs)
                    .background {
                        Capsule()
                            .fill(ManeTheme.Colors.backgroundSecondary)
                    }
                }
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            } else {
                // User Avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ManeTheme.Colors.accentPrimary)
            }
        }
    }
}

// MARK: - Themed Suggestion Button

struct ThemedSuggestionButton: View {
    let text: String
    var icon: String = "sparkles"
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: ManeTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ManeTheme.Colors.accentPrimary)
                
                Text(text)
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
            }
            .padding(.horizontal, ManeTheme.Spacing.md)
            .padding(.vertical, ManeTheme.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.md)
                    .fill(isHovered ? ManeTheme.Colors.accentPrimary.opacity(0.08) : Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.md)
                            .strokeBorder(ManeTheme.Colors.border, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ManeTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChatView()
        .environmentObject(APIService())
        .environmentObject(SidecarManager())
        .frame(width: 600, height: 500)
}
