//
//  OnboardingShaderViews.swift
//  ManeAI
//
//  SwiftUI views and modifiers that wrap the Metal shaders for onboarding effects
//  Uses TimelineView for animations and proper shader bindings
//

import SwiftUI

// MARK: - Aurora Background

/// Animated aurora/northern lights background effect
/// Uses Metal shader for smooth, GPU-accelerated animation
struct AuroraBackground: View {
    var color1: Color = ManeTheme.Colors.accentPrimary
    var color2: Color = ManeTheme.Colors.accentPurple
    var color3: Color = ManeTheme.Colors.accentTertiary
    var opacity: CGFloat = 0.6
    
    @State private var startDate = Date()
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                color1.opacity(0.3),
                                color2.opacity(0.2),
                                color3.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .colorEffect(
                        ShaderLibrary.auroraGradient(
                            .float2(geometry.size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .color(color1),
                            .color(color2),
                            .color(color3)
                        )
                    )
            }
        }
        .opacity(opacity)
    }
}

// MARK: - Mesh Gradient Background

/// Animated mesh gradient with organic flowing colors
struct AnimatedMeshBackground: View {
    var topLeft: Color = ManeTheme.Colors.accentPrimary.opacity(0.4)
    var topRight: Color = ManeTheme.Colors.accentPurple.opacity(0.3)
    var bottomLeft: Color = ManeTheme.Colors.accentTertiary.opacity(0.3)
    var bottomRight: Color = ManeTheme.Colors.accentSecondary.opacity(0.2)
    
    @State private var startDate = Date()
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.white)
                    .colorEffect(
                        ShaderLibrary.meshGradient(
                            .float2(geometry.size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .color(topLeft),
                            .color(topRight),
                            .color(bottomLeft),
                            .color(bottomRight)
                        )
                    )
            }
        }
    }
}

// MARK: - Pulsing Glow Modifier

/// Applies a pulsing glow effect around a view
struct PulsingGlowModifier: ViewModifier {
    var glowColor: Color = ManeTheme.Colors.accentPrimary
    var pulseSpeed: CGFloat = 2.0
    var glowRadius: CGFloat = 0.4
    
    @State private var startDate = Date()
    
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
            content
                .visualEffect { content, proxy in
                    content.colorEffect(
                        ShaderLibrary.pulsingGlow(
                            .float2(proxy.size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .color(glowColor),
                            .float(pulseSpeed),
                            .float(glowRadius)
                        )
                    )
                }
        }
    }
}

// MARK: - Radial Glow Modifier

/// Applies a static radial glow effect (no animation for better performance)
struct RadialGlowModifier: ViewModifier {
    var glowColor: Color = ManeTheme.Colors.accentPrimary
    var intensity: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.radialGlow(
                        .float2(proxy.size),
                        .color(glowColor),
                        .float(intensity)
                    )
                )
            }
    }
}

// MARK: - Shimmer Effect Modifier

/// Applies an animated shimmer/shine sweep effect
struct ShimmerModifier: ViewModifier {
    var speed: CGFloat = 0.3
    var isActive: Bool = true
    
    @State private var startDate = Date()
    
    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
                content
                    .visualEffect { content, proxy in
                        content.colorEffect(
                            ShaderLibrary.shimmerEffect(
                                .float2(proxy.size),
                                .float(timeline.date.timeIntervalSince(startDate)),
                                .float(speed)
                            )
                        )
                    }
            }
        } else {
            content
        }
    }
}

// MARK: - Sparkle Overlay

/// Animated sparkle/particle overlay effect
struct SparkleOverlay: View {
    var density: CGFloat = 15.0
    
    @State private var startDate = Date()
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .colorEffect(
                        ShaderLibrary.sparkles(
                            .float2(geometry.size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .float(density)
                        )
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Gradient Border Modifier

/// Applies an animated gradient border effect
struct GradientBorderModifier: ViewModifier {
    var color1: Color = ManeTheme.Colors.accentPrimary
    var color2: Color = ManeTheme.Colors.accentPurple
    var borderWidth: CGFloat = 2.0
    var isAnimated: Bool = true
    
    @State private var startDate = Date()
    
    func body(content: Content) -> some View {
        if isAnimated {
            TimelineView(.animation(minimumInterval: 1/30, paused: false)) { timeline in
                content
                    .visualEffect { content, proxy in
                        content.colorEffect(
                            ShaderLibrary.gradientBorder(
                                .float2(proxy.size),
                                .float(timeline.date.timeIntervalSince(startDate)),
                                .color(color1),
                                .color(color2),
                                .float(borderWidth)
                            )
                        )
                    }
            }
        } else {
            content
                .visualEffect { content, proxy in
                    content.colorEffect(
                        ShaderLibrary.gradientBorder(
                            .float2(proxy.size),
                            .float(0),
                            .color(color1),
                            .color(color2),
                            .float(borderWidth)
                        )
                    )
                }
        }
    }
}

// MARK: - Liquid Glass Card

/// Premium glass card with liquid wave effect and noise overlay
struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = ManeTheme.CornerRadius.xl
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .background {
                ZStack {
                    // Base glass
                    GlassBackground(
                        cornerRadius: cornerRadius,
                        opacity: 0.9,
                        noiseIntensity: 0.025
                    )
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Onboarding Background

/// Full-screen onboarding background with aurora and noise
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    ManeTheme.Colors.background,
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Aurora effect
            AuroraBackground(opacity: 0.5)
            
            // Subtle noise overlay
            StaticNoiseOverlay(intensity: 0.02)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glowing Icon Container

/// Container that adds a pulsing glow behind an icon
struct GlowingIconContainer: View {
    var icon: String
    var iconColor: Color = ManeTheme.Colors.accentPrimary
    var backgroundColor: Color = ManeTheme.Colors.accentPrimary.opacity(0.15)
    var size: CGFloat = 80
    var iconSize: CGFloat = 36
    var isPulsing: Bool = true
    
    var body: some View {
        ZStack {
            // Glow background
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)
                .modifier(
                    isPulsing
                    ? PulsingGlowModifier(glowColor: iconColor.opacity(0.5), pulseSpeed: 1.5, glowRadius: 0.5)
                    : PulsingGlowModifier(glowColor: .clear, pulseSpeed: 0, glowRadius: 0)
                )
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [iconColor, iconColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

// MARK: - Ultra Realistic Keyboard Key

/// An ultra-realistic 3D keyboard key with Metal shaders for lighting, depth, and surface texture
/// Fully interactive with realistic press animation and haptic feedback
struct RealisticKeyboardKey: View {
    let text: String
    var icon: String? = nil // Optional icon symbol (e.g., "⌃" for Control)
    var width: CGFloat = 56
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 10
    var isPressed: Bool = false
    var onPress: (() -> Void)? = nil
    
    // Key colors (Apple-style white/grey keycap)
    var keyColor: Color = Color(red: 0.96, green: 0.96, blue: 0.97)
    var highlightColor: Color = Color.white
    var shadowColor: Color = Color(red: 0.1, green: 0.1, blue: 0.12)
    var textColor: Color = Color(red: 0.15, green: 0.15, blue: 0.18)
    
    @State private var startDate = Date()
    @State private var internalPressed = false
    @State private var isHovering = false
    
    private var effectivePressed: Bool {
        isPressed || internalPressed
    }
    
    var body: some View {
        ZStack {
            // Shadow layer (rendered below key)
            keyShadowLayer
                .offset(y: effectivePressed ? 1 : 3)
                .animation(.spring(response: 0.15, dampingFraction: 0.6), value: effectivePressed)
            
            // Main key surface with shader
            keyBody
                .offset(y: effectivePressed ? 2 : 0)
                .animation(.spring(response: 0.15, dampingFraction: 0.6), value: effectivePressed)
        }
        .frame(width: width + 8, height: height + 12) // Extra space for shadow
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !internalPressed {
                        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                            internalPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        internalPressed = false
                    }
                    onPress?()
                }
        )
        .scaleEffect(isHovering && !effectivePressed ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
    }
    
    private var keyShadowLayer: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .frame(width: width, height: height)
                .colorEffect(
                    ShaderLibrary.keyShadow(
                        .float2(CGSize(width: width, height: height)),
                        .float(cornerRadius),
                        .float(effectivePressed ? 4 : 8), // shadowBlur
                        .float(effectivePressed ? 2 : 5), // shadowOffsetY
                        .float(effectivePressed ? 0.15 : 0.35) // shadowOpacity
                    )
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    private var keyBody: some View {
        TimelineView(.animation(minimumInterval: 1/60, paused: false)) { timeline in
            ZStack {
                // Key surface with realistic shader
                Rectangle()
                    .fill(keyColor)
                    .frame(width: width, height: height)
                    .colorEffect(
                        ShaderLibrary.realisticKeyboard(
                            .float2(CGSize(width: width, height: height)),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .color(keyColor),
                            .color(highlightColor),
                            .color(shadowColor),
                            .float(cornerRadius),
                            .float(1.0), // depth
                            .float(effectivePressed ? 1.0 : 0.0)
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                
                // Key label (icon + text or just text)
                keyLabel
                    .offset(y: effectivePressed ? 1 : -1)
            }
        }
    }
    
    @ViewBuilder
    private var keyLabel: some View {
        if let icon = icon {
            // Icon above text (like Mac modifier keys)
            VStack(spacing: 1) {
                Text(icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(textColor.opacity(0.7))
                    .shadow(color: .white.opacity(0.6), radius: 0, x: 0, y: 0.5)
                
                Text(text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .shadow(color: .white.opacity(0.8), radius: 0, x: 0, y: 0.5)
            }
        } else {
            // Just text
            Text(text)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .shadow(color: .white.opacity(0.8), radius: 0, x: 0, y: 0.5)
        }
    }
}

/// Displays a keyboard shortcut with ultra-realistic 3D keys
/// Fully interactive - clicking either key triggers the onActivate callback
struct RealisticKeyboardShortcut: View {
    var modifier: String = "control"
    var modifierIcon: String = "⌃" // Control symbol
    var key: String = "W"
    var spacing: CGFloat = 16
    var onActivate: (() -> Void)? = nil
    
    @State private var modifierPressed = false
    @State private var keyPressed = false
    @State private var isAnimatingSequence = false
    
    var body: some View {
        HStack(spacing: spacing) {
            RealisticKeyboardKey(
                text: modifier,
                icon: modifierIcon,
                width: 64,
                height: 48,
                cornerRadius: 9,
                isPressed: modifierPressed,
                onPress: { triggerShortcutAnimation() }
            )
            
            Text("+")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
            
            RealisticKeyboardKey(
                text: key,
                width: 48,
                height: 48,
                cornerRadius: 9,
                isPressed: keyPressed,
                onPress: { triggerShortcutAnimation() }
            )
        }
    }
    
    /// Animates both keys being pressed in sequence, like a real keyboard shortcut
    private func triggerShortcutAnimation() {
        guard !isAnimatingSequence else { return }
        isAnimatingSequence = true
        
        // Press modifier first
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            modifierPressed = true
        }
        
        // Press the key shortly after
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                keyPressed = true
            }
        }
        
        // Release both keys
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                keyPressed = false
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                modifierPressed = false
            }
            isAnimatingSequence = false
            onActivate?()
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply pulsing glow effect
    func pulsingGlow(
        color: Color = ManeTheme.Colors.accentPrimary,
        pulseSpeed: CGFloat = 2.0,
        radius: CGFloat = 0.4
    ) -> some View {
        self.modifier(PulsingGlowModifier(glowColor: color, pulseSpeed: pulseSpeed, glowRadius: radius))
    }
    
    /// Apply radial glow effect (static)
    func radialGlow(
        color: Color = ManeTheme.Colors.accentPrimary,
        intensity: CGFloat = 1.0
    ) -> some View {
        self.modifier(RadialGlowModifier(glowColor: color, intensity: intensity))
    }
    
    /// Apply shimmer effect
    func onboardingShimmer(speed: CGFloat = 0.3, isActive: Bool = true) -> some View {
        self.modifier(ShimmerModifier(speed: speed, isActive: isActive))
    }
    
    /// Apply animated gradient border
    func gradientBorder(
        color1: Color = ManeTheme.Colors.accentPrimary,
        color2: Color = ManeTheme.Colors.accentPurple,
        width: CGFloat = 2.0,
        animated: Bool = true
    ) -> some View {
        self.modifier(GradientBorderModifier(color1: color1, color2: color2, borderWidth: width, isAnimated: animated))
    }
}

// MARK: - Preview

#Preview("Onboarding Shader Effects") {
    VStack(spacing: 30) {
        // Aurora background sample
        AuroraBackground()
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                Text("Aurora Background")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        
        // Glowing icon
        GlowingIconContainer(
            icon: "sparkles",
            iconColor: ManeTheme.Colors.accentPrimary,
            size: 100,
            iconSize: 44
        )
        
        // Liquid glass card
        LiquidGlassCard {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.title)
                    .foregroundStyle(ManeTheme.Colors.accentPrimary)
                Text("Liquid Glass")
                    .font(ManeTheme.Typography.bodyMedium)
            }
            .padding(24)
        }
        
        // Shimmer button
        Text("Shimmer Effect")
            .font(ManeTheme.Typography.bodySemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(ManeTheme.Gradients.accentButton)
            .clipShape(Capsule())
            .onboardingShimmer()
        
        // Sparkle overlay
        RoundedRectangle(cornerRadius: 16)
            .fill(ManeTheme.Colors.backgroundSecondary)
            .frame(height: 80)
            .overlay {
                SparkleOverlay(density: 12)
            }
            .overlay {
                Text("Sparkles")
                    .foregroundStyle(ManeTheme.Colors.textSecondary)
            }
    }
    .padding()
    .background(OnboardingBackground())
}

#Preview("Ultra Realistic Keyboard") {
    VStack(spacing: 40) {
        Text("Ultra Realistic Keyboard Keys")
            .font(.headline)
            .foregroundStyle(.secondary)
        
        // Keyboard shortcut
        RealisticKeyboardShortcut(modifier: "Ctrl", key: "W")
        
        // Individual keys
        HStack(spacing: 20) {
            RealisticKeyboardKey(text: "⌘", width: 48, height: 48)
            RealisticKeyboardKey(text: "Space", width: 120, height: 48)
            RealisticKeyboardKey(text: "↵", width: 56, height: 48)
        }
        
        // Row of letter keys
        HStack(spacing: 6) {
            ForEach(["A", "S", "D", "F"], id: \.self) { letter in
                RealisticKeyboardKey(text: letter, width: 44, height: 44, cornerRadius: 8)
            }
        }
    }
    .padding(50)
    .background(Color(white: 0.92))
}
