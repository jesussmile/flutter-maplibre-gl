# Native Triangle Layer Requirements

## Overview
Implement a native triangle layer in MapLibre GL that renders triangles using GPU shaders, following the exact same architectural pattern as the existing circle layer implementation.

**Scope**: Android and iOS platforms only (no web or macOS in this phase)
**Approach**: Strictly native GPU shader rendering - no PNG generation, no symbol/image fallbacks

## Core Requirements

### 1. Native Layer Type
- **REQ-1.1**: Create a new `triangle` layer type in MapLibre GL core, similar to `circle` layer
- **REQ-1.2**: Triangle rendering must be handled entirely by GPU shaders (no image generation)
- **REQ-1.3**: Triangles must be rendered as native geometric primitives, not as symbols or fills
- **REQ-1.4**: Explicitly forbidden: PNG generation, sprite images, SDF images, or any symbol-based fallback

### 2. Triangle Properties (Mirror Circle Properties)
Based on circle layer properties, implement equivalent triangle properties:

#### Paint Properties
- **REQ-2.1**: `triangle-radius` - Size of the triangle from center to vertex (equivalent to `circle-radius`)
- **REQ-2.2**: `triangle-color` - Fill color of the triangle (equivalent to `circle-color`)
- **REQ-2.3**: `triangle-opacity` - Opacity of the triangle fill (equivalent to `circle-opacity`)
- **REQ-2.4**: `triangle-stroke-width` - Width of triangle outline (equivalent to `circle-stroke-width`)
- **REQ-2.5**: `triangle-stroke-color` - Color of triangle outline (equivalent to `circle-stroke-color`)
- **REQ-2.6**: `triangle-stroke-opacity` - Opacity of triangle outline (equivalent to `circle-stroke-opacity`)
- **REQ-2.7**: `triangle-blur` - Blur effect for triangle edges (equivalent to `circle-blur`)
- **REQ-2.8**: `triangle-translate` - Translation offset (equivalent to `circle-translate`)
- **REQ-2.9**: `triangle-translate-anchor` - Translation anchor point (equivalent to `circle-translate-anchor`)

#### Additional Triangle-Specific Properties
- **REQ-2.10**: `triangle-rotation` - Rotation angle in degrees (0° = pointing up)
- **REQ-2.11**: `triangle-pitch-alignment` - How triangle aligns with map pitch (`map` or `viewport`)
- **REQ-2.12**: `triangle-rotation-alignment` - How triangle rotation aligns (`map` or `viewport`)

### 3. Data-Driven Styling Support
- **REQ-3.1**: All triangle properties must support data-driven expressions (like circles)
- **REQ-3.2**: Support for interpolation expressions for smooth scaling and color transitions
- **REQ-3.3**: Support for categorical styling based on feature properties

### 4. Performance Requirements
- **REQ-4.1**: Triangle rendering performance must match circle layer performance
- **REQ-4.2**: Must efficiently handle thousands of triangles without performance degradation
- **REQ-4.3**: GPU memory usage should be minimal and comparable to circles

### 5. Platform Support (Android & iOS Only)
- **REQ-5.1**: Native implementation required for:
  - Android (OpenGL ES)
  - iOS (Metal)
- **REQ-5.2**: Consistent rendering between Android and iOS platforms
- **REQ-5.3**: No web or macOS support in this implementation phase

### 6. Flutter Integration
- **REQ-6.1**: Create `TriangleLayerProperties` class mirroring `CircleLayerProperties`
- **REQ-6.2**: Create `Triangle` annotation class mirroring `Circle` annotation class
- **REQ-6.3**: Create `TriangleManager` class mirroring `CircleManager` class
- **REQ-6.4**: Seamless integration with existing annotation management system

### 7. API Consistency
- **REQ-7.1**: Triangle layer API must be identical in structure to circle layer API
- **REQ-7.2**: Property naming conventions must follow circle layer patterns
- **REQ-7.3**: JSON serialization format must follow MapLibre GL style specification

### 8. Geometry Definition
- **REQ-8.1**: Triangles are defined by center point coordinates (like circles)
- **REQ-8.2**: Triangle shape is equilateral by default
- **REQ-8.3**: Triangle orientation: 0° rotation points upward (north)
- **REQ-8.4**: Radius defines distance from center to any vertex

### 9. Coordinate System Integration
- **REQ-9.1**: Triangles must respect map projection and zoom levels
- **REQ-9.2**: Triangle size must scale appropriately with zoom (pixel-based sizing)
- **REQ-9.3**: Proper handling of antimeridian crossing
- **REQ-9.4**: Correct rendering at different map pitch angles

### 10. Shader Requirements
- **REQ-10.1**: Vertex shader must handle triangle geometry generation
- **REQ-10.2**: Fragment shader must handle fill, stroke, and blur effects using SDF approach
- **REQ-10.3**: Efficient instancing for multiple triangles
- **REQ-10.4**: Proper depth testing and blending
- **REQ-10.5**: No texture or image sampling - pure mathematical rendering

### 11. Testing Requirements
- **REQ-11.1**: Unit tests for all triangle properties
- **REQ-11.2**: Visual regression tests comparing triangles to reference images
- **REQ-11.3**: Performance benchmarks against circle layer
- **REQ-11.4**: Cross-platform rendering consistency tests (Android vs iOS)

### 12. Documentation Requirements
- **REQ-12.1**: Complete API documentation for triangle layer
- **REQ-12.2**: Migration guide from symbol-based triangles to native triangles (emphasizing no PNG usage)
- **REQ-12.3**: Performance comparison documentation
- **REQ-12.4**: Examples and tutorials

## Success Criteria
1. Triangle layer performs identically to circle layer in all performance metrics
2. Visual quality matches or exceeds current symbol-based triangle implementation
3. API is intuitive and consistent with existing MapLibre GL patterns
4. Zero breaking changes to existing functionality
5. Cross-platform rendering is pixel-perfect consistent between Android and iOS
6. No image/PNG generation or symbol-based rendering is used anywhere in the implementation