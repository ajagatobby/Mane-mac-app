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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
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
    @FocusState private var focused: Bool
    
    // Animation namespace for morphing effects
    @Namespace private var animation
    
    // Dynamic height based on current state
    private var panelHeight: CGFloat {
        if showChat && results.isEmpty {
            // Compact height for chat mode (grows slightly with messages)
            let baseHeight: CGFloat = 320
            let messageHeight = min(CGFloat(chatMessages.count) * 40, 180)
            return baseHeight + messageHeight
        } else if !results.isEmpty {
            // Full height when showing results
            return 500
        } else {
            // Default height for quick actions
            return 500
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBarView
            
            Divider()
            
            // Content with smooth transitions
            contentView
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showChat)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchMode)
            
            // Action bar
            actionBarView
        }
        .frame(width: 680, height: panelHeight)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showChat)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chatMessages.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: results.isEmpty)
        .background {
            ZStack {
                // Base blur layer
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                
                // Solid background layer for proper opacity
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.85)
                
                // Subtle gradient for depth
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Very subtle noise for texture
                StaticNoiseOverlay(intensity: 0.012)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 50, y: 15)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            if showChat { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showChat = false 
                }
                return .handled 
            }
            onDismiss()
            return .handled
        }
        .onChange(of: searchQuery) { _, q in search(q) }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: searchMode.icon)
                .font(.system(size: 22))
                .foregroundStyle(searchMode.iconColor)
                .frame(width: 32)
                .contentTransition(.symbolEffect(.replace))
                .onTapGesture { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        cycleMode() 
                    }
                }
            
            TextField(searchMode.placeholder, text: $searchQuery)
                .font(.system(size: 20))
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { submit() }
            
            if searchQuery.isEmpty {
                Text("⌃W")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        ZStack {
            if showChat {
                chatView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.95))
                    ))
            } else if results.isEmpty && searchQuery.isEmpty {
                quickActionsView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            } else if results.isEmpty {
                noResultsView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                resultsListView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
    
    private var quickActionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Quick Actions")
                
                AnimatedActionRow(
                    title: "Chat with AI",
                    subtitle: "Ask questions about your files",
                    icon: "bubble.left.and.bubble.right",
                    color: .purple,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchMode = .chat
                        showChat = true
                    }
                }
                
                AnimatedActionRow(
                    title: "Search Documents",
                    subtitle: "Find files in your knowledge base",
                    icon: "doc.text.magnifyingglass",
                    color: .blue,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        searchMode = .documents
                    }
                }
                
                AnimatedActionRow(
                    title: "Browse Projects",
                    subtitle: "View indexed codebases",
                    icon: "folder.badge.gearshape",
                    color: .orange,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        searchMode = .projects
                    }
                }
                
                AnimatedActionRow(
                    title: "Import Files",
                    subtitle: "Add to knowledge base",
                    icon: "square.and.arrow.down",
                    color: .green,
                    namespace: animation
                ) {
                    // Import action
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No results for \"\(searchQuery)\"")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultsListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results) { section in
                    sectionHeader(section.category.rawValue)
                    ForEach(section.items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(item.iconColor)
                                .frame(width: 28, height: 28)
                                .background(item.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if let sub = item.subtitle {
                                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                    }
                }
            }
        }
    }
    
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(chatMessages) { msg in
                        HStack {
                            if msg.isUser { Spacer(minLength: 50) }
                            Text(msg.content)
                                .font(.system(size: 14))
                                .padding(10)
                                .background(msg.isUser ? Color.blue : Color.gray.opacity(0.15))
                                .foregroundStyle(msg.isUser ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if !msg.isUser { Spacer(minLength: 50) }
                        }
                    }
                }
                .padding(16)
            }
            
            HStack {
                Button { 
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showChat = false
                        chatMessages = []
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Press ↵ to send").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .separatorColor).opacity(0.3))
        }
    }
    
    // MARK: - Action Bar
    
    private var actionBarView: some View {
        HStack(spacing: 16) {
            shortcutHint("↑↓", "Navigate")
            shortcutHint("↵", "Select")
            shortcutHint("esc", "Close")
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(sidecarManager.isHealthy ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(sidecarManager.isHealthy ? "Connected" : "...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background(Color.primary.opacity(0.03))
    }
    
    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
    
    // MARK: - Actions
    
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
                    ResultItem(id: $0.id, title: URL(fileURLWithPath: $0.filePath).lastPathComponent, subtitle: $0.filePath, icon: "doc.text", iconColor: .blue, category: .documents)
                }
                await MainActor.run { results = items.isEmpty ? [] : [ResultSection(category: .documents, items: items)] }
            } catch {
                await MainActor.run { results = [] }
            }
        }
    }
}

// MARK: - Animated Action Row

struct AnimatedActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Trigger press animation
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Execute action after brief delay for visual feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPressed = false
                }
                action()
            }
        }) {
            HStack(spacing: 12) {
                // Icon with morphing background
                ZStack {
                    RoundedRectangle(cornerRadius: isPressed ? 10 : 8)
                        .fill(color.opacity(isHovered ? 0.2 : 0.12))
                        .frame(width: isPressed ? 36 : 32, height: isPressed ? 36 : 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: isPressed ? 18 : 16, weight: .medium))
                        .foregroundStyle(color)
                        .scaleEffect(isPressed ? 1.1 : 1.0)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isHovered ? color : .primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .animation(.easeOut(duration: 0.2), value: isHovered)
                
                Spacer()
                
                // Chevron with animation
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? color.opacity(0.6) : Color.gray.opacity(0.3))
                    .offset(x: isHovered ? 3 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.08) : Color.clear)
                    .padding(.horizontal, 8)
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
