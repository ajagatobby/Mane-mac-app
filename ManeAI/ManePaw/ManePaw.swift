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
import UniformTypeIdentifiers

// MARK: - Global Panel Manager

/// Singleton to manage the floating panel across the app
/// Uses OverlayPanel (NSPanel subclass) for proper Raycast-like behavior
final class PanelManager: ObservableObject {
    static let shared = PanelManager()
    
    /// The main overlay panel - uses OverlayPanel subclass for proper focus management
    private(set) var panel: OverlayPanel?
    
    /// The onboarding overlay panel - shown on first launch
    private(set) var onboardingPanel: OverlayPanel?
    
    /// Backend process manager
    let sidecarManager: SidecarManager
    
    /// API service for backend communication - shares URL with sidecarManager
    let apiService: APIService
    
    /// Document indexing service for smart deduplication
    var indexingService: DocumentIndexingService?
    
    var modelContainer: ModelContainer?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    @Published var isPanelVisible = false
    @Published var isOnboardingVisible = false
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    private init() {
        // Load onboarding state
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        // Initialize sidecar manager first
        let sidecar = SidecarManager()
        self.sidecarManager = sidecar
        
        // Initialize API service with the same base URL as sidecar
        self.apiService = APIService(baseURL: sidecar.baseURL.absoluteString)
        
        setupModelContainer()
        setupPanel()
        setupOnboardingPanel()
        setupHotkey()
        
        Task {
            await sidecar.start()
        }
        
        // Show onboarding on first launch
        if !hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        }
    }
    
    private func setupModelContainer() {
        let schema = Schema([Document.self, Project.self, ChatMessage.self, ChatConversation.self, IndexedFile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
        modelContainer = try? ModelContainer(for: schema, configurations: [config])
    }
    
    // MARK: - Panel Setup
    
    private func setupPanel() {
        guard let container = modelContainer else { return }
        
        // Initialize the indexing service with model context
        let indexService = DocumentIndexingService(
            apiService: apiService,
            modelContext: container.mainContext
        )
        self.indexingService = indexService
        
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
            apiService: apiService,
            indexingService: indexService
        )
        .modelContainer(container)
        
        panel.contentView = NSHostingView(rootView: contentView)
        self.panel = panel
    }
    
    // MARK: - Onboarding Panel Setup
    
    private func setupOnboardingPanel() {
        // Create the onboarding OverlayPanel - matches the onboarding view size
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            backing: .buffered,
            defer: false
        )
        
        // Prevent auto-dismiss on click outside for onboarding
        panel.preventDismiss = true
        
        // Set up dismissal callback
        panel.onDismiss = { [weak self] in
            self?.isOnboardingVisible = false
        }
        
        // Create SwiftUI onboarding content
        let contentView = OnboardingPanelContent(
            onComplete: { [weak self] in
                self?.completeOnboarding()
            }
        )
        
        panel.contentView = NSHostingView(rootView: contentView)
        self.onboardingPanel = panel
    }
    
    // MARK: - Onboarding Control
    
    func showOnboarding() {
        guard let panel = onboardingPanel else {
            print("❌ Onboarding panel is nil")
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        panel.present()
        isOnboardingVisible = true
        print("✅ Onboarding shown")
    }
    
    func hideOnboarding() {
        guard let panel = onboardingPanel else { return }
        
        panel.dismiss { [weak self] in
            self?.isOnboardingVisible = false
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        hideOnboarding()
        
        // Show the main panel after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showPanel()
        }
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
    
    /// Clears SwiftData cache for indexed documents (Document and IndexedFile).
    /// Call when backend documents are deleted to keep cache in sync.
    @MainActor
    func clearIndexedDocumentsCache() {
        guard let context = modelContainer?.mainContext else { return }
        do {
            try context.delete(model: Document.self)
            try context.delete(model: IndexedFile.self)
            try context.save()
        } catch {
            print("Failed to clear indexed documents cache: \(error)")
        }
    }
    
    func togglePanel() {
        // If onboarding not complete, show onboarding instead
        if !hasCompletedOnboarding {
            if isOnboardingVisible {
                // Don't allow dismissing onboarding via hotkey
                return
            } else {
                showOnboarding()
            }
            return
        }
        
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        // Don't show main panel if onboarding not complete
        guard hasCompletedOnboarding else {
            showOnboarding()
            return
        }
        
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
        // PanelManager also handles showing onboarding on first launch
        _ = PanelManager.shared
        print("✅ Mane-paw launched - Press Ctrl+W to toggle overlay")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by PanelManager.deinit
    }
}

// MARK: - Onboarding Window Content

/// Wrapper view for the onboarding window that handles window management
// MARK: - Onboarding Panel Content

/// Content view for the onboarding overlay panel
struct OnboardingPanelContent: View {
    var onComplete: () -> Void
    @State private var hasCompleted = false
    
    var body: some View {
        OnboardingView(hasCompletedOnboarding: $hasCompleted)
            .onChange(of: hasCompleted) { _, newValue in
                if newValue {
                    onComplete()
                }
            }
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
            
            Button("Show Welcome Tour") {
                // Reset onboarding and show it
                panelManager.hasCompletedOnboarding = false
                panelManager.showOnboarding()
            }
            
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
    @ObservedObject var indexingService: DocumentIndexingService
    
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
    @State private var isTranscribing = false
    @State private var isSummarizing = false
    @State private var attachedFile: URL? = nil
    @State private var attachedFileIndexed = false
    @State private var attachedFileId: String? = nil
    @State private var showFilePicker = false
    @State private var showHomeFilePicker = false
    @State private var indexingStatus: String? = nil
    @State private var homeIndexingFile: URL? = nil
    @State private var homeIndexingProgress: String? = nil
    @State private var homeIndexingComplete = false
    @State private var homeIndexingTotal = 0
    @State private var homeIndexingCurrent = 0
    @State private var showSettings = false
    @FocusState private var focused: Bool
    
    // Animation namespace for morphing effects
    @Namespace private var animation
    
    // Quick actions data - vibrant colors like Raycast
    private let quickActions: [(title: String, subtitle: String, icon: String, color: Color, id: String, useAssetImage: Bool)] = [
        ("Search All", "Search your knowledge base", "magnifyingglass", Color(red: 0.35, green: 0.45, blue: 0.95), "searchall", false),
        ("AI Chat", "Mane-paw AI", "icon", Color(red: 0.95, green: 0.3, blue: 0.35), "chat", true),
        ("Index Files", "Add files or folders", "plus.square.on.square", Color(red: 0.35, green: 0.65, blue: 0.95), "index", false),
        ("Documents", "Search files", "doc.fill", Color(red: 1.0, green: 0.78, blue: 0.28), "search", false),
        ("Projects", "Browse codebases", "folder.fill", Color(red: 0.98, green: 0.6, blue: 0.2), "projects", false)
    ]
    
    // Tools data - AI-powered utility tools
    private let tools: [(title: String, subtitle: String, icon: String, color: Color, id: String)] = [
        ("Summarize", "Condense text or documents", "text.alignleft", Color(red: 0.95, green: 0.4, blue: 0.5), "summarize"),
        ("Transcribe", "Convert audio to text", "waveform", Color(red: 0.55, green: 0.45, blue: 0.95), "transcribe"),
        ("Write", "Generate text content", "pencil.line", Color(red: 0.4, green: 0.75, blue: 0.55), "write"),
        ("Colour Picker", "Pick any color", "eyedropper.full", Color(red: 0.95, green: 0.65, blue: 0.3), "colorpicker")
    ]
    
    // Tool prefixes for highlighting
    private let toolPrefixes: [(prefix: String, icon: String, gradientColors: [Color])] = [
        ("Summarize:", "text.alignleft", [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.85, green: 0.25, blue: 0.4)]),
        ("Transcribe:", "waveform", [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.85)]),
        ("Write:", "pencil.line", [Color(red: 0.35, green: 0.75, blue: 0.5), Color(red: 0.25, green: 0.65, blue: 0.4)])
    ]
    
    // Detect active tool prefix
    private var activeToolPrefix: (prefix: String, icon: String, gradientColors: [Color])? {
        for tool in toolPrefixes {
            if searchQuery.hasPrefix(tool.prefix) {
                return tool
            }
        }
        return nil
    }
    
    // Check if current tool requires file attachment
    private var toolRequiresFile: Bool {
        guard let tool = activeToolPrefix else { return false }
        return tool.prefix == "Summarize:" || tool.prefix == "Transcribe:"
    }
    
    // Get allowed file types for current tool
    private var allowedFileTypes: [String] {
        guard let tool = activeToolPrefix else { return [] }
        switch tool.prefix {
        case "Summarize:":
            // Allow both documents and audio files (audio will be transcribed first, then summarized)
            return ["pdf", "txt", "md", "doc", "docx", "rtf", "mp3", "wav", "m4a", "aac", "ogg", "flac"]
        case "Transcribe:":
            return ["mp3", "wav", "m4a", "aac", "ogg", "flac"]
        default:
            return []
        }
    }
    
    // File type description for UI
    private var fileTypeDescription: String {
        guard let tool = activeToolPrefix else { return "" }
        switch tool.prefix {
        case "Summarize:":
            return "Add a document or audio"
        case "Transcribe:":
            return "Add an audio file"
        default:
            return ""
        }
    }
    
    // Tool hint text for empty state
    private var toolHintText: String {
        guard let tool = activeToolPrefix else { return "Ask anything about the document" }
        switch tool.prefix {
        case "Summarize:":
            return "Ready to summarize! Add a document or audio\nfile and ask for a summary."
        case "Transcribe:":
            return "Ready to transcribe! Press ↵ to get the\nfull transcription using Whisper."
        case "Write:":
            return "Ready to write! Describe what you'd like\nto create based on this document."
        default:
            return "Ask anything about the attached document."
        }
    }
    
    // Query without the tool prefix
    private var queryWithoutPrefix: String {
        if let tool = activeToolPrefix {
            return String(searchQuery.dropFirst(tool.prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return searchQuery
    }
    
    // Total selectable items
    private var totalItems: Int {
        if showChat { return 0 }
        if !results.isEmpty {
            // +1 for the "Ask AI" row at the top
            return results.flatMap { $0.items }.count + 1
        }
        return quickActions.count + tools.count
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
                
                // Noise texture overlay for subtle grain
                StaticNoiseOverlay(intensity: 0.05)
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
        .sheet(isPresented: $showSettings) {
            OverlaySettingsView()
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        }
        .onChange(of: showSettings) { _, isShowing in
            PanelManager.shared.panel?.preventDismiss = isShowing
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            // Mode indicator button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    cycleMode()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 14, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                    Text(modeName)
                        .font(.system(size: 12, weight: .medium))
                        .contentTransition(.interpolate)
                }
                .foregroundStyle(modeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(modeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchMode)
            }
            .buttonStyle(.plain)
            .help("Switch mode (Tab)")
            
            // Text field with tool prefix badge
            HStack(spacing: 6) {
                // Tool prefix badge (if active) - compact version
                if let tool = activeToolPrefix {
                    HStack(spacing: 3) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(String(tool.prefix.dropLast()))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: tool.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                // Text field with custom placeholder
                ZStack(alignment: .leading) {
                    // Custom placeholder with better contrast
                    if searchQuery.isEmpty || (activeToolPrefix != nil && queryWithoutPrefix.isEmpty) {
                        Text(activeToolPrefix != nil ? "Enter your content..." : placeholderText)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    
                    // Actual text field (show only the part after prefix if tool is active)
                    if activeToolPrefix != nil {
                        TextField("", text: Binding(
                            get: { queryWithoutPrefix },
                            set: { newValue in
                                if let tool = activeToolPrefix {
                                    searchQuery = tool.prefix + (newValue.isEmpty ? "" : " " + newValue)
                                }
                            }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color(white: 0.0))
                        .tint(Color(red: 0.95, green: 0.75, blue: 0.80))
                        .focused($focused)
                        .onSubmit { submit() }
                    } else {
                        TextField("", text: $searchQuery)
                            .font(.system(size: 17, weight: .regular))
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color(white: 0.0))
                            .tint(Color(red: 0.95, green: 0.75, blue: 0.80))
                            .focused($focused)
                            .onSubmit { submit() }
                    }
                }
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
        case .tools: return "wrench.and.screwdriver.fill"
        }
    }
    
    private var modeName: String {
        switch searchMode {
        case .search: return "Search"
        case .chat: return "Chat"
        case .documents: return "Docs"
        case .projects: return "Projects"
        case .tools: return "Tools"
        }
    }
    
    private var modeColor: Color {
        switch searchMode {
        case .search: return Color(red: 0.35, green: 0.45, blue: 0.95)
        case .chat: return Color(red: 0.95, green: 0.3, blue: 0.35)
        case .documents: return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .projects: return Color(red: 0.98, green: 0.6, blue: 0.2)
        case .tools: return Color(red: 0.95, green: 0.4, blue: 0.5)
        }
    }
    
    private var placeholderText: String {
        switch searchMode {
        case .search: return "Search your knowledge base..."
        case .chat: return "Ask Mane-paw anything..."
        case .documents: return "Search documents..."
        case .projects: return "Search projects..."
        case .tools: return "Search tools..."
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
        LoadingResultsView(
            message: "Searching your knowledge base",
            accentColor: searchModeColor
        )
        .frame(height: 300)
    }
    
    /// Returns the accent color based on current search mode
    private var searchModeColor: Color {
        switch searchMode {
        case .search:
            return ManeTheme.Colors.accentPrimary
        case .documents:
            return ManeTheme.Colors.categoryDocument
        case .projects:
            return ManeTheme.Colors.categoryProject
        case .chat:
            return ManeTheme.Colors.categoryChat
        case .tools:
            return ManeTheme.Colors.accentTertiary
        }
    }
    
    private var quickActionsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Home indexing status indicator
                if let file = homeIndexingFile {
                    let isFolder = file.hasDirectoryPath
                    
                    HStack(spacing: 10) {
                        ZStack {
                            Image(systemName: isFolder ? "folder.fill" : "doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(
                                    LinearGradient(
                                        colors: isFolder 
                                            ? [Color(red: 0.98, green: 0.6, blue: 0.2), Color(red: 0.9, green: 0.5, blue: 0.15)]
                                            : [Color(red: 0.35, green: 0.65, blue: 0.95), Color(red: 0.25, green: 0.55, blue: 0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                            
                            if homeIndexingTotal > 0 && !homeIndexingComplete {
                                // Show progress circle for folder indexing
                                Circle()
                                    .trim(from: 0, to: CGFloat(homeIndexingCurrent) / CGFloat(max(homeIndexingTotal, 1)))
                                    .stroke(Color(red: 0.3, green: 0.75, blue: 0.45), lineWidth: 2)
                                    .frame(width: 10, height: 10)
                                    .rotationEffect(.degrees(-90))
                                    .background(Circle().fill(Color.white))
                                    .offset(x: 10, y: -10)
                            } else if indexingService.isIndexing || (homeIndexingTotal == 0 && !homeIndexingComplete && homeIndexingProgress != nil) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                                    .overlay {
                                        ProgressView()
                                            .scaleEffect(0.4)
                                    }
                                    .offset(x: 10, y: -10)
                            } else if homeIndexingComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.45))
                                    .background(Circle().fill(.white).frame(width: 8, height: 8))
                                    .offset(x: 10, y: -10)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(white: 0.2))
                                .lineLimit(1)
                            
                            // Show different completion message for folders
                            if homeIndexingComplete {
                                Text(homeIndexingProgress ?? (isFolder ? "Folder indexed" : "Indexed successfully"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.3, green: 0.65, blue: 0.4))
                            } else {
                                Text(homeIndexingProgress ?? "Indexing...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(white: 0.5))
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                homeIndexingFile = nil
                                homeIndexingProgress = nil
                                homeIndexingComplete = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(white: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(homeIndexingComplete ? Color(red: 0.92, green: 0.97, blue: 0.93) : Color(white: 0.94))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                homeIndexingComplete ? Color(red: 0.3, green: 0.75, blue: 0.45).opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: homeIndexingComplete)
                }
                
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
                        isSelected: selectedIndex == index,
                        useAssetImage: action.useAssetImage
                    ) {
                        handleQuickAction(action.id)
                    }
                }
                
                // Tools section
                Text("Tools")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                
                // Tool items
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    RaycastRow(
                        icon: tool.icon,
                        iconColor: tool.color,
                        title: tool.title,
                        subtitle: tool.subtitle,
                        accessoryText: "Tool",
                        isSelected: selectedIndex == quickActions.count + index
                    ) {
                        handleTool(tool.id)
                    }
                }
            }
            .padding(.bottom, 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: homeIndexingFile != nil)
        }
        .fileImporter(
            isPresented: $showHomeFilePicker,
            allowedContentTypes: [.folder, .pdf, .plainText, .rtf, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        homeIndexingFile = url
                        homeIndexingComplete = false
                        homeIndexingProgress = "Starting..."
                        homeIndexingTotal = 0
                        homeIndexingCurrent = 0
                    }
                    
                    Task {
                        await indexHomeItem(url, didStartAccess: didStartAccess)
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
        .onChange(of: showHomeFilePicker) { _, isShowing in
            // Prevent panel from dismissing while file picker is open
            if let panel = PanelManager.shared.panel {
                panel.preventDismiss = isShowing
            }
        }
    }
    
    private func indexHomeItem(_ url: URL, didStartAccess: Bool) async {
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if exists && isDirectory.boolValue {
            // It's a folder - index all supported files
            await indexFolder(url)
        } else {
            // It's a single file
            await indexSingleFile(url)
        }
    }
    
    private func indexFolder(_ folderURL: URL) async {
        homeIndexingProgress = "Scanning folder..."
        
        // Supported file extensions for indexing (text, documents, images, audio)
        let supportedExtensions = [
            // Text documents
            "pdf", "txt", "md", "rtf", "doc", "docx", "json", "csv", "xml", "html",
            // Spreadsheets & presentations
            "xlsx", "xls", "pptx",
            // Images (for captioning)
            "jpg", "jpeg", "png", "gif", "webp", "heic",
            // Audio (for transcription)
            "mp3", "wav", "m4a", "aac", "ogg", "flac"
        ]
        
        // Find all supported files in the folder
        var filesToIndex: [URL] = []
        
        if let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    filesToIndex.append(fileURL)
                }
            }
        }
        
        guard !filesToIndex.isEmpty else {
            // No supported files found - show completion with info message
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingComplete = true
                homeIndexingProgress = "No documents found"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingFile = nil
                homeIndexingProgress = nil
                homeIndexingComplete = false
            }
            return
        }
        
        homeIndexingTotal = filesToIndex.count
        homeIndexingCurrent = 0
        
        var indexedCount = 0
        var skippedCount = 0
        var failedCount = 0
        
        for (index, fileURL) in filesToIndex.enumerated() {
            homeIndexingCurrent = index + 1
            homeIndexingProgress = "Indexing \(homeIndexingCurrent)/\(homeIndexingTotal)..."
            
            let result = await indexingService.indexFileIfNeeded(fileURL)
            
            switch result {
            case .indexed: indexedCount += 1
            case .alreadyIndexed: skippedCount += 1
            case .failed: failedCount += 1
            }
        }
        
        // Show completion summary
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            homeIndexingComplete = true
            if failedCount > 0 {
                homeIndexingProgress = "\(indexedCount) indexed, \(skippedCount) skipped, \(failedCount) failed"
            } else if skippedCount > 0 {
                homeIndexingProgress = "\(indexedCount) indexed, \(skippedCount) already indexed"
            } else {
                homeIndexingProgress = "\(indexedCount) files indexed"
            }
        }
        
        // Auto-dismiss after 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            homeIndexingFile = nil
            homeIndexingProgress = nil
            homeIndexingComplete = false
            homeIndexingTotal = 0
            homeIndexingCurrent = 0
        }
    }
    
    private func indexSingleFile(_ url: URL) async {
        homeIndexingProgress = "Reading document..."
        
        let result = await indexingService.indexFileIfNeeded(url)
        
        switch result {
        case .indexed:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingComplete = true
                homeIndexingProgress = nil
            }
            
            // Auto-dismiss after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingFile = nil
                homeIndexingProgress = nil
                homeIndexingComplete = false
            }
            
        case .alreadyIndexed:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingComplete = true
                homeIndexingProgress = "Already indexed"
            }
            
            // Auto-dismiss after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                homeIndexingFile = nil
                homeIndexingProgress = nil
                homeIndexingComplete = false
            }
            
        case .failed(let error):
            homeIndexingProgress = "Failed: \(error.localizedDescription)"
        }
    }
    
    private func handleTool(_ id: String) {
        switch id {
        case "summarize":
            // Switch to chat mode with summarize prompt
            searchMode = .chat
            showChat = true
            searchQuery = "Summarize: "
        case "transcribe":
            // Switch to chat mode with transcribe prompt
            searchMode = .chat
            showChat = true
            searchQuery = "Transcribe: "
        case "write":
            // Switch to chat mode with write prompt
            searchMode = .chat
            showChat = true
            searchQuery = "Write: "
        case "colorpicker":
            // Open color picker
            NSColorPanel.shared.makeKeyAndOrderFront(nil)
            onDismiss()
        default:
            break
        }
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
            icon: "icon",
            iconColor: Color(red: 0.95, green: 0.3, blue: 0.35),
            title: "Ask AI: \"\(searchQuery)\"",
            subtitle: "Get an AI-powered answer",
            accessoryText: "↵",
            isSelected: selectedIndex == 0,
            useAssetImage: true
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                        showChat = false
                        chatMessages = []
                        searchQuery = ""
                        searchMode = .search
                        results = []
                        streamingContent = ""
                        isStreaming = false
                        isTranscribing = false
                        isSummarizing = false
                        attachedFile = nil
                        attachedFileIndexed = false
                        attachedFileId = nil
                        indexingStatus = nil
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
                
                HStack(spacing: 6) {
                    Image("icon")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("AI Chat")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.91))
            
            // Messages
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if chatMessages.isEmpty && !isStreaming {
                                // Empty state - different for tools vs regular chat
                                if toolRequiresFile && attachedFile == nil {
                                    // Tool mode - show file upload prompt
                                    Button {
                                        showFilePicker = true
                                    } label: {
                                        VStack(spacing: 12) {
                                            // Icon with gradient background
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: activeToolPrefix?.gradientColors ?? [.gray],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .frame(width: 56, height: 56)
                                                
                                                Image(systemName: activeToolPrefix?.prefix == "Transcribe:" ? "waveform" : "doc.badge.plus")
                                                    .font(.system(size: 24, weight: .medium))
                                                    .foregroundStyle(.white)
                                            }
                                            
                                            VStack(spacing: 4) {
                                                Text(fileTypeDescription)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color(white: 0.25))
                                                
                                                Text(activeToolPrefix?.prefix == "Transcribe:" 
                                                    ? "MP3, WAV, M4A, AAC supported"
                                                    : "PDF, TXT, MD, DOC, MP3, WAV supported")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Color(white: 0.5))
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: (activeToolPrefix?.gradientColors ?? [.gray]).map { $0.opacity(0.5) },
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                                )
                                        )
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(white: 0.96))
                                        )
                                        .padding(.horizontal, 40)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .frame(height: 220)
                                } else if !toolRequiresFile || attachedFile != nil {
                                    // Regular chat or file already attached
                                    VStack(spacing: 8) {
                                        if let tool = activeToolPrefix {
                                            // Tool mode with file attached - show tool-specific hint
                                            Image(systemName: tool.icon)
                                                .font(.system(size: 32, weight: .light))
                                                .foregroundStyle(tool.gradientColors.first ?? Color(white: 0.65))
                                            
                                            // Transcribe doesn't need indexing - always show hint
                                            // Other tools need indexing to be complete
                                            if attachedFileIndexed || tool.prefix == "Transcribe:" {
                                                Text(toolHintText)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Color(white: 0.45))
                                                    .multilineTextAlignment(.center)
                                            } else {
                                                HStack(spacing: 6) {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                    Text("Indexing document...")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(Color(white: 0.45))
                                                }
                                            }
                                        } else {
                                            Image(systemName: "bubble.left.and.bubble.right")
                                                .font(.system(size: 32, weight: .light))
                                                .foregroundStyle(Color(white: 0.65))
                                            Text(attachedFile != nil 
                                                ? "Ask questions about the attached document" 
                                                : "Ask anything about your documents")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(white: 0.45))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .frame(height: 220)
                                }
                            }
                            
                            ForEach(chatMessages) { msg in
                                ChatBubble(message: msg)
                            }
                            
                            // Streaming message
                            if isStreaming {
                                if isTranscribing {
                                    TranscriptionShimmerBubble()
                                        .id("streaming")
                                } else if isSummarizing && streamingContent.isEmpty {
                                    SummarizationShimmerBubble()
                                        .id("streaming")
                                } else {
                                    StreamingChatBubble(content: streamingContent)
                                        .id("streaming")
                                }
                            }
                            
                            // Bottom padding for fade mask
                            Color.clear.frame(height: 24)
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
                
                // Bottom fade mask
                LinearGradient(
                    stops: [
                        .init(color: Color(white: 0.95).opacity(0), location: 0),
                        .init(color: Color(white: 0.95).opacity(0.8), location: 0.5),
                        .init(color: Color(white: 0.95), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)
            }
            .dropDestination(for: URL.self) { items, _ in
                guard let url = items.first else { return false }
                
                // Check if file type is supported for the current tool
                let ext = url.pathExtension.lowercased()
                
                // If a tool is active, only allow that tool's file types
                if toolRequiresFile {
                    guard allowedFileTypes.contains(ext) else { return false }
                } else {
                    // General drop - accept all supported extensions
                    let supportedExtensions = ["pdf", "txt", "md", "doc", "docx", "rtf", "mp3", "wav", "m4a", "aac", "ogg", "flac", "jpg", "jpeg", "png", "gif", "webp"]
                    guard supportedExtensions.contains(ext) else { return false }
                }
                
                // Attach the file
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    attachedFile = url
                    attachedFileIndexed = false
                    attachedFileId = nil
                    // For Transcribe tool, show "Ready" since no indexing needed
                    indexingStatus = activeToolPrefix?.prefix == "Transcribe:" ? "Ready" : "Preparing..."
                }
                
                // Skip indexing for Transcribe tool - it calls Whisper directly
                if activeToolPrefix?.prefix != "Transcribe:" {
                    Task {
                        await indexAttachedFile(url, didStartAccess: false)
                    }
                } else {
                    // Mark as ready immediately for Transcribe
                    attachedFileIndexed = true
                }
                
                return true
            }
            
            // Attached file display moved to footer (actionBarView)
            
            // File importer (attached to the view)
            Color.clear
                .frame(height: 0)
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: allowedFileTypes.compactMap { ext -> UTType? in
                        switch ext {
                        case "pdf": return .pdf
                        case "txt": return .plainText
                        case "md": return .plainText
                        case "doc", "docx": return .data
                        case "rtf": return .rtf
                        case "mp3": return .mp3
                        case "wav": return .wav
                        case "m4a": return .mpeg4Audio
                        case "aac", "ogg", "flac":
                            return UTType(filenameExtension: ext) ?? .audio
                        default: return .audio
                        }
                    },
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            // Start security-scoped access for sandboxed apps
                            _ = url.startAccessingSecurityScopedResource()
                            
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                attachedFile = url
                                attachedFileIndexed = false
                                attachedFileId = nil
                                // For Transcribe tool, show "Ready" since no indexing needed
                                indexingStatus = activeToolPrefix?.prefix == "Transcribe:" ? "Ready" : "Preparing..."
                            }
                            
                            // Skip indexing for Transcribe tool - it calls Whisper directly
                            if activeToolPrefix?.prefix != "Transcribe:" {
                                Task {
                                    await indexAttachedFile(url, didStartAccess: true)
                                }
                            } else {
                                // Mark as ready immediately for Transcribe (no indexing needed)
                                // Keep security access - will be stopped when file is removed or after transcription
                                attachedFileIndexed = true
                            }
                        }
                    case .failure:
                        break
                    }
                }
                .onChange(of: showFilePicker) { _, isShowing in
                    // Prevent panel from dismissing while file picker is open
                    if let panel = PanelManager.shared.panel {
                        panel.preventDismiss = isShowing
                    }
                }
            
            // Input hint
            HStack {
                Spacer()
                if toolRequiresFile && attachedFile == nil {
                    Text("Add a file, then press ↵")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.5))
                } else if attachedFile != nil && indexingService.isIndexing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Indexing document...")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.5))
                    }
                } else if attachedFile != nil && !attachedFileIndexed {
                    Text("Waiting for document to be indexed...")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange.opacity(0.8))
                } else {
                    Text("Type your message and press ↵")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Action Bar (Raycast style footer)
    
    private var actionBarView: some View {
        HStack(spacing: 0) {
            // Left side - attached file indicator (compact) or status/navigation
            if let file = attachedFile {
                // Compact attached file indicator
                HStack(spacing: 8) {
                    // Small file icon with status indicator
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: activeToolPrefix?.prefix == "Transcribe:" ? "waveform" : "doc.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                LinearGradient(
                                    colors: activeToolPrefix?.gradientColors ?? [Color(red: 0.95, green: 0.3, blue: 0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        
                        // Status indicator
                        if indexingService.isIndexing {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                                .overlay {
                                    ProgressView()
                                        .scaleEffect(0.4)
                                }
                                .offset(x: 3, y: 3)
                        } else if attachedFileIndexed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.45))
                                .background(Circle().fill(.white).frame(width: 8, height: 8))
                                .offset(x: 3, y: 3)
                        }
                    }
                    
                    // File name and status
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.2))
                            .lineLimit(1)
                            .frame(maxWidth: 140, alignment: .leading)
                        
                        // Status text
                        Group {
                            if let status = indexingStatus {
                                Text(status)
                            } else if indexingService.isIndexing {
                                Text(indexingService.indexingProgress)
                            } else if attachedFileIndexed {
                                Text("Ready to use")
                            } else {
                                Text("Indexing...")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(attachedFileIndexed ? Color(red: 0.3, green: 0.65, blue: 0.4) : Color(white: 0.5))
                    }
                    
                    // Remove button
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            attachedFile = nil
                            attachedFileIndexed = false
                            attachedFileId = nil
                            indexingStatus = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(attachedFileIndexed ? Color(red: 0.90, green: 0.96, blue: 0.91) : Color(white: 0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            attachedFileIndexed ? Color(red: 0.3, green: 0.75, blue: 0.45).opacity(0.35) : Color.clear,
                            lineWidth: 0.5
                        )
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: attachedFileIndexed)
            } else {
                // Default status and navigation
                HStack(spacing: 14) {
                    // Status icon
                    Image(systemName: sidecarManager.isHealthy ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(sidecarManager.isHealthy ? Color(white: 0.35) : .orange)
                    
                    // Navigation arrows
                    HStack(spacing: 5) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color(white: 0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.80), in: RoundedRectangle(cornerRadius: 5))
                        
                        Text("Navigate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
            }
            
            Spacer()
            
            // Right side - action hints (Raycast style)
            HStack(spacing: 18) {
                // Open Command action
                HStack(spacing: 7) {
                    Text("Open")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                    
                    Text("↵")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.80), in: RoundedRectangle(cornerRadius: 5))
                }
                
                // Divider
                Rectangle()
                    .fill(Color(white: 0.72))
                    .frame(width: 1, height: 18)
                
                // Actions
                HStack(spacing: 7) {
                    Text("Actions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                    
                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 12, weight: .semibold))
                        Text("K")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.80), in: RoundedRectangle(cornerRadius: 5))
                }
                
                // Divider
                Rectangle()
                    .fill(Color(white: 0.72))
                    .frame(width: 1, height: 18)
                
                // Settings button
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(white: 0.89))
        .staticNoiseOverlay(intensity: 0.06)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(white: 0.78))
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
            case "searchall":
                searchMode = .search
            case "chat":
                searchMode = .chat
                showChat = true
            case "index":
                showHomeFilePicker = true
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
        // Handle chat mode - delegate to submit() for proper document handling
        if showChat {
            submit()
            return
        }
        
        if results.isEmpty && searchQuery.isEmpty {
            // Quick actions + tools
            if selectedIndex < quickActions.count {
                handleQuickAction(quickActions[selectedIndex].id)
            } else {
                let toolIndex = selectedIndex - quickActions.count
                if toolIndex < tools.count {
                    handleTool(tools[toolIndex].id)
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
                    case .tools:
                        handleResultTool(item)
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
    
    private func handleResultTool(_ item: ResultItem) {
        handleTool(item.id)
    }
    
    private func cycleMode() {
        let modes: [SearchMode] = [.search, .documents, .projects, .chat, .tools]
        if let i = modes.firstIndex(of: searchMode) {
            let nextMode = modes[(i + 1) % modes.count]
            searchMode = nextMode
        }
    }
    
    private func submit() {
        if showChat {
            guard !searchQuery.isEmpty else { return }
            let q = searchQuery
            let userQuery = queryWithoutPrefix
            // Capture tool prefix BEFORE clearing searchQuery (since activeToolPrefix depends on it)
            let tool = activeToolPrefix
            searchQuery = ""
            
            // Check if tool mode requires a document
            if let tool = tool {
                // Tool mode - require document attachment
                guard let file = attachedFile else {
                    chatMessages.append(ChatMessage(content: q, isUser: true))
                    chatMessages.append(ChatMessage(
                        content: "Please attach a document first. \(tool.prefix.dropLast()) requires a file to work with.",
                        isUser: false
                    ))
                    return
                }
                
                let fileName = file.lastPathComponent
                
                // Handle Transcribe tool specially - call Whisper directly without LLM
                // Transcribe doesn't need indexing - it calls Whisper directly
                if tool.prefix == "Transcribe:" {
                    chatMessages.append(ChatMessage(content: q, isUser: true))
                    transcribeAudioDirectly(filePath: file.path)
                    return
                }
                
                // For other tools (Summarize, Write), ensure document is indexed before proceeding
                guard attachedFileIndexed else {
                    chatMessages.append(ChatMessage(content: q, isUser: true))
                    chatMessages.append(ChatMessage(
                        content: "Please wait for the document to finish indexing before asking questions.",
                        isUser: false
                    ))
                    return
                }
                
                // Build tool-specific queries that strictly focus on the document
                let contextQuery: String
                switch tool.prefix {
                case "Summarize:":
                    contextQuery = """
                    [INSTRUCTION: Only respond based on the content of the attached document '\(fileName)'. Do not use any external knowledge. If the question is unrelated to the document, politely redirect to the document content.]
                    
                    Task: Summarize the document '\(fileName)'.
                    \(userQuery.isEmpty ? "Provide a comprehensive summary covering the main points, key findings, and important details." : "Focus on: \(userQuery)")
                    """
                case "Write:":
                    contextQuery = """
                    [INSTRUCTION: Only use '\(fileName)' as the reference material. Base your response strictly on the content of this document. Do not incorporate external knowledge beyond what's in the document.]
                    
                    Reference document: '\(fileName)'
                    Task: \(userQuery.isEmpty ? "Generate content based on the themes and information in this document." : userQuery)
                    """
                default:
                    contextQuery = """
                    [INSTRUCTION: Only respond based on the content of '\(fileName)'. Do not use external knowledge.]
                    
                    Regarding '\(fileName)': \(q)
                    """
                }
                
                chatMessages.append(ChatMessage(content: q, isUser: true))
                // Set summarizing state if using Summarize tool
                if tool.prefix == "Summarize:" {
                    isSummarizing = true
                }
                // Pass the document ID to restrict search to ONLY this document
                streamChatResponse(query: contextQuery, documentIds: attachedFileId.map { [$0] })
                
            } else if let file = attachedFile, attachedFileIndexed {
                // Regular chat with attached file - focus on the document
                let fileName = file.lastPathComponent
                let contextQuery = """
                [INSTRUCTION: Prioritize answering based on the content of the attached document '\(fileName)'. If the question is directly about the document, only use the document content. For general questions, you may use broader knowledge but mention the document context.]
                
                Document: '\(fileName)'
                Question: \(q)
                """
                
                chatMessages.append(ChatMessage(content: q, isUser: true))
                // Pass the document ID to prioritize this document in search
                streamChatResponse(query: contextQuery, documentIds: attachedFileId.map { [$0] })
                
            } else {
                // Regular chat without document - search entire knowledge base
                chatMessages.append(ChatMessage(content: q, isUser: true))
                streamChatResponse(query: q)
            }
        } else {
            executeSelectedAction()
        }
    }
    
    /// Stream chat response with optional document filtering
    /// - Parameters:
    ///   - query: The user's query
    ///   - documentIds: Optional array of document IDs to restrict search to specific documents only
    private func streamChatResponse(query: String, documentIds: [String]? = nil) {
        isStreaming = true
        streamingContent = ""
        
        Task {
            var sources: [String] = []
            
            do {
                for try await chunk in apiService.chatStream(query: query, documentIds: documentIds) {
                    await MainActor.run {
                        switch chunk {
                        case .content(let text):
                            streamingContent += text
                        case .sources(let streamSources):
                            sources = streamSources.map { $0.filePath }
                        }
                    }
                }
                await MainActor.run {
                    chatMessages.append(ChatMessage(content: streamingContent, isUser: false, sources: sources))
                    streamingContent = ""
                    isStreaming = false
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false))
                    streamingContent = ""
                    isStreaming = false
                    isSummarizing = false
                }
            }
        }
    }
    
    /// Transcribe audio file directly using Whisper (no LLM processing)
    /// - Parameter filePath: Path to the audio file
    private func transcribeAudioDirectly(filePath: String) {
        isStreaming = true
        isTranscribing = true
        streamingContent = ""
        
        Task {
            do {
                let response = try await apiService.transcribe(filePath: filePath)
                
                await MainActor.run {
                    // Format the transcription result
                    let transcriptionText = """
                    **Transcription of \(response.fileName):**
                    
                    \(response.transcription)
                    """
                    
                    chatMessages.append(ChatMessage(
                        content: transcriptionText,
                        isUser: false,
                        sources: [filePath]
                    ))
                    streamingContent = ""
                    isStreaming = false
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatMessage(
                        content: "Failed to transcribe audio: \(error.localizedDescription)",
                        isUser: false
                    ))
                    streamingContent = ""
                    isStreaming = false
                    isTranscribing = false
                }
            }
        }
    }
    
    // MARK: - Smart Document Indexing
    
    /// Index attached file with smart deduplication
    private func indexAttachedFile(_ url: URL, didStartAccess: Bool) async {
        await MainActor.run {
            indexingStatus = "Checking index..."
        }
        
        let result = await indexingService.indexFileIfNeeded(url)
        
        // Stop security-scoped access if we started it
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
        
        await MainActor.run {
            switch result {
            case .indexed(let id, let fileName):
                attachedFileIndexed = true
                attachedFileId = id
                indexingStatus = "Indexed: \(fileName)"
                
                // Auto-clear status after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        indexingStatus = nil
                    }
                }
                
            case .alreadyIndexed(let id, let fileName):
                attachedFileIndexed = true
                attachedFileId = id
                indexingStatus = "Ready (cached)"
                
                // Auto-clear status after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        indexingStatus = nil
                    }
                }
                
            case .failed(let error):
                attachedFileIndexed = false
                attachedFileId = nil
                indexingStatus = "Failed: \(error.localizedDescription)"
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
                    
                case .tools:
                    // Filter tools locally
                    let filtered = tools.filter {
                        $0.title.localizedCaseInsensitiveContains(query) ||
                        $0.subtitle.localizedCaseInsensitiveContains(query)
                    }
                    let items = filtered.map { tool in
                        ResultItem(
                            id: tool.id,
                            title: tool.title,
                            subtitle: tool.subtitle,
                            icon: tool.icon,
                            iconColor: tool.color,
                            category: .tools
                        )
                    }
                    await MainActor.run {
                        results = items.isEmpty ? [] : [ResultSection(category: .tools, items: items)]
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
    var useAssetImage: Bool = false  // For Mane logo
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon - colored rounded square with white SF Symbol or asset image
                if useAssetImage {
                    Image(icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: iconColor.opacity(0.3), radius: 2, y: 1)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconColor)
                            .frame(width: 28, height: 28)
                            .shadow(color: iconColor.opacity(0.3), radius: 2, y: 1)
                        
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
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
                        // Ask AI button - Mane logo
                        Button {
                            onAskAI()
                        } label: {
                            Image("icon")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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

// MARK: - Advanced Markdown Text Renderer

struct MarkdownText: View {
    let content: String
    
    // Theme colors
    private let textColor = Color(white: 0.1)
    private let mutedColor = Color(white: 0.4)
    private let codeBackground = Color(white: 0.94)
    private let blockquoteBorder = Color(red: 0.95, green: 0.3, blue: 0.35)
    private let linkColor = Color(red: 0.2, green: 0.5, blue: 0.95)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }
    
    // MARK: - Block Types
    
    private enum MarkdownBlock: Equatable {
        case paragraph(String)
        case header(level: Int, text: String)
        case codeBlock(language: String?, code: String)
        case blockquote(lines: [String])
        case bulletList(items: [ListItem])
        case numberedList(items: [ListItem])
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case taskList(items: [(checked: Bool, text: String)])
        
        static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
            switch (lhs, rhs) {
            case (.paragraph(let a), .paragraph(let b)): return a == b
            case (.header(let l1, let t1), .header(let l2, let t2)): return l1 == l2 && t1 == t2
            case (.codeBlock(let l1, let c1), .codeBlock(let l2, let c2)): return l1 == l2 && c1 == c2
            case (.blockquote(let a), .blockquote(let b)): return a == b
            case (.horizontalRule, .horizontalRule): return true
            default: return false
            }
        }
    }
    
    private struct ListItem: Equatable {
        let text: String
        let indent: Int
        let children: [ListItem]
    }
    
    // MARK: - Block Parser
    
    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }
            
            // Fenced code block (```)
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            
            // Horizontal rule (---, ***, ___)
            if trimmed.count >= 3 && (
                trimmed.allSatisfy({ $0 == "-" || $0 == " " }) && trimmed.filter({ $0 == "-" }).count >= 3 ||
                trimmed.allSatisfy({ $0 == "*" || $0 == " " }) && trimmed.filter({ $0 == "*" }).count >= 3 ||
                trimmed.allSatisfy({ $0 == "_" || $0 == " " }) && trimmed.filter({ $0 == "_" }).count >= 3
            ) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }
            
            // Headers (# to ######)
            if let headerMatch = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = trimmed[headerMatch].filter({ $0 == "#" }).count
                let text = String(trimmed[headerMatch.upperBound...])
                blocks.append(.header(level: level, text: text))
                i += 1
                continue
            }
            
            // Blockquote (>)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let quoteLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if quoteLine.hasPrefix(">") {
                        let content = quoteLine.dropFirst().trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                        i += 1
                    } else if quoteLine.isEmpty && i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                        quoteLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.blockquote(lines: quoteLines))
                continue
            }
            
            // Table (| header | header |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let tableLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if tableLine.hasPrefix("|") {
                        tableLines.append(tableLine)
                        i += 1
                    } else {
                        break
                    }
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                }
                continue
            }
            
            // Task list (- [ ] or - [x])
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                var tasks: [(checked: Bool, text: String)] = []
                while i < lines.count {
                    let taskLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if taskLine.hasPrefix("- [ ]") {
                        tasks.append((checked: false, text: String(taskLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                        i += 1
                    } else if taskLine.hasPrefix("- [x]") || taskLine.hasPrefix("- [X]") {
                        tasks.append((checked: true, text: String(taskLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                        i += 1
                    } else {
                        break
                    }
                }
                if !tasks.isEmpty {
                    blocks.append(.taskList(items: tasks))
                }
                continue
            }
            
            // Bullet list (-, *, +)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let (items, newIndex) = parseListItems(lines: lines, startIndex: i, isBullet: true)
                blocks.append(.bulletList(items: items))
                i = newIndex
                continue
            }
            
            // Numbered list (1. 2. etc)
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let (items, newIndex) = parseListItems(lines: lines, startIndex: i, isBullet: false)
                blocks.append(.numberedList(items: items))
                i = newIndex
                continue
            }
            
            // Regular paragraph
            var paragraphLines: [String] = []
            while i < lines.count {
                let pLine = lines[i]
                let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                
                // Check for block-level interrupts
                if pTrimmed.isEmpty ||
                   pTrimmed.hasPrefix("#") ||
                   pTrimmed.hasPrefix("```") ||
                   pTrimmed.hasPrefix(">") ||
                   pTrimmed.hasPrefix("|") ||
                   pTrimmed.hasPrefix("- ") || pTrimmed.hasPrefix("* ") || pTrimmed.hasPrefix("+ ") ||
                   pTrimmed.hasPrefix("- [ ]") || pTrimmed.hasPrefix("- [x]") ||
                   pTrimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil ||
                   (pTrimmed.count >= 3 && pTrimmed.allSatisfy({ $0 == "-" || $0 == " " }) && pTrimmed.filter({ $0 == "-" }).count >= 3) {
                    break
                }
                paragraphLines.append(pLine)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            }
        }
        
        return blocks
    }
    
    private func parseListItems(lines: [String], startIndex: Int, isBullet: Bool) -> ([ListItem], Int) {
        var items: [ListItem] = []
        var i = startIndex
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                i += 1
                continue
            }
            
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            
            if isBullet {
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                    items.append(ListItem(text: String(trimmed.dropFirst(2)), indent: indent, children: []))
                    i += 1
                } else {
                    break
                }
            } else {
                if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    items.append(ListItem(text: String(trimmed[range.upperBound...]), indent: indent, children: []))
                    i += 1
                } else {
                    break
                }
            }
        }
        
        return (items, i)
    }
    
    private func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }
        
        func parseCells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces)
                .dropFirst()
                .dropLast()
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        
        let headers = parseCells(lines[0])
        
        // Skip separator line (|---|---|)
        var dataRows: [[String]] = []
        for line in lines.dropFirst(2) {
            dataRows.append(parseCells(line))
        }
        
        return .table(headers: headers, rows: dataRows)
    }
    
    // MARK: - Block Renderers
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            renderInlineMarkdown(text)
            
        case .header(let level, let text):
            VStack(alignment: .leading, spacing: 4) {
                renderInlineMarkdown(text)
                    .font(.system(size: headerFontSize(level), weight: headerWeight(level)))
                
                if level <= 2 {
                    Rectangle()
                        .fill(Color(white: 0.85))
                        .frame(height: 1)
                }
            }
            .padding(.top, level == 1 ? 8 : 4)
            
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
            
        case .blockquote(let lines):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(blockquoteBorder)
                    .frame(width: 3)
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.isEmpty {
                            Spacer().frame(height: 8)
                        } else {
                            renderInlineMarkdown(line)
                                .foregroundStyle(mutedColor)
                        }
                    }
                }
                .padding(.leading, 12)
            }
            .padding(.vertical, 4)
            
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(blockquoteBorder)
                            .frame(width: 12)
                        renderInlineMarkdown(item.text)
                    }
                }
            }
            
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(blockquoteBorder)
                            .frame(width: 20, alignment: .trailing)
                        renderInlineMarkdown(item.text)
                    }
                }
            }
            
        case .horizontalRule:
            Rectangle()
                .fill(Color(white: 0.8))
                .frame(height: 1)
                .padding(.vertical, 8)
            
        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows)
            
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                            .foregroundStyle(item.checked ? Color(red: 0.3, green: 0.75, blue: 0.45) : mutedColor)
                        renderInlineMarkdown(item.text)
                            .strikethrough(item.checked, color: mutedColor)
                            .foregroundStyle(item.checked ? mutedColor : textColor)
                    }
                }
            }
        }
    }
    
    private func headerFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 17
        case 3: return 15
        case 4: return 14
        case 5: return 13
        default: return 12
        }
    }
    
    private func headerWeight(_ level: Int) -> Font.Weight {
        switch level {
        case 1, 2: return .bold
        case 3: return .semibold
        default: return .medium
        }
    }
    
    // MARK: - Inline Markdown
    
    @ViewBuilder
    private func renderInlineMarkdown(_ text: String) -> some View {
        Text(parseInlineMarkdown(text))
            .font(.system(size: 13))
            .foregroundStyle(textColor)
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            var attributed = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            ))
            
            // Style inline code and links
            for run in attributed.runs {
                let range = run.range
                
                // Style inline code with background
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[range].font = .system(size: 12, weight: .medium, design: .monospaced)
                    attributed[range].backgroundColor = codeBackground
                    attributed[range].foregroundColor = Color(red: 0.85, green: 0.25, blue: 0.35)
                }
                
                // Style links
                if attributed[range].link != nil {
                    attributed[range].foregroundColor = linkColor
                }
            }
            
            return attributed
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Code Block View with Syntax Highlighting

private struct CodeBlockView: View {
    let language: String?
    let code: String
    
    @State private var isHovered = false
    @State private var showCopied = false
    
    private var languageColor: Color {
        guard let lang = language?.lowercased() else { return Color(white: 0.5) }
        switch lang {
        case "swift": return Color(red: 0.95, green: 0.4, blue: 0.2)
        case "python", "py": return Color(red: 0.3, green: 0.55, blue: 0.85)
        case "javascript", "js", "typescript", "ts": return Color(red: 0.95, green: 0.8, blue: 0.25)
        case "rust": return Color(red: 0.85, green: 0.45, blue: 0.25)
        case "go": return Color(red: 0.0, green: 0.7, blue: 0.85)
        case "ruby", "rb": return Color(red: 0.85, green: 0.2, blue: 0.2)
        case "java", "kotlin": return Color(red: 0.6, green: 0.3, blue: 0.0)
        case "c", "cpp", "c++": return Color(red: 0.3, green: 0.5, blue: 0.8)
        case "html", "css", "scss": return Color(red: 0.9, green: 0.35, blue: 0.2)
        case "json", "yaml", "yml": return Color(red: 0.5, green: 0.7, blue: 0.3)
        case "bash", "sh", "zsh", "shell": return Color(red: 0.3, green: 0.7, blue: 0.4)
        case "sql": return Color(red: 0.0, green: 0.5, blue: 0.7)
        default: return Color(white: 0.5)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language badge and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(languageColor, in: RoundedRectangle(cornerRadius: 4))
                }
                
                Spacer()
                
                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(showCopied ? Color(red: 0.3, green: 0.75, blue: 0.45) : Color(white: 0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.88), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .opacity(isHovered || showCopied ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.88))
            
            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightSyntax(code, language: language))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.96))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(white: 0.85), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func highlightSyntax(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        
        guard let lang = language?.lowercased() else {
            attributed.foregroundColor = Color(white: 0.2)
            return attributed
        }
        
        // Define syntax patterns
        let keywords: [String]
        let commentPattern: String
        
        switch lang {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "for", "while", "return", "import", "struct", "class", "enum", "case", "switch", "guard", "self", "Self", "private", "public", "internal", "fileprivate", "static", "override", "init", "deinit", "extension", "protocol", "typealias", "associatedtype", "where", "throws", "throw", "try", "catch", "async", "await", "actor", "@State", "@Binding", "@Published", "@ObservedObject", "@StateObject", "@Environment", "some", "any", "nil", "true", "false", "in", "is", "as", "do", "@ViewBuilder", "@MainActor"]
            commentPattern = "//.*"
        case "python", "py":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "pass", "break", "continue", "and", "or", "not", "in", "is", "None", "True", "False", "self", "async", "await", "raise", "global", "nonlocal"]
            commentPattern = "#.*"
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "if", "else", "for", "while", "return", "import", "export", "from", "class", "extends", "new", "this", "super", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "null", "undefined", "true", "false", "interface", "type", "enum", "implements", "public", "private", "protected", "readonly", "static", "abstract", "default", "switch", "case", "break", "continue"]
            commentPattern = "//.*"
        case "rust":
            keywords = ["fn", "let", "mut", "const", "if", "else", "for", "while", "loop", "return", "use", "mod", "pub", "struct", "enum", "impl", "trait", "where", "self", "Self", "match", "async", "await", "move", "ref", "static", "unsafe", "extern", "crate", "super", "type", "dyn", "true", "false", "Some", "None", "Ok", "Err"]
            commentPattern = "//.*"
        case "go":
            keywords = ["func", "var", "const", "if", "else", "for", "range", "return", "import", "package", "struct", "interface", "type", "switch", "case", "default", "go", "chan", "select", "defer", "make", "new", "map", "nil", "true", "false", "break", "continue", "fallthrough"]
            commentPattern = "//.*"
        default:
            attributed.foregroundColor = Color(white: 0.2)
            return attributed
        }
        
        // Apply base color
        attributed.foregroundColor = Color(white: 0.25)
        
        // Highlight strings
        highlightPattern(&attributed, pattern: #"\"[^\"]*\""#, color: Color(red: 0.75, green: 0.35, blue: 0.2))
        highlightPattern(&attributed, pattern: #"'[^']*'"#, color: Color(red: 0.75, green: 0.35, blue: 0.2))
        
        // Highlight numbers
        highlightPattern(&attributed, pattern: #"\b\d+\.?\d*\b"#, color: Color(red: 0.7, green: 0.5, blue: 0.2))
        
        // Highlight keywords
        for keyword in keywords {
            highlightPattern(&attributed, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: Color(red: 0.6, green: 0.2, blue: 0.7))
        }
        
        // Highlight comments (should be last to override other highlighting)
        highlightPattern(&attributed, pattern: commentPattern, color: Color(white: 0.55))
        
        return attributed
    }
    
    private func highlightPattern(_ attributed: inout AttributedString, pattern: String, color: Color) {
        let plainString = String(attributed.characters)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsRange = NSRange(plainString.startIndex..., in: plainString)
        let matches = regex.matches(in: plainString, options: [], range: nsRange)
        
        for match in matches {
            guard let stringRange = Range(match.range, in: plainString) else { continue }
            
            // Convert String.Index range to AttributedString range
            let startOffset = plainString.distance(from: plainString.startIndex, to: stringRange.lowerBound)
            let endOffset = plainString.distance(from: plainString.startIndex, to: stringRange.upperBound)
            
            // Get AttributedString indices by iterating through characters
            var currentIndex = attributed.startIndex
            var charCount = 0
            var startAttrIndex: AttributedString.Index?
            var endAttrIndex: AttributedString.Index?
            
            while currentIndex < attributed.endIndex {
                if charCount == startOffset {
                    startAttrIndex = currentIndex
                }
                if charCount == endOffset {
                    endAttrIndex = currentIndex
                    break
                }
                currentIndex = attributed.index(afterCharacter: currentIndex)
                charCount += 1
            }
            
            if endAttrIndex == nil && charCount == endOffset {
                endAttrIndex = attributed.endIndex
            }
            
            if let start = startAttrIndex, let end = endAttrIndex {
                attributed[start..<end].foregroundColor = color
            }
        }
    }
}

// MARK: - Table View

private struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.2))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.92))
                    
                    if index < headers.count - 1 {
                        Rectangle()
                            .fill(Color(white: 0.85))
                            .frame(width: 1)
                    }
                }
            }
            
            Rectangle()
                .fill(Color(white: 0.8))
                .frame(height: 1)
            
            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        Text(cell)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowIndex % 2 == 0 ? Color.white : Color(white: 0.98))
                        
                        if colIndex < row.count - 1 {
                            Rectangle()
                                .fill(Color(white: 0.9))
                                .frame(width: 1)
                        }
                    }
                }
                
                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(Color(white: 0.9))
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(white: 0.85), lineWidth: 1)
        )
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    @State private var isHovered = false
    @State private var showCopied = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Spacer on left for user messages (pushes content right)
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            if !message.isUser {
                // AI avatar - Mane logo
                Image("icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Mane-paw")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if message.isUser {
                            Text(message.content)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                        } else {
                            MarkdownText(content: message.content)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isUser 
                            ? AnyShapeStyle(Color(red: 0.2, green: 0.5, blue: 0.95))
                            : AnyShapeStyle(Color(white: 0.88)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    
                    // Source documents widget for AI messages
                    if !message.isUser && !message.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sources")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(white: 0.5))
                            
                            FlowLayout(spacing: 6) {
                                ForEach(Array(Set(message.sources)).prefix(5), id: \.self) { source in
                                    SourceChip(filePath: source)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Copy button for AI messages - positioned at bottom
                    if !message.isUser {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showCopied = false
                                }
                            }
                        } label: {
                            ZStack {
                                // Copy icon
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(white: 0.5))
                                    .scaleEffect(showCopied ? 0 : 1)
                                    .opacity(showCopied ? 0 : 1)
                                
                                // Checkmark icon
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.45))
                                    .scaleEffect(showCopied ? 1 : 0)
                                    .opacity(showCopied ? 1 : 0)
                            }
                            .frame(width: 22, height: 22)
                            .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered || showCopied ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isHovered)
                    }
                }
            }
            .frame(maxWidth: 400, alignment: message.isUser ? .trailing : .leading)
            
            // Spacer on right for AI messages (pushes content left)
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Source Chip (Clickable document link)

struct SourceChip: View {
    let filePath: String
    @State private var isHovered = false
    
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }
    
    private var iconName: String {
        switch fileExtension {
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "xlsx", "xls", "csv": return "tablecells"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch fileExtension {
        case "pdf": return Color(red: 0.9, green: 0.3, blue: 0.3)
        case "txt", "md": return Color(red: 0.4, green: 0.6, blue: 0.9)
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return Color(red: 0.3, green: 0.75, blue: 0.5)
        case "mp3", "wav", "m4a", "aac": return Color(red: 0.6, green: 0.4, blue: 0.9)
        case "xlsx", "xls", "csv": return Color(red: 0.2, green: 0.7, blue: 0.5)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
    
    var body: some View {
        Button {
            let url = URL(fileURLWithPath: filePath)
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(iconColor)
                
                Text(fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.3))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(white: 0.88) : Color(white: 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(iconColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help("Open \(fileName)")
    }
}

// MARK: - Streaming Chat Bubble

struct StreamingChatBubble: View {
    let content: String
    
    private var isTyping: Bool { content.isEmpty }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI avatar - Mane logo
            Image("icon")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Mane-paw")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                
                // Message bubble with morphing content
                ZStack(alignment: .leading) {
                    // Typing indicator - fades out when content arrives
                    TypingIndicator()
                        .opacity(isTyping ? 1 : 0)
                        .blur(radius: isTyping ? 0 : 8)
                        .scaleEffect(isTyping ? 1 : 0.85)
                    
                    // Text content with markdown - fades in when content arrives
                    MarkdownText(content: content)
                        .textSelection(.enabled)
                        .opacity(isTyping ? 0 : 1)
                        .blur(radius: isTyping ? 8 : 0)
                        .scaleEffect(isTyping ? 0.96 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.spring(response: 0.4, dampingFraction: 0.95), value: isTyping)
            }
            .frame(maxWidth: 400, alignment: .leading)
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Transcription Shimmer Bubble

struct TranscriptionShimmerBubble: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI avatar - Mane logo for transcription
            Image("icon")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcribing")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.95))
                
                // Shimmer content
                VStack(alignment: .leading, spacing: 8) {
                    // Waveform animation
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { index in
                            WaveformBar(index: index)
                        }
                    }
                    .frame(height: 24)
                    
                    // Shimmer text placeholder lines
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerLine(width: 280)
                        ShimmerLine(width: 220)
                        ShimmerLine(width: 250)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.88))
                        .overlay(
                            // Shimmer overlay
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0),
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .offset(x: shimmerOffset)
                                .mask(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        )
                )
            }
            .frame(maxWidth: 350, alignment: .leading)
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }
}

// Animated waveform bar
struct WaveformBar: View {
    let index: Int
    @State private var height: CGFloat = 4
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.4 + Double(index) * 0.05)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.08)
                ) {
                    height = CGFloat.random(in: 8...22)
                }
            }
    }
}

// Shimmer placeholder line
struct ShimmerLine: View {
    let width: CGFloat
    @State private var shimmerOffset: CGFloat = -100
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(white: 0.82))
            .frame(width: width, height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.5),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 60)
                    .offset(x: shimmerOffset)
                    .mask(RoundedRectangle(cornerRadius: 4))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerOffset = width + 30
                }
            }
    }
}

// MARK: - Summarization Shimmer Bubble

struct SummarizationShimmerBubble: View {
    @State private var shimmerOffset: CGFloat = -200
    @State private var textShimmerOffset: CGFloat = 0
    
    // Gradient colors for summarize (coral/red theme)
    private let gradientColors = [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.85, green: 0.25, blue: 0.4)]
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI avatar - Mane logo for summarization
            Image("icon")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                // Animated "Summarizing" text with shimmer
                HStack(spacing: 0) {
                    Text("Summarizing")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    gradientColors[0].opacity(0.8 + 0.2 * Darwin.sin(Double(textShimmerOffset))),
                                    gradientColors[1]
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    // Animated dots
                    SummarizingDots()
                }
                
                // Shimmer content - text summary placeholder
                VStack(alignment: .leading, spacing: 8) {
                    // Document icon with pulse
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(gradientColors[0].opacity(0.15))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "doc.text")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(gradientColors[0])
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            ShimmerLine(width: 120)
                            ShimmerLine(width: 80)
                        }
                    }
                    
                    // Divider
                    Rectangle()
                        .fill(Color(white: 0.85))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                    
                    // Summary placeholder lines with staggered widths
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerLine(width: 300)
                        ShimmerLine(width: 260)
                        ShimmerLine(width: 280)
                        ShimmerLine(width: 200)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.88))
                        .overlay(
                            // Shimmer overlay
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .offset(x: shimmerOffset)
                                .mask(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        )
                )
            }
            .frame(maxWidth: 380, alignment: .leading)
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmerOffset = 450
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                textShimmerOffset = .pi
            }
        }
    }
}

// Animated dots for "Summarizing..."
struct SummarizingDots: View {
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Text(".")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.45))
                    .opacity(dotOpacities[index])
            }
        }
        .onAppear {
            animateDots()
        }
    }
    
    private func animateDots() {
        for index in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.2)
            ) {
                dotOpacities[index] = 1.0
            }
        }
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
