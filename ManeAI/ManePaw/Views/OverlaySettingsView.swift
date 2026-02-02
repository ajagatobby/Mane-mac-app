//
//  OverlaySettingsView.swift
//  ManeAI
//
//  Settings UI matching the overlay home design style
//

import SwiftUI

struct OverlaySettingsView: View {
    @EnvironmentObject var sidecarManager: SidecarManager
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss
    
    @State private var ollamaStatus: OllamaStatus?
    @State private var documentCount = 0
    @State private var showLogs = false
    @State private var showDeleteAllConfirmation = false
    @State private var isDeletingDocuments = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - matches search bar area style
            HStack {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(white: 0.15))
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(white: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(white: 0.98))
            
            Rectangle()
                .fill(Color(white: 0.85))
                .frame(height: 0.5)
            
            // Content - ScrollView with sections like home UI
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Status Section
                    sectionHeader("Status")
                    
                    SettingsInfoRow(
                        icon: "bolt.fill",
                        iconColor: sidecarManager.isHealthy ? Color(red: 0.3, green: 0.75, blue: 0.45) : (sidecarManager.isRunning ? .orange : Color(red: 0.95, green: 0.4, blue: 0.5)),
                        title: "Backend",
                        value: statusText
                    )
                    
                    SettingsInfoRow(
                        icon: "cpu",
                        iconColor: ollamaStatus == nil ? Color(white: 0.5) : ((ollamaStatus?.available ?? false) ? Color(red: 0.3, green: 0.75, blue: 0.45) : Color(red: 0.95, green: 0.4, blue: 0.5)),
                        title: "Ollama",
                        value: ollamaStatus == nil ? "Checking..." : (ollamaStatus?.available == true ? (ollamaStatus?.model ?? "Connected") : "Offline")
                    )
                    
                    SettingsInfoRow(
                        icon: "doc.fill",
                        iconColor: Color(red: 1.0, green: 0.78, blue: 0.28),
                        title: "Total Indexed Documents",
                        value: "\(documentCount)"
                    )
                    
                    // Actions Section
                    sectionHeader("Actions")
                    
                    SettingsActionRow(
                        icon: "arrow.clockwise",
                        iconColor: Color(red: 0.35, green: 0.65, blue: 0.95),
                        title: "Restart Backend",
                        subtitle: "Restart the backend service",
                        disabled: !sidecarManager.isRunning
                    ) {
                        Task {
                            sidecarManager.stop()
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await sidecarManager.start()
                        }
                    }
                    
                    SettingsActionRow(
                        icon: "heart.circle",
                        iconColor: Color(red: 0.95, green: 0.4, blue: 0.5),
                        title: "Check Health",
                        subtitle: "Verify backend and Ollama"
                    ) {
                        Task {
                            await sidecarManager.checkHealth()
                            await checkOllamaStatus()
                        }
                    }
                    
                    SettingsActionRow(
                        icon: "terminal",
                        iconColor: Color(red: 0.5, green: 0.5, blue: 0.55),
                        title: "View Logs",
                        subtitle: "Backend output"
                    ) {
                        showLogs = true
                    }
                    
                    SettingsActionRow(
                        icon: "trash",
                        iconColor: Color(red: 0.95, green: 0.35, blue: 0.35),
                        title: "Delete All Indexed Documents",
                        subtitle: "Remove all documents from knowledge base",
                        disabled: documentCount == 0 || isDeletingDocuments
                    ) {
                        showDeleteAllConfirmation = true
                    }
                    
                    // About Section
                    sectionHeader("About")
                    
                    SettingsInfoRow(
                        icon: "info.circle.fill",
                        iconColor: Color(white: 0.5),
                        title: "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    )
                    
                    SettingsInfoRow(
                        icon: "number",
                        iconColor: Color(white: 0.5),
                        title: "Build",
                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    )
                    
                    // Help Section
                    sectionHeader("Help")
                    
                    SettingsActionRow(
                        icon: "arrow.up.right.square",
                        iconColor: Color(red: 0.35, green: 0.65, blue: 0.95),
                        title: "Install Ollama",
                        subtitle: "ollama.ai"
                    ) {
                        NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                    }
                    
                    // Ollama command block
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(white: 0.5).opacity(0.15))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "terminal")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(white: 0.5))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To use AI features, run:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                            
                            Text("ollama pull qwen2.5")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(white: 0.2))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                }
                .padding(.bottom, 20)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: ollamaStatus?.available)
            
            // Footer - matches action bar style
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.89))
            .staticNoiseOverlay(intensity: 0.06)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(white: 0.78))
                    .frame(height: 0.5)
            }
        }
        .frame(width: 750, height: 420)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                Color(red: 0.95, green: 0.95, blue: 0.96)
                    .opacity(0.97)
                StaticNoiseOverlay(intensity: 0.05)
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
        .sheet(isPresented: $showLogs) {
            OverlayLogsView()
                .environmentObject(sidecarManager)
        }
        .confirmationDialog("Delete All Indexed Documents", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete All (\(documentCount) documents)", role: .destructive) {
                Task {
                    await deleteAllDocuments()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(documentCount) documents from your knowledge base. This action cannot be undone.")
        }
        .task {
            await checkOllamaStatus()
            await loadDocumentCount()
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(white: 0.4))
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
    
    private var statusText: String {
        if sidecarManager.isHealthy {
            return "Running"
        } else if sidecarManager.isRunning {
            return "Starting..."
        } else {
            return "Stopped"
        }
    }
    
    private func checkOllamaStatus() async {
        do {
            ollamaStatus = try await apiService.getOllamaStatus()
        } catch {
            ollamaStatus = OllamaStatus(available: false, model: "error", url: "")
        }
    }
    
    private func loadDocumentCount() async {
        do {
            let count = try await apiService.getDocumentCount()
            documentCount = count
            // If backend has no documents, clear local cache to stay in sync
            if count == 0 {
                await MainActor.run {
                    PanelManager.shared.clearIndexedDocumentsCache()
                }
            }
        } catch {
            documentCount = 0
        }
    }
    
    private func deleteAllDocuments() async {
        isDeletingDocuments = true
        defer { isDeletingDocuments = false }
        
        do {
            try await apiService.deleteAllDocuments()
            await MainActor.run {
                PanelManager.shared.clearIndexedDocumentsCache()
            }
            await loadDocumentCount()
        } catch {
            documentCount = 0
        }
    }
}

// MARK: - Settings Info Row (display only, matches RaycastRow style)

struct SettingsInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 28, height: 28)
                    .shadow(color: iconColor.opacity(0.3), radius: 2, y: 1)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.05))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }
}

// MARK: - Settings Action Row (clickable, matches RaycastRow style)

struct SettingsActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let disabled: Bool
    let action: () -> Void
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.disabled = disabled
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 28, height: 28)
                        .shadow(color: iconColor.opacity(0.3), radius: 2, y: 1)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.05))
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(white: 0.45))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered && !disabled ? Color(white: 0.90) : Color.clear)
            )
            .padding(.horizontal, 8)
            .opacity(disabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering && !disabled
            }
        }
    }
}

// MARK: - Overlay Logs View (matches design style)

struct OverlayLogsView: View {
    @EnvironmentObject var sidecarManager: SidecarManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sidecar Logs")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(white: 0.15))
                
                Spacer()
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(sidecarManager.logs.joined(separator: "\n"), forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(white: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(white: 0.98))
            
            Rectangle()
                .fill(Color(white: 0.85))
                .frame(height: 0.5)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(sidecarManager.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.25))
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                Color(red: 0.95, green: 0.95, blue: 0.96)
                    .opacity(0.97)
                StaticNoiseOverlay(intensity: 0.05)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview("Overlay Settings") {
    OverlaySettingsView()
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
}
