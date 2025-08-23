# PNG Rotatable Symbols Documentation

## Overview

The **PNG Rotatable Symbols** feature provides a powerful way to display complex aviation symbols on MapLibre GL maps using custom PNG assets. This system creates a 4-layer composite symbol with:

- **Aircraft PNG icon** (rotates with map heading)
- **Top text label** (altitude, stays horizontal)
- **Bottom text label** (callsign, stays horizontal)  
- **Status arrow PNG** (climb/descent indicator, stays upright)

## Key Features

- ✅ **Custom PNG Assets**: Use your own aircraft and arrow icons
- ✅ **Safety-Critical Rotation**: Aircraft rotates with heading, text stays readable
- ✅ **Configurable Sizing**: Independent size control for aircraft and arrows
- ✅ **Dynamic Status**: Real-time climb/descent arrow indicators
- ✅ **Performance Optimized**: Native rendering with GPU acceleration
- ✅ **Aviation Standards**: Follows Flight Canvas design specifications

## Quick Start Example

```dart
// Step 1: Add GeoJSON source with aircraft data
await controller!.addGeoJsonSource('aircraft-source', {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [-122.4194, 37.7749], // San Francisco
      },
      'properties': {
        'rotation': 45.0,        // Aircraft heading in degrees
        'topLabel': '35K',       // Altitude display
        'bottomLabel': 'UAL123', // Flight callsign
        'isClimbing': true,      // Climb/descent status
        'labelSize': 14.0,
        'labelColor': '#000000',
        'triangleOpacity': 1.0,  // Aircraft icon opacity
        'arrowOpacity': 1.0,     // Arrow icon opacity
      },
    },
  ],
});

// Step 2: Add PNG rotatable symbol layers
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'aircraft-source',
  baseLayerId: 'aircraft-symbols',
  aircraftIconPath: 'traffic.png',    // Your aircraft PNG asset
  arrowIconPath: 'arrow.png',         // Your arrow PNG asset
  aircraftIconSize: 0.15,             // Aircraft size (0.1-0.3 recommended)
  arrowIconSize: 0.12,                // Arrow size (0.1-0.2 recommended)
  enableInteraction: true,
  config: {
    'topLabelOffset': -2.5,           // Altitude label position
    'bottomLabelOffset': 2.5,         // Callsign label position
    'arrowOffsetX': 80.0,             // Arrow horizontal offset (prevent overlap)
  },
);
```

## Asset Management

### 1. Asset Declaration in pubspec.yaml

Your PNG assets must be declared in the Flutter app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/traffic.png      # Aircraft icon
    - assets/arrow.png        # Status arrow icon
    - assets/custom-aircraft.png  # Custom aircraft variant
    - assets/helicopter.png   # Different aircraft types
```

### 2. Asset Resolution Path

The system automatically resolves Flutter assets using the **flutter_assets/assets/** path structure:

```
flutter_assets/
└── assets/
    ├── traffic.png         # Main aircraft icon
    ├── arrow.png          # Status indicator arrow
    ├── helicopter.png     # Alternative aircraft type
    └── custom-jets/       # Organized by category
        ├── boeing-737.png
        ├── airbus-a320.png
        └── cessna-172.png
```

### 3. Asset Loading in Native Code

The native implementation uses multiple loading strategies:

1. **Flutter Asset Resolution** (Primary)
   ```java
   String flutterAssetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(assetPath);
   InputStream inputStream = mapView.getContext().getAssets().open(flutterAssetPath);
   ```

2. **Direct Asset Path** (Fallback)
   ```java
   InputStream inputStream = mapView.getContext().getAssets().open(assetPath);
   ```

3. **Flutter Assets Directory** (Alternative)
   ```java
   String flutterAssetsPath = "flutter_assets/assets/" + assetPath;
   InputStream inputStream = mapView.getContext().getAssets().open(flutterAssetsPath);
   ```

## Custom PNG Assets

### Using Different Aircraft Types

You can use any PNG asset for aircraft icons:

```dart
// Helicopter symbols
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'helicopter-source',
  baseLayerId: 'helicopter-symbols',
  aircraftIconPath: 'helicopter.png',      // Custom helicopter icon
  arrowIconPath: 'arrow.png',
  aircraftIconSize: 0.18,                  // Slightly larger for helicopters
  // ... other parameters
);

// Business jet symbols  
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'bizjet-source', 
  baseLayerId: 'bizjet-symbols',
  aircraftIconPath: 'custom-jets/gulfstream.png',  // Custom business jet
  arrowIconPath: 'premium-arrow.png',              // Premium arrow design
  aircraftIconSize: 0.16,
  // ... other parameters
);
```

### Custom Arrow Indicators

Create different arrow styles for various scenarios:

```dart
// Emergency aircraft with red arrows
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'emergency-source',
  baseLayerId: 'emergency-symbols', 
  aircraftIconPath: 'emergency-aircraft.png',
  arrowIconPath: 'red-arrow.png',          // Emergency status arrow
  aircraftIconSize: 0.20,                  // Larger for visibility
  arrowIconSize: 0.15,
  // ... other parameters
);

// Military aircraft with specialized arrows
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'military-source',
  baseLayerId: 'military-symbols',
  aircraftIconPath: 'f16-fighter.png',
  arrowIconPath: 'military-arrow.png',     // Military-style indicator
  // ... other parameters
);
```

## Configuration Options

### Size Configuration

```dart
aircraftIconSize: 0.15,     // Recommended: 0.10-0.25
arrowIconSize: 0.12,        // Recommended: 0.08-0.18

// Size Guidelines:
// - 0.10-0.15: Small aircraft, dense airspace
// - 0.15-0.20: Standard commercial aircraft  
// - 0.20-0.25: Large aircraft, emergency aircraft
```

### Positioning Configuration

```dart
config: {
  'topLabelOffset': -2.5,     // Altitude position above aircraft
  'bottomLabelOffset': 2.5,   // Callsign position below aircraft
  'arrowOffsetX': 80.0,       // Arrow horizontal distance from aircraft
}

// Position Guidelines:
// - topLabelOffset: -2.0 to -3.0 (closer to farther above)
// - bottomLabelOffset: 2.0 to 3.0 (closer to farther below)
// - arrowOffsetX: 60.0-100.0 (prevent overlap with aircraft)
```

### Opacity and Interaction

```dart
enableInteraction: true,    // Allow tap events on symbols

// In GeoJSON properties:
'triangleOpacity': 1.0,     // Aircraft icon opacity (0.0-1.0)
'arrowOpacity': 1.0,        // Arrow icon opacity (0.0-1.0)
```

## Dynamic Updates

### Real-time Rotation Animation

```dart
// Update aircraft rotation continuously
Timer.periodic(Duration(milliseconds: 150), (timer) {
  _currentRotation = (_currentRotation + 2.0) % 360.0;
  _updateAircraftData();
});

Future<void> _updateAircraftData() async {
  final updatedGeoJson = {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [longitude, latitude],
        },
        'properties': {
          'rotation': _currentRotation,        // Updated heading
          'isClimbing': _isClimbing,          // Updated climb status
          'topLabel': '${altitude}K',         // Updated altitude
          'bottomLabel': callsign,            // Flight identifier
          // ... other properties
        },
      },
    ],
  };
  
  await controller!.setGeoJsonSource('aircraft-source', updatedGeoJson);
}
```

### Manual Rotation Control

```dart
void _manualRotateAircraft() {
  setState(() {
    _currentRotation = (_currentRotation + 45.0) % 360.0;
  });
  _updateAircraftData();
}
```

## Asset Requirements

### PNG Specifications

- **Format**: PNG with transparency support
- **Size**: 64x64 to 256x256 pixels recommended
- **Channels**: RGBA (red, green, blue, alpha)
- **Bit Depth**: 8-bit per channel

### Aircraft Icon Guidelines

```
Aircraft PNG Requirements:
├── Clear directional orientation (nose/tail distinction)
├── Centered registration point
├── Transparent background
├── High contrast for visibility
└── Appropriate aspect ratio (typically 2:1 or 3:1)

Recommended Sizes:
├── Light Aircraft: 64x32 pixels
├── Commercial Aircraft: 128x64 pixels
├── Large Aircraft: 256x128 pixels
└── Emergency/Special: 128x64 pixels (high contrast)
```

### Arrow Icon Guidelines

```
Arrow PNG Requirements:
├── Clear up/down orientation
├── Centered registration point
├── Transparent background
├── Bold design for visibility
└── Consistent with aircraft scale

Recommended Sizes:
├── Standard Arrows: 32x32 pixels
├── Large Arrows: 64x64 pixels
└── Custom Indicators: 48x48 pixels
```

## Error Handling

### Asset Loading Errors

```dart
try {
  await controller!.addRotatableSymbolPngLayers(
    sourceId: 'aircraft-source',
    baseLayerId: 'aircraft-symbols',
    aircraftIconPath: 'traffic.png',
    arrowIconPath: 'arrow.png',
    // ... other parameters
  );
  print('✅ PNG symbols loaded successfully');
} catch (e) {
  print('❌ Error loading PNG symbols: $e');
  
  // Implement fallback strategy
  await _useFallbackTextSymbols();
}
```

### Common Issues and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Failed to load PNG asset" | Asset not declared in pubspec.yaml | Add asset to pubspec.yaml assets section |
| "Source already exists" | Duplicate source creation | Remove existing source before adding new one |
| Arrow overlaps aircraft | Insufficient arrowOffsetX | Increase arrowOffsetX to 80.0 or higher |
| Icons too small/large | Incorrect size values | Use recommended size ranges (0.1-0.25) |

## Advanced Usage

### Multi-Layer Aircraft Types

```dart
// Create different symbol layers for different aircraft categories
await Future.wait([
  // Commercial aircraft
  controller!.addRotatableSymbolPngLayers(
    sourceId: 'commercial-source',
    baseLayerId: 'commercial-aircraft',
    aircraftIconPath: 'boeing-737.png',
    arrowIconPath: 'blue-arrow.png',
    aircraftIconSize: 0.16,
  ),
  
  // General aviation
  controller!.addRotatableSymbolPngLayers(
    sourceId: 'ga-source', 
    baseLayerId: 'ga-aircraft',
    aircraftIconPath: 'cessna-172.png',
    arrowIconPath: 'green-arrow.png',
    aircraftIconSize: 0.12,
  ),
  
  // Emergency aircraft
  controller!.addRotatableSymbolPngLayers(
    sourceId: 'emergency-source',
    baseLayerId: 'emergency-aircraft', 
    aircraftIconPath: 'helicopter.png',
    arrowIconPath: 'red-arrow.png',
    aircraftIconSize: 0.20,
  ),
]);
```

### Custom Animation Patterns

```dart
// Create complex flight patterns
void _simulateFlightPattern() {
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    // Simulate banking turns
    final bankAngle = sin(_animationStep * 0.1) * 15.0; // ±15° bank
    final heading = _baseHeading + bankAngle;
    
    // Simulate altitude changes
    final altitudeChange = cos(_animationStep * 0.05) * 1000; // ±1000ft
    final currentAltitude = _baseAltitude + altitudeChange;
    
    // Update symbol with realistic flight dynamics
    _updateAircraftWithFlightDynamics(heading, currentAltitude);
    _animationStep++;
  });
}
```

## Best Practices

### Performance Optimization

1. **Limit Active Symbols**: Keep active symbols under 100 for optimal performance
2. **Efficient Updates**: Update only changed properties in GeoJSON
3. **Asset Optimization**: Use appropriately sized PNG assets (avoid oversized images)
4. **Animation Throttling**: Use 100-150ms intervals for smooth animation

### Aviation Safety Standards

1. **Icon Sizing**: Follow 0.15-0.20 scale for commercial aircraft
2. **High Contrast**: Ensure visibility in all lighting conditions
3. **Clear Orientation**: Aircraft icons must show clear directional heading
4. **Status Indication**: Always provide climb/descent status with arrows

### User Experience

1. **Visual Hierarchy**: Aircraft primary, arrows secondary, text tertiary
2. **Consistent Scaling**: Maintain proportional relationships at all zoom levels
3. **Interaction Feedback**: Provide clear feedback for tap interactions
4. **Error Recovery**: Implement graceful fallbacks for asset loading failures

## Migration from Text-Based Symbols

If migrating from the text-based `addRotatableSymbolLayers`:

```dart
// Old text-based approach
await controller!.addRotatableSymbolLayers(
  sourceId: 'aircraft-source',
  baseLayerId: 'aircraft-symbols',
  enableInteraction: true,
);

// New PNG-based approach  
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'aircraft-source',           // Same source
  baseLayerId: 'aircraft-png-symbols',   // Different layer ID
  aircraftIconPath: 'traffic.png',       // Add PNG assets
  arrowIconPath: 'arrow.png',
  aircraftIconSize: 0.15,                // Add size config
  arrowIconSize: 0.12,
  enableInteraction: true,
  config: {
    'arrowOffsetX': 80.0,                // Adjust positioning
    // ... other config
  },
);
```

## Troubleshooting

### Debug Steps

1. **Verify Asset Declaration**: Check pubspec.yaml includes your PNG files
2. **Check Asset Paths**: Ensure paths match exactly (case-sensitive)
3. **Restart App**: Native code changes require full app restart
4. **Enable Debug Logging**: Use debug prints to trace asset loading
5. **Test with Known Assets**: Verify with working traffic.png/arrow.png first

### Common Solutions

- **Asset not found**: Add to pubspec.yaml and restart app
- **Overlap issues**: Increase arrowOffsetX value
- **Size issues**: Adjust aircraftIconSize and arrowIconSize
- **Rotation problems**: Verify rotation property in GeoJSON
- **Performance issues**: Reduce update frequency or symbol count

## Complete Working Example

See `/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/maplibre_gl_example/lib/rotatable_symbol_png_test.dart` for a complete, working implementation with:

- Asset loading and error handling
- Real-time animation controls
- Manual rotation controls
- Status displays and debugging
- Fallback strategies

This example demonstrates all features and serves as a reference implementation for production use.