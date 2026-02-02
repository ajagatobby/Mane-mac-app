//
//  SearchBar.swift
//  ManeAI
//
//  Raycast-style prominent search bar component
//

import SwiftUI

// MARK: - Search Mode

/// Different modes for the search bar
enum SearchMode: Hashable {
    case search      // General search
    case chat        // AI chat mode
    case documents   // Search documents
    case projects    // Search projects
    case tools       // Tools palette
    
    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .chat: return "bubble.left.and.bubble.right"
        case .documents: return "doc.text"
        case .projects: return "folder"
        case .tools: return "wrench.and.screwdriver"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .search: return ManeTheme.Colors.textSecondary
        case .chat: return ManeTheme.Colors.accentPurple
        case .documents: return ManeTheme.Colors.categoryDocument
        case .projects: return ManeTheme.Colors.categoryProject
        case .tools: return ManeTheme.Colors.accentPrimary
        }
    }
    
    var placeholder: String {
        switch self {
        case .search: return "Search files, chat, or type a command..."
        case .chat: return "Ask Mane-paw anything..."
        case .documents: return "Search documents..."
        case .projects: return "Search projects..."
        case .tools: return "Search tools..."
        }
    }
    
    var shortcutHint: String {
        switch self {
        case .search: return "⌘K"
        case .chat: return "⌘⇧C"
        case .documents: return "⌘⇧D"
        case .projects: return "⌘⇧P"
        case .tools: return "⌘⇧T"
        }
    }
}

// MARK: - Search Bar

/// Raycast-style prominent search bar with mode support
struct SearchBar: View {
    @Binding var text: String
    @Binding var mode: SearchMode
    @FocusState.Binding var isFocused: Bool
    
    var onSubmit: () -> Void = {}
    var onModeChange: (SearchMode) -> Void = { _ in }
    var onEscape: () -> Void = {}
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.md) {
            // Mode icon button
            modeIconButton
            
            // Search input
            searchTextField
            
            // Right side actions
            trailingActions
        }
        .padding(.horizontal, ManeTheme.Spacing.lg)
        .frame(height: ManeTheme.Sizes.searchBarHeight)
        .background {
            SearchBarGlassBackground(isActive: isFocused)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Mode Icon Button
    
    private var modeIconButton: some View {
        Button {
            // Cycle through modes
            cycleModes()
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: ManeTheme.Sizes.searchIconSize, weight: .medium))
                .foregroundStyle(mode.iconColor)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change search mode (\(mode.shortcutHint))")
    }
    
    // MARK: - Search Text Field
    
    private var searchTextField: some View {
        TextField(mode.placeholder, text: $text)
            .font(ManeTheme.Typography.searchInput)
            .foregroundStyle(ManeTheme.Colors.textPrimary)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
    }
    
    // MARK: - Trailing Actions
    
    private var trailingActions: some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            // Clear button
            if !text.isEmpty {
                Button {
                    withAnimation(ManeTheme.Animation.fast) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ManeTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Shortcut hint
            if text.isEmpty {
                KeyboardShortcutBadge(shortcut: mode.shortcutHint)
                    .transition(.opacity)
            }
        }
        .animation(ManeTheme.Animation.fast, value: text.isEmpty)
    }
    
    // MARK: - Mode Cycling
    
    private func cycleModes() {
        let modes: [SearchMode] = [.search, .chat, .documents, .projects, .tools]
        if let currentIndex = modes.firstIndex(of: mode) {
            let nextIndex = (currentIndex + 1) % modes.count
            let newMode = modes[nextIndex]
            withAnimation(ManeTheme.Animation.fast) {
                mode = newMode
            }
            onModeChange(newMode)
        }
    }
}

// MARK: - Keyboard Shortcut Badge

/// Raycast-style keyboard shortcut badge
struct KeyboardShortcutBadge: View {
    let shortcut: String
    var style: BadgeStyle = .subtle
    
    enum BadgeStyle {
        case subtle
        case prominent
    }
    
    var body: some View {
        Text(shortcut)
            .font(ManeTheme.Typography.shortcut)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, ManeTheme.Spacing.sm)
            .frame(minWidth: ManeTheme.Sizes.shortcutBadgeMinWidth)
            .frame(height: ManeTheme.Sizes.shortcutBadgeHeight)
            .background {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xs)
                    .fill(backgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xs)
                            .strokeBorder(borderColor, lineWidth: 0.5)
                    }
            }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .subtle: return ManeTheme.Colors.textTertiary
        case .prominent: return ManeTheme.Colors.textSecondary
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .subtle: return ManeTheme.Colors.backgroundSecondary
        case .prominent: return ManeTheme.Colors.backgroundTertiary
        }
    }
    
    private var borderColor: Color {
        ManeTheme.Colors.border
    }
}

// MARK: - Compound Shortcut Badge

/// Badge for compound shortcuts (e.g., ⌘ + K)
struct CompoundShortcutBadge: View {
    let keys: [String]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                KeyboardShortcutBadge(shortcut: key)
                
                if index < keys.count - 1 {
                    Text("+")
                        .font(ManeTheme.Typography.caption)
                        .foregroundStyle(ManeTheme.Colors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Simple Search Bar Variant

/// Simplified search bar without mode switching
struct SimpleSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var icon: String = "magnifyingglass"
    @FocusState.Binding var isFocused: Bool
    var onSubmit: () -> Void = {}
    
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ManeTheme.Colors.textSecondary)
            
            TextField(placeholder, text: $text)
                .font(ManeTheme.Typography.body)
                .foregroundStyle(ManeTheme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onSubmit)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ManeTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ManeTheme.Spacing.md)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.sm)
                .fill(ManeTheme.Colors.backgroundSecondary)
                .overlay {
                    RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.sm)
                        .strokeBorder(
                            isFocused ? ManeTheme.Colors.accentPrimary.opacity(0.5) : ManeTheme.Colors.border,
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - Preview

#Preview("Search Bar") {
    struct PreviewWrapper: View {
        @State private var text = ""
        @State private var mode: SearchMode = .search
        @FocusState private var isFocused: Bool
        
        var body: some View {
            VStack(spacing: 24) {
                // Full search bar
                SearchBar(
                    text: $text,
                    mode: $mode,
                    isFocused: $isFocused
                )
                .padding(.horizontal)
                
                // Different modes
                ForEach([SearchMode.search, .chat, .documents, .projects, .tools], id: \.self) { previewMode in
                    SearchBar(
                        text: .constant(""),
                        mode: .constant(previewMode),
                        isFocused: $isFocused
                    )
                    .padding(.horizontal)
                    .disabled(true)
                }
                
                // Keyboard shortcut badges
                HStack(spacing: 12) {
                    KeyboardShortcutBadge(shortcut: "⌘K")
                    KeyboardShortcutBadge(shortcut: "⌘⇧P")
                    KeyboardShortcutBadge(shortcut: "↵", style: .prominent)
                    CompoundShortcutBadge(keys: ["⌘", "⇧", "K"])
                }
                
                // Simple search bar
                SimpleSearchBar(
                    text: $text,
                    placeholder: "Filter results...",
                    isFocused: $isFocused
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
            .frame(width: 600)
            .background(ManeTheme.Colors.background)
        }
    }
    
    return PreviewWrapper()
}
