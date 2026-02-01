//
//  Animations.swift
//  ManeAI
//
//  Custom animations and transitions for Raycast-style overlay
//

import SwiftUI

// MARK: - Panel Animations

extension AnyTransition {
    /// Raycast-style panel appear transition
    static var panelAppear: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.95))
                .combined(with: .offset(y: -10)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98))
        )
    }
    
    /// Fade with slight slide from top
    static var slideFromTop: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }
    
    /// Scale and fade for result items
    static var resultItem: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)),
            removal: .opacity
        )
    }
    
    /// Slide from trailing with fade
    static var slideFromTrailing: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .trailing))
        )
    }
}

// MARK: - View Modifiers for Animations

extension View {
    /// Apply panel appear animation
    func panelAnimation() -> some View {
        self
            .transition(.panelAppear)
            .animation(ManeTheme.Animation.panelAppear, value: UUID())
    }
    
    /// Apply hover scale effect
    func hoverScale(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(ManeTheme.Animation.fast, value: isHovered)
    }
    
    /// Apply press scale effect
    func pressScale(_ isPressed: Bool, scale: CGFloat = 0.98) -> some View {
        self
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(ManeTheme.Animation.fast, value: isPressed)
    }
    
    /// Apply bounce animation on appear
    func bounceOnAppear() -> some View {
        self.modifier(BounceOnAppearModifier())
    }
    
    /// Apply shake animation
    func shake(_ shake: Bool) -> some View {
        self.modifier(ShakeEffect(shake: shake))
    }
    
    /// Apply pulse animation
    func pulse(_ isPulsing: Bool) -> some View {
        self.modifier(PulseEffect(isPulsing: isPulsing))
    }
    
    /// Apply staggered animation delay for list items
    func staggeredAnimation(index: Int, baseDelay: Double = 0.03) -> some View {
        self.animation(
            ManeTheme.Animation.springFast.delay(Double(index) * baseDelay),
            value: index
        )
    }
}

// MARK: - Animation Modifiers

/// Bounce animation on view appear
struct BounceOnAppearModifier: ViewModifier {
    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(ManeTheme.Animation.springBouncy) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
    }
}

/// Shake effect for invalid input
struct ShakeEffect: ViewModifier {
    var shake: Bool
    @State private var shakeOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: shake) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 0.05).repeatCount(5, autoreverses: true)) {
                        shakeOffset = 5
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        shakeOffset = 0
                    }
                }
            }
    }
}

/// Pulse effect for attention
struct PulseEffect: ViewModifier {
    var isPulsing: Bool
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        scale = 1.05
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Animated Gradient

/// Animated gradient background
struct AnimatedGradient: View {
    @State private var animateGradient = false
    
    var colors: [Color] = [
        ManeTheme.Colors.accentPrimary.opacity(0.3),
        ManeTheme.Colors.accentPurple.opacity(0.2),
        ManeTheme.Colors.accentSecondary.opacity(0.2)
    ]
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Loading Animation

/// Animated loading dots
struct LoadingDots: View {
    @State private var animating = false
    let count: Int = 3
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(ManeTheme.Colors.accentPrimary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

/// Typing indicator animation
struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.sm) {
            LoadingDots()
            
            Text("Typing...")
                .font(ManeTheme.Typography.caption)
                .foregroundStyle(ManeTheme.Colors.textTertiary)
        }
        .padding(.horizontal, ManeTheme.Spacing.md)
        .padding(.vertical, ManeTheme.Spacing.sm)
        .background {
            Capsule()
                .fill(ManeTheme.Colors.backgroundSecondary)
        }
    }
}

// MARK: - Shimmer Effect

/// Shimmer loading effect
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                    .animation(
                        .linear(duration: 1.5).repeatForever(autoreverses: false),
                        value: phase
                    )
                }
                .mask(content)
            }
            .onAppear {
                phase = 1
            }
    }
}

extension View {
    /// Apply shimmer loading effect
    func shimmer() -> some View {
        self.modifier(ShimmerEffect())
    }
}

// MARK: - Skeleton Loading

/// Skeleton loading placeholder
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: ManeTheme.Spacing.md) {
            // Icon placeholder
            RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.sm)
                .fill(ManeTheme.Colors.backgroundTertiary)
                .frame(width: 28, height: 28)
            
            // Content placeholder
            VStack(alignment: .leading, spacing: ManeTheme.Spacing.xs) {
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xs)
                    .fill(ManeTheme.Colors.backgroundTertiary)
                    .frame(width: 150, height: 14)
                
                RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.xs)
                    .fill(ManeTheme.Colors.backgroundTertiary)
                    .frame(width: 100, height: 10)
            }
            
            Spacer()
        }
        .padding(.horizontal, ManeTheme.Spacing.lg)
        .frame(height: ManeTheme.Sizes.resultRowHeight)
        .shimmer()
    }
}

/// Multiple skeleton rows for loading state
struct SkeletonList: View {
    var rowCount: Int = 5
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                SkeletonRow()
            }
        }
    }
}

// MARK: - Preview

#Preview("Animations") {
    VStack(spacing: 20) {
        // Loading dots
        HStack {
            Text("Loading Dots:")
            LoadingDots()
        }
        
        // Typing indicator
        TypingIndicator()
        
        // Skeleton loading
        SkeletonList(rowCount: 3)
            .frame(width: 400)
            .background(ManeTheme.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg))
        
        // Animated gradient
        AnimatedGradient()
            .frame(width: 200, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: ManeTheme.CornerRadius.lg))
    }
    .padding()
}
