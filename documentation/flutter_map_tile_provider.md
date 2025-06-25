# Custom Flutter Map TileProvider for LERC

This document describes the implementation of the custom TileProvider for Flutter Map that fetches and renders LERC terrain data.

## Overview

The `LercTileProvider` is a custom implementation of Flutter Map's `TileProvider` interface that specializes in handling LERC-encoded terrain elevation data. It's responsible for:

1. Fetching LERC-encoded terrain data for specific tile coordinates
2. Triggering the decoding process using the LERC decoder
3. Processing and caching the elevation data
4. Rendering the elevation data as visual tiles

## Implementation Details

### Class Structure

```dart
class LercTileProvider extends TileProvider {
  final DecodedLercData data;
  final double referenceAltitude;
  final double warningAltitude;
  final double minElevation;
  final double terrainResolution;
  final ValueChanged<double>? onElevationRead;

  // Caches for storing processed data and optimizing performance
  final Map<String, Uint8List> _renderedPixelCache = {};
  static final Map<String, Float64List> _elevationCache = {};
  static final Set<String> _activeTileKeys = {};
  
  // For synchronizing tile updates
  static final Map<String, _LercTileImage> _pendingTileUpdates = {};
  
  // Constructor and initialization
  LercTileProvider({
    required this.data,
    required this.referenceAltitude,
    required this.warningAltitude,
    required this.minElevation,
    required this.terrainResolution,
    this.onElevationRead,
  });
  
  // TileProvider implementation
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // Return a custom image provider for this tile
    return _LercTileImage(
      data: data,
      coordinates: coordinates,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      altitudeBucketSize: _altitudeBucketSize,
      onElevationRead: onElevationRead,
      pixelCache: _renderedPixelCache,
    );
  }
}
```

### Tile Coordinate System

The provider uses the standard web mercator tile coordinate system:
- `z`: Zoom level (higher numbers = more detailed)
- `x`: Horizontal tile position (0 to 2^zoom-1, increasing eastward)
- `y`: Vertical tile position (0 to 2^zoom-1, increasing southward)

### Tile Generation Process

1. **Request Handling**: When Flutter Map requests a tile, the `getImage` method is called with specific tile coordinates.

2. **Caching Check**: The provider first checks if the processed elevation data for these coordinates is already cached:

```dart
// Generate tile cache key
String tileKey = "${coordinates.x}_${coordinates.y}_${coordinates.z}";

// Check if we have cached elevation data
if (_elevationCache.containsKey(tileKey)) {
  // Use cached data
}
```

3. **Elevation Data Extraction**: For uncached tiles, the provider extracts elevation data from the LERC dataset:

```dart
// Calculate lat/lon bounds for the tile
final lat1 = _tile2lat(y, z);
final lat2 = _tile2lat(y + 1, z);
final lon1 = _tile2lon(x, z);
final lon2 = _tile2lon(x + 1, z);

// Extract elevation data for this geographic area
// ...
```

4. **Rendering**: The tile is rendered based on the elevation data:

```dart
// Render terrain image from elevation data
Uint8List pixels = _renderTerrainImage(elevations);
return _createImageFromPixels(pixels, tileSize, tileSize);
```

5. **Caching**: The extracted elevation data and rendered image are cached for future use.

### Memory Management

The provider implements several memory management strategies:

1. **Elevation Data Cache**: Stores decoded elevation data for each tile to avoid redundant decoding.

2. **Rendered Pixel Cache**: Stores rendered pixel data rather than Flutter UI Image objects to avoid disposal issues.

3. **Periodic Cache Cleanup**:

```dart
void _cleanupUnusedElevations() {
  // Only clean if we have more than a certain number of cached items
  if (_elevationCache.length > 200) {
    // Remove elevation data for tiles that are no longer active
    _elevationCache.removeWhere((key, _) => !_activeTileKeys.contains(key));
  }
}
```

## Optimization Techniques

### Altitude Bucketing

To reduce visual flickering and improve performance, the provider implements altitude bucketing:

```dart
// Use a broader altitude bucket size to reduce rendering frequency
double get _altitudeBucketSize => math.max(terrainResolution, 100.0);

// Apply bucketing to altitude value
String get _bucketedAltitude {
  double bucketedValue = (referenceAltitude / altitudeBucketSize).floor() * altitudeBucketSize;
  return bucketedValue.toString();
}
```

### Rendering Modes

The provider supports multiple rendering modes:

1. **Gradient Mode**: Uses a smooth gradient based on elevation values.
2. **Simple Mode**: Uses discrete altitude-based coloring.

```dart
static bool _useGradientMode = true;

static void setGradientMode(bool enabled) {
  _useGradientMode = enabled;
  // Clear caches to force re-rendering
}
```

### High-Zoom Mode

A specialized rendering mode for high zoom levels:

```dart
static bool _highZoomMode = false;

static void setHighZoomMode(bool enabled) {
  _highZoomMode = enabled;
}
```

### Throttled Updates

The provider implements throttling to prevent excessive tile updates during rapid altitude changes:

```dart
Future.delayed(Duration(milliseconds: updateDelay), () {
  // Only queue updates if the difference is still significant
  if (altDifference >= updateThreshold) {
    LercTileProvider.queueTileUpdate(_renderedImageKey, this);
  }
});
```

## Platform-Specific Optimizations

The provider includes platform-specific optimizations, particularly for iOS:

```dart
// For iOS 17, optimize the creation of new images
if (isIOS17) {
  // Pre-schedule frame rendering for better Metal performance
  WidgetsBinding.instance.scheduleFrame();
}
```

## Usage Example

```dart
// Create a LercTileProvider
final provider = LercTileProvider(
  data: decodedLercData,
  referenceAltitude: 5000, // In feet
  warningAltitude: 15000, // In feet
  minElevation: decodedLercData.minValue,
  terrainResolution: 100,
);

// Use the provider in a TileLayer
TileLayer(
  tileProvider: provider,
  maxZoom: 19,
  minZoom: 1,
  urlTemplate: "unused", // Not used but required by Flutter Map
),
```
