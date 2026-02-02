//
//  OnboardingView.swift
//  ManeAI
//
//  Fluid onboarding with smooth fade and blur transitions
//

import SwiftUI

// MARK: - Primary Color

private let primaryPink = Color(red: 0.95, green: 0.4, blue: 0.55)
private let primaryPinkLight = Color(red: 0.98, green: 0.5, blue: 0.65)
private let primaryPinkDark = Color(red: 0.85, green: 0.3, blue: 0.45)

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    
    @State private var currentStep = 0
    @State private var isTransitioning = false
    @State private var contentOpacity: Double = 1
    @State private var contentBlur: Double = 0
    @State private var contentScale: Double = 1
    
    private let totalSteps = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
                .background(Color(white: 0.88))
            
            // Content with fluid transitions
            ZStack {
                // Step 0: Welcome
                if currentStep == 0 || isTransitioning {
                    WelcomeStep()
                        .opacity(currentStep == 0 ? contentOpacity : 0)
                        .blur(radius: currentStep == 0 ? contentBlur : 8)
                        .scaleEffect(currentStep == 0 ? contentScale : 0.95)
                }
                
                // Step 1: Hotkey
                if currentStep == 1 || isTransitioning {
                    HotkeyStep()
                        .opacity(currentStep == 1 ? contentOpacity : 0)
                        .blur(radius: currentStep == 1 ? contentBlur : 8)
                        .scaleEffect(currentStep == 1 ? contentScale : 0.95)
                }
                
                // Step 2: Permissions
                if currentStep == 2 || isTransitioning {
                    PermissionsStep(accessibilityGranted: $accessibilityGranted, onRequestPermission: requestAccessibility)
                        .opacity(currentStep == 2 ? contentOpacity : 0)
                        .blur(radius: currentStep == 2 ? contentBlur : 8)
                        .scaleEffect(currentStep == 2 ? contentScale : 0.95)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            Divider()
                .background(Color(white: 0.88))
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 480)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(white: 0.85), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
    
    @State private var accessibilityGranted = false
    
    private func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
    }
    
    // MARK: - Fluid Step Transition
    
    private func goToStep(_ newStep: Int) {
        guard newStep != currentStep else { return }
        
        isTransitioning = true
        
        // Phase 1: Fade out + blur current content
        withAnimation(.easeOut(duration: 0.2)) {
            contentOpacity = 0
            contentBlur = 8
            contentScale = 0.98
        }
        
        // Phase 2: Switch step and fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentStep = newStep
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                contentOpacity = 1
                contentBlur = 0
                contentScale = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isTransitioning = false
            }
        }
    }
    
    // MARK: - Header
    
    private var headerTitle: String {
        switch currentStep {
        case 0: return "Local AI for Your Files"
        case 1: return "Quick Access"
        case 2: return "Almost Ready"
        default: return "Setup"
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 10) {
                // App icon - Mane logo
                Image("icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mane-paw")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.2))
                    
                    Text(headerTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            
            Spacer()
            
            // Animated step indicator
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= currentStep ? primaryPink : Color(white: 0.8))
                        .frame(width: step == currentStep ? 20 : 8, height: 4)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.98))
        .animation(.easeOut(duration: 0.2), value: currentStep)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Back button with fade
            if currentStep > 0 {
                Button {
                    goToStep(currentStep - 1)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color(white: 0.4))
                }
                .buttonStyle(SecondaryButtonStyle())
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            
            Spacer()
            
            // Continue button
            Button {
                if currentStep < totalSteps - 1 {
                    goToStep(currentStep + 1)
                } else {
                    // Final fade out before completing
                    withAnimation(.easeOut(duration: 0.3)) {
                        contentOpacity = 0
                        contentBlur = 10
                        contentScale = 0.95
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        hasCompletedOnboarding = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentStep < totalSteps - 1 ? "Continue" : "Get Started")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: currentStep < totalSteps - 1 ? "chevron.right" : "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(primaryPink)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(FluidButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.98))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
    }
}

// MARK: - Step Views

private struct WelcomeStep: View {
    @State private var showIcon = false
    @State private var showText = false
    @State private var showFeatures = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Icon with entrance animation - Mane logo
                Image("icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: primaryPink.opacity(0.4), radius: 20, y: 8)
                    .scaleEffect(showIcon ? 1 : 0.6)
                    .opacity(showIcon ? 1 : 0)
                
                // Text with staggered fade
                VStack(spacing: 8) {
                    Text("Search & Chat with Your Files")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(white: 0.1))
                    
                    Text("AI that runs 100% locally on your Mac.\nNo cloud, no subscriptions, your data stays private.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .offset(y: showText ? 0 : 10)
                .opacity(showText ? 1 : 0)
                
                // Feature list with staggered reveal
                VStack(spacing: 0) {
                    FeatureItem(icon: "magnifyingglass", title: "Semantic Search", subtitle: "Find files by meaning, not just keywords", color: primaryPink)
                    Divider().padding(.leading, 56)
                    FeatureItem(icon: "bubble.left.and.bubble.right", title: "Chat with Documents", subtitle: "Ask questions, get answers from your files", color: Color(red: 0.6, green: 0.4, blue: 0.9))
                    Divider().padding(.leading, 56)
                    FeatureItem(icon: "folder.fill", title: "Code Understanding", subtitle: "Index and query your codebases", color: Color(red: 1.0, green: 0.6, blue: 0.2))
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(white: 0.9), lineWidth: 1)
                }
                .scaleEffect(showFeatures ? 1 : 0.95)
                .opacity(showFeatures ? 1 : 0)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                showIcon = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                showText = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                showFeatures = true
            }
        }
    }
}

private struct HotkeyStep: View {
    @State private var showKeys = false
    @State private var showText = false
    @State private var showTips = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Ultra-realistic keyboard visual
                RealisticKeyboardShortcut(modifier: "control", modifierIcon: "⌃", key: "W", spacing: 14)
                    .scaleEffect(showKeys ? 1 : 0.9)
                    .opacity(showKeys ? 1 : 0)
                
                // Text
                VStack(spacing: 8) {
                    Text("Always One Shortcut Away")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(white: 0.1))
                    
                    Text("Access your AI assistant instantly from any app.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                }
                .offset(y: showText ? 0 : 10)
                .opacity(showText ? 1 : 0)
                
                // Tips
                VStack(spacing: 0) {
                    TipItem(icon: "app.badge.checkmark", text: "Opens instantly over any application")
                    Divider().padding(.leading, 56)
                    TipItem(icon: "keyboard", text: "Type to search, Return to select")
                    Divider().padding(.leading, 56)
                    TipItem(icon: "xmark.circle", text: "Press Escape or click outside to close")
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(white: 0.9), lineWidth: 1)
                }
                .scaleEffect(showTips ? 1 : 0.95)
                .opacity(showTips ? 1 : 0)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                showKeys = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                showText = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                showTips = true
            }
        }
    }
}

private struct PermissionsStep: View {
    @Binding var accessibilityGranted: Bool
    var onRequestPermission: () -> Void
    
    @State private var showIcon = false
    @State private var showText = false
    @State private var showButton = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Icon
                ZStack {
                    Circle()
                        .fill(accessibilityGranted ? Color(red: 0.3, green: 0.8, blue: 0.5).opacity(0.15) : primaryPink.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(accessibilityGranted ? Color(red: 0.3, green: 0.8, blue: 0.5) : primaryPink)
                }
                .scaleEffect(showIcon ? 1 : 0.6)
                .opacity(showIcon ? 1 : 0)
                
                // Text
                VStack(spacing: 8) {
                    Text(accessibilityGranted ? "You're All Set!" : "Enable Accessibility")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(white: 0.1))
                    
                    Text(accessibilityGranted
                         ? "Mane-paw is ready. Press Ctrl+W to start."
                         : "Required for the global hotkey to work.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                }
                .offset(y: showText ? 0 : 10)
                .opacity(showText ? 1 : 0)
                
                // Permission button or success
                Group {
                    if !accessibilityGranted {
                        VStack(spacing: 12) {
                            Button {
                                onRequestPermission()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 14))
                                    Text("Open System Settings")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(primaryPink)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(FluidButtonStyle())
                            
                            Text("System Settings → Privacy & Security → Accessibility")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.6))
                        }
                    } else {
                        VStack(spacing: 0) {
                            TipItem(icon: "checkmark.circle.fill", text: "Accessibility permission granted", color: Color(red: 0.3, green: 0.8, blue: 0.5))
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(white: 0.9), lineWidth: 1)
                        }
                    }
                }
                .scaleEffect(showButton ? 1 : 0.95)
                .opacity(showButton ? 1 : 0)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                showIcon = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                showText = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                showButton = true
            }
        }
        .onChange(of: accessibilityGranted) { _, _ in
            // Re-animate when permission state changes
            showIcon = false
            showText = false
            showButton = false
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                showIcon = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                showText = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                showButton = true
            }
        }
    }
}

// MARK: - Components

private struct FeatureItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.15))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct TipItem: View {
    let icon: String
    let text: String
    var color: Color = Color(white: 0.5)
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 40)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.3))
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Button Styles

/// Fluid button style with micro hover animations
/// Includes subtle lift, glow, and bounce effects
private struct FluidButtonStyle: ButtonStyle {
    var enableHoverEffect: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        FluidButtonContent(
            configuration: configuration,
            enableHoverEffect: enableHoverEffect
        )
    }
}

private struct FluidButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let enableHoverEffect: Bool
    
    @State private var isHovering = false
    @State private var hoverScale: CGFloat = 1.0
    @State private var hoverGlow: CGFloat = 0
    @State private var hoverOffset: CGFloat = 0
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : hoverScale)
            .offset(y: configuration.isPressed ? 1 : hoverOffset)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .shadow(
                color: Color(red: 0.95, green: 0.4, blue: 0.55).opacity(hoverGlow * 0.3),
                radius: 8 * hoverGlow,
                y: 2
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                guard enableHoverEffect else { return }
                isHovering = hovering
                
                if hovering {
                    // Micro bounce animation on hover enter
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        hoverScale = 1.03
                        hoverOffset = -2
                        hoverGlow = 1.0
                    }
                    
                    // Settle to subtle hover state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hoverScale = 1.02
                            hoverOffset = -1
                        }
                    }
                } else {
                    // Smooth return to normal
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        hoverScale = 1.0
                        hoverOffset = 0
                        hoverGlow = 0
                    }
                }
            }
    }
}

/// Secondary button style with subtle hover effect
private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonContent(configuration: configuration)
    }
}

private struct SecondaryButtonContent: View {
    let configuration: ButtonStyleConfiguration
    
    @State private var isHovering = false
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.5).opacity(isHovering ? 0.08 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .padding(40)
        .background(Color(white: 0.5))
}
