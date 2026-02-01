//
//  NoiseView.swift
//  ManeAI
//
//  SwiftUI view that applies noise/grain texture overlay using Metal shaders
//

import SwiftUI

// MARK: - Noise Overlay View

/// A view that adds a subtle noise/grain texture overlay
/// Uses Metal shader for GPU-accelerated rendering
struct NoiseOverlay: View {
    /// Intensity of the noise effect (0.0 - 1.0, recommended: 0.03-0.08)
    var intensity: CGFloat = 0.04
    
    /// Whether to animate the noise
    var animated: Bool = false
    
    /// Animation speed multiplier
    var animationSpeed: CGFloat = 1.0
    
    @State private var time: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1/30 : nil, paused: !animated)) { timeline in
            Rectangle()
                .fill(Color.clear)
                .colorEffect(
                    ShaderLibrary.noise(
                        .float(animated ? timeline.date.timeIntervalSinceReferenceDate * animationSpeed : 0),
                        .float(intensity)
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

/// Static noise overlay without animation
struct StaticNoiseOverlay: View {
    var intensity: CGFloat = 0.04
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .colorEffect(
                ShaderLibrary.staticNoise(
                    .float(intensity)
                )
            )
            .allowsHitTesting(false)
    }
}

/// Soft grain overlay with larger, more organic grain pattern
struct SoftGrainOverlay: View {
    var intensity: CGFloat = 0.05
    var scale: CGFloat = 2.0
    var animated: Bool = true
    
    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1/24 : nil, paused: !animated)) { timeline in
            Rectangle()
                .fill(Color.clear)
                .colorEffect(
                    ShaderLibrary.softGrain(
                        .float(animated ? timeline.date.timeIntervalSinceReferenceDate : 0),
                        .float(intensity),
                        .float(scale)
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - View Modifiers

extension View {
    /// Add subtle noise overlay to the view
    /// - Parameters:
    ///   - intensity: Noise intensity (0.0-1.0, default: 0.04)
    ///   - animated: Whether to animate the noise (default: false for performance)
    func noiseOverlay(intensity: CGFloat = 0.04, animated: Bool = false) -> some View {
        self.overlay {
            NoiseOverlay(intensity: intensity, animated: animated)
        }
    }
    
    /// Add static noise overlay (better performance)
    func staticNoiseOverlay(intensity: CGFloat = 0.04) -> some View {
        self.overlay {
            StaticNoiseOverlay(intensity: intensity)
        }
    }
    
    /// Add soft grain effect (larger, more organic grain)
    func softGrainOverlay(intensity: CGFloat = 0.05, scale: CGFloat = 2.0) -> some View {
        self.overlay {
            SoftGrainOverlay(intensity: intensity, scale: scale, animated: false)
        }
    }
}

// MARK: - Alternative CSS-style Noise (Fallback)

/// SVG-based noise pattern for cases where Metal shaders aren't available
/// This creates a static noise texture using a procedural pattern
struct SVGNoiseView: View {
    var opacity: CGFloat = 0.04
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Draw noise pattern
                let step: CGFloat = 2
                for x in stride(from: 0, to: size.width, by: step) {
                    for y in stride(from: 0, to: size.height, by: step) {
                        let random = CGFloat.random(in: 0...1)
                        let gray = random > 0.5 ? 1.0 : 0.0
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(Color(white: gray, opacity: opacity))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Noise Background Wrapper

/// A container view that adds noise over a background
struct NoiseBackground<Background: View>: View {
    let background: Background
    var noiseIntensity: CGFloat = 0.04
    var cornerRadius: CGFloat = 0
    
    init(
        noiseIntensity: CGFloat = 0.04,
        cornerRadius: CGFloat = 0,
        @ViewBuilder background: () -> Background
    ) {
        self.noiseIntensity = noiseIntensity
        self.cornerRadius = cornerRadius
        self.background = background()
    }
    
    var body: some View {
        background
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.clear)
                    .staticNoiseOverlay(intensity: noiseIntensity)
            }
    }
}

// MARK: - Preview

#Preview("Noise Overlays") {
    VStack(spacing: 20) {
        // Static noise
        RoundedRectangle(cornerRadius: 16)
            .fill(ManeTheme.Colors.background)
            .frame(height: 100)
            .staticNoiseOverlay(intensity: 0.04)
            .overlay {
                Text("Static Noise (0.04)")
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
            }
        
        // Animated noise
        RoundedRectangle(cornerRadius: 16)
            .fill(ManeTheme.Colors.background)
            .frame(height: 100)
            .noiseOverlay(intensity: 0.06, animated: true)
            .overlay {
                Text("Animated Noise (0.06)")
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
            }
        
        // Soft grain
        RoundedRectangle(cornerRadius: 16)
            .fill(ManeTheme.Colors.background)
            .frame(height: 100)
            .softGrainOverlay(intensity: 0.08, scale: 3.0)
            .overlay {
                Text("Soft Grain (0.08)")
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
            }
        
        // No noise (comparison)
        RoundedRectangle(cornerRadius: 16)
            .fill(ManeTheme.Colors.background)
            .frame(height: 100)
            .overlay {
                Text("No Noise (Comparison)")
                    .foregroundStyle(ManeTheme.Colors.textPrimary)
            }
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
