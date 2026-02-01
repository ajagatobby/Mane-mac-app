//
//  ProjectsView.swift
//  ManeAI
//
//  Project list and management view for smart codebase indexing
//

import SwiftUI
import SwiftData

struct ProjectsView: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.indexedAt, order: .reverse) private var projects: [Project]
    
    @State private var searchText = ""
    @State private var selectedProject: Project?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isIndexing = false
    @State private var indexingStatus: String?
    @State private var showDeleteAllConfirmation = false
    
    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText) ||
            project.path.localizedCaseInsensitiveContains(searchText) ||
            project.techStack.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            project.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            projectList
        } detail: {
            if let project = selectedProject {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Choose a project from the list to view details")
                )
            }
        }
        .navigationTitle("Projects")
        .searchable(text: $searchText, prompt: "Search projects")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await indexFolder()
                    }
                } label: {
                    Label("Index Project", systemImage: "folder.badge.plus")
                }
                .help("Select a codebase folder to analyze and index")
                
                if !projects.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .help("Delete all projects")
                }
                
                if isLoading || isIndexing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        if let status = indexingStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete All Projects",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All (\(projects.count) projects)", role: .destructive) {
                Task {
                    await deleteAllProjects()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(projects.count) indexed projects. This action cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await refreshProjects()
        }
    }
    
    private var projectList: some View {
        List(selection: $selectedProject) {
            if filteredProjects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder.badge.gearshape")
                } description: {
                    Text("Index a codebase folder to analyze and search your projects")
                } actions: {
                    Button {
                        Task {
                            await indexFolder()
                        }
                    } label: {
                        Label("Index Project", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(filteredProjects) { project in
                    ProjectRow(project: project)
                        .tag(project)
                        .contextMenu {
                            Button {
                                Task {
                                    await reindexProject(project, withAnalysis: false)
                                }
                            } label: {
                                Label("Re-index (Quick)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            
                            Button {
                                Task {
                                    await reindexProject(project, withAnalysis: true)
                                }
                            } label: {
                                Label("Deep Analysis (Slow)", systemImage: "brain")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                Task {
                                    await deleteProject(project)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await deleteProject(filteredProjects[index])
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
    
    private func indexFolder() async {
        guard let folderURL = await SecurityBookmarks.shared.selectDirectory(
            message: "Select a codebase folder to analyze"
        ) else { return }
        
        isIndexing = true
        indexingStatus = "Detecting codebase..."
        
        do {
            // First detect if it's a codebase
            let detection = try await apiService.detectCodebase(folderPath: folderURL.path)
            
            guard detection.isCodebase else {
                errorMessage = "No codebase detected. Looking for manifest files like package.json, Cargo.toml, etc."
                isIndexing = false
                indexingStatus = nil
                return
            }
            
            indexingStatus = "Analyzing \(detection.type ?? "project")..."
            
            // Index the project
            let response = try await apiService.indexProject(folderPath: folderURL.path)
            
            if response.success, let projectItem = response.project {
                // Save to local SwiftData
                let project = Project(
                    id: projectItem.id,
                    name: projectItem.name,
                    path: projectItem.path,
                    projectDescription: projectItem.description,
                    techStack: projectItem.techStack,
                    tags: projectItem.tags,
                    fileCount: projectItem.fileCount,
                    knowledgeDocument: projectItem.knowledgeDocument
                )
                modelContext.insert(project)
                try? modelContext.save()
                
                selectedProject = project
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = "Failed to index project: \(error.localizedDescription)"
        }
        
        isIndexing = false
        indexingStatus = nil
    }
    
    private func reindexProject(_ project: Project, withAnalysis: Bool = false) async {
        isIndexing = true
        indexingStatus = withAnalysis 
            ? "Analyzing \(project.name) with AI (this may take a moment)..."
            : "Re-indexing \(project.name)..."
        
        do {
            let response: IndexProjectResponse
            if withAnalysis {
                response = try await apiService.analyzeProject(folderPath: project.path)
            } else {
                response = try await apiService.indexProject(folderPath: project.path)
            }
            
            if response.success, let projectItem = response.project {
                // Update local SwiftData
                project.name = projectItem.name
                project.projectDescription = projectItem.description
                project.techStack = projectItem.techStack
                project.tags = projectItem.tags
                project.fileCount = projectItem.fileCount
                project.knowledgeDocument = projectItem.knowledgeDocument
                project.indexedAt = Date()
                
                try? modelContext.save()
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = "Failed to re-index project: \(error.localizedDescription)"
        }
        
        isIndexing = false
        indexingStatus = nil
    }
    
    private func deleteProject(_ project: Project) async {
        do {
            try await apiService.deleteProject(id: project.id)
        } catch {
            print("Backend delete skipped: \(error.localizedDescription)")
        }
        
        modelContext.delete(project)
        try? modelContext.save()
        
        if selectedProject == project {
            selectedProject = nil
        }
    }
    
    private func deleteAllProjects() async {
        isLoading = true
        defer { isLoading = false }
        
        for project in projects {
            do {
                try await apiService.deleteProject(id: project.id)
            } catch {
                print("Backend delete skipped for \(project.name): \(error.localizedDescription)")
            }
            modelContext.delete(project)
        }
        
        try? modelContext.save()
        selectedProject = nil
    }
    
    private func refreshProjects() async {
        do {
            let response = try await apiService.listProjects()
            
            let existingIds = Set(projects.map { $0.id })
            let remoteIds = Set(response.projects.map { $0.id })
            
            // Add missing projects
            for item in response.projects where !existingIds.contains(item.id) {
                let project = Project(
                    id: item.id,
                    name: item.name,
                    path: item.path,
                    projectDescription: item.description,
                    techStack: item.techStack,
                    tags: item.tags,
                    fileCount: item.fileCount,
                    knowledgeDocument: item.knowledgeDocument
                )
                modelContext.insert(project)
            }
            
            // Remove projects that no longer exist on backend
            for project in projects where !remoteIds.contains(project.id) {
                modelContext.delete(project)
            }
            
            try? modelContext.save()
        } catch {
            // Silently fail - projects might just not be synced yet
        }
    }
}

struct ProjectRow: View {
    let project: Project
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Tech stack badges
                    ForEach(project.techStack.prefix(2), id: \.self) { tech in
                        Text(tech)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if project.techStack.count > 2 {
                        Text("+\(project.techStack.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                    Text("\(project.fileCount) files")
                    Text("•")
                    Text(project.formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ProjectDetailView: View {
    let project: Project
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: project.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(project.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Stats
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatItem(title: "Files", value: "\(project.fileCount)")
                    StatItem(title: "Technologies", value: "\(project.techStack.count)")
                    StatItem(title: "Indexed", value: project.formattedDate)
                }
                
                Divider()
                
                // Tech Stack
                if !project.techStack.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tech Stack")
                            .font(.headline)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(project.techStack, id: \.self) { tech in
                                Text(tech)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                
                // Tags
                if !project.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.headline)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(project.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.secondary.opacity(0.1))
                                    .foregroundStyle(.secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                
                Divider()
                
                // Knowledge Document
                if let knowledgeDoc = project.knowledgeDocument, !knowledgeDoc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Document")
                            .font(.headline)
                        
                        Text(knowledgeDoc)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

#Preview {
    ProjectsView()
        .environmentObject(APIService())
}
