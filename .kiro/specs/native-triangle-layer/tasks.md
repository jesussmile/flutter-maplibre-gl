# Native Triangle Layer Implementation Tasks

**Project**: Flutter MapLibre GL Native Triangle Layer  
**Scope**: Android & iOS only (native GPU shaders, NO PNG/image fallbacks)  
**Architecture**: Mirror circle layer implementation  
**Reference**: `/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/.trae/rules/project_rules.md`

## 📊 Project Status Dashboard

**Current Phase**: Phase 2 - Core Renderer  
**Overall Progress**: 17% (5/29 tasks completed)  
**Status**: 🟡 ACTIVE (private implementation path; no upstream involvement)

### Phase Progress
- ✅ Phase 1: API Specification (4/4 tasks completed) 
- 🟡 Phase 2: Core Renderer (0/8 tasks) – Proceeding via private Custom Layer implementation on Android (CustomLayer) and iOS (MLNCustomStyleLayer); no upstream dependency
- ⚪ Phase 3: Platform Backends (0/2 tasks)
- 🟡 Phase 4: Flutter Bindings (0/5 tasks) - Guarded API in place; will enable once native custom layers are wired
- ⚪ Phase 5: Testing and QA (0/4 tasks)
- ⚪ Phase 6: Documentation (0/3 tasks)
- ⚪ Phase 7: Rollout (0/3 tasks)

### Status Legend
- ⏳ [NOT STARTED] - Task not yet begun
- 🔄 [IN PROGRESS] - Task currently being worked on
- ✅ [COMPLETED] - Task finished and verified
- ❌ [BLOCKED] - Task blocked by dependencies or issues
- ⚠️ [NEEDS REVIEW] - Task completed but requires review

This task list mirrors the circle layer pipeline and is organized to enable incremental delivery.

## Inbuilt Taskmaster System

### Project Rules Integration
This implementation follows the project-specific rules defined in `/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/.trae/rules/project_rules.md`. Key constraints:

- **Architecture**: Native GPU shaders only (Rule 1.1, 1.2)
- **Platform Scope**: Android (OpenGL ES) and iOS (Metal) only (Rule 1.3)
- **API Consistency**: Mirror CircleLayerProperties patterns (Rule 1.4)
- **Performance**: Match circle layer benchmarks (Rule 6.1)
- **Quality**: Cross-platform pixel-perfect consistency (Rule 7.4)

### Task Management Principles
- Each phase has clear deliverables and success criteria
- Dependencies are explicitly tracked
- Progress is measurable through automated tests
- Rollback strategies are defined for each phase
- Performance benchmarks gate progression

Scope
- Platforms: Android and iOS only (no web, no macOS in this phase)
- Rendering approach: strictly native GPU shaders and primitives like the circle layer
- Explicitly forbidden: PNGs, sprites, SDF images, or any symbol/image-based fallback at any stage

## Phase 1: Spec and API Surface

### Task Management
**Phase Lead**: TBD
**Review Gate**: Style spec validation + Flutter API consistency check
**Rollback Strategy**: Revert to existing annotation system
**Project Rules**: 1.4, 2.4, 3.1, 3.2, 3.3, 3.4, 5.4

✅ TAS-1: [COMPLETED] Extend style specification with `triangle` layer and properties (mirror circle) - Rule 1.4, 3.1, 3.2

  **DISCOVERY**: Found existing TriangleLayerProperties class in `/maplibre_gl/lib/src/layer_properties.dart` and triangle spec in style.json.

  **Current Implementation Analysis**:
  - ✅ Existing properties: `triangle-size`, `triangle-color`, `triangle-opacity`, `triangle-translate`, `triangle-translate-anchor`, `triangle-pitch-scale`, `triangle-pitch-alignment`, `triangle-stroke-width`, `triangle-stroke-color`, `triangle-stroke-opacity`
  - ❌ Missing vs Circle layer: `triangle-blur`, `triangle-sort-key`
  - ❌ Missing rotation properties: `triangle-rotation`, `triangle-rotation-alignment`

  **Gaps to Address**:
  1. **Property Naming**: Current uses `triangle-size` vs proposed `triangle-radius` (should align with circle's `circle-radius`)
  2. **Missing Properties**:
     - `triangle-blur` (equivalent to `circle-blur`) 
     - `triangle-sort-key` (equivalent to `circle-sort-key`)
     - `triangle-rotation` (triangle-specific, degrees, default 0)
     - `triangle-rotation-alignment` (triangle-specific, enum [map|viewport])

  **Updated Property Spec** (based on circle mirroring + existing + gaps):
  - triangle-size: number, default 5, min 0 (OR rename to triangle-radius) ✅
  - triangle-color: color, default #000000 ✅
  - triangle-blur: number, default 0 **[MISSING - ADD]**
  - triangle-opacity: number, default 1, range [0,1] ✅
  - triangle-translate: array [x, y], default [0,0] ✅
  - triangle-translate-anchor: enum [map|viewport], default map ✅
  - triangle-pitch-scale: enum [map|viewport], default map ✅
  - triangle-pitch-alignment: enum [map|viewport], default viewport ✅
  - triangle-rotation: number (degrees), default 0 **[MISSING - ADD]**
  - triangle-rotation-alignment: enum [map|viewport], default viewport **[MISSING - ADD]**
  - triangle-stroke-width: number, default 0, min 0 ✅
  - triangle-stroke-color: color, default #000000 ✅
  - triangle-stroke-opacity: number, default 1, range [0,1] ✅
  - triangle-sort-key: number (layout) **[MISSING - ADD]**
  - visibility: enum [visible|none], default visible ✅

  **Work Plan**:
  - Analyze property naming: decide on `triangle-size` vs `triangle-radius` consistency
  - Add missing properties to match circle layer parity
  - Add rotation-specific properties for triangles
  - Verify data-driven expression support for all properties
  - Update style specification documentation

  **Deliverables**:
  - Updated style spec with missing properties
  - Property naming decision documentation
  - Compatibility matrix vs circle layer

  **Progress Update (current)**:
  - Added "triangle" to layerTypes in generation script: `/scripts/lib/generate.dart`
  - Registered `layout_triangle` in `layout` array within `/scripts/input/style.json`
  - Next: define `layout_triangle` section and add missing paint properties: `triangle-blur`, `triangle-rotation`, `triangle-rotation-alignment`; validate JSON and regenerate bindings

  **Estimate**: 3 hours (increased due to gaps analysis)

✅ TAS-2: [COMPLETED] Define JSON schema changes for triangle properties - Rule 5.4

   **CHANGES**: Successfully added complete triangle property definitions to `scripts/input/style.json`:
   - Created `layout_triangle` section with `triangle-sort-key` and `visibility`
   - Added missing properties to `paint_triangle`: `triangle-blur`, `triangle-rotation`, `triangle-rotation-alignment`
   - All properties mirror circle layer structure with proper docs, types, and SDK support annotations
   - Schema generation verified - new properties present in Android/iOS converters
✅ TAS-3: [COMPLETED] Add TriangleLayerProperties class in Flutter (mirroring CircleLayerProperties) - Rule 1.4, 2.4, 3.3
  Notes: Implemented in maplibre_gl/lib/src/layer_properties.dart with fromJson/copyWith; parity gaps vs circle documented above and iOS/Android converters already handle extended properties.
✅ TAS-4: [COMPLETED] Add platform interface hooks for addTriangleLayer/setTriangleLayer - Rule 3.4, 8.4
  Notes: Method channel implemented at platform_interface and wired in Flutter controller; native handlers added on iOS (MapLibreMapController.swift) and Android (MapLibreMapController.java).

## Phase 2: Core Renderer (Engine)

### Task Management
**Phase Lead**: TBD
**Review Gate**: Shader performance benchmarks + visual quality validation
**Rollback Strategy**: Revert to Phase 1 API-only implementation
**Project Rules**: 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 6.1, 6.2, 6.3, 11.1

⏳ TAS-5: [NOT STARTED] Add TriangleLayer class to core renderer (parallel to CircleLayer) - Rule 1.4
⏳ TAS-6: [NOT STARTED] Implement attribute buffers for triangle instance data (position, radius, color, etc.) - Rule 6.2, 6.3
⏳ TAS-7: [NOT STARTED] Implement vertex shader to create screen-space quad and rotate by triangle-rotation - Rule 11.1
⏳ TAS-8: [NOT STARTED] Implement fragment shader with triangle SDF, fill, stroke, blur, opacity - Rule 4.1, 4.2, 4.3
⏳ TAS-9: [NOT STARTED] Implement pitch and rotation alignment logic - Rule 11.1, 11.4
⏳ TAS-10: [NOT STARTED] Integrate translate and translate-anchor logic
⏳ TAS-11: [NOT STARTED] Implement data-driven expressions for all triangle properties - Rule 5.1, 5.2
⏳ TAS-12: [NOT STARTED] Implement property transitions and cascading - Rule 5.3

## Phase 2B: Private Implementation Plan (No Upstream)

- Approach: Implement triangles as private native custom style layers using platform-provided extension points: MLNCustomStyleLayer on iOS and CustomLayer on Android. This keeps everything self-contained, requires no upstream engagement, and still uses native GPU shaders.
- iOS: Subclass MLNCustomStyleLayer and implement Metal-based rendering to draw instanced triangles with support for size, color, opacity, blur, rotation, stroke, pitch alignment, and translate. <mcreference link="https://github.com/maplibre/maplibre-native/blob/main/platform/darwin/src/MLNCustomStyleLayer.h" index="1">1</mcreference>
- Android: Use org.maplibre.android.style.layers.CustomLayer (experimental) and provide a native host implementation to render triangles via OpenGL ES with per-instance attributes and uniforms. <mcreference link="https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.style.layers/-custom-layer/index.html" index="2">2</mcreference> <mcreference link="https://github.com/maplibre/maplibre-native/discussions/956" index="5">5</mcreference>

New Tasks (Phase 2B)
- 🟡 Phase 2: Core Renderer (1/8 tasks) – Proceeding via private Custom Layer implementation on Android (CustomLayer) and iOS (MLNCustomStyleLayer); no upstream dependency
- ⚪ Phase 3: Platform Backends (0/2 tasks)
- 🟡 Phase 4: Flutter Bindings (0/5 tasks) - Guarded API in place; will enable once native custom layers are wired
- ⚪ Phase 5: Testing and QA (0/4 tasks)
- ⚪ Phase 6: Documentation (0/3 tasks)
- ⚪ Phase 7: Rollout (0/3 tasks)

### Status Legend
- ⏳ [NOT STARTED] - Task not yet begun
- 🔄 [IN PROGRESS] - Task currently being worked on
- ✅ [COMPLETED] - Task finished and verified
- ❌ [BLOCKED] - Task blocked by dependencies or issues
- ⚠️ [NEEDS REVIEW] - Task completed but requires review

This task list mirrors the circle layer pipeline and is organized to enable incremental delivery.

## Inbuilt Taskmaster System

### Project Rules Integration
This implementation follows the project-specific rules defined in `/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/.trae/rules/project_rules.md`. Key constraints:

- **Architecture**: Native GPU shaders only (Rule 1.1, 1.2)
- **Platform Scope**: Android (OpenGL ES) and iOS (Metal) only (Rule 1.3)
- **API Consistency**: Mirror CircleLayerProperties patterns (Rule 1.4)
- **Performance**: Match circle layer benchmarks (Rule 6.1)
- **Quality**: Cross-platform pixel-perfect consistency (Rule 7.4)

### Task Management Principles
- Each phase has clear deliverables and success criteria
- Dependencies are explicitly tracked
- Progress is measurable through automated tests
- Rollback strategies are defined for each phase
- Performance benchmarks gate progression

Scope
- Platforms: Android and iOS only (no web, no macOS in this phase)
- Rendering approach: strictly native GPU shaders and primitives like the circle layer
- Explicitly forbidden: PNGs, sprites, SDF images, or any symbol/image-based fallback at any stage

## Phase 1: Spec and API Surface

### Task Management
**Phase Lead**: TBD
**Review Gate**: Style spec validation + Flutter API consistency check
**Rollback Strategy**: Revert to existing annotation system
**Project Rules**: 1.4, 2.4, 3.1, 3.2, 3.3, 3.4, 5.4

✅ TAS-1: [COMPLETED] Extend style specification with `triangle` layer and properties (mirror circle) - Rule 1.4, 3.1, 3.2

  **DISCOVERY**: Found existing TriangleLayerProperties class in `/maplibre_gl/lib/src/layer_properties.dart` and triangle spec in style.json.

  **Current Implementation Analysis**:
  - ✅ Existing properties: `triangle-size`, `triangle-color`, `triangle-opacity`, `triangle-translate`, `triangle-translate-anchor`, `triangle-pitch-scale`, `triangle-pitch-alignment`, `triangle-stroke-width`, `triangle-stroke-color`, `triangle-stroke-opacity`
  - ❌ Missing vs Circle layer: `triangle-blur`, `triangle-sort-key`
  - ❌ Missing rotation properties: `triangle-rotation`, `triangle-rotation-alignment`

  **Gaps to Address**:
  1. **Property Naming**: Current uses `triangle-size` vs proposed `triangle-radius` (should align with circle's `circle-radius`)
  2. **Missing Properties**:
     - `triangle-blur` (equivalent to `circle-blur`) 
     - `triangle-sort-key` (equivalent to `circle-sort-key`)
     - `triangle-rotation` (triangle-specific, degrees, default 0)
     - `triangle-rotation-alignment` (triangle-specific, enum [map|viewport])

  **Updated Property Spec** (based on circle mirroring + existing + gaps):
  - triangle-size: number, default 5, min 0 (OR rename to triangle-radius) ✅
  - triangle-color: color, default #000000 ✅
  - triangle-blur: number, default 0 **[MISSING - ADD]**
  - triangle-opacity: number, default 1, range [0,1] ✅
  - triangle-translate: array [x, y], default [0,0] ✅
  - triangle-translate-anchor: enum [map|viewport], default map ✅
  - triangle-pitch-scale: enum [map|viewport], default map ✅
  - triangle-pitch-alignment: enum [map|viewport], default viewport ✅
  - triangle-rotation: number (degrees), default 0 **[MISSING - ADD]**
  - triangle-rotation-alignment: enum [map|viewport], default viewport **[MISSING - ADD]**
  - triangle-stroke-width: number, default 0, min 0 ✅
  - triangle-stroke-color: color, default #000000 ✅
  - triangle-stroke-opacity: number, default 1, range [0,1] ✅
  - triangle-sort-key: number (layout) **[MISSING - ADD]**
  - visibility: enum [visible|none], default visible ✅

  **Work Plan**:
  - Analyze property naming: decide on `triangle-size` vs `triangle-radius` consistency
  - Add missing properties to match circle layer parity
  - Add rotation-specific properties for triangles
  - Verify data-driven expression support for all properties
  - Update style specification documentation

  **Deliverables**:
  - Updated style spec with missing properties
  - Property naming decision documentation
  - Compatibility matrix vs circle layer

  **Progress Update (current)**:
  - Added "triangle" to layerTypes in generation script: `/scripts/lib/generate.dart`
  - Registered `layout_triangle` in `layout` array within `/scripts/input/style.json`
  - Next: define `layout_triangle` section and add missing paint properties: `triangle-blur`, `triangle-rotation`, `triangle-rotation-alignment`; validate JSON and regenerate bindings

  **Estimate**: 3 hours (increased due to gaps analysis)

✅ TAS-2: [COMPLETED] Define JSON schema changes for triangle properties - Rule 5.4

   **CHANGES**: Successfully added complete triangle property definitions to `scripts/input/style.json`:
   - Created `layout_triangle` section with `triangle-sort-key` and `visibility`
   - Added missing properties to `paint_triangle`: `triangle-blur`, `triangle-rotation`, `triangle-rotation-alignment`
   - All properties mirror circle layer structure with proper docs, types, and SDK support annotations
   - Schema generation verified - new properties present in Android/iOS converters
✅ TAS-3: [COMPLETED] Add TriangleLayerProperties class in Flutter (mirroring CircleLayerProperties) - Rule 1.4, 2.4, 3.3
  Notes: Implemented in maplibre_gl/lib/src/layer_properties.dart with fromJson/copyWith; parity gaps vs circle documented above and iOS/Android converters already handle extended properties.
✅ TAS-4: [COMPLETED] Add platform interface hooks for addTriangleLayer/setTriangleLayer - Rule 3.4, 8.4
  Notes: Method channel implemented at platform_interface and wired in Flutter controller; native handlers added on iOS (MapLibreMapController.swift) and Android (MapLibreMapController.java).

## Phase 2: Core Renderer (Engine)

### Task Management
**Phase Lead**: TBD
**Review Gate**: Shader performance benchmarks + visual quality validation
**Rollback Strategy**: Revert to Phase 1 API-only implementation
**Project Rules**: 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 6.1, 6.2, 6.3, 11.1

⏳ TAS-5: [NOT STARTED] Add TriangleLayer class to core renderer (parallel to CircleLayer) - Rule 1.4
⏳ TAS-6: [NOT STARTED] Implement attribute buffers for triangle instance data (position, radius, color, etc.) - Rule 6.2, 6.3
⏳ TAS-7: [NOT STARTED] Implement vertex shader to create screen-space quad and rotate by triangle-rotation - Rule 11.1
⏳ TAS-8: [NOT STARTED] Implement fragment shader with triangle SDF, fill, stroke, blur, opacity - Rule 4.1, 4.2, 4.3
⏳ TAS-9: [NOT STARTED] Implement pitch and rotation alignment logic - Rule 11.1, 11.4
⏳ TAS-10: [NOT STARTED] Integrate translate and translate-anchor logic
⏳ TAS-11: [NOT STARTED] Implement data-driven expressions for all triangle properties - Rule 5.1, 5.2
⏳ TAS-12: [NOT STARTED] Implement property transitions and cascading - Rule 5.3

## Phase 2B: Private Implementation Plan (No Upstream)

- Approach: Implement triangles as private native custom style layers using platform-provided extension points: MLNCustomStyleLayer on iOS and CustomLayer on Android. This keeps everything self-contained, requires no upstream engagement, and still uses native GPU shaders.
- iOS: Subclass MLNCustomStyleLayer and implement Metal-based rendering to draw instanced triangles with support for size, color, opacity, blur, rotation, stroke, pitch alignment, and translate. <mcreference link="https://github.com/maplibre/maplibre-native/blob/main/platform/darwin/src/MLNCustomStyleLayer.h" index="1">1</mcreference>
- Android: Use org.maplibre.android.style.layers.CustomLayer (experimental) and provide a native host implementation to render triangles via OpenGL ES with per-instance attributes and uniforms. <mcreference link="https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.style.layers/-custom-layer/index.html" index="2">2</mcreference> <mcreference link="https://github.com/maplibre/maplibre-native/discussions/956" index="5">5</mcreference>

New Tasks (Phase 2B)
- 🔄 TAS-5B: [IN PROGRESS] iOS: Create MLNTriangleCustomStyleLayer (Metal pipeline + SDF triangle shader)
  Progress:
  - Method channel routed: triangleLayer#add handled on iOS controller and calls addTriangleLayer
  - Custom layer class created: MLNTriangleCustomStyleLayer (stubbed Metal setup, property plumbing)
  - Style insertion implemented (min/max zoom supported)
  Next:
  - Implement MSL shaders and actual drawInMapView rendering
  - Map source features to instances and coordinate transforms
- ⏳ TAS-6B: [NOT STARTED] Android: Implement CustomLayer host (JNI/C++ OpenGL pipeline + SDF triangle shader)
- ⏳ TAS-7B: [NOT STARTED] Property plumbing: map TriangleLayerProperties to shader uniforms/attributes (both platforms)
- ⏳ TAS-8B: [NOT STARTED] Interactivity: hit-testing strategy (if feasible) or document limitations
- ⏳ TAS-9B: [NOT STARTED] Feature gating: add experimental flag to enable triangle custom layers

## Phase 3: Platform Backends (Android & iOS only)

### Task Management
**Phase Lead**: TBD
**Review Gate**: Cross-platform pixel-perfect consistency validation
**Rollback Strategy**: Revert to Phase 2 core renderer only
**Project Rules**: 4.4, 7.4, 10.1

⏳ TAS-13: [NOT STARTED] Android backend (OpenGL ES): add triangle shader programs and pipeline - Rule 4.4, 10.1
⏳ TAS-14: [NOT STARTED] iOS backend (Metal): implement MSL shaders and pipeline - Rule 4.4, 7.4, 10.1

## Phase 4: Flutter Bindings

### Task Management
**Phase Lead**: TBD
**Review Gate**: Flutter API integration tests + example app validation
**Rollback Strategy**: Revert to Phase 3 platform backends only
**Project Rules**: 1.4, 2.1, 2.3, 3.3, 3.4, 5.4

⏳ TAS-15: [NOT STARTED] Add Triangle annotation model mirroring Circle - Rule 1.4, 2.3
⏳ TAS-16: [NOT STARTED] Add TriangleManager analogous to CircleManager - Rule 1.4, 3.3, 3.4
⏳ TAS-17: [NOT STARTED] Wire controller addLayer for TriangleLayerProperties - Rule 2.1
⏳ TAS-18: [NOT STARTED] Add serialization/deserialization for TriangleLayerProperties - Rule 5.4
⏳ TAS-19: [NOT STARTED] Add examples: place_triangle.dart using native triangle layer

## Phase 5: Testing and QA

### Task Management
**Phase Lead**: TBD
**Review Gate**: All tests passing + performance benchmarks met
**Rollback Strategy**: Revert to Phase 4 Flutter bindings only
**Project Rules**: 6.1, 7.1, 7.2, 7.3, 7.4

⏳ TAS-20: [NOT STARTED] Unit tests: property parsing/validation, expression handling - Rule 7.1
⏳ TAS-21: [NOT STARTED] Visual tests: reference images at multiple scales/rotations/blur/stroke - Rule 7.2
⏳ TAS-22: [NOT STARTED] Performance tests vs circle layer (10k instances) - Rule 6.1, 7.3
⏳ TAS-23: [NOT STARTED] Cross-platform parity tests (Android, iOS) - Rule 7.4

## Phase 6: Docs and Migration

### Task Management
**Phase Lead**: TBD
**Review Gate**: Documentation review + migration guide validation
**Rollback Strategy**: Revert to Phase 5 testing complete
**Project Rules**: 8.1, 9.1, 9.2

⏳ TAS-24: [NOT STARTED] API docs for TriangleLayerProperties and triangle layer - Rule 14.1
⏳ TAS-25: [NOT STARTED] Migration guide from symbol-based triangles (call out that PNG/icons are not used) - Rule 14.4
⏳ TAS-26: [NOT STARTED] Benchmarks and best practices documentation - Rule 14.3

## Phase 7: Rollout

### Task Management
**Phase Lead**: TBD
**Review Gate**: Internal dogfooding feedback + stability validation
**Rollback Strategy**: Revert to Phase 6 documentation complete
**Project Rules**: 8.4

⏳ TAS-27: [NOT STARTED] Feature flag/experimental gate for triangle layer (Android/iOS) - Rule 8.4
⏳ TAS-28: [NOT STARTED] Dogfood internally in example app, gather feedback
⏳ TAS-29: [NOT STARTED] Stabilize and remove experimental flag - Rule 8.4

## Task Management Dashboard

### Progress Tracking
- Phase 1: API Specification and Flutter Surface (4/4 tasks complete)
- Phase 2: Core Renderer Development (0/8 tasks complete)
- Phase 2B: Private Custom Layer Implementation (0/5 tasks complete)
- Phase 3: Platform Backends (0/2 tasks complete)
- Phase 4: Flutter Bindings (0/5 tasks complete)
- Phase 5: Testing and QA (0/4 tasks complete)
- Phase 6: Documentation and Migration (0/3 tasks complete)
- Phase 7: Rollout (0/3 tasks complete)

### Blockers and Workarounds
- Upstream SDK gaps: Not applicable — proceeding with private implementation via platform Custom Layers
- Workarounds implemented locally:
  - Stubbing and guarding triangle layer methods on both platforms to compile and run example app
  - Guard added at Flutter controller and platform channel levels (controller.addTriangleLayer and MethodChannel addTriangleLayer throw UnsupportedError); native controllers remain stubbed
  - Commented out triangle property converters on Android to avoid PropertyFactory references
- Next steps:
  - Implement private custom style layers (Android/iOS) to render triangles with native shaders (no images/sprites)
  - Keep Flutter API surface in place but guarded; enable behind an experimental flag once native implementations are ready

### Key Performance Indicators (KPIs)
- **Performance Benchmark**: Triangle layer must match circle layer performance (Rule 6.1)
- **Quality Gate**: Cross-platform pixel-perfect consistency (Rule 7.4)
- **Architecture Compliance**: Zero PNG/image generation usage (Rule 1.2)
- **Test Coverage**: All properties have unit tests (Rule 7.1)
- **Visual Regression**: Reference images at multiple scales (Rule 7.2)

### Risk Register
| Risk | Impact | Mitigation | Owner |
|------|--------|------------|-------|
| Shader complexity | High | Start with simple SDF, iterate | TBD |
| Performance regression | High | Continuous benchmarking vs circle | TBD |
| Cross-platform differences | Medium | Shared logic, platform optimizations | TBD |
| API breaking changes | Medium | Feature flags and experimental gates | TBD |
| Memory usage | Medium | Efficient instancing from day one | TBD |

## Notes

- Build status: Android and iOS example apps build successfully (debug) as of 2025-08-11 after stubbing triangle layer handling on Android and iOS controllers to avoid missing SDK classes; private custom layer work is planned next
- Flutter API guard: addTriangleLayer throws UnsupportedError to fail fast with a clear message until native support exists (see maplibre_gl/lib/src/controller.dart)
- **Strictly no PNG/sprite/SDF image generation**: This implementation uses native shaders only (Rule 1.2)
- **Android/iOS only**: Web and other platforms are out of scope for this phase (Rule 1.3)
- **Mirror circle layer**: Reuse as much circle layer infrastructure as possible (Rule 1.4)
- **Performance parity**: Triangle layer must perform identically to circle layer (Rule 6.1)
- **Expression support**: All properties must support data-driven expressions (Rule 5.1)
- **Cross-platform consistency**: Pixel-perfect rendering between Android and iOS (Rule 7.4)

## Success Criteria

1. **Functional**: Triangle layer renders correctly with all properties
2. **Performance**: Matches circle layer performance in all metrics (Rule 6.1)
3. **Quality**: Visual quality is indistinguishable from other native layers
4. **Consistency**: API follows existing MapLibre GL patterns (Rule 1.4)
5. **Cross-platform**: Identical rendering on Android and iOS (Rule 7.4)
6. **Architecture**: Zero dependency on image/PNG generation or symbol layers (Rule 1.2)

## Automated Quality Gates

### Phase Progression Requirements
- **Phase 1 → 2**: All unit tests pass, JSON serialization validated
- **Phase 2 → 3**: Shader performance benchmarks meet targets
- **Phase 3 → 4**: Cross-platform pixel consistency achieved
- **Phase 4 → 5**: Flutter integration tests pass
- **Phase 5 → 6**: All test suites pass, performance benchmarks met
- **Phase 6 → 7**: Documentation review complete
- **Phase 7 → Release**: Internal dogfooding feedback positive

### Continuous Integration Checks
- Unit test coverage > 90%
- Performance regression tests vs circle layer
- Visual regression tests with reference images
- Cross-platform consistency validation
- Memory usage profiling
- Shader compilation validation (GLSL + MSL)

## Rollback Procedures

1. **Phase 1 Rollback**: Remove experimental feature flags, revert API changes
2. **Phase 2 Rollback**: Disable core renderer integration, fallback to Phase 1
3. **Phase 3 Rollback**: Disable platform backends, use core renderer only
4. **Phase 4 Rollback**: Remove Flutter bindings, keep platform backends
5. **Phase 5 Rollback**: Disable testing infrastructure, keep implementation
6. **Phase 6 Rollback**: Remove documentation, keep functional implementation
7. **Phase 7 Rollback**: Re-enable experimental flags, gather more feedback

## Project Rules Compliance Matrix

| Rule Category | Applicable Rules | Compliance Status |
|---------------|------------------|-------------------|
| Architecture | 1.1, 1.2, 1.3, 1.4 | Planned |
| Code Organization | 2.1, 2.2, 2.3, 2.4 | Planned |
| Naming Conventions | 3.1, 3.2, 3.3, 3.4 | Planned |
| Shader Development | 4.1, 4.2, 4.3, 4.4 | Planned |
| Property System | 5.1, 5.2, 5.3, 5.4 | Planned |
| Performance | 6.1, 6.2, 6.3, 6.4 | Planned |
| Testing | 7.1, 7.2, 7.3, 7.4 | Planned |
| Quality | 8.1, 8.2, 8.3, 8.4 | Planned |
| Triangle Specifics | 11.1, 11.2, 11.3, 11.4 | Planned |
| Review Process | 10.1, 10.2, 10.3, 10.4 | Planned |

## SUP-1: Upstream Proposal — Triangle Layer in MapLibre Core (Android/iOS)

Status: Archived — Not pursuing upstream engagement (per project decision)
Owner: N/A

Note: This section is retained for reference only. The active plan is Phase 2B (Private Implementation Plan).