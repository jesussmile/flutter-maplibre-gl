# Hillshading Support in FlightCanvas Terrain

This document provides a detailed explanation of the hillshading implementation in the FlightCanvas Terrain plugin, which enhances the visual representation of terrain elevation data.

## Overview

Hillshading is a technique used to create a 3D-like visual effect on terrain maps by simulating the illumination of a surface from a specified light source. It adds depth and relief to otherwise flat elevation data, making it easier to visually interpret terrain features such as mountains, valleys, and ridges.

In the FlightCanvas Terrain plugin, hillshading is implemented as an optional enhancement to terrain visualization that can be combined with other rendering techniques like altitude-based coloring and warning levels.

## Principles of Hillshading

### Slope and Aspect Calculation

Hillshading is based on two fundamental terrain properties:

1. **Slope**: The steepness or gradient of the terrain at a given point
2. **Aspect**: The direction or orientation of the slope (which way the slope faces)

These properties are calculated using surrounding elevation points in a 3x3 grid:

```dart
// Calculate slope and aspect from elevation data
double calculateSlope(DecodedLercData data, int x, int y) {
  // Get elevation of center and surrounding cells
  double z = data.getElevation(x, y);
  double zL = data.getElevation(x - 1, y);
  double zR = data.getElevation(x + 1, y);
  double zT = data.getElevation(x, y - 1);
  double zB = data.getElevation(x, y + 1);
  
  // Calculate slope components
  double dzdx = ((zL - z) + (z - zR)) / 2;
  double dzdy = ((zT - z) + (z - zB)) / 2;
  
  // Calculate and return slope in radians
  return math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
}

double calculateAspect(DecodedLercData data, int x, int y) {
  // Get elevation of surrounding cells
  double z = data.getElevation(x, y);
  double zL = data.getElevation(x - 1, y);
  double zR = data.getElevation(x + 1, y);
  double zT = data.getElevation(x, y - 1);
  double zB = data.getElevation(x, y + 1);
  
  // Calculate slope components
  double dzdx = ((zL - z) + (z - zR)) / 2;
  double dzdy = ((zT - z) + (z - zB)) / 2;
  
  // Calculate and return aspect in radians
  return math.atan2(dzdy, -dzdx);
}
```

### Light Source Parameters

The hillshading effect is controlled by two key light source parameters:

1. **Azimuth**: The angular direction of the light source in degrees (0° = north, 90° = east, 180° = south, 270° = west)
2. **Altitude**: The angle of the light source above the horizon in degrees (0° = horizon, 90° = directly overhead)

These parameters are customizable in the FlightCanvas Terrain plugin:

```dart
class HillshadeParams {
  /// Light source azimuth in degrees (0 = north, 90 = east)
  final double azimuth;
  
  /// Light source altitude in degrees above horizon
  final double altitude;
  
  /// Intensity of the hillshading effect (0.0 to 1.0)
  final double intensity;
  
  /// Constructor with default values
  const HillshadeParams({
    this.azimuth = 315.0,  // Northwest light direction
    this.altitude = 45.0,  // 45 degrees above horizon
    this.intensity = 0.5,  // Medium intensity
  });
}
```

The default values of 315° azimuth (northwest) and 45° altitude provide a balanced visualization that works well in most cases.

### Hillshade Value Calculation

The core hillshade calculation combines the slope, aspect, and light source parameters to determine how much light each terrain point receives:

```dart
double calculateHillshade(
  DecodedLercData data, 
  int x, 
  int y, {
  double azimuth = 315.0,
  double altitude = 45.0,
}) {
  // Calculate slope and aspect
  double slope = calculateSlope(data, x, y);
  double aspect = calculateAspect(data, x, y);
  
  // Convert azimuth and altitude to radians
  double azimuthRad = azimuth * math.pi / 180;
  double altitudeRad = altitude * math.pi / 180;
  
  // Calculate hillshade value
  double hillshade = math.cos(altitudeRad) * math.cos(slope) +
      math.sin(altitudeRad) * math.sin(slope) * math.cos(azimuthRad - aspect);
  
  // Scale to 0-1 range
  return math.max(0, hillshade);
}
```

This formula calculates the cosine of the angle between the surface normal (derived from slope and aspect) and the light vector. The result is a value between 0 and 1, where:
- 1 represents maximum illumination (surface facing directly toward the light source)
- 0 represents complete shadow (surface facing away from the light source)

## Implementation in FlightCanvas Terrain

### HillshadeLayer Class

The plugin implements hillshading primarily through the `HillshadeLayer` class, which creates a custom tile layer for rendering hillshaded terrain. This implementation:

1. Creates a custom `TileProvider` that generates hillshaded images
2. Processes each tile by calculating hillshade values for its points
3. Renders the hillshade effect as grayscale images
4. Implements caching to optimize performance

```dart
class HillshadeLayer extends StatelessWidget {
  final DecodedLercData data;

  const HillshadeLayer({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _HillshadeLayerContent(data: data);
  }
}

class HillshadeTileProvider extends TileProvider {
  final DecodedLercData data;
  final Map<String, Uint8List> _renderedPixelCache = {};

  HillshadeTileProvider({required this.data});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _HillshadeTileImage(
      data: data,
      coordinates: coordinates,
      pixelCache: _renderedPixelCache,
    );
  }
}
```

### Tile Rendering Process

Each map tile is rendered through a multi-step process:

1. **Determine Tile Geographic Bounds**: Calculate the latitude/longitude bounds for the current tile
2. **Map to Elevation Data Coordinates**: Convert geographic coordinates to indices in the elevation data array
3. **Calculate Hillshade Values**: For each pixel in the tile, calculate the hillshade value
4. **Apply Bilinear Interpolation**: Use interpolation to handle fractional positions in the elevation data
5. **Render as Grayscale Image**: Convert hillshade values to grayscale pixel data
6. **Cache for Performance**: Store the rendered tile in a cache for reuse

```dart
Uint8List _renderTile() {
  const tileSize = 256;
  final pixels = Uint8List(tileSize * tileSize * 4);

  // Get tile bounds in lat/lon
  final n = math.pow(2.0, coordinates.z).toDouble();
  final lon1 = coordinates.x * 360.0 / n - 180.0;
  final lon2 = (coordinates.x + 1) * 360.0 / n - 180.0;
  final lat1 = _tile2lat(coordinates.y + 1, coordinates.z);
  final lat2 = _tile2lat(coordinates.y, coordinates.z);

  // Convert to data indices with floating point precision for interpolation
  final startXFloat = ((lon1 + 180.0) * data.width / 360.0);
  final endXFloat = ((lon2 + 180.0) * data.width / 360.0);
  final startYFloat = ((90.0 - lat2) * data.height / 180.0);
  final endYFloat = ((90.0 - lat1) * data.height / 180.0);

  // Calculate steps for interpolation
  final xStep = (endXFloat - startXFloat) / tileSize;
  final yStep = (endYFloat - startYFloat) / tileSize;

  for (int y = 0; y < tileSize; y++) {
    for (int x = 0; x < tileSize; x++) {
      // Bilinear interpolation of elevation data
      // Calculate hillshade value
      // Convert to pixel value
      final pixelIndex = (y * tileSize + x) * 4;
      final intensity = hillshadeValue.round().clamp(0, 255);
      pixels[pixelIndex] = intensity;     // R
      pixels[pixelIndex + 1] = intensity; // G
      pixels[pixelIndex + 2] = intensity; // B
      pixels[pixelIndex + 3] = 255;       // A
    }
  }

  return pixels;
}
```

### Bilinear Interpolation for Smooth Hillshading

To achieve smooth hillshading results, the implementation uses bilinear interpolation when sampling elevation data:

```dart
// Get the four surrounding pixel values
final v00 = data.data[dataY * data.width + dataX];
final v10 = data.data[dataY * data.width + dataXNext];
final v01 = data.data[dataYNext * data.width + dataX];
final v11 = data.data[dataYNext * data.width + dataXNext];

// Perform bilinear interpolation
final v0 = v00 * (1 - xFrac) + v10 * xFrac;
final v1 = v01 * (1 - xFrac) + v11 * xFrac;
final value = v0 * (1 - yFrac) + v1 * yFrac;
```

This technique eliminates jagged edges and creates a smoother visualization, especially when zoomed in on the terrain.

## Integration with Terrain Rendering

### Combining Hillshading with Elevation-Based Coloring

While hillshading alone provides a grayscale relief effect, the plugin typically combines it with elevation-based coloring for enhanced visualization:

```dart
Color getCombinedTerrainColor(double elevation, double hillshade) {
  // Get base color from elevation
  Color baseColor = getColorForElevation(elevation);
  
  // Apply hillshading effect by modulating the base color
  return Color.lerp(
    Colors.black,
    Color.lerp(baseColor, Colors.white, hillshade * 0.5)!,
    math.min(1.0, hillshade + 0.4)
  )!;
}
```

This creates a more natural-looking terrain representation where:
- Higher hillshade values lighten the base color (simulating illuminated surfaces)
- Lower hillshade values darken the base color (simulating shadowed surfaces)

### Different Rendering Modes

The plugin supports different ways to integrate hillshading:

1. **Gradient Mode with Hillshading**: Combines smooth elevation-based coloring with hillshading
2. **Stepped Color Mode with Hillshading**: Applies hillshading to discrete color bands
3. **Monochrome Mode with Hillshading**: Uses a single base color with hillshading for a cleaner look
4. **Warning Level Mode with Hillshading**: Applies hillshading to warning level visualization

```dart
Color getTerrainColor(double elevation, double hillshade, RenderMode mode) {
  switch (mode) {
    case RenderMode.gradient:
      return getCombinedTerrainColor(elevation, hillshade);
    case RenderMode.stepped:
      return getSteppedColor(elevation, hillshade);
    case RenderMode.monochrome:
      return getMonochromeWithHillshade(elevation, hillshade);
    case RenderMode.warning:
      return getWarningLevelColor(elevation, referenceAltitude, hillshade);
  }
}
```

## Configuration and Customization

### Adjustable Parameters

The hillshading implementation allows for customization through several parameters:

1. **Light Source Direction (Azimuth)**: Controls the horizontal angle of the light source
2. **Light Source Height (Altitude)**: Controls the vertical angle of the light source
3. **Hillshade Intensity**: Controls the strength of the hillshading effect
4. **Enable/Disable Option**: Allows hillshading to be toggled on or off

```dart
// Configure terrain with custom hillshade parameters
TerrainLayer(
  elevationData: data,
  renderingMode: TerrainRenderingMode.gradient,
  enableHillshading: true,  // Toggle hillshading on/off
  hillshadeParams: HillshadeParams(
    azimuth: 270.0,        // Light from the west
    altitude: 30.0,        // Low sun angle for dramatic shadows
    intensity: 0.7,        // Strong hillshading effect
  ),
);
```

### Runtime Adjustment

The plugin allows for runtime adjustment of hillshading parameters through the `TerrainController`:

```dart
// Example of changing hillshading parameters at runtime
final terrainController = TerrainController();

// Enable/disable hillshading
terrainController.setHillshadingEnabled(true);

// Update hillshade parameters
terrainController.updateHillshadeParams(
  azimuth: 225.0,     // Southwest light direction
  altitude: 60.0,     // Higher sun angle (less dramatic shadows)
  intensity: 0.4,     // Subtle hillshading effect
);
```

## Performance Considerations

### Optimization Techniques

Hillshading can be computationally intensive, especially for large terrain datasets. The plugin implements several optimizations:

1. **Tile-Based Processing**: Only processes visible tiles
2. **Caching**: Caches rendered hillshade tiles
3. **Resolution Management**: Adapts processing detail based on zoom level
4. **Asynchronous Rendering**: Renders tiles without blocking the UI thread

```dart
// Example of caching implementation in HillshadeTileProvider
final Map<String, Uint8List> _renderedPixelCache = {};

String get _renderedImageKey =>
    '${coordinates.x}_${coordinates.y}_${coordinates.z}';

Future<ImageInfo> _createImage() async {
  // Check cache first
  final cachedPixelData = pixelCache[_renderedImageKey];
  if (cachedPixelData != null) {
    return _createImageFromPixels(cachedPixelData, 256, 256);
  }
  
  // Otherwise render the tile
  final pixelData = _renderTile();
  pixelCache[_renderedImageKey] = pixelData;
  return _createImageFromPixels(pixelData, 256, 256);
}
```

### Memory Usage

To manage memory efficiently, especially for devices with limited resources:

1. **Sparse Cache Management**: Automatically removes least recently used tiles from cache
2. **Progressive Quality**: Uses simpler calculations at lower zoom levels
3. **Memory Monitoring**: Adapts cache size based on device capabilities

## Conclusion

The hillshading implementation in the FlightCanvas Terrain plugin enhances terrain visualization by providing a 3D-like effect that makes elevation data more intuitive to interpret. By calculating slope and aspect from the elevation data and simulating illumination from a configurable light source, the plugin creates realistic terrain rendering with shadows and highlights that emphasize landscape features.

The ability to combine hillshading with other visualization techniques like altitude-based coloring and warning levels, and to customize parameters like light direction and intensity, provides a flexible and powerful terrain visualization system suitable for a variety of applications, from aviation to outdoor recreation and geographic analysis.
