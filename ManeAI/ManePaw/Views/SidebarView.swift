//
//  SidebarView.swift
//  ManeAI
//
//  Navigation sidebar with Raycast-inspired design
//

import SwiftUI
import SwiftData

enum NavigationItem: Hashable {
    case documents
    case projects
    case chat
    case settings
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @EnvironmentObject var sidecarManager: SidecarManager
    @EnvironmentObject var apiService: APIService
    
    @State private var documentCount = 0
    @State private var projectCount = 0
    
    var body: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: NavigationItem.documents) {
                    SidebarRow(
                        title: "Documents",
                        icon: "folder.fill",
                        iconColor: ManeTheme.Colors.categoryDocument,
                        count: documentCount
                    )
                }
                
                NavigationLink(value: NavigationItem.projects) {
                    SidebarRow(
                        title: "Projects",
                        icon: "folder.badge.gearshape",
                        iconColor: ManeTheme.Colors.categoryProject,
                        count: projectCount
                    )
                }
            } header: {
                Text("Library")
                    .font(ManeTheme.Typography.captionMedium)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
            }
            
            Section {
                NavigationLink(value: NavigationItem.chat) {
                    SidebarRow(
                        title: "Chat",
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: ManeTheme.Colors.categoryChat
                    )
                }
            } header: {
                Text("AI Assistant")
                    .font(ManeTheme.Typography.captionMedium)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
            }
            
            Section {
                NavigationLink(value: NavigationItem.settings) {
                    SidebarRow(
                        title: "Settings",
                        icon: "gear",
                        iconColor: ManeTheme.Colors.categorySettings
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mane-paw")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ThemedStatusIndicator(
                    isHealthy: sidecarManager.isHealthy,
                    isRunning: sidecarManager.isRunning
                )
            }
        }
        .task {
            await loadCounts()
        }
    }
    
    private func loadCounts() async {
        do {
            documentCount = try await apiService.getDocumentCount()
        } catch {
            documentCount = 0
        }
        
        do {
            let response = try await apiService.listProjects()
            projectCount = response.total
        } catch {
            projectCount = 0
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    var count: Int? = nil
    
    var body: some View {
        Label {
            HStack {
                Text(title)
                    .font(ManeTheme.Typography.body)
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
                
                Spacer()
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(ManeTheme.Typography.caption)
                        .foregroundStyle(ManeTheme.Colors.textSecondary)
                        .padding(.horizontal, ManeTheme.Spacing.sm)
                        .padding(.vertical, ManeTheme.Spacing.xxs)
                        .background {
                            Capsule()
                                .fill(ManeTheme.Colors.backgroundTertiary)
                        }
                }
            }
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }
}

// MARK: - Themed Status Indicator

struct ThemedStatusIndicator: View {
    let isHealthy: Bool
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(ManeTheme.Typography.caption)
                .foregroundStyle(ManeTheme.Colors.textSecondary)
        }
        .padding(.horizontal, ManeTheme.Spacing.sm)
        .padding(.vertical, ManeTheme.Spacing.xs)
        .background {
            Capsule()
                .fill(ManeTheme.Colors.backgroundSecondary)
        }
        .help(statusHelp)
    }
    
    private var statusColor: Color {
        if isHealthy {
            return ManeTheme.Colors.statusSuccess
        } else if isRunning {
            return ManeTheme.Colors.statusWarning
        } else {
            return ManeTheme.Colors.statusError
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

// Legacy StatusIndicator for backward compatibility
struct StatusIndicator: View {
    let isHealthy: Bool
    let isRunning: Bool
    
    var body: some View {
        ThemedStatusIndicator(isHealthy: isHealthy, isRunning: isRunning)
    }
}

// MARK: - Preview

#Preview {
    SidebarView(selection: .constant(.documents))
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
        .frame(width: 250)
}
