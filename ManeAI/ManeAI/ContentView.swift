//
//  ContentView.swift
//  ManeAI
//
//  Main app content with 3-pane navigation
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
        case .chat:
            ChatView()
                .environmentObject(apiService)
                .environmentObject(sidecarManager)
        case .settings:
            SettingsView()
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        case nil:
            ContentUnavailableView(
                "Welcome to ManeAI",
                systemImage: "sparkles",
                description: Text("Select an item from the sidebar to get started")
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
        .modelContainer(for: [Document.self, ChatMessage.self, ChatConversation.self], inMemory: true)
}
