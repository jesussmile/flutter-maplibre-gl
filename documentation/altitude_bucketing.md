# Altitude Bucketing for Terrain Rendering

This document describes the altitude bucketing implementation in the FlightCanvas Terrain plugin, which provides an efficient approach to terrain visualization at different altitude thresholds.

## Overview

Altitude bucketing is a technique used to reduce visual flickering, improve rendering performance, and efficiently handle terrain data for altitude-based visualization. In the FlightCanvas Terrain plugin, altitude bucketing allows the application to display terrain data with appropriate warning and danger zones based on aircraft altitude, without reprocessing the entire dataset for every small change in altitude.

## Purpose and Benefits

The altitude bucketing system provides several important benefits:

1. **Reduced Processing Overhead**: Instead of recalculating terrain visualization settings for each frame or small altitude change, the system uses pre-calculated buckets
2. **Visual Stability**: Prevents rapid flickering or "z-fighting" artifacts during gradual altitude changes
3. **Memory Efficiency**: Allows for more efficient storage and retrieval of processed terrain data
4. **Smooth Transitions**: Enables smooth transitions between altitude thresholds
5. **Consistent Visualization**: Ensures consistent visualization of warning and danger zones

## Implementation Details

### Bucket Definition

The plugin defines altitude buckets with the following characteristics:

- **Fixed Altitude Steps**: Buckets are defined at fixed intervals (default: 500 meters)
- **Inclusive Range**: Each bucket represents a range of altitudes centered around the bucket value
- **Warning Buffer**: Each bucket includes a "warning zone" below the danger threshold

```dart
// Constants for altitude bucketing in TerrainCache class
static const double minAltitude = 0;
static const double maxAltitude = 9000;
static const double altitudeStep = 500;
```

### Bucket Selection Algorithm

The system selects the appropriate bucket for any given altitude using a nearest-bucket algorithm:

```dart
double _findNearestCachedAltitude(double targetAltitude) {
  return (targetAltitude / altitudeStep).round() * altitudeStep;
}
```

This algorithm maps any altitude to the nearest bucket value:
- For example, 1240m would map to the 1000m bucket if 500m steps are used
- For example, 1260m would map to the 1500m bucket if 500m steps are used

### Bucket Processing and Storage

During initialization, the system processes terrain data for each altitude bucket:

1. The full terrain dataset is decoded from the LERC format
2. For each bucket:
   - Points are classified as "danger" (above bucket altitude) or "warning" (within warning zone)
   - Only relevant points (those in warning or danger zones) are stored
   - Data is saved in a compact, sparse format to save memory and storage space

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
  // ...
}
```

### Runtime Bucket Usage

At runtime, the system manages altitude buckets with the following approach:

1. **Altitude Threshold Selection**: The application determines the current altitude threshold (typically based on aircraft altitude)
2. **Bucket Lookup**: The application finds the nearest pre-computed altitude bucket
3. **Data Retrieval**: The system retrieves the pre-processed data for that bucket from memory or disk cache
4. **Terrain Visualization**: The retrieved data is used to render the terrain with appropriate warning and danger zones

```dart
Future<DecodedLercData?> getDataForAltitude(double altitude) async {
  if (!_isInitialized) return null;

  final nearestAltitude = _findNearestCachedAltitude(altitude);

  // Try memory cache first
  if (_memCache.containsKey(nearestAltitude)) {
    return _memCache[nearestAltitude];
  }

  // Try loading from disk
  final diskData = await _loadFromDisk(nearestAltitude);
  if (diskData != null) {
    _memCache[nearestAltitude] = diskData;
    _limitMemCacheSize();
    return diskData;
  }

  return null;
}
```

## Visual Rendering with Altitude Buckets

The visual rendering system uses altitude buckets to create a stable visualization:

### Terrain Coloring

Terrain is typically colored based on its relationship to the selected altitude bucket:

1. **Below Warning Zone**: Normal terrain coloring (often based on elevation)
2. **Warning Zone**: Yellow or amber coloring (terrain between warning altitude and danger altitude)
3. **Danger Zone**: Red coloring (terrain above the danger altitude)

### Handling Transitions

The system handles transitions between altitude buckets to prevent visual jarring:

1. **Stable Thresholds**: Using fixed buckets prevents rapid threshold changes
2. **Optional Interpolation**: For smoother transitions, interpolation can be used between adjacent buckets (when visual quality is prioritized over performance)

## Performance Considerations

The altitude bucketing system is designed for performance:

1. **Precomputed Data**: Most processing is done during initialization, not at runtime
2. **Sparse Storage**: Only storing relevant points significantly reduces memory usage
3. **Cache Tiering**: Tiered caching (memory and disk) ensures fast access to commonly used buckets
4. **Early Termination**: Processing stops once maximum terrain elevation is reached
   ```dart
   if (altitude - 500.0 > decodedData.maxValue) {
     debugPrint(
       'Skipping altitude ${altitude}m as no points would be above warning threshold',
     );
     break;
   }
   ```

## Trade-offs and Limitations

The altitude bucketing approach involves some trade-offs:

1. **Quantization Effects**: Altitude changes within a bucket don't update the visualization
2. **Initialization Time**: Processing all buckets during initialization takes time
3. **Memory vs. Precision**: Larger bucket steps save memory but reduce precision
4. **Fixed Warning Zones**: Warning zones are fixed at initialization time

## Customization Options

The altitude bucketing system supports customization:

1. **Bucket Step Size**: The altitude step between buckets can be adjusted
2. **Warning Zone Size**: The size of the warning zone relative to the danger threshold
3. **Altitude Range**: The minimum and maximum altitudes for bucketing
4. **Memory Cache Size**: The number of buckets kept in memory simultaneously

These parameters can be adjusted based on specific application requirements, device capabilities, and the characteristics of the terrain data.

## Integration with Other Systems

The altitude bucketing system integrates with several other components of the FlightCanvas Terrain plugin:

1. **Memory Management**: Using sparse storage for efficient memory usage
2. **Terrain Cache**: For efficient retrieval of pre-processed altitude buckets
3. **Multithreaded Processing**: Using isolates for efficient bucket processing
4. **Rendering Pipeline**: Providing stable data to the terrain rendering system

## Example Usage

Here's a simplified example of how altitude bucketing is used in the application:

```dart
class TerrainVisualization {
  final TerrainCache _cache = TerrainCache();
  double _currentAltitude = 1000.0;
  
  // Initialize with terrain data
  Future<void> initialize(Uint8List lercBytes) async {
    await _cache.initialize(lercBytes);
  }
  
  // Update when aircraft altitude changes
  Future<void> updateAltitude(double newAltitude) async {
    // Only update if the nearest bucket would change
    double nearestBucket = (newAltitude / 500).round() * 500;
    double currentBucket = (_currentAltitude / 500).round() * 500;
    
    if (nearestBucket != currentBucket) {
      _currentAltitude = newAltitude;
      await _updateVisualization();
    }
  }
  
  Future<void> _updateVisualization() async {
    final terrainData = await _cache.getDataForAltitude(_currentAltitude);
    if (terrainData != null) {
      _renderTerrain(terrainData, _currentAltitude);
    }
  }
  
  void _renderTerrain(DecodedLercData data, double threshold) {
    // Render terrain with proper coloring for warning and danger zones
    double warningThreshold = threshold - 500.0;
    
    // Rendering logic using the provided bucketed data
    // ...
  }
}
```

## Conclusion

The altitude bucketing system in FlightCanvas Terrain provides an efficient approach to handling terrain visualization at different altitudes. By pre-processing terrain data into discrete altitude buckets and implementing smart caching strategies, the system achieves a good balance between performance, memory usage, and visual quality. This enables the application to provide real-time terrain visualization with appropriate warning and danger zones based on aircraft altitude, enhancing situational awareness for pilots.
