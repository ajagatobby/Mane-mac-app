//
//  SettingsView.swift
//  ManeAI
//
//  App settings and status
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sidecarManager: SidecarManager
    @EnvironmentObject var apiService: APIService
    
    @State private var ollamaStatus: OllamaStatus?
    @State private var documentCount = 0
    @State private var showLogs = false
    @State private var showDeleteAllConfirmation = false
    
    var body: some View {
        Form {
            // Status Section
            Section("Status") {
                LabeledContent("Backend") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sidecarManager.isHealthy ? .green : (sidecarManager.isRunning ? .orange : .red))
                            .frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                
                LabeledContent("Ollama") {
                    if let status = ollamaStatus {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(status.available ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(status.available ? status.model : "Offline")
                        }
                    } else {
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    }
                }
                
                LabeledContent("Total Indexed Documents") {
                    Text("\(documentCount)")
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button("Restart Backend") {
                    Task {
                        sidecarManager.stop()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await sidecarManager.start()
                    }
                }
                .disabled(!sidecarManager.isRunning)
                
                Button("Check Health") {
                    Task {
                        await sidecarManager.checkHealth()
                        await checkOllamaStatus()
                    }
                }
                
                Button("View Logs") {
                    showLogs = true
                }
                
                Button("Delete All Indexed Documents", role: .destructive) {
                    showDeleteAllConfirmation = true
                }
                .disabled(documentCount == 0)
            }
            
            // About Section
            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
            
            // Help Section
            Section("Help") {
                Link(destination: URL(string: "https://ollama.ai")!) {
                    LabeledContent("Install Ollama") {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                
                Text("To use the AI features, install Ollama and run:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("ollama pull qwen2.5")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showLogs) {
            LogsView()
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

struct LogsView: View {
    @EnvironmentObject var sidecarManager: SidecarManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(sidecarManager.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
            .navigationTitle("Sidecar Logs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(sidecarManager.logs.joined(separator: "\n"), forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SidecarManager())
        .environmentObject(APIService())
}
