//
//  ManeTheme.swift
//  ManeAI
//
//  Centralized design system with colors, gradients, typography, and design tokens
//  Inspired by Raycast UI/UX and iOS 26 Liquid Glass design
//

import SwiftUI

// MARK: - Theme Namespace

enum ManeTheme {
    
    // MARK: - Colors
    
    enum Colors {
        // Primary Backgrounds (Light Mode)
        static let background = Color(white: 0.98)
        static let backgroundSecondary = Color(white: 0.94)
        static let backgroundTertiary = Color(white: 0.90)
        
        // Glass Effect Colors
        static let glassBackground = Color.white.opacity(0.75)
        static let glassBorder = Color.white.opacity(0.5)
        static let glassHighlight = Color.white.opacity(0.9)
        
        // Panel Background
        static let panelBackground = Color(white: 0.96)
        
        // Accent Colors (iOS 26-inspired soft tones)
        static let accentPrimary = Color(red: 0.35, green: 0.45, blue: 0.95)      // Soft blue-purple
        static let accentSecondary = Color(red: 0.95, green: 0.55, blue: 0.35)    // Warm coral
        static let accentTertiary = Color(red: 0.4, green: 0.85, blue: 0.7)       // Mint green
        static let accentPurple = Color(red: 0.6, green: 0.4, blue: 0.9)          // Soft purple
        
        // Text Colors
        static let textPrimary = Color(white: 0.1)
        static let textSecondary = Color(white: 0.45)
        static let textTertiary = Color(white: 0.6)
        static let textInverse = Color.white
        
        // Status Colors
        static let statusSuccess = Color(red: 0.3, green: 0.78, blue: 0.55)
        static let statusWarning = Color(red: 0.95, green: 0.7, blue: 0.3)
        static let statusError = Color(red: 0.95, green: 0.4, blue: 0.4)
        static let statusInfo = Color(red: 0.4, green: 0.6, blue: 0.95)
        
        // Interactive States
        static let hover = Color.black.opacity(0.04)
        static let selected = Color.black.opacity(0.08)
        static let pressed = Color.black.opacity(0.12)
        
        // Borders & Dividers
        static let border = Color.black.opacity(0.08)
        static let borderLight = Color.black.opacity(0.05)
        static let divider = Color.black.opacity(0.06)
        
        // Shadows
        static let shadowLight = Color.black.opacity(0.08)
        static let shadowMedium = Color.black.opacity(0.12)
        static let shadowHeavy = Color.black.opacity(0.2)
        
        // Category Colors (for different item types)
        static let categoryDocument = Color(red: 0.35, green: 0.55, blue: 0.95)   // Blue
        static let categoryProject = Color(red: 0.95, green: 0.6, blue: 0.35)     // Orange
        static let categoryChat = Color(red: 0.6, green: 0.4, blue: 0.9)          // Purple
        static let categorySettings = Color(red: 0.5, green: 0.55, blue: 0.6)     // Gray
        static let categoryCode = Color(red: 0.4, green: 0.75, blue: 0.5)         // Green
        static let categoryImage = Color(red: 0.9, green: 0.45, blue: 0.55)       // Pink
        static let categoryAudio = Color(red: 0.95, green: 0.75, blue: 0.3)       // Yellow
    }
    
    // MARK: - Gradients
    
    enum Gradients {
        // Background gradient for panel
        static let background = LinearGradient(
            colors: [Color(white: 0.98), Color(white: 0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // Subtle glass shine effect
        static let glassShine = LinearGradient(
            colors: [Color.white.opacity(0.5), Color.white.opacity(0.1), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Search bar inner glow
        static let searchBarGlow = LinearGradient(
            colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // Accent gradient for buttons
        static let accentButton = LinearGradient(
            colors: [
                Color(red: 0.4, green: 0.5, blue: 1.0),
                Color(red: 0.35, green: 0.45, blue: 0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // Warm accent gradient
        static let warmAccent = LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.6, blue: 0.4),
                Color(red: 0.95, green: 0.5, blue: 0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Selection highlight
        static let selection = LinearGradient(
            colors: [
                Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.15),
                Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // iOS 26-style liquid glass gradient
        static let liquidGlass = LinearGradient(
            colors: [
                Color.white.opacity(0.6),
                Color.white.opacity(0.3),
                Color.white.opacity(0.4)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Headings - SF Pro Rounded
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 22, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 16, weight: .semibold, design: .rounded)
        
        // Body - SF Pro
        static let body = Font.system(size: 14, weight: .regular)
        static let bodyMedium = Font.system(size: 14, weight: .medium)
        static let bodySemibold = Font.system(size: 14, weight: .semibold)
        
        // Search Input - Larger for prominence
        static let searchInput = Font.system(size: 18, weight: .regular)
        static let searchPlaceholder = Font.system(size: 18, weight: .regular)
        
        // Results
        static let resultTitle = Font.system(size: 14, weight: .medium)
        static let resultSubtitle = Font.system(size: 12, weight: .regular)
        
        // Captions & Labels
        static let caption = Font.system(size: 12, weight: .regular)
        static let captionMedium = Font.system(size: 12, weight: .medium)
        static let label = Font.system(size: 11, weight: .medium)
        
        // Keyboard Shortcuts
        static let shortcut = Font.system(size: 11, weight: .medium, design: .rounded)
        
        // Code/Monospace
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let codeSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let xxl: CGFloat = 22
        static let pill: CGFloat = 100
    }
    
    // MARK: - Sizes
    
    enum Sizes {
        // Panel
        static let panelWidth: CGFloat = 680
        static let panelMinHeight: CGFloat = 100
        static let panelMaxHeight: CGFloat = 520
        
        // Search Bar
        static let searchBarHeight: CGFloat = 52
        static let searchIconSize: CGFloat = 20
        
        // Results
        static let resultRowHeight: CGFloat = 48
        static let resultIconSize: CGFloat = 28
        static let resultIconCorner: CGFloat = 8
        
        // Action Panel
        static let actionPanelHeight: CGFloat = 48
        static let actionButtonHeight: CGFloat = 32
        
        // Icons
        static let iconSmall: CGFloat = 16
        static let iconMedium: CGFloat = 20
        static let iconLarge: CGFloat = 24
        static let iconXLarge: CGFloat = 32
        
        // Keyboard Shortcut Badge
        static let shortcutBadgeHeight: CGFloat = 20
        static let shortcutBadgeMinWidth: CGFloat = 24
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let panel = Shadow(
            color: Colors.shadowMedium,
            radius: 40,
            x: 0,
            y: 20
        )
        
        static let card = Shadow(
            color: Colors.shadowLight,
            radius: 8,
            x: 0,
            y: 2
        )
        
        static let button = Shadow(
            color: Colors.shadowLight,
            radius: 4,
            x: 0,
            y: 1
        )
        
        static let searchBar = Shadow(
            color: Colors.shadowLight,
            radius: 12,
            x: 0,
            y: 4
        )
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let fast = SwiftUI.Animation.easeOut(duration: 0.1)
        static let normal = SwiftUI.Animation.easeOut(duration: 0.2)
        static let slow = SwiftUI.Animation.easeOut(duration: 0.3)
        
        static let springFast = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let springNormal = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let springBouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.65)
        
        static let panelAppear = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let panelDisappear = SwiftUI.Animation.easeIn(duration: 0.15)
    }
}

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Modifiers

extension View {
    /// Apply theme shadow
    func themeShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    /// Apply panel shadow
    func panelShadow() -> some View {
        self.themeShadow(ManeTheme.Shadows.panel)
    }
    
    /// Apply card shadow
    func cardShadow() -> some View {
        self.themeShadow(ManeTheme.Shadows.card)
    }
    
    /// Apply hover effect background
    func hoverEffect(isHovered: Bool) -> some View {
        self.background(
            isHovered ? ManeTheme.Colors.hover : Color.clear
        )
    }
    
    /// Apply selection effect background
    func selectionEffect(isSelected: Bool) -> some View {
        self.background(
            isSelected ? ManeTheme.Gradients.selection : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Color Extensions

extension Color {
    /// Create a color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
