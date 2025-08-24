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
    override init(identifier: String) {
        super.init(identifier: identifier)
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
        let radius = Float(triangleProperties["triangle-size"] ?? triangleProperties["triangle-radius"] ?? "10") ?? 10.0
        let color = parseColor(triangleProperties["triangle-color"] ?? "#3388ff")
        let opacity = Float(triangleProperties["triangle-opacity"] ?? "1.0") ?? 1.0
        let strokeWidth = Float(triangleProperties["triangle-stroke-width"] ?? "0") ?? 0.0
        let strokeColor = parseColor(triangleProperties["triangle-stroke-color"] ?? "#000000")
        let blur = Float(triangleProperties["triangle-blur"] ?? "0") ?? 0.0
        let rotation = Float(triangleProperties["triangle-rotation"] ?? "0") ?? 0.0 * .pi / 180.0 // Convert degrees to radians
        
        // Create sample instances - in practice these would come from source features
        instances = [
            TriangleInstance(
                position: simd_float2(0.5, 0.5), // Normalized coordinates (center of screen)
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
    
    // MARK: - MLNCustomStyleLayer Override
    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        // Check if Metal is available and get the render encoder
        guard let renderEncoder = self.renderEncoder else {
            print("No Metal render encoder available - Metal backend may not be active")
            return
        }
        
        // Setup Metal on first draw
        if renderPipelineState == nil {
            setupMetal()
        }
        
        // Exit early if setup failed
        guard let pipelineState = renderPipelineState else {
            print("Triangle custom layer not properly initialized")
            return
        }
        
        // Exit early if no instances to draw
        guard !instances.isEmpty else {
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
        
        // Set vertex buffers and uniforms
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
    
    // MARK: - Cleanup
    deinit {
        // Metal buffers are reference counted and will be cleaned up automatically
    }
}
