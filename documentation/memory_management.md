# Memory Management for Decoded LERC Data

This document describes the memory management strategies implemented in the FlightCanvas Terrain plugin for handling decoded terrain elevation data, especially for large datasets.

## Overview

Terrain elevation data can be extremely memory-intensive due to the high resolution required for accurate visualization. The FlightCanvas Terrain plugin implements several strategies to efficiently manage memory for decoded LERC data, balancing performance and resource usage.

## Memory Management Challenges

Working with terrain data presents several memory-related challenges:

1. **Large Dataset Sizes**: Full-resolution terrain datasets can easily consume hundreds of megabytes of memory
2. **Limited Mobile Resources**: Mobile devices have constrained memory compared to desktop environments
3. **Real-time Rendering Requirements**: The application must maintain smooth rendering performance while processing data
4. **Multiple Zoom Levels**: Different zoom levels may require different resolution datasets
5. **Altitude-based Filtering**: The application needs to efficiently filter terrain data based on altitude thresholds

## Key Memory Management Strategies

### 1. Tiered Caching System

The plugin implements a tiered caching system that optimizes memory usage across different storage types:

#### Memory Cache (RAM)

- Implemented in `TerrainCache` class as `_memCache` 
- Stores a limited number of recently used terrain datasets in memory
- Uses a fixed-size LRU (Least Recently Used) approach
- Automatically removes oldest entries when the cache size limit is reached

```dart
void _limitMemCacheSize() {
  if (_memCache.length > maxMemCacheSize) {
    debugPrint(
      'Memory cache full (${_memCache.length} items), removing oldest entries',
    );
    final sortedKeys = _memCache.keys.toList()..sort();
    while (_memCache.length > maxMemCacheSize) {
      final keyToRemove = sortedKeys.removeAt(0);
      _memCache.remove(keyToRemove);
      debugPrint('Removed altitude ${keyToRemove}m from memory cache');
    }
  }
}
```

#### Disk Cache

- Stores processed terrain data on device storage
- Uses a custom binary format that optimizes for space efficiency
- Only stores elevation points that are relevant for specific altitude levels

```dart
Future<void> _saveToDisk(double altitude, DecodedLercData data) async {
  // Create a more efficient data structure to store only relevant points
  List<double> relevantElevations = [];
  List<int> relevantIndices = [];
  
  // Only store points in warning or danger zones
  for (int i = 0; i < data.data.length; i++) {
    double elevation = data.data[i] < 0 ? 0 : data.data[i];
    if (elevation >= warningAltitude) {
      relevantElevations.add(elevation);
      relevantIndices.add(i);
    }
  }
  
  // Create compact storage format
  final compactData = Float64List(2 + relevantElevations.length * 2);
  compactData[0] = relevantElevations.length.toDouble();
  compactData[1] = altitude;
  
  // Store elevation and index pairs
  for (int i = 0; i < relevantElevations.length; i++) {
    compactData[2 + i * 2] = relevantElevations[i];
    compactData[2 + i * 2 + 1] = relevantIndices[i].toDouble();
  }
  
  // Write the compact data to disk
  final file = File(_getCacheFilePath(altitude));
  final bytes = compactData.buffer.asUint8List();
  await file.writeAsBytes(bytes);
}
```

#### Original LERC Data

- Maintains the original compressed LERC data for full dataset reprocessing if needed
- LERC format provides significant compression compared to raw elevation data

### 2. Sparse Data Structures

Rather than storing full raster grids for each altitude level, the plugin uses sparse data structures:

- **Index-Value Pairs**: Only stores elevations that are relevant for a specific altitude threshold
- **Sparse Reconstruction**: Efficiently reconstructs full datasets when needed
- **Zero-Value Optimization**: Since most terrain points are below warning/danger thresholds, zeros are implied rather than stored

```dart
// Create full-size data array initialized to 0
final fullData = Float64List(_dataWidth! * _dataHeight!);

// Restore only the relevant points
for (int i = 0; i < numPoints; i++) {
  final elevation = compactData[2 + i * 2];
  final index = compactData[2 + i * 2 + 1].toInt();
  fullData[index] = elevation;
}
```

### 3. Isolate-Based Processing

The plugin uses Dart isolates for memory-efficient processing:

- **Separate Memory Heaps**: Each isolate has its own memory heap, preventing the main UI thread from being affected by large data processing
- **Memory Cleanup**: Memory allocated in worker isolates is automatically reclaimed when the isolate completes its task
- **Explicit Resource Management**: Native resources are explicitly freed using cleanup functions

```dart
static void _isolateFunction(_IsolateData isolateData) {
  try {
    // Allocate memory for processing
    final inputPtr = malloc<Uint8>(bytes.length);
    
    try {
      // Decoding process...
    } finally {
      // Explicit cleanup of native resources
      malloc.free(inputPtr);
      if (infoPtr != nullptr) {
        bindings.lerc_wrapper_free_info(infoPtr);
      }
      if (dataPtr != nullptr) {
        bindings.lerc_wrapper_free_data(dataPtr);
      }
    }
  } catch (e) {
    // Error handling...
  }
}
```

### 4. Altitude Bucketing and Data Filtering

The plugin implements an altitude bucketing system to reduce memory requirements:

- **Altitude Levels**: Data is processed and stored for specific altitude levels (e.g., every 500m)
- **Warning Zones**: Includes "warning zones" below danger thresholds to enable smooth visualization
- **Nearest Bucket Selection**: Runtime queries use the nearest pre-computed altitude bucket

```dart
double _findNearestCachedAltitude(double targetAltitude) {
  return (targetAltitude / altitudeStep).round() * altitudeStep;
}

Future<DecodedLercData?> getDataForAltitude(double altitude) async {
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

### 5. Progressive Data Loading

The plugin implements progressive data loading to manage memory during initialization:

- **Sequential Processing**: Processes altitude levels sequentially to limit peak memory usage
- **Progress Tracking**: Provides loading progress updates to allow for UI feedback
- **Early Termination**: Skips processing for altitude levels with no relevant data

```dart
double altitude = altitudeStep;
int totalLevels = ((maxAltitude - minAltitude) / altitudeStep).ceil() + 1;
int completedLevels = 1;

while (altitude <= maxAltitude) {
  if (altitude - 500.0 > firstData.maxValue) {
    // Skip processing if no relevant points would be found
    break;
  }

  final decodedData = await LercIsolateDecoder.decode(_lercBytes!);
  await _saveToDisk(altitude, decodedData);
  
  completedLevels++;
  loadingProgress.value = completedLevels / totalLevels;
  altitude += altitudeStep;
}
```

### 6. Native Memory Management

On the native side, the C++ LERC wrapper handles memory with several strategies:

- **Ownership Transfer**: Clear ownership rules for memory allocated in C++
- **Explicit Deallocation Functions**: Exposed functions for freeing memory from Dart
- **Error Handling**: Robust error handling to prevent memory leaks even in failure cases

## Memory Usage Patterns

### Initialization Phase

During initialization, memory usage follows this pattern:

1. Original LERC data is loaded into memory (compressed format)
2. Each altitude level is processed in sequence:
   - LERC data is decoded in an isolate
   - Relevant elevation points are extracted
   - Compact representation is saved to disk
   - Full decoded data is discarded
3. Basic metadata is retained for future reconstructions

### Runtime Phase

During runtime operation, memory usage follows this pattern:

1. Application requests data for a specific altitude threshold
2. System checks if the requested altitude data is in the memory cache
3. If not found, it loads the compact representation from disk
4. Sparse data is reconstructed into a full dataset only when needed
5. LRU cache management ensures memory usage stays within limits

## Memory Optimization Techniques

### 1. Typed Data Usage

The plugin consistently uses typed data structures for efficiency:

- **Float64List**: For elevation data to maintain precision
- **Uint8List**: For binary data transfer 
- **TypedData Views**: For efficient buffer manipulations without copying

### 2. Buffer Reuse

Where possible, the plugin reuses existing buffers rather than allocating new ones:

- **In-place Processing**: Algorithms are designed to modify data in-place when possible
- **Buffer Pooling**: Reuses buffers for similar operations

### 3. Explicit Cleanup

The plugin implements explicit cleanup mechanisms:

- **Cache Clearing**: Methods to clear caches when data is no longer needed
- **Isolate Termination**: Properly terminates worker isolates
- **Native Resource Freeing**: Consistently frees native resources

```dart
Future<void> clear() async {
  _memCache.clear();
  _lercBytes = null;
  _isInitialized = false;
  loadingProgress.value = 0.0;

  // Clean up cache directory
  if (await _cacheDir.exists()) {
    debugPrint('Clearing terrain cache directory: ${_cacheDir.path}');
    await _cacheDir.delete(recursive: true);
  }
}
```

## Monitoring and Debugging

The plugin includes several features to help monitor memory usage:

- **Debug Logging**: Comprehensive logging of memory operations
- **Cache Statistics**: Tracking of cache sizes and hit rates
- **File Size Reporting**: Reports on the size of generated cache files

```dart
// Get and log the file size
final fileSize = await file.length();
final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);
debugPrint(
  'File size for altitude ${altitude}m: $fileSizeKB KB (${fileSize} bytes)',
);
```

## Conclusion

The memory management system in the FlightCanvas Terrain plugin demonstrates a comprehensive approach to handling large terrain datasets efficiently. By combining multiple strategies including tiered caching, sparse data structures, isolate-based processing, and native resource management, the plugin achieves good performance while minimizing memory usage even on resource-constrained mobile devices.

These memory management techniques enable the application to work with high-resolution terrain data without overwhelming device resources, providing a smooth user experience during navigation and visualization of terrain features.
