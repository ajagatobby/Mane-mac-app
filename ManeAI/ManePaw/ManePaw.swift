//
//  ManeAIApp.swift
//  ManeAI
//
//  Local AI File Organizer - Raycast-style Overlay App
//

import SwiftUI
import SwiftData
import AppKit
import Combine

// MARK: - Global Panel Manager

/// Singleton to manage the floating panel across the app
/// Uses OverlayPanel (NSPanel subclass) for proper Raycast-like behavior
final class PanelManager: ObservableObject {
    static let shared = PanelManager()
    
    /// The overlay panel - uses OverlayPanel subclass for proper focus management
    private(set) var panel: OverlayPanel?
    
    /// Backend process manager
    let sidecarManager: SidecarManager
    
    /// API service for backend communication - shares URL with sidecarManager
    let apiService: APIService
    
    var modelContainer: ModelContainer?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    @Published var isPanelVisible = false
    
    private init() {
        // Initialize sidecar manager first
        let sidecar = SidecarManager()
        self.sidecarManager = sidecar
        
        // Initialize API service with the same base URL as sidecar
        self.apiService = APIService(baseURL: sidecar.baseURL.absoluteString)
        
        setupModelContainer()
        setupPanel()
        setupHotkey()
        
        Task {
            await sidecar.start()
        }
    }
    
    private func setupModelContainer() {
        let schema = Schema([Document.self, Project.self, ChatMessage.self, ChatConversation.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
        modelContainer = try? ModelContainer(for: schema, configurations: [config])
    }
    
    // MARK: - Panel Setup
    
    private func setupPanel() {
        guard let container = modelContainer else { return }
        
        // Create the OverlayPanel with production-quality settings
        // OverlayPanel handles: .mainMenu level, resignKey() auto-dismiss,
        // proper style masks, and memory management
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 420),
            backing: .buffered,
            defer: false
        )
        
        // Set up dismissal callback - OverlayPanel's resignKey() will call this
        panel.onDismiss = { [weak self] in
            self?.isPanelVisible = false
        }
        
        // Create SwiftUI content and bridge to AppKit via NSHostingView
        let contentView = RaycastPanelContent(
            onDismiss: { [weak self] in self?.hidePanel() },
            sidecarManager: sidecarManager,
            apiService: apiService
        )
        .modelContainer(container)
        
        panel.contentView = NSHostingView(rootView: contentView)
        self.panel = panel
    }
    
    // MARK: - Hotkey
    
    private func setupHotkey() {
        // Request accessibility permissions (required for global hotkeys)
        // User will be prompted to grant access in System Settings > Privacy > Accessibility
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Mane-paw needs Accessibility permissions for global hotkey. Please enable in System Settings > Privacy & Security > Accessibility")
        }
        
        // Global monitor: Ctrl + W (keyCode 13)
        // This captures the hotkey when app is NOT focused
        // Note: Requires Accessibility permissions to work
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Use deviceIndependentFlagsMask to filter out device-specific flags
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 13 && flags == .control {
                print("🔑 Global hotkey detected: Ctrl+W")
                DispatchQueue.main.async { self?.togglePanel() }
            }
        }
        
        // Local monitor: Same hotkey when app IS focused
        // Returns nil to consume the event (prevents beep)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 13 && flags == .control {
                print("🔑 Local hotkey detected: Ctrl+W")
                DispatchQueue.main.async { self?.togglePanel() }
                return nil // Consume the event
            }
            return event
        }
        
        print("⌨️ Hotkey monitors registered for Ctrl+W")
    }
    
    // MARK: - Panel Control
    
    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        guard let panel = panel else {
            print("❌ Panel is nil - cannot show")
            return
        }
        
        // Activate the app (bring to front) without showing a dock icon
        // This is essential for the panel to receive keyboard input
        NSApp.activate(ignoringOtherApps: true)
        
        // Present the panel with animation (handles positioning internally)
        panel.present()
        
        isPanelVisible = true
        print("✅ Panel shown")
    }
    
    func hidePanel() {
        guard let panel = panel else { return }
        
        // Dismiss with animation - OverlayPanel handles fade-out
        panel.dismiss { [weak self] in
            self?.isPanelVisible = false
        }
    }
    
    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}

// MARK: - App Delegate

/// AppDelegate ensures PanelManager is initialized immediately on app launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force PanelManager initialization on app launch
        // This ensures the global hotkey is registered immediately
        _ = PanelManager.shared
        print("✅ Mane-paw launched - Press Ctrl+W to toggle overlay")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by PanelManager.deinit
    }
}

// MARK: - App Entry Point

@main
struct ManeAIApp: App {
    // Use NSApplicationDelegateAdaptor for proper app lifecycle management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var panelManager = PanelManager.shared
    
    var body: some Scene {
        // Menu Bar Extra - This is the main interface
        MenuBarExtra {
            MenuBarView(panelManager: panelManager)
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.monochrome)
        }
        .menuBarExtraStyle(.menu)
        
        // Settings window
        Settings {
            if let container = panelManager.modelContainer {
                SettingsView()
                    .environmentObject(panelManager.sidecarManager)
                    .environmentObject(panelManager.apiService)
                    .modelContainer(container)
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var panelManager: PanelManager
    
    var body: some View {
        Group {
            // Status
            HStack {
                Circle()
                    .fill(panelManager.sidecarManager.isHealthy ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(panelManager.sidecarManager.isHealthy ? "Backend Connected" : "Connecting...")
            }
            .padding(.vertical, 4)
            
            Divider()
            
            Button("Show Mane-paw") {
                panelManager.showPanel()
            }
            .keyboardShortcut("w", modifiers: .control)
            
            Divider()
            
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit Mane-paw") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Raycast Panel Content

struct RaycastPanelContent: View {
    let onDismiss: () -> Void
    @ObservedObject var sidecarManager: SidecarManager
    @ObservedObject var apiService: APIService
    
    @State private var searchQuery = ""
    @State private var searchMode: SearchMode = .search
    @State private var results: [ResultSection] = []
    @State private var showChat = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var selectedIndex = 0
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var streamingContent = ""
    @State private var isStreaming = false
    @FocusState private var focused: Bool
    
    // Animation namespace for morphing effects
    @Namespace private var animation
    
    // Quick actions data - vibrant colors like Raycast
    private let quickActions: [(title: String, subtitle: String, icon: String, color: Color, id: String)] = [
        ("AI Chat", "Mane-paw AI", "sparkles", Color(red: 0.95, green: 0.3, blue: 0.35), "chat"),
        ("Documents", "Search files", "doc.fill", Color(red: 1.0, green: 0.78, blue: 0.28), "search"),
        ("Projects", "Browse codebases", "folder.fill", Color(red: 0.98, green: 0.6, blue: 0.2), "projects")
    ]
    
    // Commands data - essential utility tools
    private let commands: [(title: String, subtitle: String, icon: String, color: Color, id: String)] = [
        ("Calculator", "Quick math", "plus.forwardslash.minus", Color(red: 0.35, green: 0.35, blue: 0.38), "calculator"),
        ("Clipboard History", "Recent copies", "doc.on.clipboard", Color(red: 0.55, green: 0.36, blue: 0.85), "clipboard"),
        ("Color Picker", "Pick any color", "eyedropper", Color(red: 0.3, green: 0.75, blue: 0.45), "colorpicker")
    ]
    
    // Total selectable items
    private var totalItems: Int {
        if showChat { return 0 }
        if !results.isEmpty {
            // +1 for the "Ask AI" row at the top
            return results.flatMap { $0.items }.count + 1
        }
        return quickActions.count + commands.count
    }
    
    // Dynamic height based on current state
    private var panelHeight: CGFloat {
        showChat ? 450 : 420
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBarView
            
            // Divider
            Rectangle()
                .fill(Color(white: 0.85))
                .frame(height: 0.5)
            
            // Content
            contentView
                .animation(.spring(response: 0.3, dampingFraction: 1.0), value: showChat)
                .animation(.spring(response: 0.25, dampingFraction: 1.0), value: searchMode)
                .animation(.spring(response: 0.25, dampingFraction: 1.0), value: results.isEmpty)
                .animation(.spring(response: 0.2, dampingFraction: 1.0), value: isSearching)
            
            // Action bar
            actionBarView
        }
        .frame(width: 750, height: panelHeight)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: showChat)
        .background {
            // Raycast-style clean background - more opaque for better contrast
            ZStack {
                // Base blur effect
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                
                // Solid light gray overlay for better readability
                Color(red: 0.95, green: 0.95, blue: 0.96)
                    .opacity(0.97)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Inject environment objects for any nested views that need them
        .environmentObject(sidecarManager)
        .environmentObject(apiService)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), Color.black.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 40, y: 15)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .onAppear { 
            focused = true 
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            if showChat { 
                withAnimation(.easeOut(duration: 0.2)) {
                    showChat = false 
                }
                return .handled 
            }
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            withAnimation(.easeOut(duration: 0.1)) {
                selectedIndex = max(0, selectedIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            withAnimation(.easeOut(duration: 0.1)) {
                selectedIndex = min(totalItems - 1, selectedIndex + 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            executeSelectedAction()
            return .handled
        }
        .onKeyPress(.tab) {
            withAnimation(.easeOut(duration: 0.15)) {
                cycleMode()
            }
            return .handled
        }
        .onChange(of: searchQuery) { _, q in 
            selectedIndex = 0
            search(q) 
        }
        .onChange(of: searchMode) { _, newMode in
            // Re-trigger search when mode changes
            if newMode == .chat {
                showChat = true
            } else {
                showChat = false
                search(searchQuery)
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            // Mode indicator button
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    cycleMode()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 14, weight: .medium))
                    if !showChat {
                        Text(modeName)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(modeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(modeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Switch mode (Tab)")
            
            // Text field with custom placeholder
            ZStack(alignment: .leading) {
                // Custom placeholder with better contrast
                if searchQuery.isEmpty {
                    Text(placeholderText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(white: 0.5))
                }
                
                // Actual text field
                TextField("", text: $searchQuery)
                    .font(.system(size: 17, weight: .regular))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(white: 0.0))
                    .focused($focused)
                    .onSubmit { submit() }
            }
            
            Spacer()
            
            // Right side badges
            if searchQuery.isEmpty && !showChat {
                HStack(spacing: 8) {
                    // Tab to switch mode
                    Text("Tab")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 4))
                    
                    Text("to switch")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.45))
                }
            } else if !searchQuery.isEmpty {
                Button { 
                    withAnimation(.easeOut(duration: 0.15)) {
                        searchQuery = "" 
                        results = []
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(white: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }
    
    private var modeIcon: String {
        switch searchMode {
        case .search: return "magnifyingglass"
        case .chat: return "sparkles"
        case .documents: return "doc.fill"
        case .projects: return "folder.fill"
        case .command: return "terminal"
        }
    }
    
    private var modeName: String {
        switch searchMode {
        case .search: return "Search"
        case .chat: return "Chat"
        case .documents: return "Docs"
        case .projects: return "Projects"
        case .command: return "Commands"
        }
    }
    
    private var modeColor: Color {
        switch searchMode {
        case .search: return Color(red: 0.35, green: 0.45, blue: 0.95)
        case .chat: return Color(red: 0.95, green: 0.3, blue: 0.35)
        case .documents: return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .projects: return Color(red: 0.98, green: 0.6, blue: 0.2)
        case .command: return Color(red: 0.5, green: 0.5, blue: 0.55)
        }
    }
    
    private var placeholderText: String {
        switch searchMode {
        case .search: return "Search your knowledge base..."
        case .chat: return "Ask Mane-paw anything..."
        case .documents: return "Search documents..."
        case .projects: return "Search projects..."
        case .command: return "Type a command..."
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if showChat {
            chatView
                .transition(.smoothFade)
        } else if results.isEmpty && searchQuery.isEmpty {
            quickActionsView
                .transition(.smoothFade)
        } else if isSearching {
            searchingView
                .transition(.cleanFade)
        } else if results.isEmpty && !searchQuery.isEmpty {
            noResultsView
                .transition(.smoothFade)
        } else {
            resultsListView
                .transition(.smoothFade)
        }
    }
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color(red: 0.35, green: 0.45, blue: 0.95))
            
            Text("Searching your knowledge base...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var quickActionsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Section header - Raycast style
                Text("Suggestions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                
                // Quick action items
                ForEach(Array(quickActions.enumerated()), id: \.element.id) { index, action in
                    RaycastRow(
                        icon: action.icon,
                        iconColor: action.color,
                        title: action.title,
                        subtitle: action.subtitle,
                        accessoryText: "Command",
                        isSelected: selectedIndex == index
                    ) {
                        handleQuickAction(action.id)
                    }
                }
                
                // Commands section
                Text("Commands")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                
                // Command items
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    RaycastRow(
                        icon: command.icon,
                        iconColor: command.color,
                        title: command.title,
                        subtitle: command.subtitle,
                        accessoryText: "Command",
                        isSelected: selectedIndex == quickActions.count + index
                    ) {
                        handleCommand(command.id)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    private func handleCommand(_ id: String) {
        switch id {
        case "calculator":
            // Open Calculator app
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case "clipboard":
            // Show clipboard history (placeholder - future feature)
            print("Clipboard history")
        case "colorpicker":
            // Open color picker
            NSColorPanel.shared.makeKeyAndOrderFront(nil)
        default:
            break
        }
        onDismiss()
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(white: 0.65))
            
            VStack(spacing: 4) {
                Text("No Results")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.3))
                Text("No matches found for \"\(searchQuery)\"")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultsListView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Show AI suggestion at top if searching
                if !searchQuery.isEmpty {
                    askAIRow
                }
                
                ForEach(results) { section in
                    Text(section.category.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        let globalIndex = index + 1 // +1 for AI row
                        SearchResultRow(
                            item: item,
                            isSelected: selectedIndex == globalIndex,
                            onOpen: { openFile(item) },
                            onAskAI: { askAIAbout(item) }
                        )
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    private var askAIRow: some View {
        RaycastRow(
            icon: "sparkles",
            iconColor: Color(red: 0.95, green: 0.3, blue: 0.35),
            title: "Ask AI: \"\(searchQuery)\"",
            subtitle: "Get an AI-powered answer",
            accessoryText: "↵",
            isSelected: selectedIndex == 0
        ) {
            askAIDirectly()
        }
    }
    
    private func openFile(_ item: ResultItem) {
        guard let path = item.subtitle else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        onDismiss()
    }
    
    private func askAIAbout(_ item: ResultItem) {
        let query = "Tell me about the file: \(item.title)"
        searchQuery = ""
        showChat = true
        chatMessages.append(ChatMessage(content: query, isUser: true))
        streamChatResponse(query: query)
    }
    
    private func askAIDirectly() {
        let query = searchQuery
        searchQuery = ""
        results = []
        showChat = true
        chatMessages.append(ChatMessage(content: query, isUser: true))
        streamChatResponse(query: query)
    }
    
    private var chatView: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Button { 
                    withAnimation(.easeOut(duration: 0.2)) {
                        showChat = false
                        chatMessages = []
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("AI Chat")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.91))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        if chatMessages.isEmpty && !isStreaming {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(Color(white: 0.65))
                                Text("Ask anything about your documents")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                        
                        ForEach(chatMessages) { msg in
                            ChatBubble(message: msg)
                        }
                        
                        // Streaming message
                        if isStreaming {
                            StreamingChatBubble(content: streamingContent)
                                .id("streaming")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: streamingContent) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: chatMessages.count) { _, _ in
                    if let last = chatMessages.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input hint
            HStack {
                Spacer()
                Text("Type your message and press ↵")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Action Bar (Raycast style footer)
    
    private var actionBarView: some View {
        HStack(spacing: 0) {
            // Left side - status and navigation
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: sidecarManager.isHealthy ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sidecarManager.isHealthy ? Color(white: 0.35) : .orange)
                
                // Navigation arrows
                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.82), in: RoundedRectangle(cornerRadius: 4))
                    
                    Text("Navigate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                }
            }
            
            Spacer()
            
            // Right side - action hints (Raycast style)
            HStack(spacing: 16) {
                // Open Command action
                HStack(spacing: 6) {
                    Text("Open")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                    
                    Text("↵")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.3))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.82), in: RoundedRectangle(cornerRadius: 4))
                }
                
                // Divider
                Rectangle()
                    .fill(Color(white: 0.75))
                    .frame(width: 1, height: 14)
                
                // Actions
                HStack(spacing: 6) {
                    Text("Actions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                    
                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 11, weight: .semibold))
                        Text("K")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(white: 0.82), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color(white: 0.91))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(white: 0.80))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Helpers
    
    private func getFileExtension(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
    
    private func handleQuickAction(_ id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch id {
            case "chat":
                searchMode = .chat
                showChat = true
            case "search":
                searchMode = .documents
            case "projects":
                searchMode = .projects
            case "import":
                break
            default:
                break
            }
        }
    }
    
    private func executeSelectedAction() {
        // Handle chat mode - submit the message
        if showChat {
            guard !searchQuery.isEmpty else { return }
            let q = searchQuery
            searchQuery = ""
            chatMessages.append(ChatMessage(content: q, isUser: true))
            streamChatResponse(query: q)
            return
        }
        
        if results.isEmpty && searchQuery.isEmpty {
            // Quick actions + commands
            if selectedIndex < quickActions.count {
                handleQuickAction(quickActions[selectedIndex].id)
            } else {
                let commandIndex = selectedIndex - quickActions.count
                if commandIndex < commands.count {
                    handleCommand(commands[commandIndex].id)
                }
            }
        } else if results.isEmpty && !searchQuery.isEmpty {
            // No results but has query - ask AI directly
            askAIDirectly()
        } else if !results.isEmpty {
            // First item (index 0) is "Ask AI" row
            if selectedIndex == 0 {
                askAIDirectly()
            } else {
                // Results (offset by 1 for AI row)
                let allItems = results.flatMap { $0.items }
                let itemIndex = selectedIndex - 1
                if itemIndex < allItems.count {
                    let item = allItems[itemIndex]
                    // Check category to determine action
                    switch item.category {
                    case .documents:
                        openFile(item)
                    case .projects:
                        openProject(item)
                    case .commands:
                        handleResultCommand(item)
                    default:
                        openFile(item)
                    }
                }
            }
        }
    }
    
    private func openProject(_ item: ResultItem) {
        guard let path = item.subtitle else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        onDismiss()
    }
    
    private func handleResultCommand(_ item: ResultItem) {
        handleCommand(item.id)
    }
    
    private func cycleMode() {
        let modes: [SearchMode] = [.search, .documents, .projects, .chat, .command]
        if let i = modes.firstIndex(of: searchMode) {
            let nextMode = modes[(i + 1) % modes.count]
            searchMode = nextMode
        }
    }
    
    private func submit() {
        if showChat {
            guard !searchQuery.isEmpty else { return }
            let q = searchQuery
            searchQuery = ""
            chatMessages.append(ChatMessage(content: q, isUser: true))
            streamChatResponse(query: q)
        } else {
            executeSelectedAction()
        }
    }
    
    private func streamChatResponse(query: String) {
        isStreaming = true
        streamingContent = ""
        
        Task {
            do {
                for try await chunk in apiService.chatStream(query: query) {
                    await MainActor.run {
                        streamingContent += chunk
                    }
                }
                await MainActor.run {
                    chatMessages.append(ChatMessage(content: streamingContent, isUser: false))
                    streamingContent = ""
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false))
                    streamingContent = ""
                    isStreaming = false
                }
            }
        }
    }
    
    private func search(_ query: String) {
        // Cancel any existing search task
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Debounce: wait 300ms before searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard !Task.isCancelled else { return }
            
            do {
                // Search based on mode
                switch searchMode {
                case .search, .documents:
                    let resp = try await apiService.search(query: query, limit: 10)
                    let items = resp.results.map { result -> ResultItem in
                        let fileName = URL(fileURLWithPath: result.filePath).lastPathComponent
                        let (icon, color) = iconForFile(result.filePath, mediaType: result.mediaType)
                        let score = Int(result.score * 100)
                        return ResultItem(
                            id: result.id,
                            title: fileName,
                            subtitle: result.filePath,
                            icon: icon,
                            iconColor: color,
                            category: .documents,
                            metadata: ["score": "\(score)%"]
                        )
                    }
                    await MainActor.run {
                        results = items.isEmpty ? [] : [ResultSection(category: .documents, items: items)]
                        isSearching = false
                        selectedIndex = 0
                    }
                    
                case .projects:
                    let resp = try await apiService.searchProjects(query: query, limit: 10)
                    let items = resp.map { project -> ResultItem in
                        ResultItem(
                            id: project.id,
                            title: project.name,
                            subtitle: project.path,
                            icon: iconForProject(project.techStack),
                            iconColor: Color(red: 0.98, green: 0.6, blue: 0.2),
                            category: .projects,
                            metadata: ["files": "\(project.fileCount)"]
                        )
                    }
                    await MainActor.run {
                        results = items.isEmpty ? [] : [ResultSection(category: .projects, items: items)]
                        isSearching = false
                        selectedIndex = 0
                    }
                    
                case .chat:
                    // Chat mode doesn't search, it just enters chat
                    await MainActor.run {
                        isSearching = false
                    }
                    
                case .command:
                    // Filter commands locally
                    let filtered = commands.filter {
                        $0.title.localizedCaseInsensitiveContains(query) ||
                        $0.subtitle.localizedCaseInsensitiveContains(query)
                    }
                    let items = filtered.map { cmd in
                        ResultItem(
                            id: cmd.id,
                            title: cmd.title,
                            subtitle: cmd.subtitle,
                            icon: cmd.icon,
                            iconColor: cmd.color,
                            category: .commands
                        )
                    }
                    await MainActor.run {
                        results = items.isEmpty ? [] : [ResultSection(category: .commands, items: items)]
                        isSearching = false
                        selectedIndex = 0
                    }
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }
    
    // MARK: - File Type Helpers
    
    private func iconForFile(_ path: String, mediaType: MediaType?) -> (String, Color) {
        // Check media type first
        if let type = mediaType {
            switch type {
            case .image:
                return ("photo.fill", Color(red: 0.9, green: 0.45, blue: 0.55))
            case .audio:
                return ("waveform", Color(red: 0.95, green: 0.75, blue: 0.3))
            case .text:
                break // Fall through to extension check
            }
        }
        
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift":
            return ("swift", .orange)
        case "ts", "tsx":
            return ("t.square.fill", Color(red: 0.2, green: 0.5, blue: 0.8))
        case "js", "jsx":
            return ("j.square.fill", Color(red: 0.95, green: 0.85, blue: 0.3))
        case "py":
            return ("p.circle.fill", Color(red: 0.3, green: 0.5, blue: 0.75))
        case "rs":
            return ("gearshape.2.fill", Color(red: 0.8, green: 0.4, blue: 0.2))
        case "go":
            return ("g.circle.fill", Color(red: 0.3, green: 0.75, blue: 0.85))
        case "md", "markdown":
            return ("doc.richtext.fill", Color(red: 0.4, green: 0.4, blue: 0.45))
        case "json":
            return ("curlybraces", Color(red: 0.5, green: 0.5, blue: 0.55))
        case "yaml", "yml":
            return ("list.bullet.rectangle.fill", Color(red: 0.6, green: 0.4, blue: 0.6))
        case "html":
            return ("chevron.left.forwardslash.chevron.right", Color(red: 0.9, green: 0.45, blue: 0.3))
        case "css", "scss":
            return ("paintbrush.fill", Color(red: 0.3, green: 0.5, blue: 0.9))
        case "pdf":
            return ("doc.fill", Color(red: 0.9, green: 0.3, blue: 0.3))
        case "txt":
            return ("doc.text.fill", Color(red: 0.5, green: 0.5, blue: 0.55))
        default:
            return ("doc.fill", Color(red: 0.4, green: 0.55, blue: 0.9))
        }
    }
    
    private func iconForProject(_ techStack: [String]) -> String {
        let primary = techStack.first?.lowercased() ?? ""
        if primary.contains("swift") { return "swift" }
        if primary.contains("typescript") || primary.contains("javascript") { return "curlybraces" }
        if primary.contains("python") { return "p.circle.fill" }
        if primary.contains("rust") { return "gearshape.2.fill" }
        if primary.contains("go") { return "g.circle.fill" }
        return "folder.fill"
    }
}

// MARK: - Raycast Row (matches actual Raycast design)

struct RaycastRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let accessoryText: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon - colored rounded square with white SF Symbol
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 28, height: 28)
                        .shadow(color: iconColor.opacity(0.3), radius: 2, y: 1)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                // Title and optional subtitle inline
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.05))
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Right-aligned accessory text
                Text(accessoryText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(red: 0.82, green: 0.88, blue: 0.97) : (isHovered ? Color(white: 0.90) : Color.clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let item: ResultItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onAskAI: () -> Void
    
    @State private var isHovered = false
    @State private var showActions = false
    
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                // Icon - colored rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.iconColor)
                        .frame(width: 28, height: 28)
                        .shadow(color: item.iconColor.opacity(0.3), radius: 2, y: 1)
                    
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                // Title and path
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.05))
                        .lineLimit(1)
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Metadata badge (relevance score)
                if let metadata = item.metadata, let score = metadata["score"] {
                    Text(score)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.9), in: Capsule())
                }
                
                // Actions on hover/selection
                if isSelected || isHovered {
                    HStack(spacing: 4) {
                        // Ask AI button
                        Button {
                            onAskAI()
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.35))
                                .frame(width: 22, height: 22)
                                .background(Color(red: 0.95, green: 0.3, blue: 0.35).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Ask AI about this file")
                        
                        // Open indicator
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(white: 0.35))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(red: 0.82, green: 0.88, blue: 0.97) : (isHovered ? Color(white: 0.92) : Color.clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Spacer on left for user messages (pushes content right)
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            if !message.isUser {
                // AI avatar
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.25, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Mane-paw")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(message.isUser ? .white : Color(white: 0.1))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isUser 
                            ? AnyShapeStyle(Color(red: 0.2, green: 0.5, blue: 0.95))
                            : AnyShapeStyle(Color(white: 0.88)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .frame(maxWidth: 400, alignment: message.isUser ? .trailing : .leading)
            
            // Spacer on right for AI messages (pushes content left)
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

// MARK: - Streaming Chat Bubble

struct StreamingChatBubble: View {
    let content: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI avatar
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.25, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Mane-paw")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                
                // Message bubble with content or typing indicator
                HStack(spacing: 6) {
                    if content.isEmpty {
                        // Typing indicator dots
                        TypingIndicator()
                    } else {
                        Text(content)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.1))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: 400, alignment: .leading)
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    /// macOS-style subtle crossfade with blur and minimal movement
    static var smoothFade: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SmoothFadeModifier(opacity: 0, offset: 4, blur: 6),
                identity: SmoothFadeModifier(opacity: 1, offset: 0, blur: 0)
            ),
            removal: .modifier(
                active: SmoothFadeModifier(opacity: 0, offset: -2, blur: 4),
                identity: SmoothFadeModifier(opacity: 1, offset: 0, blur: 0)
            )
        )
    }
    
    /// Clean crossfade with subtle blur
    static var cleanFade: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SmoothFadeModifier(opacity: 0, offset: 0, blur: 4),
                identity: SmoothFadeModifier(opacity: 1, offset: 0, blur: 0)
            ),
            removal: .modifier(
                active: SmoothFadeModifier(opacity: 0, offset: 0, blur: 3),
                identity: SmoothFadeModifier(opacity: 1, offset: 0, blur: 0)
            )
        )
    }
}

struct SmoothFadeModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat
    let blur: CGFloat
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
            .blur(radius: blur)
    }
}
