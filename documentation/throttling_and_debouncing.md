# Throttling and Debouncing for Map Updates

This document describes the implementation of throttling and debouncing mechanisms for map events that trigger terrain tile updates in the FlightCanvas Terrain project.

## Overview

When users interact with a map by panning, zooming, or rotating, these actions can generate a large number of update events in a short time. Without proper management, these events can lead to excessive tile requests, rendering operations, and memory allocation, resulting in poor performance or visual artifacts. To address this, the FlightCanvas Terrain project implements throttling and debouncing techniques.

## Key Concepts

### Throttling vs. Debouncing

- **Throttling**: Limits the frequency of a function's execution to once per specified time interval, even if the event that triggers it occurs more frequently. For example, limit to once every 100ms.

- **Debouncing**: Delays a function's execution until after a specified time has passed since the last time it was invoked. For example, wait 200ms after the last event before executing.

## Implementation Details

### Timer Settings Configuration

The project includes a centralized `TimerSettings` class to manage timing configurations:

```dart
class TimerSettings {
  // Singleton instance
  static final TimerSettings _instance = TimerSettings._internal();
  
  // Factory constructor for singleton
  factory TimerSettings() {
    return _instance;
  }
  
  // Private constructor
  TimerSettings._internal();
  
  // Configurable settings
  int tileUpdateDelay = 30;      // Milliseconds between tile updates
  int cleanupInterval = 20000;   // Milliseconds between cache cleanup
  int maxPendingUpdates = 5;     // Maximum concurrent tile updates
  
  // Platform detection
  bool get isIOS17OrHigher {
    if (!Platform.isIOS) return false;
    // Detect iOS 17 or higher for platform-specific optimizations
    return true; // Simplified for documentation
  }
}
```

### Map Event Throttling

Map movement events are throttled to prevent excessive terrain updates during rapid interaction:

```dart
class _TerrainMapScreenState extends State<TerrainMapScreen> {
  // Map controller and event handling
  late MapController mapController;
  
  // Throttling-related variables
  Timer? _zoomStabilizeTimer;
  Timer? _terrainUpdateTimer;
  bool _isZooming = false;
  double _currentZoomLevel = 10.0;
  
  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _setupMapEventThrottling();
  }
  
  void _setupMapEventThrottling() {
    // Listen to map events with throttling
    mapController.mapEventStream.listen((event) {
      if (event is MapEventMove) {
        final newZoomLevel = event.camera.zoom;
        
        // Only process zoom changes
        if (_currentZoomLevel != newZoomLevel) {
          _debugTerrainStatus("Zoom changed: $_currentZoomLevel → $newZoomLevel");
          _currentZoomLevel = newZoomLevel;
          
          // Set flag to indicate active zooming
          _isZooming = true;
          
          // Throttle updates during active zooming
          if (!_isSliderDragging) {
            _setHighZoomMode(false);
            
            // Cancel previous timer to implement debouncing
            _zoomStabilizeTimer?.cancel();
            
            // Debounce terrain stabilization after zoom
            _zoomStabilizeTimer = Timer(const Duration(milliseconds: 300), () {
              _isZooming = false;
              _forceTerrainRefresh();
            });
          }
        }
      }
    });
  }
}
```

### Altitude Change Debouncing

Altitude changes (e.g., from slider movement) are debounced to prevent excessive terrain updates:

```dart
void _applyAltitudeChange(double value) {
  // Update reference altitude immediately for UI responsiveness
  _referenceAltitude.value = value;
  
  // Debounce terrain updates
  _terrainUpdateTimer?.cancel();
  _terrainUpdateTimer = Timer(const Duration(milliseconds: 200), () {
    // Only perform update after the debounce period
    if (mounted) setState(() {});
  });
}
```

### Tile Update Throttling

The `LercTileProvider` implements throttling for tile updates based on altitude changes:

```dart
class _LercTileImage extends ImageProvider<_LercTileImage> {
  // Properties and constructor...
  
  @override
  ImageStreamCompleter loadImage(_LercTileImage key, ImageDecoderCallback decode) {
    // Check if we have cached pixel data
    final cachedPixelData = pixelCache[_renderedImageKey];
    if (cachedPixelData != null) {
      // Use cached data for immediate response
      final completer = OneFrameImageStreamCompleter(
        _createImageFromPixels(cachedPixelData, 256, 256),
      );
      _currentCompleter = completer;
      
      // Throttle update frequency
      if (LercTileProvider._pendingTileUpdates.length < TimerSettings().maxPendingUpdates) {
        // Throttle based on current conditions
        final updateDelay = _calculateUpdateDelay();
        
        Future.delayed(Duration(milliseconds: updateDelay), () {
          // Only queue updates if the difference is still significant
          final currentAltitude = LercTileProvider._currentAltitude;
          final renderedAltitude = double.tryParse(_bucketedAltitude) ?? 0;
          final altDifference = (currentAltitude - renderedAltitude).abs();
          
          // Adaptive threshold based on altitude bucket size
          final updateThreshold = math.max(100, altitudeBucketSize * 0.5);
          
          if (altDifference >= updateThreshold) {
            LercTileProvider.queueTileUpdate(_renderedImageKey, this);
          }
        });
      }
      
      return completer;
    }
    
    // Handle uncached case...
  }
  
  // Calculate appropriate update delay based on conditions
  int _calculateUpdateDelay() {
    final timerSettings = TimerSettings();
    final currentAltitude = LercTileProvider._currentAltitude;
    final renderedAltitude = double.tryParse(_bucketedAltitude) ?? 0;
    final altDifference = (currentAltitude - renderedAltitude).abs();
    
    // Platform and situation-specific delays
    if (timerSettings.isIOS17OrHigher) {
      // iOS 17 requires more aggressive updates for significant changes
      return altDifference > 300
          ? timerSettings.tileUpdateDelay ~/ 2
          : altDifference > 100
              ? timerSettings.tileUpdateDelay
              : timerSettings.tileUpdateDelay * 2;
    } else {
      // Standard throttling for other platforms
      return altDifference > 300
          ? timerSettings.tileUpdateDelay
          : altDifference > 100
              ? timerSettings.tileUpdateDelay * 2
              : timerSettings.tileUpdateDelay * 3;
    }
  }
}
```

### Update Queue Management

The `LercTileProvider` implements a queue system to prevent too many concurrent updates:

```dart
// Static variables in LercTileProvider
static bool _isUpdateScheduled = false;
static final Map<String, _LercTileImage> _pendingTileUpdates = {};

// Queue a tile for update
static void queueTileUpdate(String key, _LercTileImage tile) {
  // Add to pending updates
  _pendingTileUpdates[key] = tile;
  
  // Schedule processing if not already scheduled
  if (!_isUpdateScheduled) {
    _scheduleUpdate();
  }
}

// Process the update queue with throttling
static void _scheduleUpdate() {
  _isUpdateScheduled = true;
  
  // Schedule update with throttling
  Future.delayed(Duration(milliseconds: TimerSettings().tileUpdateDelay), () {
    // Process a limited number of updates
    final keysToProcess = _pendingTileUpdates.keys.take(5).toList();
    
    for (final key in keysToProcess) {
      final tile = _pendingTileUpdates.remove(key);
      if (tile != null) {
        tile._rerender();
      }
    }
    
    // If there are still pending updates, schedule another processing round
    if (_pendingTileUpdates.isNotEmpty) {
      _scheduleUpdate();
    } else {
      _isUpdateScheduled = false;
    }
  });
}
```

## Rendering Mode Optimizations

The project implements additional optimizations for different rendering scenarios:

### High-Zoom Mode

During active zooming or altitude changes, a high-zoom mode can be enabled for better performance:

```dart
void _setHighZoomMode(bool enabled) {
  // Enable special rendering mode for better performance during interaction
  LercTileProvider.setHighZoomMode(enabled);
  _debugTerrainStatus(
    "High zoom mode ${enabled ? 'ENABLED' : 'DISABLED'} at zoom $_currentZoomLevel",
  );
}
```

### Forced Refresh with Debouncing

When applying changes that require a complete refresh, debouncing is used:

```dart
void _forceTerrainRefresh() {
  // Cancel any pending updates
  _terrainUpdateTimer?.cancel();
  
  // Apply a small change to trigger refresh
  final currentAlt = _referenceAltitude.value;
  
  // Delay slightly to allow rendering mode change to take effect
  Future.delayed(const Duration(milliseconds: 50), () {
    // Small change to force re-rendering
    _applyAltitudeChange(currentAlt + 0.5);
    
    // Restore original value after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      _applyAltitudeChange(currentAlt);
    });
  });
}
```

## Platform-Specific Optimizations

The throttling and debouncing implementation includes platform-specific optimizations:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Platform-specific optimizations
  final timerSettings = TimerSettings();
  
  if (Platform.isAndroid) {
    // Android needs longer delays due to performance characteristics
    timerSettings.tileUpdateDelay = 40;
  } else if (Platform.isIOS) {
    // iOS is generally more responsive
    timerSettings.tileUpdateDelay = 20;
  }
  
  // Continue with app initialization
  await LercDecoder.initialize();
  runApp(const MyApp());
}
```

## Timer Settings Overlay

For debugging and fine-tuning, the application includes a timer settings overlay:

```dart
class TimerSettingsOverlay extends StatefulWidget {
  @override
  State<TimerSettingsOverlay> createState() => _TimerSettingsOverlayState();
}

class _TimerSettingsOverlayState extends State<TimerSettingsOverlay> {
  final timerSettings = TimerSettings();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Tile Update Delay: ${timerSettings.tileUpdateDelay}ms"),
          Slider(
            min: 10,
            max: 100,
            value: timerSettings.tileUpdateDelay.toDouble(),
            onChanged: (value) {
              setState(() {
                timerSettings.tileUpdateDelay = value.toInt();
              });
            },
          ),
          // Additional settings controls...
        ],
      ),
    );
  }
}
```
