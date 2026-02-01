//
//  OverlayView.swift
//  ManeAI
//
//  Main overlay view combining SearchBar, ResultsList, and ActionPanel
//  Raycast-inspired command palette interface
//

import SwiftUI
import SwiftData

// MARK: - Overlay View

/// Main overlay view with Raycast-style command palette interface
struct OverlayView: View {
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var sidecarManager: SidecarManager
    @Environment(\.modelContext) private var modelContext
    
    // State
    @State private var searchQuery = ""
    @State private var searchMode: SearchMode = .search
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var results: [ResultSection] = []
    
    // Chat state
    @State private var chatMessages: [ChatMessage] = []
    @State private var streamingMessage: ChatMessage?
    @State private var showChatView = false
    
    // Focus
    @FocusState private var isSearchFocused: Bool
    
    // Dismiss action
    var onDismiss: () -> Void = {}
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            SearchBar(
                text: $searchQuery,
                mode: $searchMode,
                isFocused: $isSearchFocused,
                onSubmit: handleSubmit,
                onModeChange: handleModeChange,
                onEscape: onDismiss
            )
            .padding(ManeTheme.Spacing.lg)
            
            // Divider
            Divider()
                .background(ManeTheme.Colors.divider)
            
            // Content area
            contentView
            
            // Action Panel
            if !showChatView {
                ContextualActionPanel(
                    selectedItem: selectedItem,
                    mode: searchMode,
                    onAction: handleAction
                )
            }
        }
        .frame(width: ManeTheme.Sizes.panelWidth)
        .frame(minHeight: ManeTheme.Sizes.panelMinHeight, maxHeight: ManeTheme.Sizes.panelMaxHeight)
        .panelGlassBackground()
        .onAppear {
            isSearchFocused = true
            loadInitialResults()
        }
        .onChange(of: searchQuery) { _, newValue in
            performSearch(query: newValue)
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        if showChatView {
            chatContentView
        } else if isLoading {
            LoadingResultsView()
                .frame(height: 300)
        } else if results.isEmpty && !searchQuery.isEmpty {
            EmptyResultsView(query: searchQuery)
                .frame(height: 300)
        } else if results.isEmpty {
            suggestionsView
                .frame(height: 300)
        } else {
            ResultsList(
                sections: results,
                selectedIndex: $selectedIndex,
                onSelect: handleSelect,
                onAction: handleResultAction
            )
            .frame(height: min(CGFloat(totalItemCount) * ManeTheme.Sizes.resultRowHeight + 100, 350))
        }
    }
    
    // MARK: - Suggestions View
    
    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: ManeTheme.Spacing.lg) {
            // Quick actions
            Text("Quick Actions")
                .font(ManeTheme.Typography.captionMedium)
                .foregroundStyle(ManeTheme.Colors.textSecondary)
                .padding(.horizontal, ManeTheme.Spacing.lg)
                .padding(.top, ManeTheme.Spacing.md)
            
            VStack(spacing: 0) {
                SuggestionRow(
                    title: "Ask Mane-paw",
                    subtitle: "Start a conversation with AI",
                    icon: "bubble.left.and.bubble.right",
                    iconColor: ManeTheme.Colors.categoryChat,
                    shortcut: "⌘⇧C"
                ) {
                    searchMode = .chat
                    showChatView = true
                }
                
                SuggestionRow(
                    title: "Search Documents",
                    subtitle: "Find files in your knowledge base",
                    icon: "doc.text.magnifyingglass",
                    iconColor: ManeTheme.Colors.categoryDocument,
                    shortcut: "⌘⇧D"
                ) {
                    searchMode = .documents
                }
                
                SuggestionRow(
                    title: "Browse Projects",
                    subtitle: "View indexed codebases",
                    icon: "folder.badge.gearshape",
                    iconColor: ManeTheme.Colors.categoryProject,
                    shortcut: "⌘⇧P"
                ) {
                    searchMode = .projects
                }
                
                SuggestionRow(
                    title: "Import Files",
                    subtitle: "Add files to your knowledge base",
                    icon: "square.and.arrow.down",
                    iconColor: ManeTheme.Colors.accentPrimary,
                    shortcut: "⌘I"
                ) {
                    handleAction("import")
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Chat Content View
    
    private var chatContentView: some View {
        VStack(spacing: 0) {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: ManeTheme.Spacing.md) {
                        ForEach(chatMessages) { message in
                            OverlayChatBubble(message: message)
                                .id(message.id)
                        }
                        
                        if let streaming = streamingMessage {
                            OverlayChatBubble(message: streaming)
                                .id(streaming.id)
                        }
                    }
                    .padding(ManeTheme.Spacing.lg)
                }
                .onChange(of: chatMessages.count) { _, _ in
                    if let last = chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Chat input hint
            HStack {
                Text("Press")
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
                
                KeyboardShortcutBadge(shortcut: "↵")
                
                Text("to send")
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
                
                Spacer()
                
                Button {
                    showChatView = false
                    chatMessages.removeAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("Close Chat")
                    }
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ManeTheme.Spacing.lg)
            .padding(.vertical, ManeTheme.Spacing.sm)
            .background {
                ActionPanelGlassBackground()
            }
        }
        .frame(height: 350)
    }
    
    // MARK: - Computed Properties
    
    private var selectedItem: ResultItem? {
        let allItems = results.flatMap { $0.items }
        return allItems[safe: selectedIndex]
    }
    
    private var totalItemCount: Int {
        results.reduce(0) { $0 + $1.items.count }
    }
    
    // MARK: - Event Handlers
    
    private func handleSubmit() {
        if showChatView {
            sendChatMessage()
        } else if let item = selectedItem {
            handleSelect(item)
        }
    }
    
    private func handleModeChange(_ newMode: SearchMode) {
        selectedIndex = 0
        showChatView = newMode == .chat
        performSearch(query: searchQuery)
    }
    
    private func handleSelect(_ item: ResultItem) {
        // Handle selection based on category
        switch item.category {
        case .chat:
            showChatView = true
            searchMode = .chat
        case .commands:
            executeCommand(item)
        default:
            openItem(item)
        }
    }
    
    private func handleResultAction(_ item: ResultItem, action: ResultAction) {
        switch action {
        case .open:
            openItem(item)
        case .preview:
            previewItem(item)
        case .copy:
            copyItem(item)
        case .delete:
            deleteItem(item)
        }
    }
    
    private func handleAction(_ action: String) {
        switch action {
        case "open":
            if let item = selectedItem {
                openItem(item)
            }
        case "preview":
            if let item = selectedItem {
                previewItem(item)
            }
        case "copy":
            if let item = selectedItem {
                copyItem(item)
            }
        case "import":
            // Trigger file import
            break
        case "newChat":
            showChatView = true
            searchMode = .chat
            chatMessages.removeAll()
        case "reindex":
            // Trigger project reindex
            break
        default:
            break
        }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow:
            if selectedIndex > 0 {
                withAnimation(ManeTheme.Animation.fast) {
                    selectedIndex -= 1
                }
            }
            return .handled
            
        case .downArrow:
            if selectedIndex < totalItemCount - 1 {
                withAnimation(ManeTheme.Animation.fast) {
                    selectedIndex += 1
                }
            }
            return .handled
            
        case .escape:
            if showChatView {
                showChatView = false
                return .handled
            }
            onDismiss()
            return .handled
            
        default:
            return .ignored
        }
    }
    
    // MARK: - Search & Data
    
    private func loadInitialResults() {
        // Load recent items and suggestions
        Task {
            await loadDocuments()
            await loadProjects()
        }
    }
    
    private func performSearch(query: String) {
        selectedIndex = 0
        
        guard !query.isEmpty else {
            results = []
            return
        }
        
        isLoading = true
        
        Task {
            // Simulate search delay
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            var sections: [ResultSection] = []
            
            // Search based on mode
            switch searchMode {
            case .documents, .search:
                let docs = await searchDocuments(query: query)
                if !docs.isEmpty {
                    sections.append(ResultSection(category: .documents, items: docs))
                }
                
            case .projects:
                let projects = await searchProjects(query: query)
                if !projects.isEmpty {
                    sections.append(ResultSection(category: .projects, items: projects))
                }
                
            case .chat:
                // Chat mode doesn't show search results
                break
                
            case .command:
                let commands = searchCommands(query: query)
                if !commands.isEmpty {
                    sections.append(ResultSection(category: .commands, items: commands))
                }
            }
            
            await MainActor.run {
                results = sections
                isLoading = false
            }
        }
    }
    
    private func loadDocuments() async {
        // Load from API
    }
    
    private func loadProjects() async {
        // Load from API
    }
    
    private func searchDocuments(query: String) async -> [ResultItem] {
        // Search documents via API
        do {
            let response = try await apiService.search(query: query, limit: 10)
            return response.results.map { result in
                ResultItem(
                    id: result.id,
                    title: URL(fileURLWithPath: result.filePath).lastPathComponent,
                    subtitle: result.filePath,
                    icon: iconForFile(result.filePath),
                    iconColor: colorForFile(result.filePath),
                    category: .documents,
                    metadata: ["score": String(format: "%.0f%%", result.score * 100)]
                )
            }
        } catch {
            return []
        }
    }
    
    private func searchProjects(query: String) async -> [ResultItem] {
        // Search projects via API
        do {
            let response = try await apiService.listProjects()
            return response.projects
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map { project in
                    ResultItem(
                        id: project.id,
                        title: project.name,
                        subtitle: "\(project.fileCount) files",
                        icon: "folder.fill",
                        iconColor: ManeTheme.Colors.categoryProject,
                        category: .projects
                    )
                }
        } catch {
            return []
        }
    }
    
    private func searchCommands(query: String) -> [ResultItem] {
        let commands = [
            ResultItem(
                title: "Start Chat",
                subtitle: "Open AI chat interface",
                icon: "bubble.left.and.bubble.right",
                iconColor: ManeTheme.Colors.categoryChat,
                category: .commands
            ),
            ResultItem(
                title: "Import Files",
                subtitle: "Add files to knowledge base",
                icon: "square.and.arrow.down",
                iconColor: ManeTheme.Colors.accentPrimary,
                category: .commands
            ),
            ResultItem(
                title: "Check Health",
                subtitle: "Verify backend connection",
                icon: "heart.fill",
                iconColor: ManeTheme.Colors.statusSuccess,
                category: .commands
            ),
            ResultItem(
                title: "Settings",
                subtitle: "Configure Mane-paw",
                icon: "gear",
                iconColor: ManeTheme.Colors.categorySettings,
                category: .commands
            ),
        ]
        
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    
    // MARK: - Chat
    
    private func sendChatMessage() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let query = searchQuery
        searchQuery = ""
        
        // Add user message
        let userMessage = ChatMessage(content: query, isUser: true)
        chatMessages.append(userMessage)
        
        // Create streaming placeholder
        let assistantMessage = ChatMessage(content: "", isUser: false, isStreaming: true)
        streamingMessage = assistantMessage
        
        Task {
            do {
                var fullResponse = ""
                
                for try await chunk in apiService.chatStream(query: query) {
                    fullResponse += chunk
                    await MainActor.run {
                        streamingMessage?.content = fullResponse
                    }
                }
                
                await MainActor.run {
                    let finalMessage = ChatMessage(content: fullResponse, isUser: false)
                    chatMessages.append(finalMessage)
                    streamingMessage = nil
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)
                    chatMessages.append(errorMessage)
                    streamingMessage = nil
                }
            }
        }
    }
    
    // MARK: - Item Actions
    
    private func openItem(_ item: ResultItem) {
        // Open the item
        onDismiss()
    }
    
    private func previewItem(_ item: ResultItem) {
        // Quick look preview
    }
    
    private func copyItem(_ item: ResultItem) {
        // Copy to clipboard
        if let subtitle = item.subtitle {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(subtitle, forType: .string)
        }
    }
    
    private func deleteItem(_ item: ResultItem) {
        // Delete item
    }
    
    private func executeCommand(_ item: ResultItem) {
        switch item.title {
        case "Start Chat":
            showChatView = true
            searchMode = .chat
        case "Import Files":
            handleAction("import")
        case "Settings":
            // Open settings
            break
        default:
            break
        }
    }
    
    // MARK: - Helpers
    
    private func iconForFile(_ path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "t.square"
        case "js", "jsx": return "j.square"
        case "py": return "p.square"
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.rectangle"
        default: return "doc.text"
        }
    }
    
    private func colorForFile(_ path: String) -> Color {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "ts", "tsx": return .blue
        case "js", "jsx": return .yellow
        case "py": return .green
        case "md": return ManeTheme.Colors.categoryDocument
        default: return ManeTheme.Colors.textSecondary
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let shortcut: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: ManeTheme.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: ManeTheme.Sizes.resultIconCorner)
                        .fill(iconColor.opacity(0.12))
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                .frame(width: ManeTheme.Sizes.resultIconSize, height: ManeTheme.Sizes.resultIconSize)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ManeTheme.Typography.resultTitle)
                        .foregroundStyle(ManeTheme.Colors.textPrimary)
                    
                    Text(subtitle)
                        .font(ManeTheme.Typography.resultSubtitle)
                        .foregroundStyle(ManeTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Shortcut
                KeyboardShortcutBadge(shortcut: shortcut)
            }
            .padding(.horizontal, ManeTheme.Spacing.lg)
            .frame(height: ManeTheme.Sizes.resultRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardBackground(isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Overlay Chat Bubble

struct OverlayChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: ManeTheme.Spacing.sm) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                // AI avatar
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(ManeTheme.Colors.accentPurple)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(ManeTheme.Colors.accentPurple.opacity(0.12))
                    }
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(message.isUser ? ManeTheme.Colors.textInverse : ManeTheme.Colors.textPrimary)
                    .padding(ManeTheme.Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.md)
                            .fill(message.isUser ? ManeTheme.Colors.accentPrimary : ManeTheme.Colors.backgroundSecondary)
                    }
                
                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Generating...")
                            .font(ManeTheme.Typography.caption)
                            .foregroundStyle(ManeTheme.Colors.textTertiary)
                    }
                }
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            } else {
                // User avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(ManeTheme.Colors.accentPrimary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Overlay View") {
    OverlayView()
        .environmentObject(APIService())
        .environmentObject(SidecarManager())
        .modelContainer(for: [Document.self, Project.self, ChatMessage.self], inMemory: true)
}
