# Native Triangle Layer Design

This design mirrors the Circle layer implementation to create a native Triangle layer using GPU shaders on Android and iOS.

## 1. Architecture Overview

- Add a new `TriangleLayer` to the core renderer, analogous to `CircleLayer`
- Implement GPU shader-based rendering for triangles using instanced quads + SDF-like distance functions
- Integrate with tile-based rendering and style system like the circle layer
- Support data-driven styling via expressions
- Scope: Android (OpenGL ES) and iOS (Metal) only in this phase
- Explicitly forbidden: PNG sprites, SDF images, symbol/image fallbacks

## 2. Rendering Approach

Like circles, triangles are point features rendered as screen-space shapes using GPU shaders.

- For each point feature, create a screen-space quad (billboard) in the vertex shader
- Pass per-instance attributes for radius, color, stroke width, rotation, opacity
- In the fragment shader, compute coverage using a signed distance function (SDF) of an equilateral triangle
- Apply anti-aliasing using smoothstep around the SDF boundary
- Apply stroke by rendering the band between outer and inner SDF thresholds

### 2.1 Triangle SDF
- Use analytical SDF for equilateral triangle centered at origin
- Rotate by `triangle-rotation` in shader
- Scale by `triangle-radius`
- Allow `triangle-blur` to widen the anti-aliased boundary
- Do not sample textures or images; render analytically

## 3. Data Flow and GPU Instancing

- Same buffer layout as circle layer for position and feature attributes
- Add attributes specific to triangle:
  - rotation
  - pitch-alignment / rotation-alignment flags
- Reuse circle layer batching and draw call structure

## 4. Style Properties Mapping

Mirror circle properties with triangle equivalents:

- triangle-radius        <=> circle-radius
- triangle-color         <=> circle-color
- triangle-opacity       <=> circle-opacity
- triangle-stroke-width  <=> circle-stroke-width
- triangle-stroke-color  <=> circle-stroke-color
- triangle-stroke-opacity<=> circle-stroke-opacity
- triangle-blur          <=> circle-blur
- triangle-translate     <=> circle-translate
- triangle-translate-anchor <=> circle-translate-anchor
- triangle-pitch-alignment <=> circle-pitch-alignment
- triangle-rotation-alignment <=> circle-pitch-alignment
- triangle-rotation (new)

## 5. Platform Implementation Plan (Android & iOS)

- Android (OpenGL ES): Implement GLSL shaders and pipeline parallel to circle layer; reuse instancing and uniform management
- iOS (Metal): Port GLSL logic to MSL; integrate into Metal render pipeline and resource bindings mirroring circle layer
- Maintain numerical parity between backends (epsilon and AA widths)

## 6. Flutter API Surface

- Add `TriangleLayerProperties` to Flutter package mirroring `CircleLayerProperties`
- Add `Triangle` annotation model object
- Add `TriangleManager` analogous to `CircleManager`
- Add platform channel methods for addTriangleLayer, etc., matching addCircleLayer

## 7. Style Spec Extensions

- Extend MapLibre style spec to include `triangle` layer with defined properties
- Update JSON serialization/deserialization paths

## 8. Expressions and Transitions

- Support all expression types supported by circle layer (get, step, interpolate, match, case, etc.)
- Implement property transitions (duration, delay) consistent with circle layer

## 9. Testing Strategy

- Unit tests for property parsing and GPU pipeline setup
- Visual tests that render triangles at multiple scales/rotations and compare to references
- Performance tests that render 10k triangles and compare to circle layer
- Cross-platform screenshots to validate consistency (Android vs iOS)

## 10. Migration Strategy

- Provide migration helpers to convert from symbol-based triangles to native triangle properties
- Document differences in sizing (radius vs icon-size) and rotation semantics

## 11. Risks & Mitigations

- Shader complexity: Keep SDF math minimal and well-tested
- Cross-platform shader parity: Maintain one reference implementation and port carefully
- Style spec updates: coordinate with MapLibre maintainers, guard behind experimental flag initially
- Strictly forbid any PNG/sprite/image fallbacks to avoid divergence from circle architecture

## 12. Deliverables

- Core rendering changes (Android/iOS) introducing `TriangleLayer`
- Flutter bindings for `TriangleLayerProperties`, `Triangle`, and `TriangleManager`
- Documentation and examples paralleling circle examples
- Benchmarks and visual tests demonstrating parity with circle layer performance and quality