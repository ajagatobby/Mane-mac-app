//
//  NoiseShader.metal
//  ManeAI
//
//  Metal shader for subtle film grain/noise texture overlay
//

#include <metal_stdlib>
using namespace metal;

/// Generate pseudo-random noise value
float random(float2 position) {
    return fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
}

/// Noise overlay shader - adds subtle film grain effect
/// Can be applied to any SwiftUI view using .colorEffect()
[[ stitchable ]] half4 noise(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    // Generate noise value with slight animation
    float2 animatedPos = position + float2(time * 0.1, time * 0.15);
    float noiseValue = random(animatedPos);
    
    // Apply noise with adjustable intensity (typically 0.03-0.08 for subtle effect)
    half noise = half(noiseValue * intensity);
    
    // Blend noise with original color
    // Using additive blend for light mode (adds slight grain)
    half4 result = color;
    result.rgb += noise - (intensity * 0.5); // Center the noise around 0
    
    return result;
}

/// Static noise shader without animation
[[ stitchable ]] half4 staticNoise(
    float2 position,
    half4 color,
    float intensity
) {
    float noiseValue = random(position);
    half noise = half(noiseValue * intensity);
    
    half4 result = color;
    result.rgb += noise - (intensity * 0.5);
    
    return result;
}

/// Soft grain shader - more organic looking grain
[[ stitchable ]] half4 softGrain(
    float2 position,
    half4 color,
    float time,
    float intensity,
    float scale
) {
    // Scale down position for larger grain
    float2 scaledPos = position / scale;
    float2 animatedPos = scaledPos + float2(time * 0.05, time * 0.08);
    
    // Multi-octave noise for softer appearance
    float noise1 = random(animatedPos);
    float noise2 = random(animatedPos * 2.0 + float2(17.0, 31.0));
    float combinedNoise = (noise1 + noise2) * 0.5;
    
    half noise = half(combinedNoise * intensity);
    
    half4 result = color;
    result.rgb += noise - (intensity * 0.5);
    
    return result;
}

/// Vignette effect for subtle edge darkening
[[ stitchable ]] half4 vignette(
    float2 position,
    half4 color,
    float2 size,
    float intensity,
    float radius
) {
    // Normalize position to 0-1 range
    float2 uv = position / size;
    
    // Calculate distance from center
    float2 center = float2(0.5, 0.5);
    float dist = distance(uv, center);
    
    // Create smooth vignette falloff
    float vignette = smoothstep(radius, radius - 0.3, dist);
    
    // Apply vignette (darken edges)
    half4 result = color;
    result.rgb *= half(mix(1.0 - intensity, 1.0, vignette));
    
    return result;
}
