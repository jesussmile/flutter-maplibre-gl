# Terrain Visualization Techniques

This document details the techniques used in the FlightCanvas Terrain plugin for visualizing terrain elevation data.

## Overview

The FlightCanvas Terrain plugin provides terrain visualization capabilities within a Flutter application using data stored in the LERC (Limited Error Raster Compression) format. The visualization process involves several key stages:

1. Decoding LERC-compressed elevation data
2. Processing raw elevation values into a suitable data structure
3. Rendering the terrain using various visualization techniques
4. Optimizing the rendering process for mobile performance

## Elevation Data Processing

### 1. Raw Data Decoding

The first step in terrain visualization is decoding the compressed LERC data:

```dart
// Decode LERC data into raw elevation values
DecodedLercData decodedData = await LercDecoder.decode(lercBytes);
```

The `DecodedLercData` class provides a structured representation of the elevation data:

```dart
class DecodedLercData {
  final Float64List data;
  final int width;
  final int height;
  final double minValue;
  final double maxValue;

  // Methods for accessing elevation at specific coordinates
  double getElevation(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.nan;
    return data[y * width + x];
  }

  // Methods for extracting subregions
  Float64List getRegion(int startX, int startY, int regionWidth, int regionHeight) {
    // Implementation details
  }
}
```

### 2. Coordinate Mapping

The plugin maps between different coordinate systems:

1. **Raster Coordinates**: Pixel positions in the elevation grid (x, y)
2. **Geographic Coordinates**: Latitude and longitude positions (lat, lng)
3. **Map Coordinates**: Positions on the rendered map (relative to zoom level)

```dart
// Example of mapping from geographic to raster coordinates
Point<int> getRasterCoordinates(LatLng position, LatLngBounds bounds) {
  double relativeX = (position.longitude - bounds.west) / (bounds.east - bounds.west);
  double relativeY = (bounds.north - position.latitude) / (bounds.north - bounds.south);
  
  int x = (relativeX * width).round();
  int y = (relativeY * height).round();
  
  return Point(x, y);
}
```

### 3. Data Interpolation

For smoother visualization, especially at higher zoom levels, the plugin implements interpolation between elevation points:

```dart
// Bilinear interpolation example
double getInterpolatedElevation(double x, double y) {
  int x1 = x.floor();
  int y1 = y.floor();
  int x2 = x1 + 1;
  int y2 = y1 + 1;
  
  double q11 = getElevation(x1, y1);
  double q21 = getElevation(x2, y1);
  double q12 = getElevation(x1, y2);
  double q22 = getElevation(x2, y2);
  
  double dx = x - x1;
  double dy = y - y1;
  
  // Bilinear interpolation formula
  return q11 * (1 - dx) * (1 - dy) +
         q21 * dx * (1 - dy) +
         q12 * (1 - dx) * dy +
         q22 * dx * dy;
}
```

## Terrain Rendering Techniques

### 1. Altitude-Based Coloring

The most basic visualization technique applies colors based on elevation values:

```dart
// Simple color mapping based on elevation
Color getColorForElevation(double elevation) {
  // Ocean/water areas
  if (elevation < 0) {
    return Color.lerp(
      Color(0xFF000080), // Deep blue
      Color(0xFF0080FF), // Light blue
      math.min(1.0, -elevation / -5000)
    )!;
  }
  
  // Land areas
  if (elevation < 100) return Color(0xFF5F9EA0); // Greenish blue (coastal)
  if (elevation < 500) return Color(0xFF228B22); // Forest green
  if (elevation < 1500) return Color(0xFFDAA520); // Goldenrod (hills)
  if (elevation < 3000) return Color(0xFFA0522D); // Sienna (mountains)
  return Color(0xFFFFFFFF); // White (snow caps)
}
```

### 2. Hillshading

Hillshading enhances the 3D appearance of terrain by simulating how light would cast shadows on the terrain:

```dart
// Calculate hillshading value for a point
double calculateHillshade(DecodedLercData data, int x, int y,
    {double azimuth = 315, double altitude = 45}) {
  // Get elevation of surrounding cells
  double z = data.getElevation(x, y);
  double zL = data.getElevation(x - 1, y);
  double zR = data.getElevation(x + 1, y);
  double zT = data.getElevation(x, y - 1);
  double zB = data.getElevation(x, y + 1);
  
  // Calculate slope components
  double dzdx = ((zL - z) + (z - zR)) / 2;
  double dzdy = ((zT - z) + (z - zB)) / 2;
  
  // Calculate slope and aspect
  double slope = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
  double aspect = math.atan2(dzdy, -dzdx);
  
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

### 3. Combining Techniques

The plugin combines multiple rendering techniques for the final visualization:

```dart
// Combined rendering with altitude coloring and hillshading
Color getCombinedTerrainColor(double elevation, double hillshade) {
  Color baseColor = getColorForElevation(elevation);
  
  // Apply hillshading effect by darkening or lightening the base color
  return Color.lerp(
    Colors.black,
    Color.lerp(baseColor, Colors.white, hillshade * 0.5)!,
    math.min(1.0, hillshade + 0.4)
  )!;
}
```

### 4. Multiple Rendering Modes

The plugin supports different rendering modes for different use cases:

1. **Gradient Mode**: Smooth transitions between elevation-based colors
2. **Stepped Mode**: Discrete color bands for elevation ranges
3. **Single Color with Hillshade**: Monochrome rendering with 3D effect
4. **Warning Level Mode**: Custom coloring based on reference altitude thresholds

```dart
// Example of mode selection in the renderer
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

## Rendering Implementation

### 1. Custom Flutter Map Layer

The plugin implements a custom layer for the Flutter Map package:

```dart
class TerrainLayer extends MapLayer {
  final DecodedLercData elevationData;
  final RenderMode renderMode;
  final double? referenceAltitude;
  
  @override
  Widget build(BuildContext context, MapState mapState, Widget child) {
    return CustomPaint(
      painter: TerrainPainter(
        elevationData: elevationData,
        mapState: mapState,
        renderMode: renderMode,
        referenceAltitude: referenceAltitude,
      ),
      size: Size.infinite,
      child: child,
    );
  }
}
```

### 2. Custom Painter for Terrain

The terrain rendering is implemented using a `CustomPainter` for efficient drawing:

```dart
class TerrainPainter extends CustomPainter {
  final DecodedLercData elevationData;
  final MapState mapState;
  final RenderMode renderMode;
  final double? referenceAltitude;
  
  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the visible region based on map bounds
    LatLngBounds visibleBounds = mapState.bounds;
    
    // Determine which part of the elevation data is visible
    Point<int> topLeft = getRasterCoordinates(visibleBounds.northWest, dataBounds);
    Point<int> bottomRight = getRasterCoordinates(visibleBounds.southEast, dataBounds);
    
    // Draw the terrain
    for (int y = topLeft.y; y <= bottomRight.y; y++) {
      for (int x = topLeft.x; x <= bottomRight.x; x++) {
        // Get elevation value
        double elevation = elevationData.getElevation(x, y);
        
        // Calculate hillshade if needed
        double hillshade = calculateHillshade(elevationData, x, y);
        
        // Get color based on rendering mode
        Color color = getTerrainColor(elevation, hillshade, renderMode);
        
        // Draw the pixel/point
        // Implementation depends on the desired rendering technique
        drawTerrainPoint(canvas, x, y, color, mapState);
      }
    }
  }
  
  @override
  bool shouldRepaint(TerrainPainter oldDelegate) {
    // Only repaint if something significant has changed
    return oldDelegate.mapState.zoom != mapState.zoom ||
           oldDelegate.mapState.center != mapState.center ||
           oldDelegate.renderMode != renderMode ||
           oldDelegate.referenceAltitude != referenceAltitude;
  }
}
```

## Performance Optimizations

### 1. Throttling and Debouncing

The plugin implements throttling and debouncing for map interactions to prevent excessive rendering:

```dart
class ThrottledMapController {
  final mapController = MapController();
  Timer? _throttleTimer;
  bool _isThrottled = false;
  
  void onMapMove(MapPosition position, bool hasGesture) {
    if (!_isThrottled) {
      _isThrottled = true;
      _updateTerrainLayer(position);
      
      _throttleTimer = Timer(Duration(milliseconds: 150), () {
        _isThrottled = false;
        _updateTerrainLayer(mapController.camera.position);
      });
    }
  }
  
  void _updateTerrainLayer(MapPosition position) {
    // Update terrain visualization based on the new position
  }
}
```

### 2. Level of Detail Management

The rendering adapts to different zoom levels by varying the level of detail:

```dart
int calculateDetailLevel(double zoom) {
  // More detail at higher zoom levels
  if (zoom < 5) return 4; // Skip every 4 points (25% detail)
  if (zoom < 10) return 2; // Skip every 2 points (50% detail)
  return 1; // Full detail
}

void renderWithLOD(Canvas canvas, DecodedLercData data, double zoom) {
  int detailLevel = calculateDetailLevel(zoom);
  
  // Render with stride = detailLevel
  for (int y = 0; y < data.height; y += detailLevel) {
    for (int x = 0; x < data.width; x += detailLevel) {
      // Rendering code with reduced sampling
    }
  }
}
```

### 3. Tile-Based Rendering

For larger datasets, the terrain is rendered using a tile-based approach:

```dart
class TerrainTileProvider extends TileProvider {
  final Map<String, DecodedLercData> decodedTileCache = {};
  
  @override
  Future<Tile> getTile(TileCoordinates coordinates) async {
    // Generate tile cache key
    String tileKey = "${coordinates.x}-${coordinates.y}-${coordinates.z}";
    
    // Check cache first
    if (decodedTileCache.containsKey(tileKey)) {
      return _renderTerrainTile(decodedTileCache[tileKey]!, coordinates);
    }
    
    // Fetch and decode LERC data for this tile
    Uint8List lercBytes = await _fetchTileData(coordinates);
    DecodedLercData decodedData = await LercDecoder.decode(lercBytes);
    
    // Cache the decoded data
    decodedTileCache[tileKey] = decodedData;
    
    // Render the tile
    return _renderTerrainTile(decodedData, coordinates);
  }
  
  Future<Tile> _renderTerrainTile(DecodedLercData data, TileCoordinates coordinates) async {
    // Create an image from the elevation data
    // Implementation depends on the rendering technique
  }
}
```

### 4. Memory Management for Large Datasets

For very large terrain datasets, the plugin implements memory management strategies:

```dart
class TerrainMemoryManager {
  final Map<String, DecodedLercData> decodedTileCache = {};
  final int maxCacheSize = 50; // Maximum number of tiles to keep in memory
  final List<String> lruList = []; // Least recently used tracking
  
  // Add data to cache with LRU eviction
  void addToCache(String key, DecodedLercData data) {
    // If cache is full, evict least recently used item
    if (decodedTileCache.length >= maxCacheSize && !decodedTileCache.containsKey(key)) {
      String oldestKey = lruList.removeAt(0);
      decodedTileCache.remove(oldestKey);
    }
    
    // Add or update cache
    decodedTileCache[key] = data;
    
    // Update LRU list
    lruList.remove(key); // Remove if exists
    lruList.add(key); // Add to end (most recently used)
  }
  
  // Get data from cache and update LRU status
  DecodedLercData? getFromCache(String key) {
    if (decodedTileCache.containsKey(key)) {
      // Update LRU list
      lruList.remove(key);
      lruList.add(key);
      return decodedTileCache[key];
    }
    return null;
  }
}
```

## User Interface for Terrain Controls

The plugin provides UI components for controlling terrain visualization:

```dart
class TerrainControlPanel extends StatefulWidget {
  final TerrainController controller;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Rendering mode selector
        DropdownButton<RenderMode>(
          value: controller.renderMode,
          items: RenderMode.values.map((mode) {
            return DropdownMenuItem(
              value: mode,
              child: Text(mode.toString().split('.').last),
            );
          }).toList(),
          onChanged: (mode) => controller.setRenderMode(mode!),
        ),
        
        // Hillshading controls
        Row(
          children: [
            Text("Hillshading:"),
            Switch(
              value: controller.hillshadingEnabled,
              onChanged: controller.setHillshadingEnabled,
            ),
          ],
        ),
        
        // Reference altitude slider (if in warning mode)
        if (controller.renderMode == RenderMode.warning)
          Slider(
            min: controller.minAltitude,
            max: controller.maxAltitude,
            value: controller.referenceAltitude,
            onChanged: controller.setReferenceAltitude,
          ),
      ],
    );
  }
}
```

## Conclusion

The FlightCanvas Terrain plugin employs a comprehensive approach to terrain visualization, combining efficient LERC data decoding with advanced rendering techniques. The implementation balances visual quality with performance considerations, adapting to the constraints of mobile devices while providing rich visualization options for different use cases.

By leveraging Flutter's `CustomPainter` capabilities and implementing various optimization strategies, the plugin delivers responsive terrain visualization suitable for applications ranging from simple topographic displays to more complex scenarios like flight planning and terrain analysis.
