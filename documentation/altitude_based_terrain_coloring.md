# Altitude-Based Terrain Coloring

This document describes the implementation of altitude-based terrain coloring in the FlightCanvas Terrain project.

## Overview

Altitude-based terrain coloring is a visualization technique that assigns colors to different elevation values, creating a visual representation of the terrain's topography. The implementation in this project offers multiple coloring schemes, including:

1. **Gradient Mode**: Smooth transitions between colors based on elevation
2. **Simple Mode**: Discrete color bands for different elevation ranges
3. **Warning-Based**: Special coloring for areas above or below reference altitudes

## Implementation Details

### Color Mapping Logic

The core of altitude-based terrain coloring is implemented in the `_renderTerrainImage` method of the `_LercTileImage` class:

```dart
Uint8List _renderTerrainImage(Float64List elevations) {
  const int tileSize = 256;
  final pixels = Uint8List(tileSize * tileSize * 4);

  // Convert feet to meters for comparison with ETOPO elevation data
  const double feetToMeters = 0.3048;
  final double altInMeters = referenceAltitude * feetToMeters;
  final double warningAltInMeters = warningAltitude * feetToMeters;

  if (LercTileProvider._useGradientMode) {
    // Gradient coloring implementation
    _renderGradientMode(elevations, pixels, altInMeters, warningAltInMeters);
  } else {
    // Simple coloring implementation
    _renderSimpleMode(elevations, pixels, altInMeters, warningAltInMeters);
  }
  
  return pixels;
}
```

### Gradient Coloring Mode

The gradient coloring mode provides smooth transitions between colors based on elevation values:

```dart
void _renderGradientMode(Float64List elevations, Uint8List pixels, 
                          double altInMeters, double warningAltInMeters) {
  const int tileSize = 256;
  
  for (int i = 0; i < tileSize * tileSize; i++) {
    // Get pixel index (RGBA)
    int pixelIndex = i * 4;
    
    // Get elevation value
    double elev = elevations[i];
    
    // Calculate normalized elevation (0.0 - 1.0) for gradient
    double normalizedElev = (elev - minElevation) / (10000 - minElevation);
    normalizedElev = normalizedElev.clamp(0.0, 1.0);

    // Create gradient color based on normalized elevation
    Color color = _getGradientColor(normalizedElev);

    // Apply warning color if above warning altitude
    if (elev > warningAltInMeters) {
      // Blend with warning color (red)
      double warningFactor = ((elev - warningAltInMeters) / 1000).clamp(0.0, 0.8);
      color = Color.lerp(color, const Color(0xFFFF0000), warningFactor)!;
    }
    
    // Apply reference altitude highlight
    if ((elev - altInMeters).abs() < 100) {
      // Add highlight for elevations near reference altitude
      double highlightFactor = 1.0 - ((elev - altInMeters).abs() / 100);
      color = Color.lerp(color, const Color(0xFFFFFF00), highlightFactor * 0.5)!;
    }
    
    // Set pixel colors
    pixels[pixelIndex] = color.red;
    pixels[pixelIndex + 1] = color.green;
    pixels[pixelIndex + 2] = color.blue;
    pixels[pixelIndex + 3] = 255; // Alpha
  }
}
```

### Simple Coloring Mode

The simple coloring mode uses discrete color bands for different elevation ranges:

```dart
void _renderSimpleMode(Float64List elevations, Uint8List pixels, 
                        double altInMeters, double warningAltInMeters) {
  const int tileSize = 256;
  
  // Define elevation bands
  final elevationBands = [
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
  final bandColors = [
    const Color(0xFF000080), // Deep blue
    const Color(0xFF0000FF), // Blue
    const Color(0xFF00FFFF), // Cyan
    const Color(0xFF00FF00), // Green
    const Color(0xFFFFFF00), // Yellow
    const Color(0xFFFF8000), // Orange
    const Color(0xFFFF0000), // Red
    const Color(0xFF800000), // Dark red
    const Color(0xFFFFFFFF), // White (highest elevations)
  ];
  
  for (int i = 0; i < tileSize * tileSize; i++) {
    // Get pixel index (RGBA)
    int pixelIndex = i * 4;
    
    // Get elevation value
    double elev = elevations[i];
    
    // Find elevation band
    int bandIndex = 0;
    for (int j = 0; j < elevationBands.length; j++) {
      if (elev > elevationBands[j]) {
        bandIndex = j + 1;
      }
    }
    
    // Get color for this band
    Color color = bandColors[bandIndex];
    
    // Apply warning coloring
    if (elev > warningAltInMeters) {
      // Add warning highlight (pulsating in actual implementation)
      double warningFactor = ((elev - warningAltInMeters) / 1000).clamp(0.0, 0.8);
      color = Color.lerp(color, const Color(0xFFFF0000), warningFactor)!;
    }
    
    // Apply reference altitude highlight
    if ((elev - altInMeters).abs() < 100) {
      // Highlight with yellow for reference altitude
      color = const Color(0xFFFFFF00);
    }
    
    // Set pixel colors
    pixels[pixelIndex] = color.red;
    pixels[pixelIndex + 1] = color.green;
    pixels[pixelIndex + 2] = color.blue;
    pixels[pixelIndex + 3] = 255; // Alpha
  }
}
```

### Gradient Color Generation

The project includes a utility function to generate gradient colors based on normalized elevation values:

```dart
Color _getGradientColor(double normalizedElevation) {
  // Ocean depths (deep blue to lighter blue)
  if (normalizedElevation < 0.4) {
    double oceanFactor = normalizedElevation / 0.4;
    return Color.lerp(
      const Color(0xFF000040), // Deep ocean
      const Color(0xFF0000FF), // Ocean surface
      oceanFactor,
    )!;
  }
  // Land elevations
  else {
    // Remap to 0-1 range for land
    double landFactor = (normalizedElevation - 0.4) / 0.6;
    
    // Create multi-step gradient for land
    if (landFactor < 0.2) {
      // Coast to lowlands (green)
      return Color.lerp(
        const Color(0xFF00FFFF), // Coast
        const Color(0xFF00FF00), // Green lowlands
        landFactor / 0.2,
      )!;
    } else if (landFactor < 0.4) {
      // Lowlands to hills (green-yellow)
      return Color.lerp(
        const Color(0xFF00FF00), // Green lowlands
        const Color(0xFFFFFF00), // Yellow hills
        (landFactor - 0.2) / 0.2,
      )!;
    } else if (landFactor < 0.7) {
      // Hills to mountains (yellow-orange-brown)
      return Color.lerp(
        const Color(0xFFFFFF00), // Yellow hills
        const Color(0xFFFF8000), // Orange mountains
        (landFactor - 0.4) / 0.3,
      )!;
    } else {
      // High mountains to peaks (brown-red-white)
      return Color.lerp(
        const Color(0xFFFF8000), // Orange mountains
        const Color(0xFFFFFFFF), // White peaks
        (landFactor - 0.7) / 0.3,
      )!;
    }
  }
}
```

## Reference Altitude Visualization

A key feature of the coloring system is highlighting elevations near the reference altitude:

```dart
// Apply reference altitude highlight
if ((elev - altInMeters).abs() < 100) {
  // Add highlight for elevations near reference altitude
  double highlightFactor = 1.0 - ((elev - altInMeters).abs() / 100);
  color = Color.lerp(color, const Color(0xFFFFFF00), highlightFactor * 0.5)!;
}
```

## Warning Altitude Visualization

The system also highlights terrain above the warning altitude:

```dart
// Apply warning color if above warning altitude
if (elev > warningAltInMeters) {
  // Blend with warning color (red)
  double warningFactor = ((elev - warningAltInMeters) / 1000).clamp(0.0, 0.8);
  color = Color.lerp(color, const Color(0xFFFF0000), warningFactor)!;
}
```

## Alpha Blending and Transparency

The implementation supports variable transparency for terrain visualization:

```dart
// For specific visualization needs, we can adjust alpha transparency
double alphaValue = 255;

// Reduce alpha for areas below certain elevation
if (elev < (altInMeters - 5000)) {
  // Gradually reduce alpha for very low terrain
  double reductionFactor = ((altInMeters - 5000) - elev) / 10000;
  alphaValue = 255 * (1.0 - reductionFactor.clamp(0.0, 0.7));
}

pixels[pixelIndex + 3] = alphaValue.round(); // Alpha
```

## Usage Example

```dart
// Configure terrain layer with altitude-based coloring
final terrainLayer = LocalLercLayer(
  data: decodedLercData,
  referenceAltitude: ValueNotifier<double>(10000),
  terrainResolution: ValueNotifier<double>(100),
  onElevationRead: (elevation) {
    print('Current elevation: $elevation m');
  },
);

// Toggle coloring mode
LercTileProvider.setGradientMode(true); // Use gradient coloring
// Or
LercTileProvider.setGradientMode(false); // Use simple band coloring
```
