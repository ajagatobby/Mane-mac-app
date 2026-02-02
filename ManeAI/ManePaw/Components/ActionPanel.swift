//
//  ActionPanel.swift
//  ManeAI
//
//  Raycast-style bottom action panel with context-aware actions and keyboard shortcuts
//

import SwiftUI

// MARK: - Action Item Model

/// An action that can be performed
struct ActionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let shortcut: String?
    let isPrimary: Bool
    let isDestructive: Bool
    let action: () -> Void
    
    init(
        id: String = UUID().uuidString,
        title: String,
        icon: String,
        shortcut: String? = nil,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isPrimary = isPrimary
        self.isDestructive = isDestructive
        self.action = action
    }
    
    // Hashable conformance (excluding action)
    static func == (lhs: ActionItem, rhs: ActionItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Action Group

/// A group of related actions
struct ActionGroup: Identifiable {
    let id: String
    let title: String?
    var actions: [ActionItem]
    
    init(id: String = UUID().uuidString, title: String? = nil, actions: [ActionItem]) {
        self.id = id
        self.title = title
        self.actions = actions
    }
}

// MARK: - Action Panel

/// Raycast-style bottom action panel
struct ActionPanel: View {
    let actions: [ActionItem]
    var selectedItem: ResultItem?
    var showNavigationHints: Bool = true
    
    /// Filter to show only primary or first few actions
    private var visibleActions: [ActionItem] {
        let primary = actions.filter { $0.isPrimary }
        if !primary.isEmpty {
            return Array(primary.prefix(4))
        }
        return Array(actions.prefix(4))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: Navigation hints
            if showNavigationHints {
                navigationHints
                
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, ManeTheme.Spacing.md)
            }
            
            // Center: Selected item info (optional)
            if let item = selectedItem {
                selectedItemInfo(item)
                
                Spacer()
            } else {
                Spacer()
            }
            
            // Right side: Actions
            actionButtons
        }
        .padding(.horizontal, ManeTheme.Spacing.lg)
        .frame(height: ManeTheme.Sizes.actionPanelHeight)
        .background {
            ActionPanelGlassBackground()
        }
    }
    
    // MARK: - Navigation Hints
    
    private var navigationHints: some View {
        HStack(spacing: ManeTheme.Spacing.lg) {
            // Arrow navigation
            HStack(spacing: ManeTheme.Spacing.xs) {
                KeyboardShortcutBadge(shortcut: "↑")
                KeyboardShortcutBadge(shortcut: "↓")
                Text("Navigate")
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
            }
            
            // Enter to select
            HStack(spacing: ManeTheme.Spacing.xs) {
                KeyboardShortcutBadge(shortcut: "↵")
                Text("Open")
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
            }
            
            // Escape to close
            HStack(spacing: ManeTheme.Spacing.xs) {
                KeyboardShortcutBadge(shortcut: "esc")
                Text("Close")
                    .font(ManeTheme.Typography.caption)
                    .foregroundStyle(ManeTheme.Colors.textTertiary)
            }
        }
    }
    
    // MARK: - Selected Item Info
    
    private func selectedItemInfo(_ item: ResultItem) -> some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(item.iconColor)
            
            Text(item.title)
                .font(ManeTheme.Typography.caption)
                .foregroundStyle(ManeTheme.Colors.textSecondary)
                .lineLimit(1)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            ForEach(visibleActions) { action in
                ActionButton(action: action)
            }
            
            // More actions menu
            if actions.count > 4 {
                moreActionsButton
            }
        }
    }
    
    // MARK: - More Actions Button
    
    private var moreActionsButton: some View {
        Menu {
            ForEach(actions.dropFirst(4)) { action in
                Button {
                    action.action()
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
                .keyboardShortcut(action.shortcut.flatMap { parseShortcut($0) } ?? .defaultAction)
            }
        } label: {
            HStack(spacing: ManeTheme.Spacing.xs) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                
                KeyboardShortcutBadge(shortcut: "⌘K")
            }
            .foregroundStyle(ManeTheme.Colors.textSecondary)
            .padding(.horizontal, ManeTheme.Spacing.sm)
            .frame(height: ManeTheme.Sizes.actionButtonHeight)
            .background {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.sm)
                    .fill(ManeTheme.Colors.hover)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
    
    // Parse shortcut string to KeyboardShortcut
    private func parseShortcut(_ shortcut: String) -> KeyboardShortcut? {
        // Simple parsing for common shortcuts
        if shortcut.contains("↵") {
            return KeyboardShortcut(.return)
        }
        return nil
    }
}

// MARK: - Action Button

/// Individual action button in the panel
struct ActionButton: View {
    let action: ActionItem
    @State private var isHovered = false
    
    var body: some View {
        Button {
            action.action()
        } label: {
            HStack(spacing: ManeTheme.Spacing.xs) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(action.title)
                    .font(ManeTheme.Typography.captionMedium)
                
                if let shortcut = action.shortcut {
                    KeyboardShortcutBadge(shortcut: shortcut)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, ManeTheme.Spacing.md)
            .frame(height: ManeTheme.Sizes.actionButtonHeight)
            .background {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.sm)
                    .fill(backgroundColor)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var foregroundColor: Color {
        if action.isDestructive {
            return ManeTheme.Colors.statusError
        } else if action.isPrimary {
            return ManeTheme.Colors.accentPrimary
        }
        return ManeTheme.Colors.textSecondary
    }
    
    private var backgroundColor: Color {
        if isHovered {
            if action.isPrimary {
                return ManeTheme.Colors.accentPrimary.opacity(0.1)
            }
            return ManeTheme.Colors.hover
        }
        return Color.clear
    }
}

// MARK: - Contextual Action Panel

/// Action panel that changes based on selected item
struct ContextualActionPanel: View {
    var selectedItem: ResultItem?
    var mode: SearchMode
    var onAction: (String) -> Void
    
    var body: some View {
        ActionPanel(
            actions: actionsForContext,
            selectedItem: selectedItem
        )
    }
    
    private var actionsForContext: [ActionItem] {
        var actions: [ActionItem] = []
        
        // Common actions
        if selectedItem != nil {
            actions.append(ActionItem(
                title: "Open",
                icon: "arrow.right.circle",
                shortcut: "↵",
                isPrimary: true
            ) {
                onAction("open")
            })
            
            actions.append(ActionItem(
                title: "Quick Look",
                icon: "eye",
                shortcut: "⌘Y"
            ) {
                onAction("preview")
            })
            
            actions.append(ActionItem(
                title: "Copy Path",
                icon: "doc.on.doc",
                shortcut: "⌘C"
            ) {
                onAction("copy")
            })
        }
        
        // Mode-specific actions
        switch mode {
        case .chat:
            actions.append(ActionItem(
                title: "New Chat",
                icon: "plus.bubble",
                shortcut: "⌘N"
            ) {
                onAction("newChat")
            })
            
        case .documents:
            actions.append(ActionItem(
                title: "Import",
                icon: "square.and.arrow.down",
                shortcut: "⌘I"
            ) {
                onAction("import")
            })
            
        case .projects:
            actions.append(ActionItem(
                title: "Reindex",
                icon: "arrow.clockwise",
                shortcut: "⌘R"
            ) {
                onAction("reindex")
            })
            
        case .tools, .search:
            break
        }
        
        return actions
    }
}

// MARK: - Compact Action Bar

/// A more compact action bar for inline use
struct CompactActionBar: View {
    let actions: [ActionItem]
    
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            ForEach(actions.prefix(3)) { action in
                Button {
                    action.action()
                } label: {
                    Image(systemName: action.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            action.isPrimary ? ManeTheme.Colors.accentPrimary : ManeTheme.Colors.textSecondary
                        )
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(ManeTheme.Colors.hover)
                        }
                }
                .buttonStyle(.plain)
                .help("\(action.title)\(action.shortcut.map { " (\($0))" } ?? "")")
            }
        }
    }
}

// MARK: - Preview

#Preview("Action Panel") {
    VStack(spacing: 0) {
        Spacer()
        
        // Full action panel
        ActionPanel(
            actions: [
                ActionItem(title: "Open", icon: "arrow.right.circle", shortcut: "↵", isPrimary: true) {},
                ActionItem(title: "Quick Look", icon: "eye", shortcut: "⌘Y") {},
                ActionItem(title: "Copy", icon: "doc.on.doc", shortcut: "⌘C") {},
                ActionItem(title: "Delete", icon: "trash", shortcut: "⌘⌫", isDestructive: true) {},
                ActionItem(title: "Share", icon: "square.and.arrow.up") {},
            ],
            selectedItem: ResultItem(
                title: "README.md",
                subtitle: "Documents",
                icon: "doc.text.fill",
                iconColor: ManeTheme.Colors.categoryDocument
            )
        )
    }
    .frame(width: 680, height: 400)
    .background(ManeTheme.Colors.background)
}

#Preview("Contextual Action Panel") {
    VStack(spacing: 0) {
        Spacer()
        
        ContextualActionPanel(
            selectedItem: ResultItem(
                title: "ChatView.swift",
                icon: "swift",
                iconColor: .orange
            ),
            mode: .documents,
            onAction: { action in
                print("Action: \(action)")
            }
        )
    }
    .frame(width: 680, height: 300)
    .background(ManeTheme.Colors.background)
}
