# Custom Flutter Map Terrain Layer

This document describes the implementation of the custom Flutter Map Layer for rendering LERC-encoded terrain elevation data.

## Overview

The custom terrain layer extends the Flutter Map framework to add specialized terrain visualization capabilities. It integrates with the `LercTileProvider` to display elevation data with various visualization options.

## Implementation Details

### Layer Structure

The terrain layer implementation consists of several key components:

1. **Main Layer Widget**: Manages layer state and configuration
2. **Terrain Rendering**: Handles the visual representation of elevation data
3. **Integration with Flutter Map**: Hooks into the map's coordinate system and rendering pipeline

### Main Layer Implementation

```dart
class LocalLercLayer extends StatefulWidget {
  final DecodedLercData data;
  final ValueNotifier<double> referenceAltitude;
  final ValueNotifier<double> terrainResolution;
  final ValueChanged<double>? onElevationRead;
  final ValueChanged<String>? onDebugMessage;

  const LocalLercLayer({
    Key? key,
    required this.data,
    required this.referenceAltitude,
    required this.terrainResolution,
    this.onElevationRead,
    this.onDebugMessage,
  }) : super(key: key);

  @override
  State<LocalLercLayer> createState() => _LocalLercLayerState();
}
```

### State Management

The state class handles initialization, updates, and terrain settings:

```dart
class _LocalLercLayerState extends State<LocalLercLayer> {
  // Cached provider to avoid recreation
  LercTileProvider? _cachedProvider;
  double? _cachedReferenceAltitude;
  double? _cachedTerrainResolution;
  LercTileProvider? _currentProvider;
  
  // Last rendered altitude for optimization
  double _lastRenderedAltitude = 0.0;
  
  // Terrain settings
  late _TerrainSettings _terrainSettings;
  
  @override
  void initState() {
    super.initState();
    _terrainSettings = _TerrainSettings();
    _terrainSettings.warningAltitude = 15000;
    
    // Initialize with current altitude
    _updateAltitude(widget.referenceAltitude.value);
    
    // Listen for altitude changes
    widget.referenceAltitude.addListener(() {
      _updateAltitude(widget.referenceAltitude.value);
    });
  }
}
```

### Integration with Flutter Map

The layer integrates with Flutter Map by returning a standard map layer structure with a custom tile provider:

```dart
@override
Widget build(BuildContext context) {
  // Get or create the tile provider
  final provider = _getProvider();
  _currentProvider = provider;
  
  return RepaintBoundary(
    child: Stack(
      children: [
        // Background layers
        Positioned.fill(child: Container(color: Colors.black)),
        
        // TileLayer with terrain provider
        Positioned.fill(
          child: TileLayer(
            tileProvider: provider,
            maxZoom: 19,
            minZoom: 1,
            urlTemplate: "unused", // Required by Flutter Map but not used
            tileDisplay: const TileDisplay.instantaneous(),
            keepBuffer: 20,
          ),
        ),
      ],
    ),
  );
}
```

### Provider Management

The layer manages the `LercTileProvider` instance to optimize performance and prevent unnecessary recreations:

```dart
// Get or create provider, avoiding recreation when possible
LercTileProvider _getProvider() {
  final currentAltitude = _terrainSettings.referenceAltitude;
  final currentResolution = widget.terrainResolution.value;

  // If altitude or resolution changed, we need a new provider
  if (_cachedProvider == null ||
      _cachedReferenceAltitude != currentAltitude ||
      _cachedTerrainResolution != currentResolution) {
    _cachedProvider = LercTileProvider(
      data: widget.data,
      referenceAltitude: currentAltitude,
      warningAltitude: _terrainSettings.warningAltitude,
      minElevation: widget.data.minValue,
      terrainResolution: currentResolution,
      onElevationRead: widget.onElevationRead,
    );

    _cachedReferenceAltitude = currentAltitude;
    _cachedTerrainResolution = currentResolution;
  }

  return _cachedProvider!;
}
```

## Rendering Techniques

### Terrain Settings

The layer uses a dedicated class to manage terrain visualization settings:

```dart
class _TerrainSettings {
  double referenceAltitude = 0.0;
  double warningAltitude = 15000.0;
  
  void updateReferenceAltitude(double altitude) {
    referenceAltitude = altitude;
  }
}
```

### Rendering Modes

The layer supports different rendering modes through the `LercTileProvider`:

1. **Gradient Mode**: Smooth elevation-based color transitions
2. **Simple Mode**: Discrete elevation bands with clear boundaries
3. **Hillshade Integration**: Optional terrain shading based on slope and aspect

```dart
// Toggle between different rendering modes
void setRenderingMode(RenderMode mode) {
  switch(mode) {
    case RenderMode.gradient:
      LercTileProvider.setGradientMode(true);
      break;
    case RenderMode.simple:
      LercTileProvider.setGradientMode(false);
      break;
  }
}
```

### Altitude Reference System

The layer maintains a reference altitude that can be adjusted dynamically:

```dart
// Update the reference altitude
void _updateAltitude(double altitude) {
  if (!mounted) return;
  _lastRenderedAltitude = altitude;
  _terrainSettings.updateReferenceAltitude(altitude);
}
```

## Performance Optimizations

The terrain layer implements several optimizations:

1. **RepaintBoundary**: Prevents unnecessary repainting of the entire map
2. **Cached Provider**: Avoids recreating the provider unless necessary
3. **Platform-Specific Rendering**: Adapts to different platform capabilities
4. **Optimized Tile Updates**: Uses efficient update mechanisms for altitude changes

```dart
// Platform-specific optimizations
final platformOpt = PlatformOptimization();

// Conditional optimizations based on platform
if (platformOpt.requiresSpecialRendering) {
  // Apply platform-specific rendering techniques
}
```

## Usage Example

```dart
// Create the terrain layer
final terrainLayer = LocalLercLayer(
  data: decodedLercData,
  referenceAltitude: ValueNotifier<double>(10000),
  terrainResolution: ValueNotifier<double>(100),
  onElevationRead: (elevation) {
    print('Current elevation: $elevation m');
  },
);

// Add to Flutter Map
FlutterMap(
  options: MapOptions(
    center: LatLng(37.7749, -122.4194),
    zoom: 10.0,
  ),
  nonRotatedChildren: [
    // Add base layers...
    
    // Add terrain layer
    terrainLayer,
    
    // Add overlay layers...
  ],
),
```

## Integration with Other Layers

The terrain layer can be combined with other Flutter Map layers:

1. **Base Layers**: Typically displayed below the terrain layer (e.g., satellite imagery)
2. **Overlay Layers**: Displayed on top of the terrain (e.g., routes, markers)
3. **Hillshade Layer**: Can be used in conjunction with the terrain layer for enhanced visual effects
