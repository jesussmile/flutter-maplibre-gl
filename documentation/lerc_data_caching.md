# Implementing Caching for Fetched LERC Data

This document describes the caching implementation for LERC terrain data in the FlightCanvas Terrain plugin, which helps to optimize performance and minimize redundant decoding operations.

## Overview

Terrain elevation data in LERC format requires significant processing power to decode, which can affect application performance, especially on mobile devices. The caching system in FlightCanvas Terrain implements a multi-level approach to storing and retrieving decoded elevation data, reducing the need for repeated decoding operations.

## Caching Architecture

The caching system is implemented as a tiered architecture with three distinct layers:

### 1. Memory Cache (Primary)

The memory cache provides the fastest access to decoded terrain data by keeping it in RAM:

- **Implementation**: Using the `TerrainMemoryCache` class in Dart
- **Storage**: Maintains a fixed-size LRU (Least Recently Used) cache
- **Benefits**: Instant access to recently used terrain data with no decoding overhead
- **Limitations**: Limited by available device memory, typically stores 20-50 tiles

```dart
class TerrainMemoryCache {
  final int maxSize;
  final Map<String, DecodedLercData> _cache = {};
  final List<String> _lruList = [];

  TerrainMemoryCache({this.maxSize = 50});

  void put(String key, DecodedLercData data) {
    // If cache is full, evict least recently used item
    if (_cache.length >= maxSize && !_cache.containsKey(key)) {
      String oldestKey = _lruList.removeAt(0);
      _cache.remove(oldestKey);
    }
    
    // Add or update cache
    _cache[key] = data;
    
    // Update LRU tracking
    _lruList.remove(key);
    _lruList.add(key);
  }

  DecodedLercData? get(String key) {
    final data = _cache[key];
    if (data != null) {
      // Update LRU tracking
      _lruList.remove(key);
      _lruList.add(key);
    }
    return data;
  }

  bool contains(String key) => _cache.containsKey(key);
  void remove(String key) {
    _cache.remove(key);
    _lruList.remove(key);
  }
  void clear() {
    _cache.clear();
    _lruList.clear();
  }
  int get size => _cache.length;
}
```

### 2. Persistent Disk Cache

The disk cache stores decoded terrain data on the device's file system for longer-term storage:

- **Implementation**: Custom binary format optimized for each altitude level
- **Storage**: Application documents directory with organized folder structure
- **Benefits**: Persists between application sessions, conserves memory
- **Limitations**: Slower access than memory cache, but much faster than re-decoding

```dart
Future<DecodedLercData?> _loadFromDisk(double altitude) async {
  final file = File(_getCacheFilePath(altitude));
  
  try {
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final buffer = bytes.buffer;
      final dataArray = Float64List.view(buffer);
      
      // First element contains the count of relevant points
      final count = dataArray[0].toInt();
      final referenceAltitude = dataArray[1];
      
      // Create sparse representation from compact storage
      final elevations = Float64List(width * height);
      elevations.fillRange(0, elevations.length, 0);
      
      for (int i = 0; i < count; i++) {
        final value = dataArray[2 + i * 2];
        final index = dataArray[2 + i * 2 + 1].toInt();
        elevations[index] = value;
      }
      
      return DecodedLercData(
        data: elevations,
        width: width,
        height: height,
        minValue: 0,
        maxValue: referenceAltitude,
      );
    }
  } catch (e) {
    debugPrint('Error loading terrain data from disk: $e');
  }
  
  return null;
}

Future<void> _saveToDisk(double altitude, DecodedLercData data) async {
  // Create compact representation for storage
  List<double> relevantElevations = [];
  List<int> relevantIndices = [];
  
  final double warningAltitude = altitude - 500.0; // 500m warning zone
  
  for (int i = 0; i < data.data.length; i++) {
    double elevation = data.data[i] < 0 ? 0 : data.data[i];
    if (elevation >= warningAltitude) {
      relevantElevations.add(elevation);
      relevantIndices.add(i);
    }
  }
  
  // Create compact data format for disk storage
  final compactData = Float64List(2 + relevantElevations.length * 2);
  compactData[0] = relevantElevations.length.toDouble();
  compactData[1] = altitude;
  
  for (int i = 0; i < relevantElevations.length; i++) {
    compactData[2 + i * 2] = relevantElevations[i];
    compactData[2 + i * 2 + 1] = relevantIndices[i].toDouble();
  }
  
  // Write to disk
  final file = File(_getCacheFilePath(altitude));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(compactData.buffer.asUint8List());
}
```

### 3. Original LERC Data (Backup)

The original compressed LERC data serves as a backup source:

- **Implementation**: Stored as raw binary data in its compressed format
- **Storage**: Either bundled with the app or downloaded and stored in app storage
- **Benefits**: Smallest file size, complete source data
- **Limitations**: Requires full decoding to access elevation values

## Cache Key Strategy

Cache keys are designed to be unique and intuitive:

1. **For Tile-Based Data**: Combines zoom level and coordinates
   ```dart
   String tileKey = "${zoom}_${x}_${y}";
   ```

2. **For Altitude-Based Data**: Uses the altitude level, usually rounded to predefined steps
   ```dart
   String altitudeKey = altitude.toString();
   // Or with rounding to nearest bucket
   String altitudeKey = ((altitude / 500).round() * 500).toString();
   ```

## Cache Lookup Sequence

When terrain data is requested, the system follows this lookup sequence:

1. **Check Memory Cache**: First attempt to retrieve from fast in-memory cache
2. **Check Disk Cache**: If not in memory, load from disk cache if available
3. **Decode Original Data**: If not found in either cache, decode from original LERC data
4. **Update Caches**: After decoding, store the result in both memory and disk caches

```dart
Future<DecodedLercData> getTerrainData(String key) async {
  // Try memory cache first
  DecodedLercData? data = memoryCache.get(key);
  if (data != null) {
    return data;
  }
  
  // Try disk cache next
  data = await loadFromDiskCache(key);
  if (data != null) {
    // Add to memory cache for faster future access
    memoryCache.put(key, data);
    return data;
  }
  
  // Fall back to decoding original LERC data
  final lercBytes = await loadOriginalLercData(key);
  data = await LercDecoder.decode(lercBytes);
  
  // Update both caches
  memoryCache.put(key, data);
  await saveToDiscCache(key, data);
  
  return data;
}
```

## Cache Eviction Policies

The cache implements several eviction policies to manage memory usage efficiently:

1. **LRU (Least Recently Used)**: Memory cache removes the least recently used items first
2. **Size-Based Limits**: Fixed maximum number of items in memory cache (configurable)
3. **Manual Clearing**: API for explicitly clearing caches when needed (e.g., low memory conditions)
4. **Altitude-Based Filtering**: Only stores relevant elevation points based on altitude thresholds

## Performance Optimizations

Several optimizations are implemented to maximize cache efficiency:

1. **Sparse Data Storage**: Stores only relevant elevation points rather than full datasets
2. **Binary Format**: Uses compact binary format for disk storage
3. **Lazy Loading**: Defers loading from disk until needed
4. **Background Processing**: Cache operations run in background isolates when possible
5. **Progressive Initialization**: Processes altitude levels sequentially to limit peak memory usage

## Debugging and Monitoring

The caching system includes debugging and monitoring capabilities:

1. **Cache Statistics**: Tracks cache hit/miss rates and sizes
2. **Diagnostic Logging**: Optional debug logging of cache operations
3. **Performance Metrics**: Timing statistics for cache operations

## Conclusion

The multi-tiered caching system in FlightCanvas Terrain provides significant performance benefits by reducing the need for expensive LERC decoding operations. By combining in-memory caching for speed with persistent disk caching for longer-term storage, the plugin achieves a good balance between performance and resource usage. The sparse data structure approach further optimizes memory usage by storing only the data points relevant to the application's needs.
