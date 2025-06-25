# Basic Terrain Display UI Controls

This document describes the implementation of user interface controls for controlling and interacting with the terrain visualization in the FlightCanvas Terrain project.

## Overview

The FlightCanvas Terrain project includes a comprehensive set of UI controls that allow users to:

1. Toggle the visibility of the terrain layer
2. Adjust the reference altitude
3. Switch between different rendering modes
4. Control visualization parameters
5. View terrain statistics and debug information

## Implementation Details

### Main UI Components

The main UI controls are implemented in the application's main screen:

```dart
class _TerrainMapScreenState extends State<TerrainMapScreen> {
  // MapController for interacting with the map
  late MapController mapController;
  
  // State variables for UI controls
  final ValueNotifier<double> _referenceAltitude = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _useGradientMode = ValueNotifier<bool>(true);
  final ValueNotifier<double> _terrainResolution = ValueNotifier<double>(100.0);
  final ValueNotifier<bool> _showTerrain = ValueNotifier<bool>(true);
  
  // Additional state variables
  bool _isZooming = false;
  bool _isSliderDragging = false;
  double _currentZoomLevel = 10.0;
  
  // State for debugging and info
  final ValueNotifier<String> _terrainDebugInfo = ValueNotifier<String>("");
  
  // Timer-related variables
  Timer? _zoomStabilizeTimer;
  Timer? _terrainUpdateTimer;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map with terrain layers
          _buildMap(),
          
          // UI controls overlay
          _buildUIControls(),
          
          // Debug information overlay
          _buildDebugOverlay(),
        ],
      ),
    );
  }
}
```

### Terrain Visibility Toggle

A simple toggle switch for enabling/disabling the terrain layer:

```dart
Widget _buildTerrainToggle() {
  return ValueListenableBuilder<bool>(
    valueListenable: _showTerrain,
    builder: (context, showTerrain, child) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Terrain"),
          Switch(
            value: showTerrain,
            onChanged: (value) {
              _showTerrain.value = value;
              _debugTerrainStatus(
                "Terrain ${value ? 'ENABLED' : 'DISABLED'}",
              );
            },
          ),
        ],
      );
    },
  );
}
```

### Reference Altitude Control

The application provides an intuitive control for adjusting the reference altitude:

```dart
Widget _buildAltitudeSlider() {
  return ValueListenableBuilder<double>(
    valueListenable: _referenceAltitude,
    builder: (context, altitude, child) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Altitude: ${altitude.round()} ft",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            width: 300,
            child: Slider(
              min: 0,
              max: 30000,
              value: altitude,
              onChanged: (value) {
                _setHighZoomMode(true); // Enable high-performance mode during slider drag
                _isSliderDragging = true;
                _applyAltitudeChange(value);
              },
              onChangeEnd: (value) {
                _isSliderDragging = false;
                _setHighZoomMode(false); // Disable high-performance mode after drag
              },
            ),
          ),
        ],
      );
    },
  );
}

// Apply altitude change with debouncing
void _applyAltitudeChange(double value) {
  // Update the reference altitude immediately
  _referenceAltitude.value = value;
  
  // Debounce terrain updates for smooth interaction
  _terrainUpdateTimer?.cancel();
  _terrainUpdateTimer = Timer(const Duration(milliseconds: 200), () {
    // Additional updates after debounce period
    if (mounted) setState(() {});
  });
}
```

### Rendering Mode Controls

Controls for switching between different terrain rendering modes:

```dart
Widget _buildRenderingModeToggle() {
  return ValueListenableBuilder<bool>(
    valueListenable: _useGradientMode,
    builder: (context, useGradientMode, child) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Gradient Mode"),
          Switch(
            value: useGradientMode,
            onChanged: (value) {
              _useGradientMode.value = value;
              _debugTerrainStatus(
                "Rendering mode changed to ${value ? 'GRADIENT' : 'SIMPLE'} - refreshing terrain",
              );
              _forceTerrainRefresh();
            },
          ),
        ],
      );
    },
  );
}
```

### Resolution Control

A slider for adjusting the terrain resolution:

```dart
Widget _buildResolutionSlider() {
  return ValueListenableBuilder<double>(
    valueListenable: _terrainResolution,
    builder: (context, resolution, child) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Resolution: ${resolution.round()} m",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            width: 200,
            child: Slider(
              min: 10,
              max: 500,
              value: resolution,
              onChanged: (value) {
                _terrainResolution.value = value;
              },
            ),
          ),
        ],
      );
    },
  );
}
```

### Debug Information Display

A display for showing technical information about the terrain rendering:

```dart
Widget _buildDebugOverlay() {
  return Positioned(
    bottom: 10,
    left: 10,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main debug info from terrain layer
          ValueListenableBuilder<String>(
            valueListenable: LercTileProvider.debugStats,
            builder: (context, stats, child) {
              return Text(
                stats,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
              );
            },
          ),
          // Custom debug info
          ValueListenableBuilder<String>(
            valueListenable: _terrainDebugInfo,
            builder: (context, info, child) {
              if (info.isEmpty) return Container();
              return Text(
                info,
                style: const TextStyle(
                  color: Colors.yellow,
                  fontFamily: 'monospace',
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}
```

### Map Interaction Handling

The application implements special handling for map interactions to optimize terrain updates:

```dart
void _initMapEventListeners() {
  // Set initial terrain modes
  LercTileProvider.setHighZoomMode(false);
  LercTileProvider.setGradientMode(_useGradientMode.value);
  
  // Listen for rendering mode changes
  _useGradientMode.addListener(() {
    LercTileProvider.setGradientMode(_useGradientMode.value);
    _debugTerrainStatus(
      "Rendering mode changed to ${_useGradientMode.value ? 'GRADIENT' : 'SIMPLE'} - refreshing terrain",
    );
    _forceTerrainRefresh();
  });
  
  // Listen for map movement events
  mapController.mapEventStream.listen((event) {
    if (event is MapEventMove) {
      final newZoomLevel = event.camera.zoom;
      
      if (_currentZoomLevel != newZoomLevel) {
        _debugTerrainStatus(
          "Zoom changed: $_currentZoomLevel → $newZoomLevel",
        );
        _currentZoomLevel = newZoomLevel;
        
        // Handle zoom changes
        if (!_isSliderDragging) {
          _setHighZoomMode(false);
          
          // Stabilize terrain after zoom
          _zoomStabilizeTimer?.cancel();
          _zoomStabilizeTimer = Timer(const Duration(milliseconds: 300), () {
            _isZooming = false;
            _forceTerrainRefresh();
          });
        }
      }
    }
  });
}
```

### Toggle High Zoom Mode

A utility method for managing high-zoom rendering mode:

```dart
void _setHighZoomMode(bool enabled) {
  LercTileProvider.setHighZoomMode(enabled);
  _debugTerrainStatus(
    "High zoom mode ${enabled ? 'ENABLED' : 'DISABLED'} at zoom $_currentZoomLevel",
  );
}
```

### Force Terrain Refresh

A utility method to force a complete refresh of the terrain rendering:

```dart
void _forceTerrainRefresh() {
  // First clear any pending updates
  _terrainUpdateTimer?.cancel();
  
  // Apply a small shift to altitude to force re-rendering
  final currentAlt = _referenceAltitude.value;
  
  // Wait briefly for the rendering mode change to take effect
  Future.delayed(const Duration(milliseconds: 50), () {
    // Apply a small change to trigger complete re-rendering
    _applyAltitudeChange(currentAlt + 0.5);
    
    // Then restore the original value after a short delay to avoid flicker
    Future.delayed(const Duration(milliseconds: 100), () {
      _applyAltitudeChange(currentAlt);
    });
  });
}
```

## UI Layout Organization

The controls are organized in the main stack with the map:

```dart
Widget _buildUIControls() {
  return Positioned(
    top: MediaQuery.of(context).padding.top + 10,
    left: 10,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTerrainToggle(),
          const SizedBox(height: 8),
          _buildRenderingModeToggle(),
          const SizedBox(height: 8),
          _buildAltitudeSlider(),
          const SizedBox(height: 8),
          _buildResolutionSlider(),
        ],
      ),
    ),
  );
}
```

## Usage in Main Application

The UI controls are integrated in the main application structure:

```dart
@override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'Terrain Visualization',
    theme: ThemeData.dark(),
    home: TerrainMapScreen(),
  );
}
```

## Platform-Specific Optimizations

The UI includes platform-specific optimizations for better performance:

```dart
// Detect platform and adjust UI behavior
final bool isIOS = Platform.isIOS;

// iOS-specific wheel slider implementation
Widget _buildIosWheelSlider() {
  return Container(
    height: 150,
    width: 100,
    child: WheelSlider(
      perspective: 0.01,
      totalCount: 300,  // 30,000 feet in steps of 100
      initValue: (_referenceAltitude.value / 100).round(),
      onValueChanged: (val) {
        _setHighZoomMode(true);
        _isSliderDragging = true;
        _applyAltitudeChange(val * 100);
      },
      hapticFeedback: true,
      showSecondBorder: false,
      itemSize: 50,
      onValueChangeEnd: (_) {
        _isSliderDragging = false;
        _setHighZoomMode(false);
      },
    ),
  );
}
```

## Timer Settings for Performance

The application includes a configurable timer system for performance optimization:

```dart
// Initialize timer settings with optimized values based on platform
final timerSettings = TimerSettings();

// Set platform-specific tile update delay
if (Platform.isAndroid) {
  timerSettings.tileUpdateDelay = 40; // Android-specific value
} else if (Platform.isIOS) {
  timerSettings.tileUpdateDelay = 20; // iOS is generally faster
}
```
