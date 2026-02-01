//
//  GlassBackground.swift
//  ManeAI
//
//  iOS 26 Liquid Glass-inspired translucent background components
//

import SwiftUI
import AppKit

// MARK: - Visual Effect View (NSVisualEffectView Bridge)

/// Bridge AppKit's NSVisualEffectView into SwiftUI for native blur effects
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active
    var emphasized: Bool = false
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = emphasized
    }
}

// MARK: - Glass Background View

/// iOS 26 Liquid Glass-inspired background
/// Combines blur, translucency, gradients, and noise for a premium glass effect
struct GlassBackground: View {
    var cornerRadius: CGFloat = ManeTheme.CornerRadius.xl
    var material: NSVisualEffectView.Material = .hudWindow
    var opacity: CGFloat = 0.85
    var showBorder: Bool = true
    var showShine: Bool = true
    var noiseIntensity: CGFloat = 0.03
    
    var body: some View {
        ZStack {
            // Base blur layer
            VisualEffectView(
                material: material,
                blendingMode: .behindWindow,
                state: .active
            )
            
            // White overlay for light mode glass effect
            Color.white.opacity(opacity * 0.6)
            
            // Subtle gradient overlay for depth
            ManeTheme.Gradients.liquidGlass
                .opacity(0.4)
            
            // Glass shine highlight (top-left to bottom-right)
            if showShine {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
            
            // Subtle noise texture
            if noiseIntensity > 0 {
                StaticNoiseOverlay(intensity: noiseIntensity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Panel Glass Background

/// Specialized glass background for the main floating panel
struct PanelGlassBackground: View {
    var body: some View {
        ZStack {
            // Primary blur
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow,
                state: .active
            )
            
            // Light mode base
            ManeTheme.Colors.panelBackground.opacity(0.92)
            
            // Gradient for visual interest
            ManeTheme.Gradients.background
                .opacity(0.5)
            
            // Subtle noise
            StaticNoiseOverlay(intensity: 0.025)
        }
        .clipShape(RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xxl)
                .strokeBorder(
                    ManeTheme.Colors.border,
                    lineWidth: 0.5
                )
        }
        .panelShadow()
    }
}

// MARK: - Search Bar Glass Background

/// Glass background specifically styled for the search bar
struct SearchBarGlassBackground: View {
    var isActive: Bool = false
    
    var body: some View {
        ZStack {
            // Base
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                .fill(Color.white.opacity(0.95))
            
            // Inner glow when active
            if isActive {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                    .fill(
                        ManeTheme.Gradients.searchBarGlow
                            .opacity(0.3)
                    )
            }
            
            // Subtle noise
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                .fill(Color.clear)
                .staticNoiseOverlay(intensity: 0.02)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg)
                .strokeBorder(
                    isActive ? ManeTheme.Colors.accentPrimary.opacity(0.5) : ManeTheme.Colors.border,
                    lineWidth: isActive ? 2 : 1
                )
        }
        .shadow(
            color: isActive ? ManeTheme.Colors.accentPrimary.opacity(0.15) : Color.clear,
            radius: 8,
            x: 0,
            y: 0
        )
    }
}

// MARK: - Card Glass Background

/// Glass background for cards and list items
struct CardGlassBackground: View {
    var isSelected: Bool = false
    var isHovered: Bool = false
    var cornerRadius: CGFloat = ManeTheme.CornerRadius.md
    
    var body: some View {
        ZStack {
            // Base color
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
            
            // Selection gradient
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ManeTheme.Gradients.selection)
            }
            
            // Subtle noise on hover/selection
            if isHovered || isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.clear)
                    .staticNoiseOverlay(intensity: 0.015)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        ManeTheme.Colors.accentPrimary.opacity(0.3),
                        lineWidth: 1
                    )
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return ManeTheme.Colors.accentPrimary.opacity(0.08)
        } else if isHovered {
            return ManeTheme.Colors.hover
        }
        return Color.clear
    }
}

// MARK: - Action Panel Glass Background

/// Glass background for the bottom action panel
struct ActionPanelGlassBackground: View {
    var body: some View {
        ZStack {
            // Blur base
            VisualEffectView(
                material: .headerView,
                blendingMode: .withinWindow
            )
            
            // Light overlay
            Color.white.opacity(0.7)
            
            // Noise
            StaticNoiseOverlay(intensity: 0.02)
        }
        .overlay(alignment: .top) {
            // Top border
            Rectangle()
                .fill(ManeTheme.Colors.divider)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Floating Badge Glass

/// Small glass background for badges and tags
struct BadgeGlassBackground: View {
    var color: Color = ManeTheme.Colors.accentPrimary
    
    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.12))
            
            Capsule()
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        }
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply glass background to any view
    func glassBackground(
        cornerRadius: CGFloat = ManeTheme.CornerRadius.xl,
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        self.background {
            GlassBackground(cornerRadius: cornerRadius, material: material)
        }
    }
    
    /// Apply panel glass background
    func panelGlassBackground() -> some View {
        self.background {
            PanelGlassBackground()
        }
    }
    
    /// Apply card glass background with selection state
    func cardBackground(isSelected: Bool = false, isHovered: Bool = false) -> some View {
        self.background {
            CardGlassBackground(isSelected: isSelected, isHovered: isHovered)
        }
    }
}

// MARK: - Preview

#Preview("Glass Backgrounds") {
    ZStack {
        // Colorful background to show transparency
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3), .pink.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 24) {
            // Panel glass
            VStack {
                Text("Panel Glass Background")
                    .font(ManeTheme.Typography.title3)
            }
            .frame(width: 300, height: 100)
            .panelGlassBackground()
            
            // Search bar glass
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search...")
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
                Spacer()
            }
            .padding()
            .frame(width: 300)
            .background {
                SearchBarGlassBackground(isActive: false)
            }
            
            // Card backgrounds
            HStack(spacing: 12) {
                VStack {
                    Text("Normal")
                        .font(ManeTheme.Typography.caption)
                }
                .frame(width: 80, height: 60)
                .cardBackground()
                
                VStack {
                    Text("Hovered")
                        .font(ManeTheme.Typography.caption)
                }
                .frame(width: 80, height: 60)
                .cardBackground(isHovered: true)
                
                VStack {
                    Text("Selected")
                        .font(ManeTheme.Typography.caption)
                }
                .frame(width: 80, height: 60)
                .cardBackground(isSelected: true)
            }
            
            // Badge
            Text("Badge")
                .font(ManeTheme.Typography.label)
                .foregroundStyle(ManeTheme.Colors.accentPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    BadgeGlassBackground()
                }
        }
        .padding()
    }
    .frame(width: 400, height: 500)
}
