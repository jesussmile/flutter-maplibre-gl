# Native LERC Integration for MapLibre GL Flutter

This document describes the native LERC (Limited Error Raster Compression) decoder integration in the MapLibre GL Flutter library, providing a high-performance, flicker-free alternative to server-based terrain rendering.

## Overview

The native LERC integration provides:
- **Native Performance**: C++ LERC decoding on both Android and iOS
- **No Server Dependency**: Eliminates flickering and latency from server-based processing
- **Seamless Integration**: Part of the core MapLibre GL Flutter library
- **Cross-Platform**: Full Android and iOS support

## Features

### LERC Decoder
- Native C++ implementation using the official ESRI LERC library
- Direct integration with Flutter through JNI (Android) and Swift (iOS)
- High-performance elevation data decoding
- Memory-efficient processing

### Terrain Visualization
- Multiple color schemes (terrain, grayscale, hypsometric)
- Customizable elevation mapping
- Real-time terrain rendering
- Opacity and styling controls

## Installation

The LERC decoder is integrated into the main `maplibre_gl` library. No additional setup is required beyond the standard MapLibre GL installation.

### Dependencies
- Flutter SDK
- MapLibre GL Flutter plugin
- Android NDK (for Android builds)
- Xcode (for iOS builds)

## Usage

### Basic LERC Decoding

```dart
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:typed_data';

// Decode LERC data directly
Future<void> decodeLercData(Uint8List lercBuffer) async {
  // Get information about the LERC data
  final info = await LercDecoder.getLercInfo(lercBuffer);
  if (info == null) {
    print('Failed to get LERC info');
    return;
  }

  print('LERC Info: ${info.width}x${info.height}, range: ${info.minValue} to ${info.maxValue}');

  // Decode the elevation data
  final decodedData = await LercDecoder.decodeLerc(lercBuffer, info);
  if (decodedData == null) {
    print('Failed to decode LERC data');
    return;
  }

  // Access elevation values
  final centerX = info.width ~/ 2;
  final centerY = info.height ~/ 2;
  final elevation = decodedData.getElevation(centerX, centerY);
  print('Center elevation: $elevation');
}

// Or decode in one step
Future<void> quickDecode(Uint8List lercBuffer) async {
  final decodedData = await LercDecoder.decode(lercBuffer);
  if (decodedData != null) {
    print('Decoded ${decodedData.data.length} elevation values');
  }
}
```

### Terrain Layer Implementation

```dart
import 'package:maplibre_gl/maplibre_gl.dart';

class TerrainService {
  late MapLibreMapController _controller;

  void initializeMap(MapLibreMapController controller) {
    _controller = controller;
  }

  Future<void> addTerrainLayer(String terrainUrl) async {
    // Create terrain tile provider with native LERC decoding
    final provider = LercTerrainTileProvider(
      baseUrl: terrainUrl,
      colorScheme: ColorScheme.terrain,
      headers: {'User-Agent': 'MyFlightApp/1.0'},
    );

    // Add raster source
    await _controller.addSource(
      'terrain-source',
      RasterSourceProperties(
        tiles: [terrainUrl],
        tileSize: 256,
        maxzoom: 14,
      ),
    );

    // Add terrain layer
    await _controller.addLayer(
      'terrain-source',
      'terrain-layer',
      const RasterLayerProperties(
        rasterOpacity: 0.8,
      ),
    );
  }

  Future<void> setTerrainOpacity(double opacity) async {
    await _controller.setLayerProperties(
      'terrain-layer',
      RasterLayerProperties(
        rasterOpacity: opacity.clamp(0.0, 1.0),
      ),
    );
  }
}
```

### Color Schemes

The library provides three built-in color schemes:

```dart
// Terrain colors (blue -> green -> yellow -> red -> white)
LercTerrainTileProvider(
  baseUrl: terrainUrl,
  colorScheme: ColorScheme.terrain,
);

// Grayscale
LercTerrainTileProvider(
  baseUrl: terrainUrl,
  colorScheme: ColorScheme.grayscale,
);

// Hypsometric tinting (traditional cartographic colors)
LercTerrainTileProvider(
  baseUrl: terrainUrl,
  colorScheme: ColorScheme.hypsometric,
);
```

## API Reference

### LercDecoder

Static methods for LERC decoding:

```dart
class LercDecoder {
  // Get metadata about LERC data
  static Future<LercInfo?> getLercInfo(Uint8List buffer);
  
  // Decode LERC data with provided info
  static Future<DecodedLercData?> decodeLerc(Uint8List buffer, LercInfo info);
  
  // Decode in one step (info + decode)
  static Future<DecodedLercData?> decode(Uint8List buffer);
}
```

### LercInfo

Metadata about LERC data:

```dart
class LercInfo {
  final int width;          // Image width in pixels
  final int height;         // Image height in pixels
  final int numBands;       // Number of bands (usually 1 for elevation)
  final int numValidPixels; // Number of valid (non-NoData) pixels
  final double minValue;    // Minimum elevation value
  final double maxValue;    // Maximum elevation value
  final double noDataValue; // NoData/invalid value indicator
}
```

### DecodedLercData

Decoded elevation data with utility methods:

```dart
class DecodedLercData {
  final List<double> data;  // Raw elevation values
  final LercInfo info;      // Associated metadata
  
  // Get elevation at specific coordinates
  double getElevation(int x, int y);
  
  // Check if data is valid
  bool isValid();
  
  // Extract a region of elevation data
  List<double> getRegion(int startX, int startY, int width, int height);
}
```

### LercTerrainTileProvider

Tile provider for terrain visualization:

```dart
class LercTerrainTileProvider {
  const LercTerrainTileProvider({
    required String baseUrl,           // Tile URL template with {x}, {y}, {z}
    Map<String, String> headers = const {}, // HTTP headers
    ColorScheme colorScheme = ColorScheme.terrain, // Color mapping
  });
  
  // Get processed tile image
  Future<Uint8List?> getTile(int x, int y, int z);
}
```

## Performance Considerations

### Memory Usage
- LERC decoding is memory-efficient but can use significant RAM for large tiles
- Consider tile size limits based on device capabilities
- The decoder automatically frees native memory after processing

### Threading
- LERC decoding runs on background isolates to avoid blocking the UI
- Multiple tiles can be decoded concurrently
- Native operations are thread-safe

### Caching
- Implement tile caching to avoid repeated downloads and decoding
- Consider both raw LERC data and processed image caching
- Use appropriate cache eviction policies for memory management

## Troubleshooting

### Build Issues

**Android:**
```bash
# Ensure NDK is properly configured
flutter clean
flutter build apk --debug
```

**iOS:**
```bash
# Clean and rebuild iOS project
cd ios
rm -rf Pods/ Podfile.lock
pod install
cd ..
flutter clean
flutter build ios --debug
```

### Runtime Issues

**LERC Decoder Initialization:**
- Check that the native library is properly loaded
- Verify that LERC data is valid and properly formatted
- Ensure sufficient memory is available for decoding

**Terrain Rendering:**
- Verify tile URLs are accessible and return valid LERC data
- Check network connectivity and HTTP headers
- Validate color scheme and opacity settings

### Debug Output

Enable debug logging to troubleshoot issues:

```dart
// Check if LERC info can be read
final info = await LercDecoder.getLercInfo(lercBuffer);
if (info == null) {
  print('Failed to read LERC info - data may be corrupted');
} else {
  print('LERC Info: $info');
}
```

## Migration from Server-Based Implementation

If you're migrating from a server-based LERC implementation:

1. **Remove server dependencies**: No longer need terrain processing servers
2. **Update tile URLs**: Use direct LERC tile URLs instead of processed image URLs
3. **Adjust caching strategy**: Cache raw LERC data rather than processed images
4. **Update error handling**: Handle native decoding errors appropriately

### Before (Server-based):
```dart
// Old server-based approach
final terrainUrl = 'https://server.com/terrain/{z}/{x}/{y}.png?elevation=true';
```

### After (Native LERC):
```dart
// New native LERC approach
final terrainUrl = 'https://tiles.server.com/terrain/{z}/{x}/{y}.lerc';
final provider = LercTerrainTileProvider(
  baseUrl: terrainUrl,
  colorScheme: ColorScheme.terrain,
);
```

## Contributing

The LERC integration is part of the main MapLibre GL Flutter library. Contributions should be made to the main repository following the standard contribution guidelines.

### Development Setup

1. Clone the MapLibre GL Flutter repository
2. Navigate to the `maplibre_gl` package
3. The LERC implementation is in:
   - `android/src/main/cpp/` (Android native code)
   - `ios/maplibre_gl/Sources/maplibre_gl/LERC/` (iOS native code)
   - `lib/src/lerc_decoder.dart` (Dart interface)
   - `lib/src/terrain_layer.dart` (Terrain provider)

## License

The LERC integration follows the same license as the MapLibre GL Flutter library. The LERC library itself is licensed under the Apache 2.0 license by ESRI. 