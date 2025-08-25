import MapLibre
import Metal
import MetalKit
import simd

/// Native LERC Canvas Style Layer for iOS
/// Provides real-time, GPU-accelerated terrain rendering with altitude-based coloring
/// Similar to HTML canvas functionality but with native Metal performance
class MLNLercCanvasStyleLayer: MLNCustomStyleLayer {
    
    // MARK: - Properties
    private var metalDevice: MTLDevice?
    private var renderPipelineState: MTLRenderPipelineState?
    private var elevationTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    
    // LERC elevation data
    private var elevationData: [Float] = []
    private var elevationWidth: Int = 0
    private var elevationHeight: Int = 0
    private var elevationBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) = (0, 0, 0, 0)
    
    // Altitude thresholds (in feet, converted from LERC meters)
    private var referenceAltitude: Float = 2000.0  // feet
    private var warningAltitude: Float = 1000.0    // feet
    
    // Performance tracking
    private var lastRenderTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    
    // Layer identifier and state
    private var layerId: String
    private var isInitialized: Bool = false
    
    // MARK: - Initialization
    override init(identifier: String) {
        self.layerId = identifier
        super.init(identifier: identifier)
        setupMetal()
    }
    
    // MARK: - Public API
    
    /// Initialize the layer with LERC elevation data
    /// - Parameters:
    ///   - elevationData: Array of elevation values in meters
    ///   - width: Width of elevation grid
    ///   - height: Height of elevation grid
    ///   - bounds: Geographic bounds (minLat, maxLat, minLon, maxLon)
    func initializeWithElevationData(
        _ elevationData: [Float],
        width: Int,
        height: Int,
        bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) {
        print("🚀 MLNLercCanvasStyleLayer: Initializing with \(width)x\(height) elevation data")
        
        self.elevationData = elevationData
        self.elevationWidth = width
        self.elevationHeight = height
        self.elevationBounds = bounds
        
        // Create elevation texture
        createElevationTexture()
        
        self.isInitialized = true
        print("✅ MLNLercCanvasStyleLayer: Initialization complete")
    }
    
    /// Update altitude thresholds for real-time coloring changes
    /// - Parameters:
    ///   - referenceAltitude: Reference altitude in feet
    ///   - warningAltitude: Warning altitude in feet
    func updateAltitudes(referenceAltitude: Float, warningAltitude: Float) {
        print("⚡ MLNLercCanvasStyleLayer: Updating altitudes - ref: \(referenceAltitude)ft, warn: \(warningAltitude)ft")
        
        self.referenceAltitude = referenceAltitude
        self.warningAltitude = warningAltitude
        
        // Trigger redraw
        setNeedsDisplay()
    }
    
    // MARK: - Metal Setup
    
    private func setupMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        guard let device = metalDevice else {
            print("❌ MLNLercCanvasStyleLayer: Metal device creation failed")
            return
        }
        
        print("🔧 MLNLercCanvasStyleLayer: Setting up Metal pipeline")
        
        // Create Metal shaders
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexIn {
            float2 position [[attribute(0)]];
            float2 texCoord [[attribute(1)]];
        };
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        struct Uniforms {
            float4x4 projectionMatrix;
            float2 mapBounds_min;  // Bottom-left corner in map coordinates
            float2 mapBounds_max;  // Top-right corner in map coordinates
            float referenceAltitude; // Reference altitude in meters (converted from feet)
            float warningAltitude;   // Warning altitude in meters (converted from feet)
            float zoomLevel;
        };
        
        vertex VertexOut lercCanvasVertexShader(VertexIn vertexIn [[stage_in]],
                                                constant Uniforms& uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.projectionMatrix * float4(vertexIn.position, 0.0, 1.0);
            out.texCoord = vertexIn.texCoord;
            return out;
        }
        
        fragment float4 lercCanvasFragmentShader(VertexOut in [[stage_in]],
                                                 texture2d<float> elevationTexture [[texture(0)]],
                                                 constant Uniforms& uniforms [[buffer(1)]]) {
            constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
            
            // Sample elevation from texture (elevation in meters)
            float elevation = elevationTexture.sample(textureSampler, in.texCoord).r;
            
            // Convert elevation from meters to feet for comparison
            float elevationFeet = elevation * 3.28084;
            
            // Determine color based on altitude thresholds
            float4 color;
            
            if (elevationFeet >= uniforms.referenceAltitude) {
                // Above reference altitude - RED (danger zone)
                color = float4(1.0, 0.0, 0.0, 0.8);  // Red with transparency
            } else if (elevationFeet >= uniforms.warningAltitude) {
                // Between warning and reference - YELLOW (caution zone)
                color = float4(1.0, 1.0, 0.0, 0.6);  // Yellow with transparency
            } else {
                // Below warning altitude - safe, no rendering
                color = float4(0.0, 0.0, 0.0, 0.0);  // Transparent
            }
            
            // Add subtle transparency based on zoom for better visibility
            float zoomFactor = clamp(uniforms.zoomLevel / 15.0, 0.5, 1.0);
            color.a *= zoomFactor;
            
            return color;
        }
        """
        
        // Create Metal library from source
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "lercCanvasVertexShader")
            let fragmentFunction = library.makeFunction(name: "lercCanvasFragmentShader")
            
            // Create render pipeline descriptor
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Enable blending for transparency
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            // Create vertex buffer for a full-screen quad
            let vertices: [Float] = [
                // Position,  TexCoord
                -1.0, -1.0,   0.0, 0.0,  // Bottom-left
                 1.0, -1.0,   1.0, 0.0,  // Bottom-right
                -1.0,  1.0,   0.0, 1.0,  // Top-left
                 1.0,  1.0,   1.0, 1.0   // Top-right
            ]
            vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
            
            print("✅ MLNLercCanvasStyleLayer: Metal pipeline setup complete")
        } catch {
            print("❌ MLNLercCanvasStyleLayer: Pipeline state creation failed: \(error)")
        }
    }
    
    private func createElevationTexture() {
        guard let device = metalDevice, !elevationData.isEmpty else {
            print("❌ MLNLercCanvasStyleLayer: Cannot create texture - no device or data")
            return
        }
        
        print("🖼️ MLNLercCanvasStyleLayer: Creating elevation texture \(elevationWidth)x\(elevationHeight)")
        
        // Create texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: elevationWidth,
            height: elevationHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        // Create texture
        elevationTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // Upload elevation data
        elevationData.withUnsafeBytes { bytes in
            elevationTexture?.replace(
                region: MTLRegionMake2D(0, 0, elevationWidth, elevationHeight),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: elevationWidth * MemoryLayout<Float>.size
            )
        }
        
        print("✅ MLNLercCanvasStyleLayer: Elevation texture created and uploaded")
    }
    
    // MARK: - MLNCustomStyleLayer Override
    
    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        // Track performance
        let currentTime = CACurrentMediaTime()
        if lastRenderTime > 0 {
            let deltaTime = currentTime - lastRenderTime
            frameCount += 1
            if frameCount % 60 == 0 {
                let fps = 1.0 / deltaTime
                print("📊 MLNLercCanvasStyleLayer: FPS: \(fps.rounded())")
            }
        }
        lastRenderTime = currentTime
        
        // Check if we're initialized and ready to render
        guard isInitialized,
              let renderEncoder = self.renderEncoder,
              let pipelineState = renderPipelineState,
              let texture = elevationTexture,
              let buffer = vertexBuffer else {
            return
        }
        
        // Set render pipeline state
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Create uniforms
        var uniforms = createUniforms(from: context, mapView: mapView)
        
        // Set vertex buffer and uniforms
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        
        // Draw full-screen quad using triangle strip
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    // MARK: - Helper Methods
    
    private struct Uniforms {
        var projectionMatrix: simd_float4x4
        var mapBounds_min: simd_float2
        var mapBounds_max: simd_float2
        var referenceAltitude: Float  // In meters
        var warningAltitude: Float    // In meters
        var zoomLevel: Float
    }
    
    private func createUniforms(from context: MLNStyleLayerDrawingContext, mapView: MLNMapView) -> Uniforms {
        // Create orthographic projection matrix
        let projectionMatrix = simd_float4x4(
            simd_float4(2.0 / Float(context.size.width), 0, 0, 0),
            simd_float4(0, -2.0 / Float(context.size.height), 0, 0),
            simd_float4(0, 0, -1, 0),
            simd_float4(-1, 1, 0, 1)
        )
        
        // Get current map bounds
        let visibleBounds = mapView.visibleCoordinateBounds
        let mapBounds_min = simd_float2(
            Float(visibleBounds.sw.longitude),
            Float(visibleBounds.sw.latitude)
        )
        let mapBounds_max = simd_float2(
            Float(visibleBounds.ne.longitude),
            Float(visibleBounds.ne.latitude)
        )
        
        return Uniforms(
            projectionMatrix: projectionMatrix,
            mapBounds_min: mapBounds_min,
            mapBounds_max: mapBounds_max,
            referenceAltitude: referenceAltitude * 0.3048, // Convert feet to meters
            warningAltitude: warningAltitude * 0.3048,     // Convert feet to meters
            zoomLevel: Float(context.zoomLevel)
        )
    }
    
    // MARK: - Cleanup
    
    func dispose() {
        print("🗑️ MLNLercCanvasStyleLayer: Disposing resources")
        
        elevationTexture = nil
        vertexBuffer = nil
        renderPipelineState = nil
        elevationData.removeAll()
        isInitialized = false
        
        print("✅ MLNLercCanvasStyleLayer: Disposed")
    }
    
    deinit {
        dispose()
    }
}
