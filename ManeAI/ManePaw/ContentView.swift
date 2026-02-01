//
//  ContentView.swift
//  ManeAI
//
//  Main app content with 3-pane navigation
//  Note: This view is now primarily used for the traditional window interface.
//  The new overlay interface uses OverlayView.swift
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @EnvironmentObject var sidecarManager: SidecarManager
    @EnvironmentObject var apiService: APIService
    
    @State private var selectedNavigation: NavigationItem? = .documents
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedNavigation)
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .background(ManeTheme.Colors.background)
        .task {
            // Start sidecar when app launches
            await sidecarManager.start()
        }
        .onDisappear {
            // Stop sidecar when app closes
            sidecarManager.stop()
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedNavigation {
        case .documents:
            DocumentsView()
                .environmentObject(apiService)
        case .projects:
            ProjectsView()
                .environmentObject(apiService)
        case .chat:
            ChatView()
                .environmentObject(apiService)
                .environmentObject(sidecarManager)
        case .settings:
            SettingsView()
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        case nil:
            WelcomeView()
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: ManeTheme.Spacing.xl) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ManeTheme.Colors.accentPrimary.opacity(0.2),
                                ManeTheme.Colors.accentPurple.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ManeTheme.Colors.accentPrimary, ManeTheme.Colors.accentPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: ManeTheme.Spacing.sm) {
                Text("Welcome to Mane-paw")
                    .font(ManeTheme.Typography.title1)
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
                
                Text("Select an item from the sidebar to get started")
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
            }
            
            // Quick tips
            VStack(alignment: .leading, spacing: ManeTheme.Spacing.md) {
                QuickTipRow(
                    icon: "magnifyingglass",
                    title: "Quick Search",
                    description: "Press ⌘⇧Space to open the quick search overlay"
                )
                
                QuickTipRow(
                    icon: "folder.badge.plus",
                    title: "Import Files",
                    description: "Add documents to your knowledge base with ⌘I"
                )
                
                QuickTipRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "AI Chat",
                    description: "Ask questions about your files using AI"
                )
            }
            .padding(ManeTheme.Spacing.xl)
            .background {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                    .fill(Color.white)
                    .shadow(color: ManeTheme.Colors.shadowLight, radius: 8, x: 0, y: 2)
            }
        }
        .frame(maxWidth: 400)
        .padding(ManeTheme.Spacing.xxxl)
    }
}

// MARK: - Quick Tip Row

struct QuickTipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: ManeTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ManeTheme.Colors.accentPrimary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: ManeTheme.Spacing.xxs) {
                Text(title)
                    .font(ManeTheme.Typography.bodyMedium)
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
                
                Text(description)
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
        .modelContainer(for: [Document.self, Project.self, ChatMessage.self, ChatConversation.self], inMemory: true)
}
