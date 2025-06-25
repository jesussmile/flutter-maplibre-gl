# Reference Altitude and Warning Levels

This document describes the implementation of reference altitude and warning level visualizations in the FlightCanvas Terrain project.

## Overview

The Reference Altitude and Warning Levels system allows users to:

1. Set a specific reference altitude (e.g., current aircraft altitude)
2. Visualize terrain relative to this reference altitude
3. Receive visual warnings for terrain above designated warning levels
4. Identify terrain at or near the reference altitude

This feature is especially valuable for flight navigation and safety applications, helping to quickly identify terrain that may pose a hazard.

## Implementation Details

### Core Components

The feature is implemented through several key components:

1. **Reference Altitude State Management**: ValueNotifiers for real-time updates
2. **Warning Altitude Configuration**: Settings for warning thresholds
3. **Visualization Logic**: Algorithms for highlighting relevant terrain
4. **UI Controls**: Interface elements for adjusting reference altitude

### Reference Altitude Management

Reference altitude is managed through a ValueNotifier in the main application:

```dart
class _TerrainMapScreenState extends State<TerrainMapScreen> {
  // Reference altitude value notifier
  final ValueNotifier<double> _referenceAltitude = ValueNotifier<double>(0.0);
  
  // Warning altitude configuration
  double _warningAltitude = 15000.0;  // In feet
  
  @override
  void initState() {
    super.initState();
    
    // Initialize with default reference altitude
    _updateReferenceAltitude(5000.0);
    
    // Set up listeners for reference altitude changes
    _referenceAltitude.addListener(_onReferenceAltitudeChanged);
  }
  
  void _updateReferenceAltitude(double newAltitude) {
    // Validate and update the reference altitude
    double validAltitude = newAltitude.clamp(0.0, 30000.0);
    _referenceAltitude.value = validAltitude;
  }
  
  void _onReferenceAltitudeChanged() {
    // Update terrain visualization when reference altitude changes
    LercTileProvider._currentAltitude = _referenceAltitude.value;
    
    // Force terrain update on significant changes
    _terrainUpdateTimer?.cancel();
    _terrainUpdateTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }
}
```

### Warning Level Configuration

The application supports multiple warning levels and thresholds:

```dart
class _TerrainSettings {
  // Reference and warning altitudes
  double referenceAltitude = 0.0;
  double warningAltitude = 15000.0;  // Primary warning level (red)
  double cautionAltitude = 10000.0;  // Secondary warning level (yellow)
  
  // Warning level offsets
  double criticalOffset = 1000.0;    // Terrain within this distance above reference is critical
  double warningOffset = 2000.0;     // Terrain within this distance above reference is warning
  double cautionOffset = 5000.0;     // Terrain within this distance above reference is caution
  
  void updateReferenceAltitude(double altitude) {
    referenceAltitude = altitude;
    
    // Optionally update warning levels relative to reference altitude
    // warningAltitude = referenceAltitude + warningOffset;
  }
  
  // Get appropriate warning color for an elevation
  Color getWarningColorForElevation(double elevation, double refAlt) {
    final double elevFeet = elevation * 3.28084; // Convert meters to feet
    final double refFeet = refAlt * 3.28084;     // Convert meters to feet
    
    // Terrain above reference altitude
    if (elevFeet > refFeet) {
      double difference = elevFeet - refFeet;
      
      if (difference > criticalOffset) {
        return const Color(0xFFFF0000); // Critical (red)
      } else if (difference > warningOffset) {
        return const Color(0xFFFF8000); // Warning (orange)
      } else if (difference > cautionOffset) {
        return const Color(0xFFFFFF00); // Caution (yellow)
      }
    }
    
    // Default - no warning
    return const Color(0xFF00FF00); // Safe (green)
  }
}
```

### Visualization Implementation

The reference altitude and warning level visualization is implemented in the terrain rendering logic:

```dart
Uint8List _renderTerrainImage(Float64List elevations) {
  const int tileSize = 256;
  final pixels = Uint8List(tileSize * tileSize * 4);

  // Convert feet to meters for comparison with elevation data
  const double feetToMeters = 0.3048;
  final double altInMeters = referenceAltitude * feetToMeters;
  final double warningAltInMeters = warningAltitude * feetToMeters;

  // For each pixel in the tile
  for (int i = 0; i < tileSize * tileSize; i++) {
    // Get the elevation at this point
    double elev = elevations[i];
    
    // Get pixel index (RGBA)
    int pixelIndex = i * 4;
    
    // Get base color based on rendering mode and elevation
    Color color;
    if (LercTileProvider._useGradientMode) {
      // Gradient coloring based on elevation
      double normalizedElev = (elev - minElevation) / (10000 - minElevation);
      normalizedElev = normalizedElev.clamp(0.0, 1.0);
      color = _getGradientColor(normalizedElev);
    } else {
      // Band coloring based on elevation ranges
      color = _getElevationBandColor(elev);
    }
    
    // Apply reference altitude highlighting
    if ((elev - altInMeters).abs() < 100) {
      // Smooth highlight factor based on distance from reference altitude
      double highlightFactor = 1.0 - ((elev - altInMeters).abs() / 100);
      
      // Blend with reference highlight color (yellow)
      color = Color.lerp(
        color, 
        const Color(0xFFFFFF00), 
        highlightFactor * 0.7
      )!;
      
      // Apply stronger highlight for exact matches
      if ((elev - altInMeters).abs() < 20) {
        double exactFactor = 1.0 - ((elev - altInMeters).abs() / 20);
        color = Color.lerp(
          color, 
          const Color(0xFFFFFFFF), 
          exactFactor * 0.5
        )!;
      }
    }
    
    // Apply warning highlighting for terrain above warning altitude
    if (elev > warningAltInMeters) {
      // Calculate how far above warning level (with clamping)
      double excessElevation = elev - warningAltInMeters;
      double warningFactor = (excessElevation / 1000).clamp(0.0, 0.8);
      
      // Blend with warning color (red)
      color = Color.lerp(
        color, 
        const Color(0xFFFF0000), 
        warningFactor
      )!;
      
      // Add pulsating effect for severe warnings
      if (excessElevation > 2000) {
        // Pulse logic based on time or frame count would be here
        // For documentation purposes, simplified to static value
        color = Color.lerp(color, const Color(0xFFFF8080), 0.3)!;
      }
    }
    
    // Set final pixel color
    pixels[pixelIndex] = color.red;
    pixels[pixelIndex + 1] = color.green;
    pixels[pixelIndex + 2] = color.blue;
    pixels[pixelIndex + 3] = 255;  // Alpha (fully opaque)
  }
  
  return pixels;
}
```

### Reference Altitude UI Controls

The application provides UI controls for adjusting the reference altitude:

```dart
Widget _buildAltitudeControls() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Reference altitude display and slider
      ValueListenableBuilder<double>(
        valueListenable: _referenceAltitude,
        builder: (context, altitude, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Reference Altitude: ${altitude.round()} ft",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                width: 300,
                child: Slider(
                  min: 0,
                  max: 30000,
                  divisions: 300, // 100ft increments
                  value: altitude,
                  label: "${altitude.round()} ft",
                  onChanged: (value) {
                    _setHighZoomMode(true);
                    _isSliderDragging = true;
                    _applyAltitudeChange(value);
                  },
                  onChangeEnd: (value) {
                    _isSliderDragging = false;
                    _setHighZoomMode(false);
                  },
                ),
              ),
            ],
          );
        },
      ),
      
      // Warning altitude display and slider
      ValueListenableBuilder<double>(
        valueListenable: _warningAltitudeNotifier,
        builder: (context, warningAlt, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Warning Altitude: ${warningAlt.round()} ft",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(
                width: 300,
                child: Slider(
                  min: 0,
                  max: 30000,
                  divisions: 300, // 100ft increments
                  value: warningAlt,
                  activeColor: Colors.red,
                  label: "${warningAlt.round()} ft",
                  onChanged: (value) {
                    _warningAltitudeNotifier.value = value;
                    _applyWarningAltitudeChange(value);
                  },
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

### Altitude Quick Adjust Buttons

For rapid reference altitude adjustments, the application provides quick-adjust buttons:

```dart
Widget _buildQuickAdjustButtons() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _buildAltButton(-1000, "↓ 1K"),
      _buildAltButton(-500, "↓ 500"),
      _buildAltButton(-100, "↓ 100"),
      const SizedBox(width: 8),
      const SizedBox(width: 8),
      _buildAltButton(100, "↑ 100"),
      _buildAltButton(500, "↑ 500"),
      _buildAltButton(1000, "↑ 1K"),
    ],
  );
}

Widget _buildAltButton(double change, String label) {
  Color buttonColor = change < 0 ? Colors.orange : Colors.lightBlueAccent;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () {
        final newAlt = _referenceAltitude.value + change;
        _applyAltitudeChange(newAlt.clamp(0, 30000));
      },
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ),
  );
}
```

### Warning Level Settings Dialog

A dialog for configuring warning levels and thresholds:

```dart
void _showWarningSettingsDialog() {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Warning Level Settings"),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primary warning level
              Text("Primary Warning Level: ${_warningAltitudeNotifier.value.round()} ft"),
              Slider(
                min: 0,
                max: 30000,
                value: _warningAltitudeNotifier.value,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    _warningAltitudeNotifier.value = value;
                  });
                },
              ),
              
              // Secondary (caution) level
              Text("Caution Level: ${_cautionAltitudeNotifier.value.round()} ft"),
              Slider(
                min: 0,
                max: 30000,
                value: _cautionAltitudeNotifier.value,
                activeColor: Colors.orange,
                onChanged: (value) {
                  setState(() {
                    _cautionAltitudeNotifier.value = value;
                  });
                },
              ),
              
              // Critical offset from reference
              Text("Critical Offset: ${_criticalOffsetNotifier.value.round()} ft"),
              Slider(
                min: 0,
                max: 5000,
                value: _criticalOffsetNotifier.value,
                activeColor: Colors.purpleAccent,
                onChanged: (value) {
                  setState(() {
                    _criticalOffsetNotifier.value = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              _applyWarningSettings();
              Navigator.of(context).pop();
            },
            child: const Text("Apply"),
          ),
        ],
      );
    },
  );
}

void _applyWarningSettings() {
  // Apply new warning settings
  _terrainSettings.warningAltitude = _warningAltitudeNotifier.value;
  _terrainSettings.cautionAltitude = _cautionAltitudeNotifier.value;
  _terrainSettings.criticalOffset = _criticalOffsetNotifier.value;
  
  // Force terrain refresh to update visualization
  _forceTerrainRefresh();
}
```

## Reference Altitude Relative Terrain Statistics

The application can display statistics about terrain relative to the reference altitude:

```dart
Widget _buildTerrainStatistics() {
  return ValueListenableBuilder<TerrainStatistics?>(
    valueListenable: _terrainStatsNotifier,
    builder: (context, stats, child) {
      if (stats == null) {
        return Container();
      }
      
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Terrain Statistics (visible area):",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Max Elevation: ${stats.maxElevation.round()} ft"),
            Text("Min Elevation: ${stats.minElevation.round()} ft"),
            Text(
              "Above Reference: ${stats.percentageAboveReference.toStringAsFixed(1)}%",
              style: TextStyle(
                color: stats.percentageAboveReference > 30
                    ? Colors.red
                    : Colors.green,
              ),
            ),
            Text(
              "Above Warning: ${stats.percentageAboveWarning.toStringAsFixed(1)}%",
              style: TextStyle(
                color: stats.percentageAboveWarning > 5
                    ? Colors.red
                    : Colors.green,
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

## Integration with Altitude Bucketing

The reference altitude system is integrated with altitude bucketing for efficient updates:

```dart
// Get the bucketed reference altitude for optimization
String get _bucketedAltitude {
  double bucketedValue = (referenceAltitude / altitudeBucketSize).floor() * altitudeBucketSize;
  return bucketedValue.toString();
}

// Check if a tile needs updating based on altitude change
bool _needsUpdate() {
  final currentAltitude = LercTileProvider._currentAltitude;
  final renderedAltitude = double.tryParse(_bucketedAltitude) ?? 0;
  final difference = (currentAltitude - renderedAltitude).abs();
  
  // Only update if altitude difference exceeds half the bucket size
  return difference >= (altitudeBucketSize * 0.5);
}
```

## Usage Example

```dart
// Create terrain layer with reference altitude
final terrainLayer = LocalLercLayer(
  data: decodedLercData,
  referenceAltitude: ValueNotifier<double>(10000), // 10,000 ft initial reference
  terrainResolution: ValueNotifier<double>(100),
  onElevationRead: (elevation) {
    // Display current terrain elevation under cursor
    _currentElevationNotifier.value = elevation * 3.28084; // Convert m to ft
  },
);

// Later, update reference altitude
_referenceAltitude.value = 15000; // Change to 15,000 ft

// Update warning altitude
_terrainSettings.warningAltitude = 18000; // Set warning at 18,000 ft
```
