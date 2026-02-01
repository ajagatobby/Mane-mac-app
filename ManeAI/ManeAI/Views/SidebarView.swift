//
//  SidebarView.swift
//  ManeAI
//
//  Navigation sidebar
//

import SwiftUI
import SwiftData

enum NavigationItem: Hashable {
    case documents
    case chat
    case settings
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @EnvironmentObject var sidecarManager: SidecarManager
    @EnvironmentObject var apiService: APIService
    
    @State private var documentCount = 0
    
    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: NavigationItem.documents) {
                    Label {
                        HStack {
                            Text("Documents")
                            Spacer()
                            if documentCount > 0 {
                                Text("\(documentCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Section("AI Assistant") {
                NavigationLink(value: NavigationItem.chat) {
                    Label {
                        Text("Chat")
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            Section {
                NavigationLink(value: NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ManeAI")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StatusIndicator(
                    isHealthy: sidecarManager.isHealthy,
                    isRunning: sidecarManager.isRunning
                )
            }
        }
        .task {
            await loadDocumentCount()
        }
    }
    
    private func loadDocumentCount() async {
        do {
            documentCount = try await apiService.getDocumentCount()
        } catch {
            documentCount = 0
        }
    }
}

struct StatusIndicator: View {
    let isHealthy: Bool
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(statusHelp)
    }
    
    private var statusColor: Color {
        if isHealthy {
            return .green
        } else if isRunning {
            return .orange
        } else {
            return .red
        }
    }
    
    private var statusText: String {
        if isHealthy {
            return "Connected"
        } else if isRunning {
            return "Starting..."
        } else {
            return "Offline"
        }
    }
    
    private var statusHelp: String {
        if isHealthy {
            return "Backend is running and healthy"
        } else if isRunning {
            return "Backend is starting up"
        } else {
            return "Backend is not running. Check the logs."
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.documents))
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
}
