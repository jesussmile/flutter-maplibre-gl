# Performance Optimization Techniques

This document details the performance optimization techniques used in the FlightCanvas Terrain plugin to ensure smooth terrain rendering and efficient memory usage on resource-constrained mobile devices.

## Overview

Rendering terrain data efficiently on mobile devices presents several challenges:
1. Processing large elevation datasets
2. Performing computationally intensive rendering operations
3. Managing memory constraints
4. Providing a responsive user interface

The FlightCanvas Terrain plugin addresses these challenges through various optimization techniques at different levels of the application.

## Data Processing Optimizations

### 1. Isolate-Based Processing

One of the most important optimizations is the use of Dart isolates for LERC decoding:

```dart
static Future<DecodedLercData> decode(Uint8List bytes) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _isolateFunction,
    _IsolateData(bytes, receivePort.sendPort, libraryPath),
  );

  try {
    final result = await receivePort.first as _IsolateMessage;
    return result.data as DecodedLercData;
  } finally {
    isolate.kill();
    receivePort.close();
  }
}
```

Benefits of isolate-based processing:
- Prevents blocking the UI thread during intensive decoding operations
- Utilizes additional CPU cores for parallel processing
- Maintains UI responsiveness during heavy computation

### 2. Native Code Integration

The plugin leverages native C++ code for the computationally intensive parts:

```dart
// Native function called via FFI
Pointer<Double> lerc_wrapper_decode(
  Pointer<Uint8> buffer,
  int size,
  Pointer<LercInfo> info,
);
```

Benefits of native code integration:
- Significantly faster processing of binary data
- Direct access to optimized LERC library implementations
- Reduced memory overhead for large data operations

### 3. Partial Decoding

For very large datasets, the plugin supports partial decoding of LERC data:

```cpp
// C++ implementation of partial decoding
double* decode_partial_lerc_data(
    const uint8_t* buffer, 
    size_t size,
    uint32_t startX, 
    uint32_t startY, 
    uint32_t width, 
    uint32_t height) {
  // Implementation details
}
```

This allows the application to:
- Load only the visible portion of large terrain datasets
- Reduce memory usage for high-resolution data
- Minimize processing time for initial rendering

## Memory Management Techniques

### 1. LRU Caching

The plugin implements a Least Recently Used (LRU) caching mechanism for decoded terrain data:

```dart
class TerrainMemoryCache {
  final int _maxSize;
  final Map<String, _CacheEntry> _cache = {};
  final LinkedList<_CacheEntry> _lruList = LinkedList();
  
  void put(String key, DecodedLercData data) {
    // If cache is full, remove least recently used item
    if (_cache.length >= _maxSize && !_cache.containsKey(key)) {
      final oldest = _lruList.first;
      _lruList.remove(oldest);
      _cache.remove(oldest.key);
    }
    
    // Add or update cache
    _CacheEntry entry;
    if (_cache.containsKey(key)) {
      entry = _cache[key]!;
      _lruList.remove(entry);
    } else {
      entry = _CacheEntry(key, data);
      _cache[key] = entry;
    }
    
    // Add to end of LRU list (most recently used)
    _lruList.add(entry);
  }
  
  DecodedLercData? get(String key) {
    if (!_cache.containsKey(key)) return null;
    
    // Update LRU status
    final entry = _cache[key]!;
    _lruList.remove(entry);
    _lruList.add(entry);
    
    return entry.data;
  }
}
```

Benefits of LRU caching:
- Prevents redundant decoding of the same data
- Limits memory usage to a predefined maximum
- Automatically prioritizes recently accessed tiles
- Improves responsiveness for repeated views of the same area

### 2. Memory-Mapped File Access

For extremely large datasets, the plugin supports memory-mapped file access:

```dart
class MemoryMappedLERCAccess {
  RandomAccessFile? _file;
  Pointer<Void>? _fileMapping;
  
  Future<void> initialize(String path) async {
    _file = await File(path).open(mode: FileMode.read);
    // Implementation details for platform-specific memory mapping
  }
  
  Future<DecodedLercData?> getRegion(int x, int y, int width, int height) async {
    // Access only the required portion of the file
    // Implementation details
  }
  
  void dispose() {
    // Clean up resources
  }
}
```

Benefits of memory mapping:
- Avoids loading the entire dataset into memory
- Allows operating system to manage memory paging
- Enables working with datasets larger than available RAM
- Reduces application memory footprint

### 3. Adaptive Memory Usage

The plugin dynamically adjusts memory usage based on device capabilities and current memory pressure:

```dart
class AdaptiveMemoryManager {
  int getOptimalCacheSize() {
    // Platform-specific implementation to determine available memory
    // and set appropriate cache size
  }
  
  void handleLowMemory() {
    // Clear non-essential caches
    // Reduce resolution temporarily
    // Release unused resources
  }
}
```

This approach ensures the application:
- Works efficiently across a range of device capabilities
- Responds appropriately to system memory pressure
- Avoids application crashes due to memory limitations
- Gracefully degrades performance when resources are constrained

## Rendering Optimizations

### 1. Level of Detail (LOD) Management

The plugin dynamically adjusts the level of detail based on zoom level:

```dart
class LODManager {
  int getStepSize(double zoom) {
    if (zoom < 5) return 8;      // Sample every 8th point
    else if (zoom < 8) return 4;  // Sample every 4th point
    else if (zoom < 12) return 2; // Sample every 2nd point
    return 1;                     // Full resolution
  }
  
  void renderWithLOD(Canvas canvas, DecodedLercData data, double zoom) {
    int step = getStepSize(zoom);
    
    for (int y = 0; y < data.height; y += step) {
      for (int x = 0; x < data.width; x += step) {
        // Render terrain point
      }
    }
  }
}
```

Benefits of LOD management:
- Reduces the number of points processed and rendered
- Scales detail proportionally to zoom level
- Maintains visual quality at different zoom levels
- Significantly improves rendering performance

### 2. Viewport Culling

The plugin implements viewport culling to only process and render terrain data within the visible area:

```dart
Rect getViewportInTerrainSpace(MapState mapState, LatLngBounds terrainBounds) {
  // Convert map viewport to terrain coordinates
  // Implementation details
}

void renderWithCulling(Canvas canvas, DecodedLercData data, MapState mapState) {
  Rect viewport = getViewportInTerrainSpace(mapState, data.bounds);
  
  // Only process points within the viewport (with some margin)
  int startX = max(0, (viewport.left - 10).floor());
  int endX = min(data.width - 1, (viewport.right + 10).ceil());
  int startY = max(0, (viewport.top - 10).floor());
  int endY = min(data.height - 1, (viewport.bottom + 10).ceil());
  
  for (int y = startY; y <= endY; y++) {
    for (int x = startX; x <= endX; x++) {
      // Render terrain point
    }
  }
}
```

Benefits of viewport culling:
- Eliminates processing of off-screen data points
- Reduces rendering workload proportionally to viewport size
- Improves performance especially at high zoom levels
- Enables working with large terrain datasets efficiently

### 3. Progressive Rendering

For complex terrain visualizations, the plugin implements progressive rendering:

```dart
class ProgressiveRenderer {
  bool _isRendering = false;
  int _currentPass = 0;
  
  void startProgressiveRendering(Canvas canvas, DecodedLercData data) {
    if (_isRendering) return;
    _isRendering = true;
    _currentPass = 0;
    
    // Schedule multiple rendering passes with increasing detail
    _scheduleNextPass(canvas, data);
  }
  
  void _scheduleNextPass(Canvas canvas, DecodedLercData data) {
    Future.microtask(() {
      _renderPass(canvas, data, _currentPass);
      _currentPass++;
      
      if (_currentPass < 4) {  // 4 passes of increasing detail
        _scheduleNextPass(canvas, data);
      } else {
        _isRendering = false;
      }
    });
  }
  
  void _renderPass(Canvas canvas, DecodedLercData data, int passIndex) {
    // Lower passes render fewer points with simpler visualization
    // Higher passes add more detail and effects
    int step = 8 >> passIndex;  // 8, 4, 2, 1
    bool includeHillshade = passIndex > 1;
    
    // Render with appropriate detail level
  }
}
```

Benefits of progressive rendering:
- Provides immediate visual feedback to users
- Distributes rendering workload across multiple frames
- Maintains UI responsiveness during complex visualizations
- Creates a perceptually smoother experience

## User Interaction Optimizations

### 1. Event Throttling and Debouncing

The plugin implements throttling and debouncing for user interaction events:

```dart
class MapInteractionHandler {
  Timer? _throttleTimer;
  Timer? _debounceTimer;
  bool _isThrottled = false;
  
  void handleMapMove(MapPosition position, bool hasGesture) {
    // Throttling: limit frequency of updates during continuous interaction
    if (!_isThrottled) {
      _isThrottled = true;
      
      // Perform minimal update for responsiveness
      _updateTerrainQuickPass(position);
      
      _throttleTimer = Timer(Duration(milliseconds: 100), () {
        _isThrottled = false;
      });
    }
    
    // Debouncing: wait until interaction stops before doing expensive update
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
    }
    
    _debounceTimer = Timer(Duration(milliseconds: 300), () {
      // Perform full quality update when user stops interacting
      _updateTerrainFullQuality(position);
    });
  }
}
```

Benefits of event throttling and debouncing:
- Reduces the frequency of terrain updates during rapid user interactions
- Prevents UI lag during continuous panning and zooming
- Delivers high-quality rendering when interaction pauses
- Balances responsiveness and visual quality

### 2. Preloading and Predictive Loading

The plugin implements preloading of adjacent tiles and predictive loading based on user movement:

```dart
class PredictiveLoader {
  MapPosition _lastPosition = MapPosition();
  LatLng _movementDirection = LatLng(0, 0);
  
  void updatePosition(MapPosition newPosition) {
    // Calculate movement direction
    if (_lastPosition.center != null) {
      _movementDirection = LatLng(
        newPosition.center!.latitude - _lastPosition.center!.latitude,
        newPosition.center!.longitude - _lastPosition.center!.longitude
      );
    }
    
    _lastPosition = newPosition;
    
    // Preload adjacent tiles
    _preloadAdjacentTiles(newPosition);
    
    // Preload in the direction of movement
    if (_movementDirection.latitude != 0 || _movementDirection.longitude != 0) {
      _preloadInDirection(_movementDirection);
    }
  }
}
```

Benefits of preloading:
- Reduces perception of loading delays during navigation
- Improves responsiveness when panning and zooming
- Utilizes idle time to prepare data that may be needed soon
- Creates a more seamless user experience

## Buffering Techniques

### 1. Double Buffering

For smooth updates during animations or continuous changes, the plugin implements double buffering:

```dart
class TerrainRenderer {
  ui.Image? _frontBuffer;
  ui.Image? _backBuffer;
  bool _isUpdating = false;
  
  Future<void> updateTerrain(DecodedLercData data) async {
    if (_isUpdating) return;
    _isUpdating = true;
    
    // Render new terrain to the back buffer
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    
    // Perform terrain rendering
    _renderTerrain(canvas, data);
    
    // Convert to image
    ui.Picture picture = recorder.endRecording();
    ui.Image newImage = await picture.toImage(data.width, data.height);
    
    // Swap buffers
    _backBuffer = _frontBuffer;
    _frontBuffer = newImage;
    
    _isUpdating = false;
  }
  
  void paint(Canvas canvas, Size size) {
    if (_frontBuffer != null) {
      // Paint the front buffer (most recent complete rendering)
      canvas.drawImage(_frontBuffer!, Offset.zero, Paint());
    }
  }
}
```

Benefits of double buffering:
- Eliminates visual tearing during updates
- Provides smooth transitions between states
- Maintains a consistent visual display during rendering
- Improves perceived performance and responsiveness

### 2. Tile Buffering

The plugin implements tile buffering to manage multiple terrain tiles efficiently:

```dart
class TileBuffer {
  final Map<String, DecodedLercData> _loadedTiles = {};
  final Set<String> _visibleTileKeys = {};
  final Set<String> _loadingTiles = {};
  
  void updateVisibleTiles(List<TileCoordinates> visibleCoordinates) {
    // Update tracking of which tiles are visible
    _visibleTileKeys.clear();
    for (var coord in visibleCoordinates) {
      String key = _getTileKey(coord);
      _visibleTileKeys.add(key);
      
      if (!_loadedTiles.containsKey(key) && !_loadingTiles.contains(key)) {
        _loadTile(coord);
      }
    }
    
    // Clean up tiles that are no longer visible or nearby
    _cleanupTiles();
  }
  
  Future<void> _loadTile(TileCoordinates coord) async {
    String key = _getTileKey(coord);
    _loadingTiles.add(key);
    
    try {
      // Load and decode tile
      Uint8List lercData = await _fetchTileData(coord);
      DecodedLercData decodedData = await LercDecoder.decode(lercData);
      
      // Store in buffer
      _loadedTiles[key] = decodedData;
    } finally {
      _loadingTiles.remove(key);
    }
  }
  
  void _cleanupTiles() {
    // Remove tiles that are not visible and not adjacent to visible tiles
    // Implementation details
  }
}
```

Benefits of tile buffering:
- Manages loading and unloading of terrain data in chunks
- Optimizes memory usage by keeping only necessary tiles
- Provides a framework for prefetching and caching
- Enables working with theoretically unlimited terrain extents

## Conclusion

The FlightCanvas Terrain plugin employs a comprehensive set of performance optimization techniques to deliver responsive and efficient terrain visualization on mobile devices. By carefully managing memory usage, optimizing rendering operations, and implementing sophisticated buffering techniques, the plugin achieves a balance between visual quality and performance.

These optimizations enable the plugin to handle complex terrain datasets and provide smooth user interactions even on devices with limited processing power and memory. The multi-layered approach to optimization ensures that the plugin can scale to different device capabilities while maintaining a consistent user experience.
