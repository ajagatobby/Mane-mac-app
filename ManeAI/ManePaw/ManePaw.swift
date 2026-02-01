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
    var sidecarManager = SidecarManager()
    var apiService = APIService()
    var modelContainer: ModelContainer?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    @Published var isPanelVisible = false
    
    private init() {
        setupModelContainer()
        setupPanel()
        setupHotkey()
        
        Task {
            await sidecarManager.start()
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
        if !results.isEmpty { return results.flatMap { $0.items }.count }
        return quickActions.count + commands.count
    }
    
    // Dynamic height based on current state
    private var panelHeight: CGFloat {
        if showChat && results.isEmpty {
            let baseHeight: CGFloat = 340
            let messageHeight = min(CGFloat(chatMessages.count) * 50, 160)
            return baseHeight + messageHeight
        }
        return 420
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
                .animation(.easeInOut(duration: 0.25), value: showChat)
                .animation(.easeInOut(duration: 0.2), value: searchMode)
            
            // Action bar
            actionBarView
        }
        .frame(width: 750, height: panelHeight)
        .animation(.easeInOut(duration: 0.3), value: showChat)
        .animation(.easeInOut(duration: 0.2), value: chatMessages.count)
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
        .onChange(of: searchQuery) { _, q in 
            selectedIndex = 0
            search(q) 
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            // Text field with custom placeholder
            ZStack(alignment: .leading) {
                // Custom placeholder with better contrast
                if searchQuery.isEmpty {
                    Text("Search for apps and commands...")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(white: 0.5))
                }
                
                // Actual text field
                TextField("", text: $searchQuery)
                    .font(.system(size: 17, weight: .regular))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(white: 0.0))
                    .focused($focused)
                    .onSubmit { 
                        if showChat {
                            submit()
                        } else {
                            executeSelectedAction()
                        }
                    }
            }
            
            Spacer()
            
            // Right side badges
            if searchQuery.isEmpty {
                HStack(spacing: 8) {
                    // Ask AI badge
                    Text("Ask AI")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.4))
                    
                    // Tab badge
                    Text("Tab")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 4))
                }
            } else {
                Button { 
                    withAnimation(.easeOut(duration: 0.15)) {
                        searchQuery = "" 
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
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if showChat {
            chatView
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .trailing))
                ))
        } else if results.isEmpty && searchQuery.isEmpty {
            quickActionsView
                .transition(.opacity)
        } else if results.isEmpty && !searchQuery.isEmpty {
            noResultsView
                .transition(.opacity)
        } else {
            resultsListView
                .transition(.opacity)
        }
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
                ForEach(results) { section in
                    Text(section.category.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        RaycastRow(
                            icon: item.icon,
                            iconColor: item.iconColor,
                            title: item.title,
                            subtitle: item.subtitle,
                            accessoryText: getFileExtension(item.title),
                            isSelected: selectedIndex == index
                        ) {
                            // Open file action
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
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
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if chatMessages.isEmpty {
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
                }
                .padding(16)
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
        if showChat { return }
        
        if results.isEmpty && searchQuery.isEmpty {
            // Quick actions
            if selectedIndex < quickActions.count {
                handleQuickAction(quickActions[selectedIndex].id)
            }
        } else if !results.isEmpty {
            // Results
            let allItems = results.flatMap { $0.items }
            if selectedIndex < allItems.count {
                // Handle result selection
            }
        }
    }
    
    private func cycleMode() {
        let modes: [SearchMode] = [.search, .chat, .documents, .projects]
        if let i = modes.firstIndex(of: searchMode) {
            searchMode = modes[(i + 1) % modes.count]
            showChat = searchMode == .chat
        }
    }
    
    private func submit() {
        guard showChat, !searchQuery.isEmpty else { return }
        let q = searchQuery
        searchQuery = ""
        chatMessages.append(ChatMessage(content: q, isUser: true))
        
        Task {
            var resp = ""
            do {
                for try await chunk in apiService.chatStream(query: q) { resp += chunk }
                await MainActor.run { chatMessages.append(ChatMessage(content: resp, isUser: false)) }
            } catch {
                await MainActor.run { chatMessages.append(ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)) }
            }
        }
    }
    
    private func search(_ query: String) {
        guard !query.isEmpty else { results = []; return }
        
        Task {
            do {
                let resp = try await apiService.search(query: query, limit: 10)
                let items = resp.results.map {
                    ResultItem(id: $0.id, title: URL(fileURLWithPath: $0.filePath).lastPathComponent, subtitle: $0.filePath, icon: "doc.fill", iconColor: .blue, category: .documents)
                }
                await MainActor.run { results = items.isEmpty ? [] : [ResultSection(category: .documents, items: items)] }
            } catch {
                await MainActor.run { results = [] }
            }
        }
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

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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
            
            if message.isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}
