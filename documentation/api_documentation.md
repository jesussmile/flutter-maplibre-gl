# API Documentation

This document provides a comprehensive reference for the public API of the FlightCanvas Terrain plugin.

## Core Classes and Components

### LercDecoder

The `LercDecoder` class provides the primary interface for decoding LERC-compressed elevation data.

```dart
class LercDecoder {
  /// Initialize the native LERC decoder library
  /// Must be called before any decoding operations
  static Future<void> initialize() async;
  
  /// Decode LERC-compressed data into elevation values
  /// Returns a DecodedLercData object containing the elevation grid
  static Future<DecodedLercData> decode(Uint8List bytes) async;
}
```

#### Example Usage

```dart
// Initialize the decoder
await LercDecoder.initialize();

// Load LERC data from an asset
final ByteData byteData = await rootBundle.load('assets/elevation.lerc2');
final Uint8List bytes = byteData.buffer.asUint8List();

// Decode the data
DecodedLercData elevationData = await LercDecoder.decode(bytes);
```

### DecodedLercData

The `DecodedLercData` class represents the decoded elevation data and provides methods for accessing the elevation values.

```dart
class DecodedLercData {
  /// Raw elevation data as a flat array
  final Float64List data;
  
  /// Width of the elevation grid
  final int width;
  
  /// Height of the elevation grid
  final int height;
  
  /// Minimum elevation value in the data
  final double minValue;
  
  /// Maximum elevation value in the data
  final double maxValue;
  
  /// Constructor
  DecodedLercData(this.data, this.width, this.height, this.minValue, this.maxValue);
  
  /// Check if the data is valid
  bool isValid() => data.isNotEmpty && width > 0 && height > 0;
  
  /// Get elevation at specific grid coordinates
  /// Returns double.nan if coordinates are out of bounds
  double getElevation(int x, int y);
  
  /// Extract a rectangular region of elevation data
  Float64List getRegion(int startX, int startY, int regionWidth, int regionHeight);
  
  /// Get interpolated elevation at non-integer coordinates
  double getInterpolatedElevation(double x, double y);
}
```

#### Example Usage

```dart
// Access elevation at specific coordinates
double elevationAtPoint = elevationData.getElevation(100, 150);

// Extract a region of interest
Float64List regionData = elevationData.getRegion(50, 50, 100, 100);

// Get interpolated elevation for smooth sampling
double interpolatedElevation = elevationData.getInterpolatedElevation(100.5, 150.3);
```

## Terrain Visualization Components

### TerrainLayer

The `TerrainLayer` class is a Flutter Map layer for rendering terrain elevation data.

```dart
class TerrainLayer extends MapLayer {
  /// Elevation data to render
  final DecodedLercData elevationData;
  
  /// Optional geographic bounds of the elevation data
  /// If not provided, the full extent of the map will be used
  final LatLngBounds? bounds;
  
  /// Rendering mode to use
  final TerrainRenderingMode renderingMode;
  
  /// Whether to apply hillshading
  final bool enableHillshading;
  
  /// Color scheme to use for elevation coloring
  final TerrainColorScheme colorScheme;
  
  /// Optional reference altitude for warning level visualization
  final double? referenceAltitude;
  
  /// Optional visible elevation range
  /// Elevations outside this range will use min/max colors
  final ElevationRange? visibleElevationRange;
  
  /// Constructor
  TerrainLayer({
    required this.elevationData,
    this.bounds,
    this.renderingMode = TerrainRenderingMode.gradient,
    this.enableHillshading = true,
    this.colorScheme = TerrainColorScheme.default,
    this.referenceAltitude,
    this.visibleElevationRange,
  });
}
```

#### Example Usage

```dart
FlutterMap(
  mapController: mapController,
  options: MapOptions(
    center: LatLng(37.7749, -122.4194),
    zoom: 10,
  ),
  children: [
    TileLayer(
      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
    TerrainLayer(
      elevationData: decodedLercData,
      renderingMode: TerrainRenderingMode.gradient,
      enableHillshading: true,
      colorScheme: TerrainColorScheme.earthTones,
    ),
  ],
)
```

### TerrainController

The `TerrainController` class provides methods for controlling the terrain visualization at runtime.

```dart
class TerrainController extends ChangeNotifier {
  /// Current rendering mode
  TerrainRenderingMode get renderingMode;
  
  /// Set the rendering mode
  void setRenderingMode(TerrainRenderingMode mode);
  
  /// Whether hillshading is enabled
  bool get isHillshadingEnabled;
  
  /// Enable or disable hillshading
  void setHillshadingEnabled(bool enabled);
  
  /// Current color scheme
  TerrainColorScheme get colorScheme;
  
  /// Set the color scheme
  void setColorScheme(TerrainColorScheme scheme);
  
  /// Current reference altitude (for warning level visualization)
  double? get referenceAltitude;
  
  /// Set the reference altitude
  void setReferenceAltitude(double? altitude);
  
  /// Current visible elevation range
  ElevationRange? get visibleElevationRange;
  
  /// Set the visible elevation range
  void setVisibleElevationRange(double min, double max);
  
  /// Reset to default settings
  void resetToDefaults();
}
```

#### Example Usage

```dart
// Create a controller
final terrainController = TerrainController();

// Use the controller with a TerrainLayer
TerrainLayer(
  elevationData: decodedLercData,
  controller: terrainController,
),

// Later, update visualization settings
terrainController.setRenderingMode(TerrainRenderingMode.warningLevels);
terrainController.setReferenceAltitude(5000.0);
```

## Enumerations and Support Classes

### TerrainRenderingMode

```dart
enum TerrainRenderingMode {
  /// Smooth gradient coloring based on elevation
  gradient,
  
  /// Discrete color bands for elevation ranges
  stepped,
  
  /// Single color with hillshading
  monochrome,
  
  /// Colored based on relation to reference altitude
  warningLevels,
}
```

### TerrainColorScheme

```dart
enum TerrainColorScheme {
  /// Default color scheme (earth tones)
  default,
  
  /// Earth-like colors (green lowlands, brown mountains, white peaks)
  earthTones,
  
  /// Hypsometric tint (traditional elevation map colors)
  hypsometric,
  
  /// Grayscale (black to white)
  grayscale,
  
  /// High contrast colors for visibility
  highContrast,
}
```

### ElevationRange

```dart
class ElevationRange {
  /// Minimum elevation in the range
  final double min;
  
  /// Maximum elevation in the range
  final double max;
  
  /// Constructor
  const ElevationRange(this.min, this.max);
  
  /// Create an elevation range that includes all values in the data
  factory ElevationRange.fromData(DecodedLercData data) {
    return ElevationRange(data.minValue, data.maxValue);
  }
}
```

## Tile Providers

### LercTileProvider

The `LercTileProvider` class provides a way to load and manage LERC data in a tile-based system.

```dart
class LercTileProvider {
  /// Create a LercTileProvider from a URL template
  /// The template should include {z}, {x}, and {y} placeholders
  LercTileProvider.network(String urlTemplate, {
    Map<String, String>? headers,
    int maxConcurrentRequests = 6,
    int maxCachedTiles = 100,
  });
  
  /// Create a LercTileProvider from asset paths
  LercTileProvider.asset(String assetPathTemplate);
  
  /// Create a LercTileProvider from local files
  LercTileProvider.file(String filePathTemplate);
  
  /// Get a tile for specific coordinates
  Future<DecodedLercData> getTile(int z, int x, int y);
  
  /// Preload tiles around a specific location
  Future<void> preloadTiles(LatLng center, int zoom, {int radius = 1});
  
  /// Clear the tile cache
  void clearCache();
}
```

#### Example Usage

```dart
// Create a tile provider from a network source
final tileProvider = LercTileProvider.network(
  'https://example.com/terrain/{z}/{x}/{y}.lerc2',
  headers: {'Authorization': 'Bearer $apiKey'},
);

// Get a specific tile
DecodedLercData tileData = await tileProvider.getTile(10, 123, 456);

// Preload tiles around the current location
await tileProvider.preloadTiles(mapController.center, mapController.zoom);
```

## Utility Classes

### TerrainAnalysis

The `TerrainAnalysis` class provides methods for analyzing terrain data.

```dart
class TerrainAnalysis {
  /// Calculate slope (in degrees) for a point in the terrain
  /// Returns a value between 0 (flat) and 90 (vertical)
  static double calculateSlope(DecodedLercData data, int x, int y);
  
  /// Calculate aspect (direction of slope) for a point
  /// Returns value in degrees (0-360, clockwise from north)
  static double calculateAspect(DecodedLercData data, int x, int y);
  
  /// Calculate hillshade value for a point
  /// Returns value between 0 (shadowed) and 1 (fully lit)
  static double calculateHillshade(
    DecodedLercData data, 
    int x, 
    int y, {
    double azimuth = 315, 
    double altitude = 45,
  });
  
  /// Get the elevation profile between two geographic points
  /// Returns a list of [distance, elevation] pairs
  static List<List<double>> getElevationProfile(
    DecodedLercData data,
    LatLngBounds bounds,
    LatLng start,
    LatLng end, {
    int samples = 100,
  });
}
```

#### Example Usage

```dart
// Calculate slope at a specific point
double slope = TerrainAnalysis.calculateSlope(elevationData, 100, 150);

// Calculate hillshade with custom light direction
double hillshade = TerrainAnalysis.calculateHillshade(
  elevationData, 
  100, 
  150,
  azimuth: 270,  // Light from the west
  altitude: 30,  // Low sun angle
);

// Get elevation profile between two points
List<List<double>> profile = TerrainAnalysis.getElevationProfile(
  elevationData,
  mapBounds,
  LatLng(37.7749, -122.4194),  // San Francisco
  LatLng(37.3382, -121.8863),  // San Jose
);
```

### TerrainMemoryCache

The `TerrainMemoryCache` class provides memory management for terrain data.

```dart
class TerrainMemoryCache {
  /// Create a new cache with a specified maximum size
  TerrainMemoryCache({int maxSize = 50});
  
  /// Add data to the cache
  void put(String key, DecodedLercData data);
  
  /// Get data from the cache
  /// Returns null if the key is not in the cache
  DecodedLercData? get(String key);
  
  /// Check if the cache contains a key
  bool contains(String key);
  
  /// Remove an item from the cache
  void remove(String key);
  
  /// Clear all items from the cache
  void clear();
  
  /// Current number of items in the cache
  int get size;
}
```

#### Example Usage

```dart
// Create a cache
final terrainCache = TerrainMemoryCache(maxSize: 20);

// Store decoded data
terrainCache.put('tile_10_123_456', decodedData);

// Retrieve data
DecodedLercData? cachedData = terrainCache.get('tile_10_123_456');
if (cachedData != null) {
  // Use cached data
} else {
  // Data not in cache, need to decode
}
```

## Configuration

### TerrainOptions

The `TerrainOptions` class provides configuration options for the terrain visualization.

```dart
class TerrainOptions {
  /// Default color for elevations below sea level
  final Color belowSeaLevelColor;
  
  /// Default color for the lowest elevations above sea level
  final Color lowElevationColor;
  
  /// Default color for mid-range elevations
  final Color midElevationColor;
  
  /// Default color for high elevations
  final Color highElevationColor;
  
  /// Default color for the highest elevations (peaks)
  final Color peakElevationColor;
  
  /// Default hillshade parameters
  final HillshadeParams hillshadeParams;
  
  /// Default memory cache size
  final int defaultCacheSize;
  
  /// Constructor with default values
  const TerrainOptions({
    this.belowSeaLevelColor = const Color(0xFF000080),
    this.lowElevationColor = const Color(0xFF228B22),
    this.midElevationColor = const Color(0xFFDAA520),
    this.highElevationColor = const Color(0xFFA0522D),
    this.peakElevationColor = const Color(0xFFFFFFFF),
    this.hillshadeParams = const HillshadeParams(),
    this.defaultCacheSize = 50,
  });
}

class HillshadeParams {
  /// Light source azimuth in degrees (0 = north, 90 = east)
  final double azimuth;
  
  /// Light source altitude in degrees above horizon
  final double altitude;
  
  /// Intensity of the hillshading effect (0.0 to 1.0)
  final double intensity;
  
  /// Constructor with default values
  const HillshadeParams({
    this.azimuth = 315.0,
    this.altitude = 45.0,
    this.intensity = 0.5,
  });
}
```

#### Example Usage

```dart
// Create custom terrain options
final customOptions = TerrainOptions(
  belowSeaLevelColor: Colors.blue[900]!,
  lowElevationColor: Colors.green[700]!,
  midElevationColor: Colors.amber[600]!,
  highElevationColor: Colors.brown[500]!,
  peakElevationColor: Colors.white,
  hillshadeParams: HillshadeParams(
    azimuth: 270.0,
    altitude: 30.0,
    intensity: 0.7,
  ),
  defaultCacheSize: 30,
);

// Apply the options to the FlightCanvas terrain configuration
FlightCanvasTerrain.setOptions(customOptions);
```

## Error Handling

### TerrainException

The `TerrainException` class represents errors that occur during terrain operations.

```dart
class TerrainException implements Exception {
  /// Error code
  final int code;
  
  /// Error message
  final String message;
  
  /// Optional details about the error
  final dynamic details;
  
  /// Constructor
  const TerrainException(this.code, this.message, [this.details]);
  
  /// Error codes
  static const int INITIALIZATION_FAILED = 1;
  static const int DECODING_FAILED = 2;
  static const int INVALID_DATA = 3;
  static const int MEMORY_ERROR = 4;
  static const int TILE_LOAD_ERROR = 5;
  
  @override
  String toString() => 'TerrainException($code): $message';
}
```

#### Example Usage

```dart
try {
  await LercDecoder.decode(bytes);
} on TerrainException catch (e) {
  if (e.code == TerrainException.DECODING_FAILED) {
    print('Failed to decode LERC data: ${e.message}');
  } else {
    print('Other terrain error: $e');
  }
}
```

## Plugin Configuration

### FlightCanvasTerrain

The `FlightCanvasTerrain` class provides global configuration for the plugin.

```dart
class FlightCanvasTerrain {
  /// Initialize the terrain plugin
  /// This must be called before using any other terrain functionality
  static Future<void> initialize() async;
  
  /// Set global options for terrain visualization
  static void setOptions(TerrainOptions options);
  
  /// Get the current terrain options
  static TerrainOptions getOptions();
  
  /// Enable or disable debug logging
  static void setDebugLoggingEnabled(bool enabled);
}
```

#### Example Usage

```dart
// Initialize the plugin
await FlightCanvasTerrain.initialize();

// Configure global options
FlightCanvasTerrain.setOptions(TerrainOptions(
  defaultCacheSize: 30,
  hillshadeParams: HillshadeParams(intensity: 0.7),
));

// Enable debug logging during development
FlightCanvasTerrain.setDebugLoggingEnabled(true);
```

## Conclusion

This API documentation provides a comprehensive reference for developers using the FlightCanvas Terrain plugin. The API is designed to be intuitive and flexible, allowing for various terrain visualization use cases while maintaining good performance on mobile devices.

The plugin's architecture separates concerns into distinct components:
- Data decoding and access (LercDecoder, DecodedLercData)
- Visualization (TerrainLayer, TerrainController)
- Data management (LercTileProvider, TerrainMemoryCache)
- Analysis and utilities (TerrainAnalysis)

This design enables developers to customize the terrain visualization experience while benefiting from the optimized native implementation of the LERC decoding process.
