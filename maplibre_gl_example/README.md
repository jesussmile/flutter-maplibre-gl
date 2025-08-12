# MapLibre GL Examples

This project demonstrates various features of the flutter-maplibre-gl plugin, including the experimental triangle annotations.

## Featured Examples

### Triangle Annotations (Experimental)

The **Place triangle** example demonstrates the experimental triangle annotation feature:

- **Add triangles**: Create triangle annotations at different positions with various colors
- **Interactive selection**: Tap triangles to select them
- **Property modification**: Change size, color, opacity, stroke, position, and draggable state
- **Lifecycle management**: Add, remove, clear all triangles
- **Implementation**: Uses triangle annotations with fallback to circle rendering

#### Triangle Fallback Behavior

The triangle annotations are experimental and support fallback rendering:

- **With experimental flag enabled**: Renders as true triangles using symbol layers
- **Without the experimental flag**: Falls back to orange circle markers
- **Consistent API**: Same triangle annotation API regardless of fallback state

#### Running Triangle Example

**Triangle Annotations** (with fallback behavior):
- Without experimental flag: Triangle annotations render as orange circles
- With experimental flag: Triangle annotations use symbol-based triangle rendering
```bash
flutter run  # Circle fallback
# or
export MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS=true
flutter run  # Triangle symbols
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


## Resources

- [MapLibre GL Documentation](https://maplibre.org/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Plugin Repository](https://github.com/maplibre/flutter-maplibre-gl)
