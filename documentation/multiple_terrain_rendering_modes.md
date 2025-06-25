# Multiple Terrain Rendering Modes

This document describes the implementation of multiple terrain rendering modes in the FlightCanvas Terrain project.

## Overview

The FlightCanvas Terrain project supports multiple rendering modes to visualize terrain elevation data in different ways. These rendering modes provide options for displaying terrain with varying levels of detail, different color schemes, and specialized visualizations for specific use cases.

## Rendering Mode Types

The project implements the following primary rendering modes:

1. **Gradient Mode**: A smooth, continuous color gradient based on elevation values
2. **Simple Mode**: Discrete elevation bands with clear boundaries
3. **Reference Mode**: Highlighting terrain relative to a reference altitude
4. **Warning Mode**: Emphasizing terrain above designated warning altitudes

## Implementation Details

### Mode Management in LercTileProvider

The rendering modes are managed through static variables and methods in the `LercTileProvider` class:

```dart
class LercTileProvider extends TileProvider {
  // Other class members...
  
  // Rendering mode flag
  static bool _useGradientMode = true;
  
  // Method to toggle between rendering modes
  static void setGradientMode(bool enabled) {
    if (_useGradientMode != enabled) {
      // Store the previous mode before changing
      final previousMode = _useGradientMode;
      _useGradientMode = enabled;
      
      // Clear caches to force re-rendering with new mode
      _clearPixelCache();
      _clearPendingUpdates();
      _renderedTileKeys.clear();
      
      // Print debug info about the mode change
      print("Rendering mode changed: ${previousMode ? 'Gradient' : 'Simple'} → ${enabled ? 'Gradient' : 'Simple'}");
    }
  }
  
  // Helper method to clear pixel cache
  static void _clearPixelCache() {
    // Find all LercTileProvider instances
    for (var provider in _activeTileProviders) {
      // Clear the pixel cache
      provider._renderedPixelCache.clear();
    }
  }
  
  // Helper method to clear pending updates
  static void _clearPendingUpdates() {
    _pendingTileUpdates.clear();
    _isUpdateScheduled = false;
  }
}
```

### Gradient Mode Implementation

The gradient mode renders terrain using a smooth color gradient based on elevation:

```dart
void _renderGradientMode(Float64List elevations, Uint8List pixels, 
                          double referenceAltitude, double warningAltitude) {
  const int tileSize = 256;
  
  for (int i = 0; i < elevations.length; i++) {
    // Get pixel index (RGBA format)
    int pixelIndex = i * 4;
    
    // Get elevation value
    double elevation = elevations[i];
    
    // Normalize elevation to 0.0 - 1.0 for color mapping
    double normalizedElev = (elevation - minElevation) / (10000 - minElevation);
    normalizedElev = normalizedElev.clamp(0.0, 1.0);
    
    // Get base color from gradient
    Color baseColor = _getGradientColor(normalizedElev);
    
    // Apply reference altitude and warning highlights
    Color finalColor = _applySpecialHighlighting(
      baseColor, 
      elevation, 
      referenceAltitude, 
      warningAltitude
    );
    
    // Set pixel RGBA values
    pixels[pixelIndex] = finalColor.red;
    pixels[pixelIndex + 1] = finalColor.green;
    pixels[pixelIndex + 2] = finalColor.blue;
    pixels[pixelIndex + 3] = finalColor.alpha;
  }
}

// Helper method to get a color from the gradient based on normalized elevation
Color _getGradientColor(double normalizedElevation) {
  // Define gradient stops
  const List<Color> gradientColors = [
    Color(0xFF000040),  // Deep ocean (dark blue)
    Color(0xFF0000FF),  // Ocean (blue)
    Color(0xFF00FFFF),  // Coast (cyan)
    Color(0xFF00FF00),  // Lowlands (green)
    Color(0xFFFFFF00),  // Hills (yellow)
    Color(0xFFFF8000),  // Mountains (orange)
    Color(0xFFFF0000),  // High mountains (red)
    Color(0xFFFFFFFF),  // Peaks (white)
  ];
  
  // Define positions for each color stop (0.0 - 1.0)
  const List<double> gradientStops = [0.0, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 1.0];
  
  // Find the appropriate segment in the gradient
  for (int i = 0; i < gradientStops.length - 1; i++) {
    if (normalizedElevation >= gradientStops[i] && 
        normalizedElevation <= gradientStops[i + 1]) {
      // Calculate position within this segment
      double segmentPosition = (normalizedElevation - gradientStops[i]) / 
                              (gradientStops[i + 1] - gradientStops[i]);
      
      // Interpolate between the two colors
      return Color.lerp(
        gradientColors[i],
        gradientColors[i + 1],
        segmentPosition,
      )!;
    }
  }
  
  // Fallback (should not reach here)
  return const Color(0xFF000000);
}
```

### Simple Mode Implementation

The simple mode uses discrete color bands for elevation ranges:

```dart
void _renderSimpleMode(Float64List elevations, Uint8List pixels, 
                        double referenceAltitude, double warningAltitude) {
  const int tileSize = 256;
  
  // Define elevation bands in meters
  const List<double> elevationBands = [
    -11000, // Deep ocean
    -5000,  // Ocean
    -100,   // Near sea level
    500,    // Low elevation
    1000,   // Hills
    2000,   // Mountains
    4000,   // High mountains
    6000,   // Very high mountains
  ];
  
  // Define colors for each band
  const List<Color> bandColors = [
    Color(0xFF000080), // Deep blue
    Color(0xFF0000FF), // Blue
    Color(0xFF00FFFF), // Cyan
    Color(0xFF00FF00), // Green
    Color(0xFFFFFF00), // Yellow
    Color(0xFFFF8000), // Orange
    Color(0xFFFF0000), // Red
    Color(0xFF800000), // Dark red
    Color(0xFFFFFFFF), // White (highest elevations)
  ];
  
  for (int i = 0; i < elevations.length; i++) {
    // Get pixel index (RGBA format)
    int pixelIndex = i * 4;
    
    // Get elevation value
    double elevation = elevations[i];
    
    // Find elevation band
    int bandIndex = 0;
    for (int j = 0; j < elevationBands.length; j++) {
      if (elevation > elevationBands[j]) {
        bandIndex = j + 1;
      }
    }
    
    // Get base color for this band
    Color baseColor = bandColors[bandIndex];
    
    // Apply reference altitude and warning highlights
    Color finalColor = _applySpecialHighlighting(
      baseColor, 
      elevation, 
      referenceAltitude, 
      warningAltitude
    );
    
    // Set pixel RGBA values
    pixels[pixelIndex] = finalColor.red;
    pixels[pixelIndex + 1] = finalColor.green;
    pixels[pixelIndex + 2] = finalColor.blue;
    pixels[pixelIndex + 3] = finalColor.alpha;
  }
}
```

### Reference Altitude and Warning Highlighting

Both rendering modes use a common method for applying reference altitude and warning highlights:

```dart
Color _applySpecialHighlighting(Color baseColor, double elevation, 
                              double referenceAltitude, double warningAltitude) {
  Color result = baseColor;
  
  // Apply warning highlight for elevations above warning altitude
  if (elevation > warningAltitude) {
    double warningFactor = ((elevation - warningAltitude) / 1000).clamp(0.0, 0.8);
    result = Color.lerp(result, const Color(0xFFFF0000), warningFactor)!;
  }
  
  // Apply reference altitude highlight
  double referenceDifference = (elevation - referenceAltitude).abs();
  if (referenceDifference < 100) {
    // Create highlight for elevations near reference altitude
    double highlightFactor = 1.0 - (referenceDifference / 100);
    result = Color.lerp(result, const Color(0xFFFFFF00), highlightFactor * 0.7)!;
    
    // Create very strong highlight for exact matches
    if (referenceDifference < 20) {
      double exactFactor = 1.0 - (referenceDifference / 20);
      result = Color.lerp(result, const Color(0xFFFFFFFF), exactFactor * 0.5)!;
    }
  }
  
  return result;
}
```

### UI Controls for Rendering Mode Selection

The application provides UI controls for selecting the rendering mode:

```dart
Widget _buildRenderingModeControls(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Rendering Mode:",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      
      // Gradient mode toggle
      ValueListenableBuilder<bool>(
        valueListenable: _useGradientMode,
        builder: (context, useGradient, child) {
          return Row(
            children: [
              Switch(
                value: useGradient,
                onChanged: (value) {
                  _useGradientMode.value = value;
                  LercTileProvider.setGradientMode(value);
                  _forceTerrainRefresh();
                },
              ),
              Text(
                useGradient ? "Gradient Mode" : "Simple Mode",
                style: TextStyle(
                  color: useGradient ? Colors.lightBlue : Colors.amber,
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}
```

### Separate Hillshade Integration

The hillshade rendering can be combined with any of the coloring modes:

```dart
Widget _buildMap() {
  return FlutterMap(
    mapController: mapController,
    options: MapOptions(
      initialCenter: const latLng.LatLng(37.7749, -122.4194),
      initialZoom: 5,
    ),
    children: [
      // Base tile layer (e.g., satellite imagery)
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.app',
      ),
      
      // Optional hillshade layer
      ValueListenableBuilder<bool>(
        valueListenable: _showHillshade,
        builder: (context, showHillshade, child) {
          if (!showHillshade) return Container();
          return HillshadeLayer(data: hillshadeData);
        },
      ),
      
      // Main terrain layer with selected rendering mode
      ValueListenableBuilder<bool>(
        valueListenable: _showTerrain,
        builder: (context, showTerrain, child) {
          if (!showTerrain) return Container();
          return LocalLercLayer(
            data: widget.data,
            referenceAltitude: _referenceAltitude,
            terrainResolution: _terrainResolution,
            onElevationRead: _updateReadElevation,
            onDebugMessage: _updateDebugMessage,
          );
        },
      ),
    ],
  );
}
```

## Dynamic Mode Switching

The application supports dynamic switching between rendering modes with smooth transitions:

```dart
void _forceTerrainRefresh() {
  // Clear any pending updates
  _terrainUpdateTimer?.cancel();
  
  // Apply a small shift to altitude to force re-rendering
  final currentAlt = _referenceAltitude.value;
  
  // Wait briefly for the rendering mode change to take effect
  Future.delayed(const Duration(milliseconds: 50), () {
    // Apply a small change to trigger complete re-rendering
    _applyAltitudeChange(currentAlt + 0.5);
    
    // Then restore the original value after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      _applyAltitudeChange(currentAlt);
    });
  });
}
```

## Single-Color Mode

The project also supports a simplified single-color mode where only the terrain shape is emphasized through hillshading:

```dart
void _renderSingleColorMode(Float64List elevations, Uint8List pixels, 
                          double referenceAltitude) {
  const int tileSize = 256;
  final baseColor = const Color(0xFF404040); // Base gray color
  
  for (int i = 0; i < elevations.length; i++) {
    // Get pixel index (RGBA format)
    int pixelIndex = i * 4;
    
    // Get elevation value
    double elevation = elevations[i];
    
    // Calculate hillshade value (0.5-1.5)
    double hillshade = _calculateSimpleHillshade(i, elevations, tileSize);
    
    // Apply hillshade to base color
    int r = (baseColor.red * hillshade).round().clamp(0, 255);
    int g = (baseColor.green * hillshade).round().clamp(0, 255);
    int b = (baseColor.blue * hillshade).round().clamp(0, 255);
    
    // Set pixel RGBA values
    pixels[pixelIndex] = r;
    pixels[pixelIndex + 1] = g;
    pixels[pixelIndex + 2] = b;
    pixels[pixelIndex + 3] = 255; // Full opacity
  }
}

// Simple hillshade calculation
double _calculateSimpleHillshade(int index, Float64List elevations, int tileSize) {
  // Default for edge cases
  if (index % tileSize == 0 || 
      index % tileSize == tileSize - 1 || 
      index < tileSize || 
      index >= elevations.length - tileSize) {
    return 1.0;
  }
  
  // Get surrounding elevation values
  double center = elevations[index];
  double left = elevations[index - 1];
  double right = elevations[index + 1];
  double top = elevations[index - tileSize];
  double bottom = elevations[index + tileSize];
  
  // Calculate slopes
  double xSlope = (right - left) / 2;
  double ySlope = (bottom - top) / 2;
  
  // Simple hillshade approximation
  double slope = math.sqrt(xSlope * xSlope + ySlope * ySlope);
  
  // Convert slope to shading factor (0.5-1.5)
  return 1.0 - slope * 0.2;
}
```

## Usage Example

```dart
// Initialize with gradient mode
LercTileProvider.setGradientMode(true);

// Create terrain layer with default rendering mode
final terrainLayer = LocalLercLayer(
  data: decodedLercData,
  referenceAltitude: ValueNotifier<double>(10000),
  terrainResolution: ValueNotifier<double>(100),
);

// Later, switch to simple mode
LercTileProvider.setGradientMode(false);

// Force refresh to apply new rendering mode
_forceTerrainRefresh();
```
