//
//  OnboardingShaders.metal
//  ManeAI
//
//  Advanced Metal shaders for onboarding visual effects
//  Includes aurora gradients, pulsing glows, and liquid wave distortions
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Helper Functions

/// Attempt a smooth noise function
float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

/// Smooth noise interpolation
float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Smooth interpolation
    float2 u = f * f * (3.0 - 2.0 * f);
    
    // Four corners
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Fractal Brownian Motion for organic movement
float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * smoothNoise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// MARK: - Aurora Gradient Shader

/// Creates an animated aurora/northern lights effect
/// Uses multi-layer sine waves with smooth color blending
[[ stitchable ]] half4 auroraGradient(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 color1,
    half4 color2,
    half4 color3
) {
    // Normalize to UV space (0-1)
    float2 uv = position / size;
    
    // Create flowing wave patterns
    float wave1 = sin(uv.x * 3.0 + time * 0.5) * 0.5 + 0.5;
    float wave2 = sin(uv.x * 2.0 - time * 0.3 + 1.5) * 0.5 + 0.5;
    float wave3 = sin(uv.x * 4.0 + time * 0.7 + 3.0) * 0.5 + 0.5;
    
    // Vertical gradient with wave modulation
    float y1 = uv.y + wave1 * 0.15;
    float y2 = uv.y + wave2 * 0.12;
    float y3 = uv.y + wave3 * 0.1;
    
    // Create smooth color bands
    half intensity1 = half(smoothstep(0.2, 0.5, y1) * smoothstep(0.8, 0.5, y1));
    half intensity2 = half(smoothstep(0.3, 0.6, y2) * smoothstep(0.9, 0.6, y2));
    half intensity3 = half(smoothstep(0.1, 0.4, y3) * smoothstep(0.7, 0.4, y3));
    
    // Blend colors using intensities
    half4 result = half4(0.0h);
    result += color1 * intensity1 * 0.6h;
    result += color2 * intensity2 * 0.5h;
    result += color3 * intensity3 * 0.4h;
    
    // Add subtle shimmer
    half shimmer = half(smoothNoise(float2(uv.x * 10.0 + time, uv.y * 10.0)) * 0.1);
    result.rgb += shimmer;
    
    // Ensure alpha is set
    result.a = max(result.a, 0.3h);
    
    return result;
}

// MARK: - Mesh Gradient Shader

/// Creates a smooth animated mesh gradient with organic movement
/// Perfect for backgrounds with flowing color transitions
[[ stitchable ]] half4 meshGradient(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 topLeft,
    half4 topRight,
    half4 bottomLeft,
    half4 bottomRight
) {
    float2 uv = position / size;
    
    // Add subtle organic movement to UV
    float distortX = sin(uv.y * 3.14159 + time * 0.5) * 0.05;
    float distortY = cos(uv.x * 3.14159 + time * 0.4) * 0.05;
    
    float2 distortedUV = float2(
        clamp(uv.x + distortX, 0.0, 1.0),
        clamp(uv.y + distortY, 0.0, 1.0)
    );
    
    // Bilinear interpolation with distorted UVs
    half4 top = mix(topLeft, topRight, half(distortedUV.x));
    half4 bottom = mix(bottomLeft, bottomRight, half(distortedUV.x));
    half4 result = mix(top, bottom, half(distortedUV.y));
    
    return result;
}

// MARK: - Pulsing Glow Shader

/// Creates a radial pulsing glow effect
/// Great for highlighting icons or buttons
[[ stitchable ]] half4 pulsingGlow(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 glowColor,
    float pulseSpeed,
    float glowRadius
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    
    // Distance from center
    float dist = distance(uv, center);
    
    // Pulsing factor using sine wave
    float pulse = 0.5 + 0.5 * sin(time * pulseSpeed);
    
    // Adjust glow radius based on pulse
    float adjustedRadius = glowRadius * (0.8 + pulse * 0.4);
    
    // Create soft glow falloff (no branching)
    half glow = half(smoothstep(adjustedRadius, 0.0, dist));
    glow = glow * glow; // Quadratic falloff for softer edges
    
    // Blend glow with original color
    half4 result = color;
    result.rgb = mix(result.rgb, glowColor.rgb, glow * 0.6h);
    result.a = max(result.a, glow * glowColor.a);
    
    return result;
}

// MARK: - Radial Glow Shader

/// Static radial glow for icons - no animation
[[ stitchable ]] half4 radialGlow(
    float2 position,
    half4 color,
    float2 size,
    half4 glowColor,
    float intensity
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    
    float dist = distance(uv, center);
    
    // Soft radial gradient
    half glow = half(1.0 - smoothstep(0.0, 0.5, dist));
    glow = glow * glow * half(intensity);
    
    half4 result = color;
    result.rgb += glowColor.rgb * glow;
    result.a = max(result.a, glow * 0.5h);
    
    return result;
}

// MARK: - Liquid Wave Distortion Shader

/// Creates subtle liquid/wave distortion effect
/// Use with .layerEffect for actual distortion, or .colorEffect for color shifts
[[ stitchable ]] half4 liquidWave(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float amplitude,
    float frequency
) {
    float2 uv = position / size;
    
    // Create wave offset
    float waveX = sin(uv.y * frequency + time) * amplitude;
    float waveY = cos(uv.x * frequency + time * 0.8) * amplitude;
    
    // Apply color shift based on wave (simulated distortion for colorEffect)
    half shift = half((waveX + waveY) * 0.5);
    
    half4 result = color;
    // Subtle color temperature shift based on wave
    result.r += shift * 0.05h;
    result.b -= shift * 0.05h;
    
    return result;
}

// MARK: - Shimmer Effect Shader

/// Creates a horizontal shimmer/shine sweep effect
/// Perfect for loading states or attention-grabbing elements
[[ stitchable ]] half4 shimmerEffect(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float speed
) {
    float2 uv = position / size;
    
    // Calculate shimmer position (sweeps left to right)
    float shimmerPos = fract(time * speed);
    
    // Create shimmer band
    float shimmerWidth = 0.3;
    float dist = abs(uv.x - shimmerPos);
    
    // Wrap around for continuous effect
    dist = min(dist, 1.0 - dist);
    
    // Soft shimmer falloff
    half shimmer = half(smoothstep(shimmerWidth, 0.0, dist));
    shimmer = shimmer * shimmer;
    
    // Apply shimmer as additive brightness
    half4 result = color;
    result.rgb += shimmer * 0.3h;
    
    return result;
}

// MARK: - Gradient Border Shader

/// Creates an animated gradient border effect
[[ stitchable ]] half4 gradientBorder(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 color1,
    half4 color2,
    float borderWidth
) {
    float2 uv = position / size;
    
    // Calculate distance to edges
    float distToEdge = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );
    
    // Normalize border distance
    float normalizedBorder = borderWidth / min(size.x, size.y);
    
    // Create border mask
    half borderMask = half(smoothstep(normalizedBorder, normalizedBorder * 0.5, distToEdge));
    
    // Animated gradient angle
    float angle = atan2(uv.y - 0.5, uv.x - 0.5) + time;
    half gradientT = half(0.5 + 0.5 * sin(angle * 2.0));
    
    // Blend border colors
    half4 borderColor = mix(color1, color2, gradientT);
    
    // Apply border
    half4 result = mix(color, borderColor, borderMask);
    
    return result;
}

// MARK: - Sparkle/Particle Effect

/// Creates subtle animated sparkle points
[[ stitchable ]] half4 sparkles(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float density
) {
    float2 uv = position / size;
    
    // Create grid for sparkle positions
    float2 grid = floor(uv * density);
    float2 gridUV = fract(uv * density);
    
    // Random sparkle phase per grid cell
    float phase = hash(grid) * 6.28318;
    float sparkleTime = time * 2.0 + phase;
    
    // Sparkle brightness (pulsing)
    half brightness = half(0.5 + 0.5 * sin(sparkleTime));
    brightness = brightness * brightness * brightness; // Sharp peaks
    
    // Sparkle shape (small point)
    float2 center = float2(0.5, 0.5);
    float dist = distance(gridUV, center);
    half sparkle = half(smoothstep(0.15, 0.0, dist)) * brightness;
    
    // Random visibility (not all cells have sparkles)
    half visible = half(step(0.85, hash(grid + float2(17.0, 31.0))));
    sparkle *= visible;
    
    half4 result = color;
    result.rgb += sparkle * 0.8h;
    
    return result;
}

// MARK: - Realistic Keyboard Key Shader

/// Creates an ultra-realistic 3D keyboard key with proper lighting, depth, and surface texture
/// Simulates physical key with top highlight, side bevels, concave dish, and ambient occlusion
[[ stitchable ]] half4 realisticKeyboard(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 keyColor,
    half4 highlightColor,
    half4 shadowColor,
    float cornerRadius,
    float depth,
    float isPressed
) {
    float2 uv = position / size;
    
    // Normalize corner radius relative to size
    float2 normalizedRadius = float2(cornerRadius) / size;
    
    // Calculate signed distance to rounded rectangle
    float2 centered = uv - 0.5;
    float2 halfSize = float2(0.5) - normalizedRadius;
    float2 d = abs(centered) - halfSize;
    float roundedDist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - min(normalizedRadius.x, normalizedRadius.y);
    
    // Key edge mask with anti-aliasing
    float pixelSize = 1.0 / min(size.x, size.y);
    half keyMask = half(1.0 - smoothstep(-pixelSize * 2.0, pixelSize * 2.0, roundedDist));
    
    // If outside key, return transparent
    if (keyMask < 0.01h) {
        return half4(0.0h);
    }
    
    // ===== 3D DEPTH SIMULATION =====
    
    // Bevel/chamfer effect - brighten top-left, darken bottom-right
    float bevelWidth = 0.08;
    float topLeftDist = min(uv.x, uv.y);
    float bottomRightDist = min(1.0 - uv.x, 1.0 - uv.y);
    
    half topBevel = half(smoothstep(0.0, bevelWidth, topLeftDist));
    half bottomBevel = half(smoothstep(0.0, bevelWidth, bottomRightDist));
    
    // ===== CONCAVE DISH EFFECT =====
    
    // Create the concave surface (key center is lower than edges)
    float dishStrength = 0.12 * depth;
    float2 dishCenter = float2(0.5, 0.48); // Slightly offset for realism
    float dishDist = distance(uv, dishCenter);
    half dishFactor = half(1.0 - smoothstep(0.0, 0.45, dishDist));
    dishFactor = dishFactor * dishFactor; // Quadratic for natural curve
    
    // ===== LIGHTING =====
    
    // Light direction (from top-left, slightly in front)
    float3 lightDir = normalize(float3(-0.4, -0.6, 0.7));
    
    // Surface normal based on dish and bevel
    float3 normal;
    // Dish affects normal toward center
    float2 dishGrad = (uv - dishCenter) * dishStrength * 2.0;
    // Bevel affects normal at edges
    float2 bevelGrad = float2(
        smoothstep(0.0, bevelWidth, uv.x) - smoothstep(1.0 - bevelWidth, 1.0, uv.x),
        smoothstep(0.0, bevelWidth, uv.y) - smoothstep(1.0 - bevelWidth, 1.0, uv.y)
    ) * 0.3;
    
    normal = normalize(float3(dishGrad.x + bevelGrad.x, dishGrad.y + bevelGrad.y, 1.0));
    
    // Diffuse lighting
    half diffuse = half(max(dot(normal, lightDir), 0.0));
    diffuse = 0.5h + diffuse * 0.5h; // Ambient + diffuse
    
    // Specular highlight (for that shiny key look)
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfVec = normalize(lightDir + viewDir);
    half specular = half(pow(max(dot(normal, halfVec), 0.0), 32.0));
    
    // ===== TOP SURFACE HIGHLIGHT =====
    
    // Soft highlight at top edge (simulates light catching top of key)
    half topHighlight = half(smoothstep(0.25, 0.0, uv.y));
    topHighlight *= half(smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x)); // Fade at corners
    topHighlight *= 0.4h;
    
    // ===== EDGE DARKENING (Ambient Occlusion) =====
    
    // Darken near edges to simulate depth/shadow
    float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    half ao = half(smoothstep(0.0, 0.12, edgeDist));
    ao = 0.7h + ao * 0.3h; // Don't go too dark
    
    // ===== SURFACE TEXTURE =====
    
    // Subtle noise for matte plastic/keycap texture
    float noiseScale = 80.0;
    half surfaceNoise = half(smoothNoise(uv * noiseScale + float2(time * 0.01, 0.0)));
    surfaceNoise = 0.97h + surfaceNoise * 0.06h; // Very subtle
    
    // ===== BOTTOM SHADOW (3D depth illusion) =====
    
    // Shadow gets darker toward bottom edge
    half bottomShadow = half(smoothstep(0.6, 1.0, uv.y));
    bottomShadow *= 0.15h * half(depth);
    
    // ===== SIDE DEPTH GRADIENT =====
    
    // Simulate key side/wall being visible at bottom
    float sideVisible = smoothstep(0.85, 0.95, uv.y);
    half sideDarken = half(sideVisible * 0.25 * depth);
    
    // ===== PRESS ANIMATION =====
    
    // When pressed, reduce highlights and add slight darkening
    half pressedDarken = half(isPressed) * 0.08h;
    half pressedHighlightReduce = 1.0h - half(isPressed) * 0.5h;
    
    // ===== COMBINE ALL EFFECTS =====
    
    half4 result = keyColor;
    
    // Apply base lighting
    result.rgb *= diffuse;
    
    // Apply dish shading (center slightly darker due to depth)
    result.rgb *= (1.0h - dishFactor * 0.08h);
    
    // Apply ambient occlusion
    result.rgb *= ao;
    
    // Apply surface texture
    result.rgb *= surfaceNoise;
    
    // Add specular highlight
    result.rgb += highlightColor.rgb * specular * 0.5h * pressedHighlightReduce;
    
    // Add top edge highlight
    result.rgb += highlightColor.rgb * topHighlight * pressedHighlightReduce;
    
    // Apply bottom shadow
    result.rgb -= bottomShadow;
    
    // Apply side darkening
    result.rgb -= sideDarken;
    
    // Apply pressed darkening
    result.rgb -= pressedDarken;
    
    // Apply bevel highlights/shadows
    result.rgb += (1.0h - topBevel) * highlightColor.rgb * 0.15h * pressedHighlightReduce;
    result.rgb -= (1.0h - bottomBevel) * 0.1h;
    
    // Clamp to valid range
    result.rgb = clamp(result.rgb, half3(0.0h), half3(1.0h));
    
    // Apply key mask with soft edges
    result.a = keyMask;
    
    return result;
}

// MARK: - Key Shadow Shader

/// Creates a realistic soft shadow beneath a keyboard key
[[ stitchable ]] half4 keyShadow(
    float2 position,
    half4 color,
    float2 size,
    float cornerRadius,
    float shadowBlur,
    float shadowOffsetY,
    float shadowOpacity
) {
    float2 uv = position / size;
    
    // Offset UV for shadow position (shadow is below and slightly larger)
    float2 shadowUV = uv;
    shadowUV.y -= shadowOffsetY / size.y;
    
    // Normalize corner radius
    float2 normalizedRadius = float2(cornerRadius) / size;
    
    // Calculate distance to shadow shape (slightly expanded)
    float expansion = 0.02;
    float2 centered = shadowUV - 0.5;
    float2 halfSize = float2(0.5 + expansion) - normalizedRadius;
    float2 d = abs(centered) - halfSize;
    float roundedDist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - min(normalizedRadius.x, normalizedRadius.y);
    
    // Soft shadow falloff
    float blurNormalized = shadowBlur / min(size.x, size.y);
    half shadow = half(1.0 - smoothstep(-blurNormalized, blurNormalized * 2.0, roundedDist));
    
    // Fade shadow toward edges for more natural look
    shadow *= half(smoothstep(0.0, 0.3, shadowUV.y)); // Fade at top
    shadow *= half(shadowOpacity);
    
    return half4(0.0h, 0.0h, 0.0h, shadow);
}

// MARK: - Key Inset Border

/// Creates an inset border effect for the key (like the edge of real keycaps)
[[ stitchable ]] half4 keyInsetBorder(
    float2 position,
    half4 color,
    float2 size,
    float cornerRadius,
    float borderWidth,
    half4 lightColor,
    half4 darkColor
) {
    float2 uv = position / size;
    
    // Normalize values
    float2 normalizedRadius = float2(cornerRadius) / size;
    float normalizedBorder = borderWidth / min(size.x, size.y);
    
    // Outer edge distance
    float2 centered = uv - 0.5;
    float2 halfSize = float2(0.5) - normalizedRadius;
    float2 d = abs(centered) - halfSize;
    float outerDist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - min(normalizedRadius.x, normalizedRadius.y);
    
    // Inner edge distance
    float2 innerHalfSize = halfSize - float2(normalizedBorder);
    float2 dInner = abs(centered) - innerHalfSize;
    float innerDist = length(max(dInner, 0.0)) + min(max(dInner.x, dInner.y), 0.0) - min(normalizedRadius.x - normalizedBorder, normalizedRadius.y - normalizedBorder);
    
    // Border mask
    float pixelSize = 1.0 / min(size.x, size.y);
    half borderMask = half(smoothstep(pixelSize, -pixelSize, outerDist) * smoothstep(-pixelSize, pixelSize * 2.0, innerDist));
    
    // Determine if top-left (light) or bottom-right (dark) edge
    float angle = atan2(centered.y, centered.x);
    half isTopLeft = half(smoothstep(0.5, -0.5, sin(angle + 0.785398))); // 45 degree offset
    
    // Blend border color
    half4 borderColor = mix(darkColor, lightColor, isTopLeft);
    
    // Apply to existing color
    half4 result = color;
    result.rgb = mix(result.rgb, borderColor.rgb, borderMask * 0.5h);
    
    return result;
}
