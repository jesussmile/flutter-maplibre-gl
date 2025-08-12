import MapLibre
import Metal
import MetalKit
import simd

/// Custom style layer that renders triangles using Metal shaders.
/// This implementation provides a workaround for missing MLNTriangleStyleLayer in the core SDK.
class MLNTriangleCustomStyleLayer: MLNCustomStyleLayer {
    
    // MARK: - Properties
    private var metalDevice: MTLDevice?
    private var renderPipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var triangleProperties: [String: String] = [:]
    
    // Triangle instance data structure
    struct TriangleInstance {
        var position: simd_float2
        var radius: Float
        var color: simd_float4
        var rotation: Float
        var opacity: Float
        var strokeWidth: Float
        var strokeColor: simd_float4
        var blur: Float
    }
    
    private var instances: [TriangleInstance] = []
    
    // MARK: - Initialization
    init(identifier: String) {
        super.init(identifier: identifier)
        setupMetal()
    }
    
    // MARK: - Metal Setup
    private func setupMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        guard let device = metalDevice else {
            print("Metal device creation failed")
            return
        }
        
        // Create Metal library and functions
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "triangleVertexShader")
        let fragmentFunction = library?.makeFunction(name: "triangleFragmentShader")
        
        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Pipeline state creation failed: \(error)")
        }
    }
    
    // MARK: - Property Management
    func updateProperties(_ properties: [String: String]) {
        triangleProperties = properties
        // Parse and update triangle instances based on properties
        updateTriangleInstances()
        // Force redraw
        setNeedsDisplay()
    }
    
    private func updateTriangleInstances() {
        // This is a simplified implementation - in practice, instances would be
        // created from the source data and styled according to the properties
        
        // Extract common properties with defaults
        let radius = Float(triangleProperties["triangle-radius"] ?? "10") ?? 10.0
        let color = parseColor(triangleProperties["triangle-color"] ?? "#3388ff")
        let opacity = Float(triangleProperties["triangle-opacity"] ?? "1.0") ?? 1.0
        let strokeWidth = Float(triangleProperties["triangle-stroke-width"] ?? "0") ?? 0.0
        let strokeColor = parseColor(triangleProperties["triangle-stroke-color"] ?? "#000000")
        let blur = Float(triangleProperties["triangle-blur"] ?? "0") ?? 0.0
        let rotation = Float(triangleProperties["triangle-rotation"] ?? "0") ?? 0.0
        
        // Create sample instances - in practice these would come from source features
        instances = [
            TriangleInstance(
                position: simd_float2(0.5, 0.5), // Normalized coordinates
                radius: radius,
                color: color,
                rotation: rotation,
                opacity: opacity,
                strokeWidth: strokeWidth,
                strokeColor: strokeColor,
                blur: blur
            )
        ]
    }
    
    private func parseColor(_ colorString: String) -> simd_float4 {
        // Simple hex color parser - returns RGBA
        var hex = colorString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 6 {
            let scanner = Scanner(string: hex)
            var hexNumber: UInt64 = 0
            
            if scanner.scanHexInt64(&hexNumber) {
                let r = Float((hexNumber & 0xff0000) >> 16) / 255.0
                let g = Float((hexNumber & 0x00ff00) >> 8) / 255.0
                let b = Float(hexNumber & 0x0000ff) / 255.0
                return simd_float4(r, g, b, 1.0)
            }
        }
        return simd_float4(0.2, 0.53, 1.0, 1.0) // Default blue
    }
    
    // MARK: - MLNCustomStyleLayer Override
    override func drawInMapView(_ mapView: MLNMapView, withContext context: MLNStyleLayerDrawingContext) {
        // Exit early if no render encoder available (Metal backend)
        guard let renderEncoder = self.renderEncoder else {
            print("No Metal render encoder available")
            return
        }
        
        // Exit early if no pipeline state created
        guard let pipelineState = renderPipelineState else {
            print("Pipeline state not created")
            return
        }
        
        // Exit early if no instances to draw
        guard !instances.isEmpty else {
            // Nothing to render
            return
        }
        
        // Set the render pipeline state
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Create uniforms for this frame
        var uniforms = createUniforms(from: context)
        
        // Upload instance data to a buffer if needed
        guard let device = metalDevice else { return }
        
        // Create or update vertex buffer with current instances
        let instanceDataSize = instances.count * MemoryLayout<TriangleInstance>.stride
        if vertexBuffer == nil || vertexBuffer!.length < instanceDataSize {
            vertexBuffer = device.makeBuffer(length: max(instanceDataSize, 1024), options: .storageModeShared)
        }
        
        guard let buffer = vertexBuffer else { return }
        
        // Copy instance data to buffer
        let bufferPointer = buffer.contents().bindMemory(to: TriangleInstance.self, capacity: instances.count)
        for (index, instance) in instances.enumerated() {
            bufferPointer[index] = instance
        }
        
        // Set vertex buffers
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        
        // Draw triangles using instanced rendering
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: instances.count)
    }
    
    // MARK: - Helper Methods
    private struct Uniforms {
        var viewportSize: simd_float2
        var zoomLevel: Float
        var projectionMatrix: simd_float4x4
    }
    
    private func createUniforms(from context: MLNStyleLayerDrawingContext) -> Uniforms {
        let viewportSize = simd_float2(Float(context.size.width), Float(context.size.height))
        let zoomLevel = Float(context.zoomLevel)
        
        // Create a simple orthographic projection matrix for screen space
        let projectionMatrix = simd_float4x4(
            simd_float4(2.0 / Float(context.size.width), 0, 0, 0),
            simd_float4(0, -2.0 / Float(context.size.height), 0, 0),
            simd_float4(0, 0, -1, 0),
            simd_float4(-1, 1, 0, 1)
        )
        
        return Uniforms(
            viewportSize: viewportSize,
            zoomLevel: zoomLevel,
            projectionMatrix: projectionMatrix
        )
    }
    
    private func parseColor(_ colorString: String) -> simd_float4 {
        var color = colorString.trimmingCharacters(in: .whitespaces)
        
        // Handle hex colors
        if color.hasPrefix("#") {
            color = String(color.dropFirst())
            
            var rgb: UInt64 = 0
            Scanner(string: color).scanHexInt64(&rgb)
            
            if color.count == 6 {
                // RGB format
                return simd_float4(
                    Float((rgb >> 16) & 0xFF) / 255.0,
                    Float((rgb >> 8) & 0xFF) / 255.0,
                    Float(rgb & 0xFF) / 255.0,
                    1.0
                )
            } else if color.count == 8 {
                // RGBA format
                return simd_float4(
                    Float((rgb >> 24) & 0xFF) / 255.0,
                    Float((rgb >> 16) & 0xFF) / 255.0,
                    Float((rgb >> 8) & 0xFF) / 255.0,
                    Float(rgb & 0xFF) / 255.0
                )
            }
        }
        
        // Default to blue if parsing fails
        return simd_float4(0.2, 0.5, 1.0, 1.0)
    }
}

// MARK: - Metal Shaders (would be in separate .metal file in full implementation)
/*
 Metal shaders would include:
 
 vertex VertexOut triangleVertexShader(uint vid [[vertex_id]],
                                       uint iid [[instance_id]],
                                       constant TriangleInstance* instances [[buffer(0)]],
                                       constant Uniforms& uniforms [[buffer(1)]]) {
     // Generate triangle vertices and transform to screen space
     const float2 vertices[6] = {
         float2(-1, -1), float2(1, -1), float2(0, 1),   // First triangle
         float2(-1, -1), float2(1, -1), float2(1, 1)    // Second triangle (for quad if needed)
     };
     
     TriangleInstance instance = instances[iid];
     float2 vertex = vertices[vid];
     
     // Apply scaling and rotation
     float c = cos(instance.rotation);
     float s = sin(instance.rotation);
     float2x2 rotation = float2x2(float2(c, -s), float2(s, c));
     
     vertex = rotation * (vertex * instance.radius);
     vertex += instance.position * uniforms.viewportSize;
     
     float4 position = uniforms.projectionMatrix * float4(vertex, 0, 1);
     
     VertexOut out;
     out.position = position;
     out.color = instance.color * instance.opacity;
     out.uv = vertices[vid];
     return out;
 }
 
 fragment float4 triangleFragmentShader(VertexOut in [[stage_in]]) {
     // Render SDF triangle with fill, stroke, blur, etc.
     float dist = /* SDF triangle distance calculation */;
     float alpha = smoothstep(0.5, 0.5 - fwidth(dist), dist);
     return float4(in.color.rgb, in.color.a * alpha);
 }
 */