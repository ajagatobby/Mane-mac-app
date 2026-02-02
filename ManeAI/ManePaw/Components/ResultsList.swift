//
//  ResultsList.swift
//  ManeAI
//
//  Keyboard-navigable results list with Raycast-style design
//

import SwiftUI
import Combine

// MARK: - Result Item Model

/// A search result item
struct ResultItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let category: ResultCategory
    let metadata: [String: String]?
    
    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = ManeTheme.Colors.textSecondary,
        category: ResultCategory = .general,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.category = category
        self.metadata = metadata
    }
}

/// Categories for grouping results
enum ResultCategory: String, CaseIterable {
    case documents = "Documents"
    case projects = "Projects"
    case chat = "Chat"
    case tools = "Tools"
    case recent = "Recent"
    case general = "Results"
    
    var icon: String {
        switch self {
        case .documents: return "doc.text.fill"
        case .projects: return "folder.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .recent: return "clock.fill"
        case .general: return "magnifyingglass"
        }
    }
    
    var color: Color {
        switch self {
        case .documents: return ManeTheme.Colors.categoryDocument
        case .projects: return ManeTheme.Colors.categoryProject
        case .chat: return ManeTheme.Colors.categoryChat
        case .tools: return ManeTheme.Colors.accentPrimary
        case .recent: return ManeTheme.Colors.textSecondary
        case .general: return ManeTheme.Colors.textSecondary
        }
    }
}

/// A section of results
struct ResultSection: Identifiable {
    let id: String
    let category: ResultCategory
    var items: [ResultItem]
    
    init(category: ResultCategory, items: [ResultItem]) {
        self.id = category.rawValue
        self.category = category
        self.items = items
    }
}

// MARK: - Results List

/// Keyboard-navigable results list with sections
struct ResultsList: View {
    let sections: [ResultSection]
    @Binding var selectedIndex: Int
    var onSelect: (ResultItem) -> Void = { _ in }
    var onAction: (ResultItem, ResultAction) -> Void = { _, _ in }
    
    @State private var hoveredId: String?
    
    /// Flat list of all items for index calculation
    private var allItems: [ResultItem] {
        sections.flatMap { $0.items }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        if !section.items.isEmpty {
                            sectionHeader(section.category)
                            
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { localIndex, item in
                                let globalIndex = globalIndex(for: item)
                                
                                ResultRow(
                                    item: item,
                                    isSelected: globalIndex == selectedIndex,
                                    isHovered: hoveredId == item.id,
                                    onSelect: {
                                        selectedIndex = globalIndex
                                        onSelect(item)
                                    },
                                    onAction: { action in
                                        onAction(item, action)
                                    }
                                )
                                .id(item.id)
                                .onHover { hovering in
                                    hoveredId = hovering ? item.id : nil
                                    if hovering {
                                        selectedIndex = globalIndex
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, ManeTheme.Spacing.sm)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if let item = allItems[safe: newIndex] {
                    withAnimation(ManeTheme.Animation.fast) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ category: ResultCategory) -> some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(category.color)
            
            Text(category.rawValue)
                .font(ManeTheme.Typography.captionMedium)
                .foregroundStyle(ManeTheme.Colors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, ManeTheme.Spacing.lg)
        .padding(.top, ManeTheme.Spacing.md)
        .padding(.bottom, ManeTheme.Spacing.xs)
    }
    
    // MARK: - Index Calculation
    
    private func globalIndex(for item: ResultItem) -> Int {
        allItems.firstIndex(where: { $0.id == item.id }) ?? 0
    }
}

// MARK: - Result Row

/// Individual result row with Raycast-style design
struct ResultRow: View {
    let item: ResultItem
    var isSelected: Bool = false
    var isHovered: Bool = false
    var onSelect: () -> Void = {}
    var onAction: (ResultAction) -> Void = { _ in }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ManeTheme.Spacing.md) {
                // Icon
                resultIcon
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(ManeTheme.Typography.resultTitle)
                        .foregroundStyle(ManeTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(ManeTheme.Typography.resultSubtitle)
                            .foregroundStyle(ManeTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Trailing content
                if isSelected || isHovered {
                    trailingContent
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, ManeTheme.Spacing.lg)
            .frame(height: ManeTheme.Sizes.resultRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardBackground(isSelected: isSelected, isHovered: isHovered)
        .animation(ManeTheme.Animation.fast, value: isSelected)
        .animation(ManeTheme.Animation.fast, value: isHovered)
    }
    
    // MARK: - Icon
    
    private var resultIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ManeTheme.Sizes.resultIconCorner)
                .fill(item.iconColor.opacity(0.12))
            
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(item.iconColor)
        }
        .frame(width: ManeTheme.Sizes.resultIconSize, height: ManeTheme.Sizes.resultIconSize)
    }
    
    // MARK: - Trailing Content
    
    private var trailingContent: some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            // Metadata badges
            if let metadata = item.metadata {
                ForEach(Array(metadata.prefix(2)), id: \.key) { key, value in
                    Text(value)
                        .font(ManeTheme.Typography.caption)
                        .foregroundStyle(ManeTheme.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(ManeTheme.Colors.backgroundSecondary)
                        }
                }
            }
            
            // Action hint
            if isSelected {
                KeyboardShortcutBadge(shortcut: "↵", style: .prominent)
            }
        }
    }
}

// MARK: - Result Actions

/// Actions that can be performed on a result
enum ResultAction: String, CaseIterable {
    case open = "Open"
    case preview = "Quick Look"
    case copy = "Copy"
    case delete = "Delete"
    
    var icon: String {
        switch self {
        case .open: return "arrow.right.circle"
        case .preview: return "eye"
        case .copy: return "doc.on.doc"
        case .delete: return "trash"
        }
    }
    
    var shortcut: String {
        switch self {
        case .open: return "↵"
        case .preview: return "⌘Y"
        case .copy: return "⌘C"
        case .delete: return "⌘⌫"
        }
    }
}

// MARK: - Empty Results View

/// View shown when there are no results
struct EmptyResultsView: View {
    var query: String = ""
    var message: String? = nil
    
    var body: some View {
        VStack(spacing: ManeTheme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(ManeTheme.Colors.textTertiary)
            
            VStack(spacing: ManeTheme.Spacing.xs) {
                if query.isEmpty {
                    Text("Start typing to search")
                        .font(ManeTheme.Typography.body)
                        .foregroundStyle(ManeTheme.Colors.textSecondary)
                } else {
                    Text("No results for \"\(query)\"")
                        .font(ManeTheme.Typography.bodyMedium)
                        .foregroundStyle(ManeTheme.Colors.textPrimary)
                    
                    if let message = message {
                        Text(message)
                            .font(ManeTheme.Typography.caption)
                            .foregroundStyle(ManeTheme.Colors.textTertiary)
                    } else {
                        Text("Try a different search term")
                            .font(ManeTheme.Typography.caption)
                            .foregroundStyle(ManeTheme.Colors.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Loading Results View

/// Beautiful animated view shown while loading results
struct LoadingResultsView: View {
    var message: String = "Searching your knowledge base"
    var accentColor: Color = ManeTheme.Colors.accentPrimary
    
    @State private var isAnimating = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    
    var body: some View {
        VStack(spacing: ManeTheme.Spacing.xl) {
            // Animated search indicator
            searchIndicator
            
            // Animated message with dots
            animatedMessage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Search Indicator
    
    private var searchIndicator: some View {
        ZStack {
            // Outer pulsing rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        accentColor.opacity(0.15 - Double(index) * 0.04),
                        lineWidth: 2
                    )
                    .frame(width: 80 + CGFloat(index) * 24, height: 80 + CGFloat(index) * 24)
                    .scaleEffect(isAnimating ? 1.0 + CGFloat(index) * 0.05 : 0.95)
                    .opacity(isAnimating ? 0.8 - Double(index) * 0.2 : 0.4)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
            
            // Scanning arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    AngularGradient(
                        colors: [
                            accentColor.opacity(0),
                            accentColor.opacity(0.6),
                            accentColor
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(120)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(rotationAngle))
            
            // Center icon container
            ZStack {
                // Glow background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentColor.opacity(0.2),
                                accentColor.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulseScale)
                
                // Glass effect circle
                Circle()
                    .fill(ManeTheme.Colors.glassBackground)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: ManeTheme.Colors.shadowLight, radius: 8, x: 0, y: 4)
                
                // Magnifying glass icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isAnimating ? 1.0 : 0.9)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.5)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            
            // Floating document icons
            floatingDocuments
        }
        .frame(height: 140)
    }
    
    // MARK: - Floating Documents
    
    private var floatingDocuments: some View {
        ZStack {
            ForEach(Array(floatingIcons.enumerated()), id: \.offset) { index, iconData in
                FloatingDocumentIcon(
                    icon: iconData.icon,
                    color: iconData.color,
                    size: iconData.size,
                    offset: iconData.offset,
                    delay: Double(index) * 0.15,
                    isAnimating: isAnimating
                )
            }
        }
    }
    
    private var floatingIcons: [(icon: String, color: Color, size: CGFloat, offset: CGSize)] {
        [
            ("doc.text.fill", ManeTheme.Colors.categoryDocument, 14, CGSize(width: -55, height: -35)),
            ("folder.fill", ManeTheme.Colors.categoryProject, 13, CGSize(width: 58, height: -25)),
            ("doc.fill", ManeTheme.Colors.accentTertiary, 12, CGSize(width: -50, height: 40)),
            ("doc.richtext.fill", ManeTheme.Colors.accentSecondary, 13, CGSize(width: 52, height: 38)),
        ]
    }
    
    // MARK: - Animated Message
    
    private var animatedMessage: some View {
        HStack(spacing: 0) {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ManeTheme.Colors.textSecondary)
            
            // Animated dots
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(ManeTheme.Colors.textSecondary)
                        .frame(width: 4, height: 4)
                        .opacity(dotOpacities[index])
                }
            }
            .padding(.leading, 2)
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Main animation flag
        withAnimation {
            isAnimating = true
        }
        
        // Pulse animation
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
        
        // Rotation animation
        withAnimation(
            .linear(duration: 2.0)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
        
        // Dot animation
        animateDots()
    }
    
    private func animateDots() {
        // Cycle through dots with staggered timing
        func animateDot(_ index: Int) {
            withAnimation(.easeInOut(duration: 0.4)) {
                dotOpacities[index] = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    dotOpacities[index] = 0.3
                }
            }
        }
        
        // Recursive animation loop
        func loop() {
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                    animateDot(i)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                loop()
            }
        }
        
        loop()
    }
}

// MARK: - Floating Document Icon

private struct FloatingDocumentIcon: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let offset: CGSize
    let delay: Double
    let isAnimating: Bool
    
    @State private var floatOffset: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Soft glow
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size + 12, height: size + 12)
                .blur(radius: 4)
            
            // Icon background
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size + 8, height: size + 8)
                .shadow(color: color.opacity(0.2), radius: 4, x: 0, y: 2)
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
        }
        .offset(x: offset.width, y: offset.height + floatOffset)
        .opacity(opacity)
        .onAppear {
            // Fade in
            withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                opacity = 1.0
            }
            
            // Float animation
            withAnimation(
                .easeInOut(duration: 1.8 + delay * 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay)
            ) {
                floatOffset = -8
            }
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Results List") {
    struct PreviewWrapper: View {
        @State private var selectedIndex = 0
        
        let sections: [ResultSection] = [
            ResultSection(category: .recent, items: [
                ResultItem(
                    title: "README.md",
                    subtitle: "~/Documents/Mane-paw",
                    icon: "doc.text.fill",
                    iconColor: ManeTheme.Colors.categoryDocument,
                    category: .recent,
                    metadata: ["type": "Markdown"]
                ),
            ]),
            ResultSection(category: .documents, items: [
                ResultItem(
                    title: "APIService.swift",
                    subtitle: "Services • 488 lines",
                    icon: "swift",
                    iconColor: .orange,
                    category: .documents,
                    metadata: ["lang": "Swift"]
                ),
                ResultItem(
                    title: "ChatView.swift",
                    subtitle: "Views • 332 lines",
                    icon: "swift",
                    iconColor: .orange,
                    category: .documents
                ),
            ]),
            ResultSection(category: .projects, items: [
                ResultItem(
                    title: "Mane-paw",
                    subtitle: "Swift, TypeScript • 15 files",
                    icon: "folder.fill",
                    iconColor: ManeTheme.Colors.categoryProject,
                    category: .projects
                ),
            ]),
            ResultSection(category: .tools, items: [
                ResultItem(
                    title: "Start Chat",
                    subtitle: "Open AI chat interface",
                    icon: "bubble.left.and.bubble.right",
                    iconColor: ManeTheme.Colors.categoryChat,
                    category: .tools
                ),
                ResultItem(
                    title: "Import Files",
                    subtitle: "Add files to knowledge base",
                    icon: "square.and.arrow.down",
                    iconColor: ManeTheme.Colors.accentPrimary,
                    category: .tools
                ),
            ]),
        ]
        
        var body: some View {
            VStack(spacing: 0) {
                ResultsList(
                    sections: sections,
                    selectedIndex: $selectedIndex,
                    onSelect: { item in
                        print("Selected: \(item.title)")
                    }
                )
                .frame(height: 350)
            }
            .frame(width: 600)
            .background(ManeTheme.Colors.background)
        }
    }
    
    return PreviewWrapper()
}

#Preview("Empty Results") {
    VStack {
        EmptyResultsView(query: "")
            .frame(height: 200)
        
        EmptyResultsView(query: "nonexistent file")
            .frame(height: 200)
    }
    .frame(width: 400)
    .background(ManeTheme.Colors.background)
}

#Preview("Loading Results - Default") {
    LoadingResultsView()
        .frame(width: 500, height: 350)
        .background(ManeTheme.Colors.background)
}

#Preview("Loading Results - Documents") {
    LoadingResultsView(
        message: "Searching documents",
        accentColor: ManeTheme.Colors.categoryDocument
    )
    .frame(width: 500, height: 350)
    .background(ManeTheme.Colors.background)
}

#Preview("Loading Results - Projects") {
    LoadingResultsView(
        message: "Searching projects",
        accentColor: ManeTheme.Colors.categoryProject
    )
    .frame(width: 500, height: 350)
    .background(ManeTheme.Colors.background)
}
