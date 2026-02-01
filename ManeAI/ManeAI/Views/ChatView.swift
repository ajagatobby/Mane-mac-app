//
//  ChatView.swift
//  ManeAI
//
//  AI Chat interface with streaming responses and Agent mode
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var sidecarManager: SidecarManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var actionHandler = ActionHandler.shared
    
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var messages: [ChatMessage] = []
    @State private var streamingMessage: ChatMessage?
    @State private var ollamaStatus: OllamaStatus?
    @State private var errorMessage: String?
    
    // Agent mode
    @State private var isAgentMode = false
    @State private var agentStatus: AgentStatus?
    @State private var showActionConfirmation = false
    @State private var pendingSessionId: String?
    @State private var pendingActions: [AgentFileAction] = []
    @State private var permissionsNeeded: [String] = []
    @State private var showPermissionRequest = false
    @State private var executionResults: [ActionResult] = []
    @State private var showResultsSummary = false
    
    // Undo support
    @State private var canUndo = false
    @State private var undoDescription: String?
    @State private var showUndoConfirmation = false
    @State private var undoActions: [AgentFileAction] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            // Messages
            messagesView
            
            // Input
            inputView
        }
        .navigationTitle(isAgentMode ? "Agent Mode" : "AI Chat")
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showActionConfirmation) {
            ActionConfirmationView(
                actions: pendingActions,
                onConfirm: {
                    Task {
                        await executeConfirmedActions()
                    }
                },
                onCancel: {
                    showActionConfirmation = false
                    pendingActions = []
                    pendingSessionId = nil
                }
            )
        }
        .sheet(isPresented: $showPermissionRequest) {
            PermissionRequestView(
                folders: permissionsNeeded,
                onGranted: {
                    showPermissionRequest = false
                    showActionConfirmation = true
                },
                onCancel: {
                    showPermissionRequest = false
                    permissionsNeeded = []
                }
            )
        }
        .sheet(isPresented: $showResultsSummary) {
            ResultsSummaryView(
                results: executionResults,
                onDismiss: {
                    showResultsSummary = false
                    executionResults = []
                }
            )
        }
        .sheet(isPresented: $showUndoConfirmation) {
            UndoConfirmationView(
                actions: undoActions,
                description: undoDescription ?? "Undo last operation",
                onConfirm: {
                    Task {
                        await executeUndoActions()
                    }
                },
                onCancel: {
                    showUndoConfirmation = false
                    undoActions = []
                }
            )
        }
        .task {
            await checkOllamaStatus()
            await checkAgentStatus()
        }
        .onChange(of: isAgentMode) { _, newValue in
            if newValue {
                Task {
                    await checkUndoStatus()
                }
            }
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
            
            // Undo button (only in agent mode when undo is available)
            if isAgentMode && canUndo {
                Button {
                    Task {
                        await prepareUndo()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                        Text("Undo")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
            }
            
            // Agent mode toggle
            Toggle(isOn: $isAgentMode) {
                HStack(spacing: 4) {
                    Image(systemName: isAgentMode ? "wand.and.stars" : "bubble.left.and.bubble.right")
                        .font(.caption)
                    Text(isAgentMode ? "Agent" : "Chat")
                        .font(.caption)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isAgentMode ? .purple : .blue)
            
            if !messages.isEmpty {
                Button("Clear") {
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
            Image(systemName: isAgentMode ? "wand.and.stars" : "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(isAgentMode ? .purple : .secondary)
            
            Text(isAgentMode ? "Give me a command to organize your files" : "Ask me anything about your files")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            if isAgentMode {
                // Agent mode suggestions
                VStack(alignment: .leading, spacing: 8) {
                    SuggestionButton(text: "Organize my Downloads folder", color: .purple) {
                        inputText = "Organize the files in my Downloads folder into categories"
                    }
                    
                    SuggestionButton(text: "Find and group cat photos", color: .purple) {
                        inputText = "Find all images containing cats and move them to a folder called Cats on my Desktop"
                    }
                    
                    SuggestionButton(text: "Find duplicate files", color: .purple) {
                        inputText = "Find duplicate files in my documents"
                    }
                }
                .padding(.top, 8)
            } else {
                // Chat mode suggestions
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var inputView: some View {
        HStack(spacing: 12) {
            TextField(isAgentMode ? "Give a command..." : "Ask about your files...", text: $inputText, axis: .vertical)
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
                    Image(systemName: isAgentMode ? "wand.and.stars" : "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
            .foregroundColor(inputText.isEmpty ? .secondary : (isAgentMode ? .purple : .blue))
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
        
        isLoading = true
        
        if isAgentMode {
            await sendAgentCommand(query)
        } else {
            await sendChatMessage(query)
        }
        
        isLoading = false
    }
    
    private func sendChatMessage(_ query: String) async {
        // Create streaming message placeholder
        let assistantMessage = ChatMessage(content: "", isUser: false, isStreaming: true)
        streamingMessage = assistantMessage
        
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
    }
    
    private func sendAgentCommand(_ command: String) async {
        // Create streaming message for agent thinking
        let thinkingMessage = ChatMessage(content: "", isUser: false, isStreaming: true)
        streamingMessage = thinkingMessage
        
        do {
            var fullThought = ""
            var collectedActions: [AgentFileAction] = []
            var finalAnswer = ""
            var streamingFailed = false
            
            // Try streaming first
            do {
                for try await event in apiService.agentExecuteStream(command: command) {
                    switch event.type {
                    case "thought":
                        fullThought += "💭 \(event.content)\n"
                        streamingMessage?.content = fullThought
                        
                    case "action":
                        fullThought += "⚡ \(event.content)\n"
                        streamingMessage?.content = fullThought
                        if let action = event.action {
                            collectedActions.append(action)
                        }
                        
                    case "observation":
                        fullThought += "👁 Observed results\n"
                        streamingMessage?.content = fullThought
                        
                    case "final":
                        finalAnswer = event.content
                        
                    case "error":
                        errorMessage = event.content
                        
                    default:
                        break
                    }
                }
            } catch {
                print("Streaming failed, falling back to non-streaming: \(error)")
                streamingFailed = true
            }
            
            // If streaming failed or no actions collected, use non-streaming mode
            if streamingFailed || (finalAnswer.contains("[Session:") && collectedActions.isEmpty) {
                streamingMessage?.content = "🔄 Processing command..."
                
                let response = try await apiService.agentExecute(command: command)
                finalAnswer = response.finalAnswer
                collectedActions = response.actions
                fullThought = "💭 \(response.thought)"
            }
            
            // Create final message
            let responseContent = finalAnswer.isEmpty ? fullThought : finalAnswer
            let finalMessage = ChatMessage(
                content: responseContent,
                isUser: false,
                isStreaming: false
            )
            messages.append(finalMessage)
            streamingMessage = nil
            
            // Check if we have actions that need confirmation
            if !collectedActions.isEmpty {
                // Extract session ID from response
                if let sessionMatch = responseContent.range(of: #"\[Session: ([^\]]+)\]"#, options: .regularExpression) {
                    let sessionString = String(responseContent[sessionMatch])
                    let sessionId = sessionString
                        .replacingOccurrences(of: "[Session: ", with: "")
                        .replacingOccurrences(of: "]", with: "")
                    pendingSessionId = sessionId
                }
                
                pendingActions = collectedActions
                
                // Check permissions
                let fileOps = FileOperations.shared
                let neededFolders = collectedActions.compactMap { $0.requiresPermission }.filter { !fileOps.hasAccess(to: $0) }
                
                if neededFolders.isEmpty {
                    showActionConfirmation = true
                } else {
                    permissionsNeeded = Array(Set(neededFolders))
                    showPermissionRequest = true
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
            streamingMessage = nil
        }
    }
    
    private func executeConfirmedActions() async {
        showActionConfirmation = false
        
        // Convert API actions to ActionHandler format
        let actions = pendingActions.map { apiAction -> FileAction in
            FileAction(
                id: apiAction.id,
                type: FileActionType(rawValue: apiAction.type) ?? .move,
                sourcePath: apiAction.sourcePath,
                destinationPath: apiAction.destinationPath,
                requiresPermission: apiAction.requiresPermission,
                description: apiAction.description
            )
        }
        
        // Add executing message
        let executingMessage = ChatMessage(content: "⏳ Executing \(actions.count) action(s)...", isUser: false)
        messages.append(executingMessage)
        
        // Execute actions
        let results = await actionHandler.executeActions(actions)
        
        // Report results back to server
        if let sessionId = pendingSessionId {
            let resultItems = results.map { result in
                ActionResultItem(
                    actionId: result.actionId,
                    success: result.success,
                    error: result.error
                )
            }
            try? await apiService.agentReportResults(sessionId: sessionId, results: resultItems)
        }
        
        // Show results
        executionResults = results
        let (succeeded, failed) = actionHandler.getResultsSummary(results)
        
        // Update message with results
        let resultMessage = ChatMessage(
            content: "✅ Completed: \(succeeded) succeeded, \(failed) failed",
            isUser: false
        )
        messages.append(resultMessage)
        
        if failed > 0 {
            showResultsSummary = true
        }
        
        // Update undo status (actions are now undoable)
        await checkUndoStatus()
        
        // Clear pending state
        pendingActions = []
        pendingSessionId = nil
    }
    
    private func checkOllamaStatus() async {
        do {
            ollamaStatus = try await apiService.getOllamaStatus()
        } catch {
            ollamaStatus = OllamaStatus(available: false, model: "unknown", url: "")
        }
    }
    
    private func checkAgentStatus() async {
        do {
            agentStatus = try await apiService.getAgentStatus()
        } catch {
            agentStatus = nil
        }
    }
    
    private func checkUndoStatus() async {
        do {
            let status = try await apiService.getUndoStatus()
            canUndo = status.canUndo
            undoDescription = status.description
        } catch {
            canUndo = false
            undoDescription = nil
        }
    }
    
    private func prepareUndo() async {
        do {
            let undoResponse = try await apiService.getUndoStatus()
            
            if undoResponse.canUndo && !undoResponse.actions.isEmpty {
                undoActions = undoResponse.actions
                undoDescription = undoResponse.description
                showUndoConfirmation = true
            } else {
                errorMessage = "No actions to undo"
            }
        } catch {
            errorMessage = "Failed to get undo status: \(error.localizedDescription)"
        }
    }
    
    private func executeUndoActions() async {
        showUndoConfirmation = false
        
        // Add message
        let undoingMessage = ChatMessage(content: "↩️ Undoing: \(undoDescription ?? "last operation")...", isUser: false)
        messages.append(undoingMessage)
        
        // Convert API actions to ActionHandler format
        let actions = undoActions.map { apiAction -> FileAction in
            FileAction(
                id: apiAction.id,
                type: FileActionType(rawValue: apiAction.type) ?? .move,
                sourcePath: apiAction.sourcePath,
                destinationPath: apiAction.destinationPath,
                requiresPermission: apiAction.requiresPermission,
                description: apiAction.description
            )
        }
        
        // Execute undo actions
        let results = await actionHandler.executeActions(actions)
        
        // Notify server that undo was executed
        do {
            _ = try await apiService.executeUndo()
        } catch {
            print("Failed to notify server of undo: \(error)")
        }
        
        // Show results
        let (succeeded, failed) = actionHandler.getResultsSummary(results)
        
        let resultMessage = ChatMessage(
            content: "↩️ Undo completed: \(succeeded) succeeded, \(failed) failed",
            isUser: false
        )
        messages.append(resultMessage)
        
        // Update undo status
        await checkUndoStatus()
        
        // Clear state
        undoActions = []
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
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color.opacity(0.1))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Confirmation View

struct ActionConfirmationView: View {
    let actions: [AgentFileAction]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                Text("Confirm Actions")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            // Actions list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(actions) { action in
                        ActionRow(action: action)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Summary and buttons
            HStack {
                Text("\(actions.count) action(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Execute") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct ActionRow: View {
    let action: AgentFileAction
    
    var icon: String {
        switch action.type {
        case "move": return "arrow.right.square"
        case "copy": return "doc.on.doc"
        case "rename": return "pencil"
        case "delete": return "trash"
        case "createFolder": return "folder.badge.plus"
        default: return "questionmark.circle"
        }
    }
    
    var iconColor: Color {
        switch action.type {
        case "delete": return .red
        case "createFolder": return .green
        default: return .blue
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(action.description)
                    .font(.subheadline)
                
                if let source = action.sourcePath {
                    Text("From: \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if let dest = action.destinationPath {
                    Text("To: \(dest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let folders: [String]
    let onGranted: () -> Void
    let onCancel: () -> Void
    
    @State private var grantedFolders: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.open")
                    .foregroundStyle(.orange)
                Text("Permission Required")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            // Explanation
            Text("The agent needs access to these folders to execute the requested actions:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
            
            // Folders list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(folders, id: \.self) { folder in
                        HStack {
                            Image(systemName: grantedFolders.contains(folder) ? "checkmark.circle.fill" : "folder")
                                .foregroundStyle(grantedFolders.contains(folder) ? .green : .secondary)
                            
                            Text(folder)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if !grantedFolders.contains(folder) {
                                Button("Grant") {
                                    Task {
                                        await grantAccess(to: folder)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Continue") {
                    onGranted()
                }
                .buttonStyle(.borderedProminent)
                .disabled(grantedFolders.count < folders.count)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 300)
    }
    
    private func grantAccess(to folder: String) async {
        if let url = await SecurityBookmarks.shared.selectDirectory(message: "Grant access to: \(folder)") {
            // Check if granted access covers the needed folder
            if url.path == folder || folder.hasPrefix(url.path) || url.path.hasPrefix(folder.components(separatedBy: "/").dropLast().joined(separator: "/")) {
                grantedFolders.insert(folder)
            }
        }
    }
}

// MARK: - Results Summary View

struct ResultsSummaryView: View {
    let results: [ActionResult]
    let onDismiss: () -> Void
    
    var succeeded: [ActionResult] {
        results.filter { $0.success }
    }
    
    var failed: [ActionResult] {
        results.filter { !$0.success }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(failed.isEmpty ? .green : .orange)
                Text("Execution Results")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            // Summary
            HStack(spacing: 24) {
                VStack {
                    Text("\(succeeded.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("Succeeded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text("\(failed.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            // Failed actions details
            if !failed.isEmpty {
                Divider()
                
                Text("Failed Actions:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(failed, id: \.actionId) { result in
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.actionId)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    if let error = result.error {
                                        Text(error)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
            
            // Dismiss button
            HStack {
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Undo Confirmation View

struct UndoConfirmationView: View {
    let actions: [AgentFileAction]
    let description: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.orange)
                Text("Confirm Undo")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Undo: \(description)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("This will reverse the following \(actions.count) action(s):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            // Actions list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(actions) { action in
                        UndoActionRow(action: action)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Buttons
            HStack {
                Text("\(actions.count) action(s) to undo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Undo") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 350)
    }
}

struct UndoActionRow: View {
    let action: AgentFileAction
    
    var icon: String {
        switch action.type {
        case "move": return "arrow.left.square"
        case "delete": return "arrow.uturn.backward"
        case "rename": return "pencil.slash"
        case "deleteFolder": return "folder.badge.minus"
        default: return "arrow.uturn.backward"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(action.description)
                    .font(.subheadline)
                
                if let source = action.sourcePath {
                    Text("From: \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if let dest = action.destinationPath {
                    Text("To: \(dest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ChatView()
        .environmentObject(APIService())
        .environmentObject(SidecarManager())
}
