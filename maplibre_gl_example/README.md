# MapLibre GL Examples

This project demonstrates various features of the flutter-maplibre-gl plugin, including the experimental triangle annotation layer.

## Featured Examples

### Triangle Annotations (Experimental)

#### 1. Place Triangle (Annotation-based)
The **Place triangle** example demonstrates the experimental triangle annotation feature:

- **Add triangles**: Create triangle annotations at different positions with various colors
- **Interactive selection**: Tap triangles to select them
- **Property modification**: Change size, color, opacity, stroke, position, and draggable state
- **Lifecycle management**: Add, remove, clear all triangles
- **Implementation**: Uses triangle annotations with fallback to circle rendering

#### 2. Native Triangle Layer (TAS-19)
The **Native triangle layer** example demonstrates the native GPU-based triangle layer implementation:

- **Native GPU rendering**: Uses OpenGL ES/Metal shaders for triangle rendering
- **Layer-based approach**: Creates triangle layers with GeoJSON data sources
- **Data-driven styling**: Supports expressions for dynamic size, color, and rotation
- **Performance**: Optimized for rendering thousands of triangles
- **Experimental feature**: Requires `MapLibreExperimentalFeatures.triangles`

#### Triangle Fallback Behavior

The triangle layer is experimental and supports fallback rendering:

- **With `MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS=true`**: Renders as true triangles
- **Without the environment variable**: Falls back to orange circle markers
- **iOS Fallback**: Uses `addTriangleLayerFallback` method to convert triangle properties to circle properties
- **Consistent API**: Same triangle annotation API regardless of fallback state

#### Running Triangle Examples

1. **Triangle Annotations** (fallback behavior):
   - Without experimental flag: Triangle annotations render as orange circles
   - With experimental flag: Triangle annotations use native triangle rendering
   ```bash
   flutter run  # Circle fallback
   # or
   export MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS=true
   flutter run  # Native triangles
   ```

2. **Native Triangle Layer** (TAS-19 implementation):
   - Always requires experimental flag enabled
   - Demonstrates native GPU-based triangle layer
   ```bash
   export MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS=true
   flutter run
   # Then select "Native triangle layer" from the examples list
   ```

### Other Examples

The example app includes demonstrations of:
- Map UI controls and camera movement
- Symbols, circles, fills, and lines
- Custom markers and batch annotations
- PMTiles and local style loading
- GPS location and offline regions
- And much more!

## Getting Started

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the example app**:
   ```bash
   flutter run
   ```

3. **Browse examples**: Select any example from the main menu to see it in action

## Triangle API Usage

### Triangle Annotations API

```dart
// Enable experimental triangles in MapLibreMap
MapLibreMap(
  experimentalFeatures: MapLibreExperimentalFeatures.triangles,
  // ... other properties
)

// Add a triangle annotation
controller.addTriangle(
  TriangleOptions(
    geometry: LatLng(lat, lng),
    triangleColor: "#FF6B35",
    triangleSize: 15.0,
    triangleOpacity: 0.8,
    triangleStrokeWidth: 2.0,
    triangleStrokeColor: "#FFFFFF",
    draggable: true,
  ),
);

// Update triangle properties
controller.updateTriangle(triangle, TriangleOptions(
  triangleSize: 25.0,
  triangleColor: "#FF0000",
));

// Remove triangle
controller.removeTriangle(triangle);

// Clear all triangles
controller.clearTriangles();
```

### Native Triangle Layer API (TAS-19)

```dart
// Enable experimental features
MapLibreMap(
  experimentalFeatures: MapLibreExperimentalFeatures.triangles,
  // ... other properties
)

// Add GeoJSON source with triangle points
await controller.addGeoJsonSource("triangle-source", {
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"size": 20, "color": "#FF6B35"},
      "geometry": {
        "type": "Point",
        "coordinates": [lng, lat]
      }
    }
  ]
});

// Add native triangle layer
await controller.addTriangleLayer(
  "triangle-source",
  "triangle-layer",
  TriangleLayerProperties(
    triangleSize: ["get", "size"],  // Data-driven size
    triangleColor: ["get", "color"], // Data-driven color
    triangleOpacity: 0.8,
    triangleStrokeWidth: 2.0,
    triangleStrokeColor: "#FFFFFF",
    triangleRotation: [
      "*", ["get", "size"], 3  // Rotation based on size
    ],
  ),
  enableInteraction: true,
);

// Update layer properties with expressions
await controller.setLayerProperties("triangle-layer", 
  TriangleLayerProperties(
    triangleSize: [
      "interpolate", ["linear"], ["zoom"],
      8, 10,   // Size 10 at zoom 8
      16, 40   // Size 40 at zoom 16
    ],
  )
);
```

## Resources

- [MapLibre GL Documentation](https://maplibre.org/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Plugin Repository](https://github.com/maplibre/flutter-maplibre-gl)
