//
//  TriangleShaders.metal
//  maplibre_gl
//
//  Created by Native Triangle Layer Implementation
//  Metal shaders for SDF-based triangle rendering
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// MARK: - Structs matching Swift side

struct TriangleInstance {
    float2 position;
    float radius;
    float4 color;
    float rotation;
    float opacity;
    float strokeWidth;
    float4 strokeColor;
    float blur;
};

struct Uniforms {
    float2 viewportSize;
    float zoomLevel;
    float4x4 projectionMatrix;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float radius;
    float strokeWidth;
    float4 strokeColor;
    float blur;
    float opacity;
};

// MARK: - Vertex Shader

vertex VertexOut triangleVertexShader(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     constant TriangleInstance* instances [[buffer(0)]],
                                     constant Uniforms& uniforms [[buffer(1)]]) {
    
    // Generate vertices for a triangle inscribed in a circle
    // We create 3 vertices forming an equilateral triangle
    const float2 vertices[3] = {
        float2(0.0, -1.0),      // Top vertex
        float2(-0.866, 0.5),    // Bottom left vertex  
        float2(0.866, 0.5)      // Bottom right vertex
    };
    
    TriangleInstance instance = instances[iid];
    float2 vertex = vertices[vid];
    
    // Apply rotation if specified
    float c = cos(instance.rotation);
    float s = sin(instance.rotation);
    float2x2 rotationMatrix = float2x2(float2(c, -s), float2(s, c));
    
    // Scale by radius and apply rotation
    vertex = rotationMatrix * (vertex * instance.radius);
    
    // Transform to world space (map coordinates to screen)
    vertex += instance.position * uniforms.viewportSize;
    
    // Apply projection matrix to get clip space coordinates
    float4 position = uniforms.projectionMatrix * float4(vertex, 0.0, 1.0);
    
    VertexOut out;
    out.position = position;
    out.color = instance.color;
    out.uv = vertices[vid]; // Pass through original vertex coordinates for SDF
    out.radius = instance.radius;
    out.strokeWidth = instance.strokeWidth;
    out.strokeColor = instance.strokeColor;
    out.blur = instance.blur;
    out.opacity = instance.opacity;
    
    return out;
}

// MARK: - Fragment Shader with SDF Triangle

// SDF function for an equilateral triangle
float triangleSDF(float2 p) {
    const float k = sqrt(3.0);
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0/k;
    if (p.x + k*p.y > 0.0) {
        p = float2(p.x - k*p.y, -k*p.x - p.y) / 2.0;
    }
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y);
}

fragment float4 triangleFragmentShader(VertexOut in [[stage_in]]) {
    // Calculate distance from fragment to triangle edge using SDF
    float dist = triangleSDF(in.uv);
    
    // Apply blur/antialiasing
    float blur = max(in.blur, fwidth(dist));
    float alpha = smoothstep(0.5 - blur, 0.5 + blur, -dist);
    
    // Handle stroke if stroke width > 0
    float4 finalColor = in.color;
    if (in.strokeWidth > 0.0) {
        // Calculate stroke distance
        float strokeDist = abs(dist + 0.5) - in.strokeWidth / 2.0;
        float strokeAlpha = smoothstep(0.5 - blur, 0.5 + blur, -strokeDist);
        
        // Mix fill and stroke colors
        if (dist > -0.5) {
            // Outside fill, show stroke
            finalColor = in.strokeColor;
            alpha = strokeAlpha;
        } else {
            // Inside fill, show fill color
            alpha = alpha;
        }
    }
    
    // Apply global opacity
    finalColor.a *= alpha * in.opacity;
    
    return finalColor;
}
