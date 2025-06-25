# Processing Raw Decoded Elevation Data

This document details how raw elevation data decoded from LERC files is processed and transformed for visualization in the FlightCanvas Terrain plugin.

## Overview

After LERC data is decoded into raw elevation values via FFI, it needs to be processed into a format suitable for visualization. This processing involves:

1. Organizing the raw elevation values into a structured format
2. Mapping between different coordinate systems (geographic, tile, and data coordinates)
3. Interpolating elevation values for smooth visualization
4. Transforming elevation data for specific use cases (rendering, analysis, etc.)

## Data Representation: DecodedLercData

The fundamental data structure for processed elevation data is the `DecodedLercData` class:

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
  double getElevation(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.nan;
    return data[y * width + x];
  }
  
  /// Extract a rectangular region of elevation data
  Float64List getRegion(int startX, int startY, int regionWidth, int regionHeight) {
    if (startX < 0 ||
        startY < 0 ||
        startX + regionWidth > width ||
        startY + regionHeight > height) {
      throw RangeError('Invalid region coordinates');
    }

    final result = Float64List(regionWidth * regionHeight);
    for (var y = 0; y < regionHeight; y++) {
      final srcOffset = (startY + y) * width + startX;
      final destOffset = y * regionWidth;
      result.setRange(
        destOffset,
        destOffset + regionWidth,
        data.sublist(srcOffset, srcOffset + regionWidth),
      );
    }
    return result;
  }
  
  /// Get interpolated elevation at non-integer coordinates
  double getInterpolatedElevation(double x, double y) {
    // Implementation of bilinear interpolation
    // ...
  }
}
```

This class serves as the bridge between the raw decoded data and higher-level visualization components. It includes methods for:

- Accessing individual elevation values at grid coordinates
- Extracting regions of interest
- Interpolating values for smoother visualization
- Validating data integrity

## Coordinate System Mapping

One of the critical aspects of processing elevation data is mapping between different coordinate systems:

### 1. Geographic Coordinates (Latitude/Longitude)

Geographic coordinates represent positions on Earth's surface:

```dart
// Convert from tile coordinates to latitude
double _tile2lat(int y, int z) {
  final n = math.pow(2.0, z);
  final lat_rad = math.atan(_sinh(math.pi * (1 - 2 * y / n)));
  return lat_rad * 180.0 / math.pi;
}

// Convert from tile coordinates to longitude
double _tile2lon(int x, int z) {
  final n = math.pow(2.0, z);
  return x * 360.0 / n - 180.0;
}
```

### 2. Tile Coordinates (x, y, z)

Tile coordinates reference a specific tile in a map tile grid:
- x: Tile column (0 to 2^zoom - 1, increasing eastward)
- y: Tile row (0 to 2^zoom - 1, increasing southward)
- z: Zoom level (integer determining tile resolution)

### 3. Data Coordinates (grid indices)

Data coordinates reference positions within the decoded elevation grid:
- Horizontal position: 0 to width-1
- Vertical position: 0 to height-1

### 4. Mapping Process

The conversion between these coordinate systems is handled as follows:

```dart
// Calculate lat/lon bounds for the tile
final lat1 = _tile2lat(y, z);      // Top latitude (Northern edge)
final lat2 = _tile2lat(y + 1, z);  // Bottom latitude (Southern edge)
final lon1 = _tile2lon(x, z);      // Left longitude (Western edge)
final lon2 = _tile2lon(x + 1, z);  // Right longitude (Eastern edge)

// For each pixel in the tile
for (int py = 0; py < tileSize; py++) {
  // Calculate latitude for this pixel
  final lat = lat1 + (py / tileSize) * (lat2 - lat1);
  
  // Convert to data y-coordinate
  final latRatio = (lat - minLat) / (maxLat - minLat);
  final dataYFloat = (1.0 - latRatio) * data.height;
  final dataY = dataYFloat.floor();
  
  for (int px = 0; px < tileSize; px++) {
    // Calculate longitude for this pixel
    final lon = lon1 + (px / tileSize) * (lon2 - lon1);
    
    // Convert to data x-coordinate
    final lonRatio = (lon - minLon) / (maxLon - minLon);
    final dataXFloat = lonRatio * data.width;
    final dataX = dataXFloat.floor();
    
    // Now we can access the elevation at this point
    elevations[py * tileSize + px] = data.data[dataY * data.width + dataX];
  }
}
```

## Bilinear Interpolation

For higher quality visualization, especially at higher zoom levels, the system implements bilinear interpolation to get smoother elevation values:

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

Bilinear interpolation produces smoother terrain transitions by:
1. Taking four neighboring elevation values
2. Applying weighted averaging based on the fractional position
3. Producing a smoothly interpolated elevation value

## Unit Conversion

The system handles unit conversion between meters (typically used in elevation data) and feet (commonly used in aviation):

```dart
// Convert from meters to feet before returning the elevations
for (int i = 0; i < elevations.length; i++) {
  if (elevations[i].isFinite) {
    elevations[i] = elevations[i] * 3.28084; // Convert from meters to feet
  }
}
```

This ensures the data is presented in the appropriate units for the application context.

## Handling Different Zoom Levels

The system optimizes data processing for different map zoom levels:

```dart
// Use bilinear interpolation for zoom levels 6 and above for better quality
if (coordinates.z >= 6) {
  // Use high-quality bilinear interpolation
  // ...
} else {
  // Use simpler nearest-neighbor sampling for lower zoom levels
  // ...
}
```

At higher zoom levels, more detailed rendering is needed, while at lower zoom levels, faster but less precise methods can be used to improve performance.

## Elevation Data Extraction for Tiles

A key aspect of processing raw elevation data is extracting the relevant subset for a specific map tile:

```dart
Float64List _getElevationsForTile() {
  // Check cache first
  final cacheKey = '${coordinates.x}_${coordinates.y}_${coordinates.z}';
  if (_elevationCache.containsKey(cacheKey)) {
    return _elevationCache[cacheKey]!;
  }

  const tileSize = 256;
  final elevations = Float64List(tileSize * tileSize);
  
  // Calculate tile geographic bounds
  final lat1 = _tile2lat(coordinates.y, coordinates.z);
  final lat2 = _tile2lat(coordinates.y + 1, coordinates.z);
  final lon1 = _tile2lon(coordinates.x, coordinates.z);
  final lon2 = _tile2lon(coordinates.x + 1, coordinates.z);
  
  // Find the corresponding data points in the elevation dataset
  // ...
  
  // Extract elevation values
  // ...
  
  // Cache the result
  _elevationCache[cacheKey] = elevations;
  return elevations;
}
```

This approach:
1. Uses a caching mechanism to avoid redundant processing
2. Maps between tile coordinates and geographic coordinates
3. Maps between geographic coordinates and elevation data indices
4. Extracts the relevant elevation values

## Special Case Handling

The system implements special handling for various edge cases:

### 1. Out-of-bounds coordinates

```dart
// Check if coordinates are within valid range
if (dataX >= 0 && dataX < data.width && dataY >= 0 && dataY < data.height) {
  // Valid coordinates
  elevation = data.data[dataY * data.width + dataX];
} else {
  // Out of bounds
  elevation = minElevation - 1; // Use a sentinel value
}
```

### 2. Missing or invalid elevation data

```dart
// Handle NaN or infinite values
if (!elevation.isFinite) {
  elevation = minElevation - 1;
}
```

### 3. Sea level normalization

```dart
// Normalize values below sea level
double elevation = data.data[i] < 0 ? 0 : data.data[i];
```

## Tile-Based Processing

The system uses a tile-based approach to process elevation data efficiently:

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
    
    // Process and render the tile
    return _renderTerrainTile(decodedData, coordinates);
  }
  
  Future<Tile> _renderTerrainTile(DecodedLercData data, TileCoordinates coordinates) async {
    // Process elevation data into a visual representation
    // ...
  }
}
```

This approach enables:
1. Processing only the data relevant to the visible map area
2. Caching processed data to avoid redundant processing
3. Dynamic loading and unloading of data as the map view changes

## Advanced Data Analysis

Beyond basic data access, the system provides advanced analytical capabilities through the `TerrainAnalysis` class:

```dart
class TerrainAnalysis {
  /// Calculate slope (in degrees) for a point in the terrain
  static double calculateSlope(DecodedLercData data, int x, int y) {
    // Get elevation of center and surrounding cells
    double z = data.getElevation(x, y);
    double zL = data.getElevation(x - 1, y);
    double zR = data.getElevation(x + 1, y);
    double zT = data.getElevation(x, y - 1);
    double zB = data.getElevation(x, y + 1);
    
    // Calculate slope components
    double dzdx = ((zL - z) + (z - zR)) / 2;
    double dzdy = ((zT - z) + (z - zB)) / 2;
    
    // Calculate slope in radians
    return math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
  }
  
  /// Calculate aspect (direction of slope)
  static double calculateAspect(DecodedLercData data, int x, int y) {
    // Implementation details
  }
  
  /// Calculate hillshade value
  static double calculateHillshade(DecodedLercData data, int x, int y, 
                                double azimuth, double altitude) {
    // Implementation details
  }
  
  /// Generate an elevation profile between two points
  static List<List<double>> getElevationProfile(
      DecodedLercData data, LatLngBounds bounds, LatLng start, LatLng end, int samples) {
    // Implementation details
  }
}
```

These analytical capabilities make the raw elevation data more useful for aviation applications by:
1. Calculating terrain slope and aspect
2. Generating hillshading for enhanced visualization
3. Creating elevation profiles for flight planning

## Bucketing for Performance and Safety

For aviation applications, the system implements altitude bucketing to prioritize data based on safety relevance:

```dart
Future<void> _saveToDisk(double altitude, DecodedLercData data) async {
  // Create a more efficient data structure to store only relevant points
  List<double> relevantElevations = [];
  List<int> relevantIndices = [];
  int warningCount = 0;
  int dangerCount = 0;
  double warningAltitude = altitude - 500.0; // 500 meters warning zone

  // First pass: collect only points that are in warning or danger zones
  for (int i = 0; i < data.data.length; i++) {
    double elevation = data.data[i] < 0 ? 0 : data.data[i];

    if (elevation >= altitude) {
      relevantElevations.add(elevation);
      relevantIndices.add(i);
      dangerCount++;
    } else if (elevation >= warningAltitude) {
      relevantElevations.add(elevation);
      relevantIndices.add(i);
      warningCount++;
    }
  }
  
  // Create compact storage format and save to disk
  // Implementation details
}
```

This bucketing strategy:
1. Reduces memory usage by only storing relevant elevation points
2. Improves performance by focusing on safety-critical data
3. Supports efficient warning and danger zone visualization

## Performance Optimizations

The system implements several optimizations for processing raw elevation data:

### 1. Caching at Multiple Levels

```dart
// Cache decoded elevation data
if (_elevationCache.containsKey(cacheKey)) {
  return _elevationCache[cacheKey]!;
}

// Cache rendered pixel data
if (pixelCache.containsKey(_renderedImageKey)) {
  return _createImageFromPixels(pixelCache[_renderedImageKey]!, 256, 256);
}
```

### 2. Adaptive Detail Level

```dart
// Optimize rendering based on zoom level
if (coordinates.z > 12) {
  skipFactor = 4; // Very high zoom - still visible but coarser
} else if (coordinates.z > 10) {
  skipFactor = 2; // High zoom - medium detail
} else {
  skipFactor = 1; // Normal detail for lower zoom
}
```

### 3. Data Structure Optimization

```dart
// Use typed arrays for performance
final pixels = Uint8List(tileSize * tileSize * 4);
final elevations = Float64List(tileSize * tileSize);
```

### 4. Cleanup of Unused Data

```dart
void _cleanupUnusedElevations() {
  if (_activeTileKeys.isEmpty) return;

  // Remove entries that are no longer active
  _elevationCache.removeWhere((key, value) => !_activeTileKeys.contains(key));
  
  // Log cache size after cleanup
  print("Elevation cache size after cleanup: ${_elevationCache.length}");
}
```

## Conclusion

The processing of raw decoded elevation data involves numerous steps and techniques:

1. **Data Representation**: Structured storage in the `DecodedLercData` class
2. **Coordinate Mapping**: Conversion between geographic, tile, and data coordinates
3. **Interpolation**: Smooth transitions using bilinear interpolation
4. **Tile-Based Processing**: Efficient handling of large datasets
5. **Analytical Capabilities**: Slope, aspect, and hillshade calculations
6. **Performance Optimizations**: Caching, adaptive detail, and cleanup strategies

These processes transform the raw elevation data from the native LERC decoder into a format that's suitable for high-performance visualization and analysis in the FlightCanvas Terrain plugin, while maintaining the critical accuracy needed for aviation safety applications.
