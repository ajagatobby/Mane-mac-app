//
//  ManeAIApp.swift
//  ManeAI
//
//  Local AI File Organizer
//

import SwiftUI
import SwiftData

@main
struct ManeAIApp: App {
    // Services
    @StateObject private var sidecarManager = SidecarManager()
    @StateObject private var apiService = APIService()
    
    // Model Container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Document.self,
            Project.self,
            ChatMessage.self,
            ChatConversation.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Files...") {
                    Task {
                        await importFiles()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            
            CommandGroup(after: .appInfo) {
                Button("Check Backend Health") {
                    Task {
                        await sidecarManager.checkHealth()
                    }
                }
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(sidecarManager)
                .environmentObject(apiService)
        }
        #endif
    }
    
    private func importFiles() async {
        let urls = await SecurityBookmarks.shared.selectFiles(
            allowedTypes: ["txt", "md", "swift", "ts", "js", "py", "json", "yaml", "yml"],
            allowMultiple: true
        )
        
        for url in urls {
            do {
                let content = try SecurityBookmarks.shared.readFile(at: url)
                _ = try await apiService.ingestDocument(
                    content: content,
                    filePath: url.path
                )
            } catch {
                print("Failed to import \(url.lastPathComponent): \(error)")
            }
        }
    }
}
