# Real-Time PNG Color Changing Documentation

## Overview

This guide explains how to implement **real-time color changes** for PNG aircraft symbols based on proximity, status, or any dynamic data. Perfect for safety-critical aviation applications where visual alerts are essential.

## 🎨 Color-Changing Options

### Option 1: Icon Tinting (Recommended)
**Best for**: Single-color PNG icons with transparency
**Performance**: Excellent (GPU-accelerated)
**Flexibility**: High

```dart
// Dynamic color properties in GeoJSON
'properties': {
  'aircraftIconColor': '#FF0000',  // Red for critical proximity
  'arrowIconColor': '#FFA500',     // Orange for warning
  // ... other properties
}
```

### Option 2: Multiple PNG Variants
**Best for**: Complex multi-color designs
**Performance**: Good (asset switching)
**Flexibility**: Medium

```dart
// Switch between different PNG assets
'properties': {
  'aircraftType': _proximityDistance < 2.0 ? 'critical' : 'normal',
  // ... other properties
}

// In native code, load different PNG files based on type
String aircraftIconPath = aircraftType == 'critical' ? 'aircraft-red.png' : 'traffic.png';
```

### Option 3: SDF (Signed Distance Field) Icons
**Best for**: Vector-like scaling and coloring
**Performance**: Excellent
**Flexibility**: Very High

```dart
// Use SDF icons for perfect scaling and coloring
style.addImage(iconId, bitmap, true); // true = SDF enabled
```

## 🚨 Proximity-Based Color Coding

### Aviation Standard Color Scheme

```dart
String getAircraftColor(double proximityDistance) {
  if (proximityDistance < 2.0) {
    return '#FF0000'; // 🔴 Red - Critical proximity (<2nm)
  } else if (proximityDistance < 5.0) {
    return '#FFA500'; // 🟠 Orange - Warning proximity (2-5nm)
  } else if (proximityDistance < 10.0) {
    return '#FFFF00'; // 🟡 Yellow - Caution proximity (5-10nm)
  } else {
    return '#00FF00'; // 🟢 Green - Safe distance (>10nm)
  }
}
```

### Traffic Alert and Collision Avoidance System (TCAS) Colors

```dart
String getTcasColor(String tcasLevel) {
  switch (tcasLevel) {
    case 'RA': return '#FF0000';  // Resolution Advisory - Red
    case 'TA': return '#FFA500';  // Traffic Advisory - Amber
    case 'OT': return '#FFFF00';  // Other Traffic - Yellow
    case 'NT': return '#00FF00';  // No Threat - Green
    default: return '#808080';    // Unknown - Gray
  }
}
```

## 🔄 Real-Time Implementation

### Basic Proximity Monitoring

```dart
class ProximityMonitor {
  Timer? _updateTimer;
  List<Aircraft> _aircraftList = [];
  
  void startMonitoring() {
    _updateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      _updateProximityColors();
    });
  }
  
  void _updateProximityColors() {
    for (final aircraft in _aircraftList) {
      // Calculate proximity to own aircraft
      final distance = _calculateDistance(ownAircraftPosition, aircraft.position);
      
      // Update aircraft color based on proximity
      aircraft.iconColor = _getProximityColor(distance);
      aircraft.priority = _getProximityPriority(distance);
    }
    
    // Update map with new colors
    _updateMapSymbols();
  }
}
```

### Advanced Multi-Factor Coloring

```dart
String getAdvancedAircraftColor(Aircraft aircraft) {
  // Priority 1: Emergency aircraft (always red)
  if (aircraft.isEmergency) {
    return '#FF0000';
  }
  
  // Priority 2: Proximity-based coloring
  if (aircraft.proximityDistance < 2.0) {
    return '#FF0000'; // Critical proximity
  }
  
  // Priority 3: Altitude separation
  final altitudeSeparation = (aircraft.altitude - ownAircraft.altitude).abs();
  if (altitudeSeparation < 1000 && aircraft.proximityDistance < 5.0) {
    return '#FF4500'; // Orange-red for altitude conflict
  }
  
  // Priority 4: Relative velocity (closing rate)
  if (aircraft.closingRate > 500) { // 500 knots closing
    return '#FFA500'; // Orange for high closing rate
  }
  
  // Priority 5: Flight level (same altitude band)
  if (altitudeSeparation < 2000) {
    return '#FFFF00'; // Yellow for same flight level
  }
  
  // Default: Safe
  return '#00FF00';
}
```

## 📊 Dynamic Data Sources

### ADS-B Integration

```dart
class AdsbDataManager {
  StreamSubscription? _adsbSubscription;
  
  void connectToAdsbSource() {
    _adsbSubscription = adsbStream.listen((AdsbMessage message) {
      final aircraft = _aircraftList[message.icao];
      
      // Update position
      aircraft.position = LatLng(message.latitude, message.longitude);
      aircraft.altitude = message.altitude;
      aircraft.heading = message.heading;
      
      // Calculate proximity
      final distance = _calculateProximity(aircraft.position);
      aircraft.proximityDistance = distance;
      
      // Determine threat level
      aircraft.threatLevel = _assessThreatLevel(aircraft);
      
      // Update colors based on threat
      aircraft.iconColor = _getThreatColor(aircraft.threatLevel);
      
      // Update map display
      _updateAircraftSymbol(aircraft);
    });
  }
}
```

### Weather-Based Coloring

```dart
String getWeatherBasedColor(Aircraft aircraft, WeatherData weather) {
  // Turbulence severity coloring
  if (weather.turbulence == TurbulenceLevel.severe) {
    return '#8B0000'; // Dark red for severe turbulence
  } else if (weather.turbulence == TurbulenceLevel.moderate) {
    return '#FF4500'; // Orange-red for moderate turbulence
  }
  
  // Icing conditions
  if (weather.icingProbability > 0.7) {
    return '#4169E1'; // Royal blue for icing
  }
  
  // Default proximity-based coloring
  return getProximityColor(aircraft.proximityDistance);
}
```

## 🎯 Complete Working Example

```dart
class DynamicColorAircraft {
  String icao;
  LatLng position;
  double altitude;
  double heading;
  double proximityDistance;
  bool isClimbing;
  bool isEmergency;
  double closingRate;
  ThreatLevel threatLevel;
  
  String get iconColor {
    // Multi-factor color determination
    if (isEmergency) return '#FF0000';
    if (proximityDistance < 2.0) return '#FF0000';
    if (proximityDistance < 5.0 && closingRate > 300) return '#FF4500';
    if (proximityDistance < 5.0) return '#FFA500';
    if (proximityDistance < 10.0) return '#FFFF00';
    return '#00FF00';
  }
  
  String get arrowColor {
    if (proximityDistance < 2.0) return '#FF0000';
    return isClimbing ? '#00FF00' : '#FF4500';
  }
  
  Map<String, dynamic> toGeoJsonProperties() {
    return {
      'rotation': heading,
      'topLabel': '${(altitude / 100).round()}K',
      'bottomLabel': icao,
      'isClimbing': isClimbing,
      'aircraftIconColor': iconColor,
      'arrowIconColor': arrowColor,
      'labelSize': proximityDistance < 5.0 ? 16.0 : 14.0, // Larger labels for close aircraft
      'labelColor': proximityDistance < 2.0 ? '#FF0000' : '#000000',
      'triangleOpacity': 1.0,
      'arrowOpacity': 1.0,
    };
  }
}

// Usage in map update
Future<void> updateAircraftColors() async {
  final features = aircraftList.map((aircraft) => {
    'type': 'Feature',
    'geometry': {
      'type': 'Point',
      'coordinates': [aircraft.position.longitude, aircraft.position.latitude],
    },
    'properties': aircraft.toGeoJsonProperties(),
  }).toList();
  
  final geoJson = {
    'type': 'FeatureCollection',
    'features': features,
  };
  
  await controller.setGeoJsonSource('aircraft-source', geoJson);
}
```

## 🎨 PNG Asset Requirements for Color Tinting

### Optimal PNG Design for Tinting

1. **Use Grayscale or White Icons**: Start with white/light gray icons for best tinting results
2. **Maintain Transparency**: Preserve alpha channel for proper overlay
3. **Simple Color Palette**: Avoid complex gradients that don't tint well
4. **High Contrast**: Ensure visibility after tinting

### Example PNG Creation Workflow

```bash
# Using ImageMagick to create tintable aircraft icons
convert aircraft-original.png -colorspace Gray aircraft-gray.png
convert aircraft-gray.png -alpha set -channel RGBA -fill white -colorize 100% aircraft-white.png
```

### Testing Different Colors

```dart
// Test color visibility for accessibility
final testColors = [
  '#FF0000', // Red
  '#FFA500', // Orange  
  '#FFFF00', // Yellow
  '#00FF00', // Green
  '#0000FF', // Blue
  '#800080', // Purple
];

for (final color in testColors) {
  // Test each color for visibility and contrast
  final visibility = calculateVisibility(color, backgroundColor);
  print('Color $color visibility: $visibility');
}
```

## 🚀 Performance Optimization

### Efficient Color Updates

```dart
class ColorUpdateOptimizer {
  Map<String, String> _lastColors = {};
  
  bool shouldUpdateColor(String aircraftId, String newColor) {
    final lastColor = _lastColors[aircraftId];
    if (lastColor != newColor) {
      _lastColors[aircraftId] = newColor;
      return true;
    }
    return false;
  }
  
  void batchUpdateColors(List<Aircraft> aircraft) {
    final updates = <Aircraft>[];
    
    for (final ac in aircraft) {
      if (shouldUpdateColor(ac.icao, ac.iconColor)) {
        updates.add(ac);
      }
    }
    
    if (updates.isNotEmpty) {
      _updateMapWithChangedColors(updates);
    }
  }
}
```

### Memory Management

```dart
class ColorCache {
  static const int maxCacheSize = 1000;
  final Map<String, String> _colorCache = {};
  
  String getCachedColor(String key) {
    if (_colorCache.length > maxCacheSize) {
      _colorCache.clear(); // Clear cache when too large
    }
    
    return _colorCache.putIfAbsent(key, () => _calculateColor(key));
  }
}
```

## 🎛️ User Configuration

### Customizable Color Schemes

```dart
class ColorSchemeManager {
  static const Map<String, Map<String, String>> schemes = {
    'standard': {
      'critical': '#FF0000',
      'warning': '#FFA500', 
      'caution': '#FFFF00',
      'safe': '#00FF00',
    },
    'colorblind': {
      'critical': '#D55E00',
      'warning': '#E69F00',
      'caution': '#F0E442', 
      'safe': '#009E73',
    },
    'night': {
      'critical': '#8B0000',
      'warning': '#B8860B',
      'caution': '#9ACD32',
      'safe': '#006400',
    },
  };
  
  static String getColor(String scheme, String level) {
    return schemes[scheme]?[level] ?? schemes['standard']![level]!;
  }
}
```

## 📱 Complete Demo Implementation

The complete working example is available at:
`/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/maplibre_gl_example/lib/color_changing_png_symbols.dart`

This demo includes:
- ✅ Real-time proximity simulation
- ✅ Multiple aircraft with different threat levels
- ✅ Dynamic color changes based on distance
- ✅ Interactive controls for testing
- ✅ Visual status indicators
- ✅ Aviation-standard color coding

## 🔧 Integration Steps

1. **Add Native Color Support**: Update native MapLibre implementation to support `iconColor` property
2. **Implement Color Logic**: Create color calculation functions based on your requirements  
3. **Update GeoJSON Properties**: Include color properties in aircraft data
4. **Handle Real-Time Updates**: Update colors based on live data streams
5. **Test Visibility**: Ensure colors are visible in all conditions
6. **Add User Controls**: Allow users to customize color schemes

This system provides maximum flexibility for implementing any color-changing logic while maintaining excellent performance and aviation safety standards!