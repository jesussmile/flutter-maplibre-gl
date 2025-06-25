# LERC Implementation Guide

This guide outlines the step-by-step process for implementing LERC (Limited Error Raster Compression) terrain visualization functionality in a new Flutter project. It covers native code integration, Flutter bindings, and terrain rendering, with references to the specific documentation files for detailed information on each component.

## Implementation Sequence

To successfully implement LERC terrain visualization, follow the sequence below and refer to the linked documentation files for detailed information on each step.

### Phase 1: Project Setup and Dependencies

**Documentation References:**
- [Project Structure](project_structure.md) - Overview of the entire project structure
- [API Documentation](api_documentation.md) - Core API details

1. **Create a new Flutter plugin project**
   ```bash
   flutter create --template=plugin --platforms=android,ios terrain_visualization
   ```

2. **Configure pubspec.yaml with required dependencies**
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     flutter_map: ^5.0.0  # Or latest version
     latlong2: ^0.9.0     # Or latest version
     ffi: ^2.0.0          # For native code integration
   
   dev_dependencies:
     flutter_test:
       sdk: flutter
     ffigen: ^8.0.0       # For generating FFI bindings
   ```

3. **Set up FFI plugin configuration in pubspec.yaml**
   ```yaml
   flutter:
     plugin:
       platforms:
         android:
           ffiPlugin: true
         ios:
           ffiPlugin: true
   ```

4. **Create assets folder and add LERC test files**
   - Create an `assets` directory in the project root
   - Add sample LERC files (*.lerc2) for testing
   - Reference [Project Structure](project_structure.md) for the expected directory layout

### Phase 2: LERC Library Integration

**Documentation References:**
- [LERC Integration](lerc_integration.md) - Overview of LERC library integration
- [LERC Source Directory](lerc_source_directory.md) - Details of the LERC library structure
- [C++ Wrapper Implementation](cpp_wrapper_implementation.md) - Complete details of the wrapper
- [CMake Configuration](cmake_configuration.md) - Details of the build system
- [Platform Specific Implementation](platform_specific_implementation.md) - Android and iOS specifics

1. **Obtain the LERC library source code**
   - Clone or download the LERC source from the official repository
   - Place it in a directory (e.g., `lerc-master`) within your project
   - Reference [LERC Source Directory](lerc_source_directory.md) for structure details

2. **Create C++ wrapper files**
   - Create a `src` directory in the project root
   - Create `lerc_wrapper.h` with the C API interface for FFI
   - Create `lerc_wrapper.cpp` with the implementation that calls LERC
   - Follow [C++ Wrapper Implementation](cpp_wrapper_implementation.md) for detailed implementation

3. **Create CMakeLists.txt in the project root**
   ```cmake
   cmake_minimum_required(VERSION 3.10)

   # Set LERC source files
   file(GLOB LERC_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/*.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode/*.cpp"
   )

   # Create LERC library as static
   add_library(lerc STATIC ${LERC_SOURCES})
   target_include_directories(lerc PUBLIC
       "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
       "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
       "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
   )

   # Create the wrapper library
   add_library(lerc_wrapper SHARED "src/lerc_wrapper.cpp")
   target_link_libraries(lerc_wrapper PRIVATE lerc)
   ```
   - Reference [CMake Configuration](cmake_configuration.md) for detailed CMake setup

4. **Configure Android integration**
   - Ensure `android/build.gradle.kts` is configured for CMake
   - See [Platform Specific Implementation](platform_specific_implementation.md) for Android details

5. **Configure iOS integration**
   - Create a build script (`compile_lerc_ios.sh`) for iOS builds
   - Create an Objective-C++ wrapper (`ios/Classes/LercWrapper.mm`)
   - Follow [Platform Specific Implementation](platform_specific_implementation.md) for iOS-specific details

### Phase 3: Dart FFI Bindings

**Documentation References:**
- [Dart FFI Integration](dart_ffi_integration.md) - Complete FFI implementation details
- [Dart FFI Bindings](dart_ffi_bindings.md) - Details of the bindings generation
- [Basic LERC Decoding](basic_lerc_decoding.md) - Core decoding functionality
- [Multithreaded Decoding](multithreaded_decoding.md) - Isolate-based processing
- [Memory Management](memory_management.md) - Native memory handling

1. **Create ffigen.yaml configuration**
   ```yaml
   name: LercBindings
   description: 'Bindings for LERC decoder'
   output: 'lib/src/bindings/lerc_bindings.dart'
   headers:
     entry-points:
       - 'src/lerc_wrapper.h'
     include-directives:
       - 'src/lerc_wrapper.h'
   ```
   - Reference [Dart FFI Bindings](dart_ffi_bindings.md) for detailed configuration

2. **Generate the FFI bindings**
   ```bash
   flutter pub run ffigen --config ffigen.yaml
   ```

3. **Create Dart LERC decoder class**
   - Implement a class to load the native library
   - Add functions that call the native code through FFI
   - Implement isolate-based background processing
   - Follow [Dart FFI Integration](dart_ffi_integration.md) for the implementation
   - See [Multithreaded Decoding](multithreaded_decoding.md) for isolate details
   - Refer to [Memory Management](memory_management.md) for proper memory handling

### Phase 4: Terrain Visualization Implementation

**Documentation References:**
- [Flutter Map Terrain Layer](flutter_map_terrain_layer.md) - Implementation of the map layer
- [Flutter Map Tile Provider](flutter_map_tile_provider.md) - Custom tile provider details
- [Raw Elevation Data Processing](raw_elevation_data_processing.md) - Processing elevation data
- [Terrain Visualization Techniques](terrain_visualization_techniques.md) - Visualization approaches
- [Altitude-Based Terrain Coloring](altitude_based_terrain_coloring.md) - Coloring algorithms
- [Altitude Bucketing](altitude_bucketing.md) - Discrete altitude ranges
- [Reference Altitude and Warning Levels](reference_altitude_and_warning_levels.md) - Managing altitude references

1. **Define data structures for decoded elevation data**
   - Create a class to hold decoded LERC data
   - Implement methods for accessing elevation values
   - Reference [Raw Elevation Data Processing](raw_elevation_data_processing.md) for implementation details

2. **Create tile provider for flutter_map**
   - Implement a custom tile provider that uses LERC data
   - Add coloring and rendering algorithms
   - Follow [Flutter Map Tile Provider](flutter_map_tile_provider.md) for implementation
   - Use [Altitude-Based Terrain Coloring](altitude_based_terrain_coloring.md) for coloring algorithms
   - See [Altitude Bucketing](altitude_bucketing.md) for discrete elevation ranges

3. **Implement the terrain map layer**
   - Create a Flutter widget that renders terrain data
   - Support multiple rendering modes
   - Implement UI controls for altitude reference
   - Refer to [Flutter Map Terrain Layer](flutter_map_terrain_layer.md) for detailed implementation
   - See [Reference Altitude and Warning Levels](reference_altitude_and_warning_levels.md) for altitude management
   - Use [Basic Terrain Display UI Controls](basic_terrain_display_ui_controls.md) for UI elements

### Phase 5: Advanced Features

**Documentation References:**
- [Multiple Terrain Rendering Modes](multiple_terrain_rendering_modes.md) - Different rendering techniques
- [Hillshading Support](hillshading_support.md) - Adding hillshade visualization
- [LERC Data Caching](lerc_data_caching.md) - Caching strategies
- [Performance Optimization Techniques](performance_optimization_techniques.md) - Improving performance
- [Throttling and Debouncing](throttling_and_debouncing.md) - Handling frequent updates
- [Enhanced Visualization UI Controls](enhanced_visualization_ui_controls.md) - Advanced UI controls
- [Offline Terrain Data](offline_terrain_data.md) - Support for offline use
- [Custom Terrain Data Sources](custom_terrain_data_sources.md) - Using different data sources

1. **Add multi-threading support**
   - Implement isolate-based parallel processing
   - Add memory management for large datasets
   - Reference [Multithreaded Decoding](multithreaded_decoding.md) for implementation details
   - See [Memory Management](memory_management.md) for handling large datasets

2. **Implement data caching**
   - Create caching mechanisms for LERC data
   - Implement tile caching for rendering
   - Follow [LERC Data Caching](lerc_data_caching.md) for caching strategies
   - Consider [Offline Terrain Data](offline_terrain_data.md) for persistent caching

3. **Add hill shading support**
   - Integrate hillshade data with elevation data
   - Implement hill shading algorithms
   - Use [Hillshading Support](hillshading_support.md) for detailed implementation
   - See [Multiple Terrain Rendering Modes](multiple_terrain_rendering_modes.md) for integration with other modes

4. **Implement performance optimizations**
   - Add throttling and debouncing for map interactions
   - Optimize memory usage for large datasets
   - Follow [Performance Optimization Techniques](performance_optimization_techniques.md) for general optimizations
   - Use [Throttling and Debouncing](throttling_and_debouncing.md) for smooth map interactions

## Detailed Implementation Steps

### C++ Wrapper Implementation

Create `src/lerc_wrapper.h`:

```cpp
#ifndef LERC_WRAPPER_H
#define LERC_WRAPPER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t numBands;
    uint32_t numValidPixels;
    double minValue;
    double maxValue;
    double noDataValue;
} LercInfo;

bool lerc_wrapper_initialize(void);
LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size);
double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info);
void lerc_wrapper_free_info(LercInfo* info);
void lerc_wrapper_free_data(double* data);

#ifdef __cplusplus
}
#endif

#endif // LERC_WRAPPER_H
```

Create `src/lerc_wrapper.cpp`:

```cpp
#include "lerc_wrapper.h"
#include "Lerc_c_api.h"
#include <cstdio>

bool lerc_wrapper_initialize() {
    return true;
}

LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size) {
    try {
        unsigned int infoArray[10];
        double dataRangeArray[3];
        
        lerc_status status = lerc_getBlobInfo(
            buffer,
            static_cast<unsigned int>(size),
            infoArray,
            dataRangeArray,
            10,
            3
        );
        
        if (status != 0) return nullptr;

        auto* info = new LercInfo{
            infoArray[3],  // width
            infoArray[4],  // height
            infoArray[5],  // numBands
            infoArray[6],  // numValidPixels
            dataRangeArray[0],  // minValue
            dataRangeArray[1],  // maxValue
            -9999.0  // noDataValue (default)
        };
        
        return info;
    } catch (...) {
        return nullptr;
    }
}

double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info) {
    try {
        if (!info) return nullptr;

        size_t numPixels = info->width * info->height;
        auto* floatData = new float[numPixels];
        auto* doubleData = new double[numPixels];

        // Try decoding as float first
        lerc_status status = lerc_decode(
            buffer,
            static_cast<unsigned int>(size),
            0,         // bitmap mask (none)
            nullptr,   // bitmap mask (none)
            1,         // number of bands to process
            info->width,
            info->height,
            1,         // number of bands in input
            6,         // data type = float
            floatData
        );

        if (status != 0) {
            // If float fails, try decoding as double
            status = lerc_decode(
                buffer,
                static_cast<unsigned int>(size),
                0,
                nullptr,
                1,
                info->width,
                info->height,
                1,
                7,         // data type = double
                doubleData
            );

            if (status != 0) {
                delete[] floatData;
                delete[] doubleData;
                return nullptr;
            }

            delete[] floatData;
            return doubleData;
        }

        // Convert float to double if decoded as float
        for (size_t i = 0; i < numPixels; i++) {
            doubleData[i] = static_cast<double>(floatData[i]);
        }

        delete[] floatData;
        return doubleData;
    } catch (...) {
        return nullptr;
    }
}

void lerc_wrapper_free_info(LercInfo* info) {
    delete info;
}

void lerc_wrapper_free_data(double* data) {
    delete[] data;
}
```

### Dart FFI Implementation

Create `lib/src/lerc_decoder.dart`:

```dart
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'bindings/lerc_bindings.dart';

class DecodedLercData {
  final Float64List data;
  final int width;
  final int height;
  final double minValue;
  final double maxValue;

  DecodedLercData(
    this.data,
    this.width,
    this.height,
    this.minValue,
    this.maxValue,
  );

  bool isValid() {
    return data.isNotEmpty && width > 0 && height > 0;
  }

  // Get elevation at specific coordinates
  double getElevation(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.nan;
    return data[y * width + x];
  }

  // Get a subregion of elevations
  Float64List getRegion(int startX, int startY, int regionWidth, int regionHeight) {
    final result = Float64List(regionWidth * regionHeight);
    for (int y = 0; y < regionHeight; y++) {
      for (int x = 0; x < regionWidth; x++) {
        final sourceX = startX + x;
        final sourceY = startY + y;
        if (sourceX >= 0 && sourceX < width && sourceY >= 0 && sourceY < height) {
          result[y * regionWidth + x] = data[sourceY * width + sourceX];
        }
      }
    }
    return result;
  }
}

class _IsolateData {
  final Uint8List bytes;
  final SendPort sendPort;
  final String libraryPath;

  _IsolateData(this.bytes, this.sendPort, this.libraryPath);
}

class _IsolateMessage {
  final bool success;
  final dynamic data;
  final String? error;

  _IsolateMessage.success(this.data)
      : success = true,
        error = null;

  _IsolateMessage.error(this.error)
      : success = false,
        data = null;
}

class LercDecoder {
  static DynamicLibrary? _dylib;
  static bool _initialized = false;
  static late LercBindings _bindings;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Determine the appropriate library path based on platform
      String libraryPath;
      if (Platform.isAndroid) {
        libraryPath = 'liblerc_wrapper.so';
      } else if (Platform.isIOS) {
        libraryPath = 'lerc_wrapper';
      } else {
        throw UnsupportedError(
          'This app only supports Android and iOS platforms',
        );
      }

      if (Platform.isAndroid) {
        // Android uses a shared library
        _dylib = DynamicLibrary.open(libraryPath);
      } else if (Platform.isIOS) {
        // iOS process name is the library name
        _dylib = DynamicLibrary.process();
      }

      _bindings = LercBindings(_dylib!);

      if (!_bindings.lerc_wrapper_initialize()) {
        throw Exception('Failed to initialize LERC decoder');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing LERC library: $e');
      rethrow;
    }
  }

  static Future<DecodedLercData> decode(Uint8List bytes) async {
    if (!_initialized) {
      await initialize();
    }

    final receivePort = ReceivePort();
    String libraryPath = '';
    if (Platform.isAndroid) {
      libraryPath = 'liblerc_wrapper.so';
    }

    final isolate = await Isolate.spawn(
      _isolateFunction,
      _IsolateData(bytes, receivePort.sendPort, libraryPath),
    );

    try {
      final result = await receivePort.first as _IsolateMessage;
      if (!result.success) {
        throw Exception(result.error);
      }
      return result.data as DecodedLercData;
    } finally {
      isolate.kill();
      receivePort.close();
    }
  }

  static void _isolateFunction(_IsolateData isolateData) {
    try {
      // Load library in isolate
      DynamicLibrary dylib;
      if (Platform.isAndroid) {
        dylib = DynamicLibrary.open(isolateData.libraryPath);
      } else if (Platform.isIOS) {
        dylib = DynamicLibrary.process();
      } else {
        isolateData.sendPort.send(
          _IsolateMessage.error('Unsupported platform'),
        );
        return;
      }

      final bindings = LercBindings(dylib);
      if (!bindings.lerc_wrapper_initialize()) {
        isolateData.sendPort.send(
          _IsolateMessage.error('Failed to initialize LERC decoder in isolate'),
        );
        return;
      }

      final bytes = isolateData.bytes;
      final inputPtr = malloc<Uint8>(bytes.length);
      final inputArray = inputPtr.asTypedList(bytes.length);
      inputArray.setAll(0, bytes);

      Pointer<LercInfo> infoPtr = nullptr;
      Pointer<Double> dataPtr = nullptr;

      try {
        infoPtr = bindings.lerc_wrapper_get_info(inputPtr.cast(), bytes.length);
        if (infoPtr == nullptr) {
          isolateData.sendPort.send(
            _IsolateMessage.error('Failed to get LERC info'),
          );
          return;
        }

        final info = infoPtr.ref;
        
        dataPtr = bindings.lerc_wrapper_decode(
          inputPtr.cast(),
          bytes.length,
          infoPtr,
        );
        
        if (dataPtr == nullptr) {
          isolateData.sendPort.send(
            _IsolateMessage.error('Failed to decode LERC data'),
          );
          return;
        }

        final numPixels = info.width * info.height;
        final data = Float64List.fromList(dataPtr.asTypedList(numPixels));

        final result = DecodedLercData(
          data,
          info.width,
          info.height,
          info.minValue,
          info.maxValue,
        );

        isolateData.sendPort.send(_IsolateMessage.success(result));
      } finally {
        malloc.free(inputPtr);
        if (infoPtr != nullptr) {
          bindings.lerc_wrapper_free_info(infoPtr);
        }
        if (dataPtr != nullptr) {
          bindings.lerc_wrapper_free_data(dataPtr);
        }
      }
    } catch (e) {
      isolateData.sendPort.send(_IsolateMessage.error(e.toString()));
    }
  }
}
```

### Terrain Layer Implementation 

Create `lib/src/lerc_tile_provider.dart`:

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';

import 'lerc_decoder.dart';

enum TerrainColorMode {
  gradient,
  discrete,
  hillshade
}

class LercTileProvider extends TileProvider {
  final DecodedLercData data;
  final double referenceAltitude;
  final double warningAltitude;
  final double minElevation;
  final double terrainResolution;
  final ValueChanged<double>? onElevationRead;
  
  static bool _gradientMode = true;
  static TerrainColorMode _colorMode = TerrainColorMode.gradient;
  
  // Color settings
  static final List<Color> _elevationColors = [
    Colors.darkBlue,     // Deep water
    Colors.blue,         // Water
    Colors.lightBlue,    // Shallow water
    Colors.lightGreen,   // Low terrain
    Colors.green,        // Medium terrain
    Colors.brown,        // High terrain
    Colors.grey,         // Very high terrain
    Colors.white,        // Mountain peaks
  ];
  
  // Discrete altitude buckets (in feet above reference)
  static const List<double> _altitudeBuckets = [
    -2000.0, -1000.0, 0.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0
  ];

  const LercTileProvider({
    required this.data,
    required this.referenceAltitude,
    required this.warningAltitude,
    required this.minElevation,
    required this.terrainResolution,
    this.onElevationRead,
  });

  static void setGradientMode(bool enabled) {
    _gradientMode = enabled;
  }
  
  static void setColorMode(TerrainColorMode mode) {
    _colorMode = mode;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return LercTileImage(
      data: data,
      coordinates: coordinates,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      terrainResolution: terrainResolution,
    );
  }
}

class LercTileImage extends ImageProvider<LercTileImage> {
  final DecodedLercData data;
  final TileCoordinates coordinates;
  final double referenceAltitude;
  final double warningAltitude;
  final double minElevation;
  final double terrainResolution;

  const LercTileImage({
    required this.data,
    required this.coordinates,
    required this.referenceAltitude,
    required this.warningAltitude,
    required this.minElevation,
    required this.terrainResolution,
  });

  @override
  Future<LercTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<LercTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(LercTileImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadAsync());
  }

  Future<ImageInfo> _loadAsync() async {
    // Calculate tile position within global elevation data
    final tileSize = 256;
    final scale = data.width / (2 << coordinates.z);
    final x = (coordinates.x * tileSize * scale).floor();
    final y = (coordinates.y * tileSize * scale).floor();
    final width = (tileSize * scale).ceil();
    final height = (tileSize * scale).ceil();
    
    // Get data for this tile region
    final tileData = data.getRegion(x, y, width, height);

    // Create image from elevation data
    final ui.Image image = await _createImageFromElevation(
      tileData,
      width,
      height,
      tileSize,
    );
    
    return ImageInfo(image: image, scale: 1.0);
  }

  Future<ui.Image> _createImageFromElevation(
    Float64List elevations,
    int sourceWidth,
    int sourceHeight,
    int targetSize,
  ) async {
    final pixels = Uint32List(targetSize * targetSize);
    
    // Rendering logic depends on the color mode
    if (LercTileProvider._colorMode == TerrainColorMode.discrete) {
      _renderDiscreteColorMode(
        elevations, sourceWidth, sourceHeight, 
        targetSize, pixels
      );
    } else {
      _renderGradientColorMode(
        elevations, sourceWidth, sourceHeight, 
        targetSize, pixels
      );
    }
    
    // Create image from pixel data
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(),
      targetSize,
      targetSize,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    
    return completer.future;
  }

  void _renderGradientColorMode(
    Float64List elevations,
    int sourceWidth,
    int sourceHeight,
    int targetSize,
    Uint32List pixels,
  ) {
    // Calculation factors
    final xScale = sourceWidth / targetSize;
    final yScale = sourceHeight / targetSize;
    
    // Colors for gradient
    final colors = LercTileProvider._elevationColors;
    final buckets = LercTileProvider._altitudeBuckets;
    
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        // Find corresponding elevation data point
        final sourceX = (x * xScale).floor();
        final sourceY = (y * yScale).floor();
        final index = sourceY * sourceWidth + sourceX;
        
        if (index >= elevations.length) continue;
        
        // Get elevation and convert to feet relative to reference
        final elevation = elevations[index];
        final relativeElevation = (elevation - referenceAltitude) * 3.28084;
        
        // Find color based on elevation
        Color color;
        if (relativeElevation <= buckets.first) {
          color = colors.first;
        } else if (relativeElevation >= buckets.last) {
          color = colors.last;
        } else {
          // Find the bucket this elevation falls into
          int i = 0;
          while (i < buckets.length - 1 && relativeElevation > buckets[i + 1]) {
            i++;
          }
          
          // Calculate interpolation factor
          final factor = (relativeElevation - buckets[i]) / 
              (buckets[i + 1] - buckets[i]);
          
          // Interpolate color
          color = Color.lerp(colors[i], colors[i + 1], factor)!;
        }
        
        // Convert to ARGB for image
        pixels[y * targetSize + x] = color.value;
      }
    }
  }

  void _renderDiscreteColorMode(
    Float64List elevations,
    int sourceWidth,
    int sourceHeight,
    int targetSize,
    Uint32List pixels,
  ) {
    // Similar to gradient mode but without interpolation
    final xScale = sourceWidth / targetSize;
    final yScale = sourceHeight / targetSize;
    
    final colors = LercTileProvider._elevationColors;
    final buckets = LercTileProvider._altitudeBuckets;
    
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final sourceX = (x * xScale).floor();
        final sourceY = (y * yScale).floor();
        final index = sourceY * sourceWidth + sourceX;
        
        if (index >= elevations.length) continue;
        
        final elevation = elevations[index];
        final relativeElevation = (elevation - referenceAltitude) * 3.28084;
        
        // Find the appropriate bucket without interpolation
        int colorIndex = 0;
        while (colorIndex < buckets.length - 1 && 
               relativeElevation > buckets[colorIndex + 1]) {
          colorIndex++;
        }
        
        pixels[y * targetSize + x] = colors[colorIndex].value;
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is LercTileImage &&
        other.coordinates == coordinates &&
        other.referenceAltitude == referenceAltitude;
  }

  @override
  int get hashCode => Object.hash(coordinates, referenceAltitude);
}
```

### Example Usage

Create a simple terrain viewer in `lib/main.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'src/lerc_decoder.dart';
import 'src/lerc_tile_provider.dart';

void main() {
  runApp(const TerrainApp());
}

class TerrainApp extends StatelessWidget {
  const TerrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terrain Visualization',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TerrainMapScreen(),
    );
  }
}

class TerrainMapScreen extends StatefulWidget {
  const TerrainMapScreen({super.key});

  @override
  State<TerrainMapScreen> createState() => _TerrainMapScreenState();
}

class _TerrainMapScreenState extends State<TerrainMapScreen> {
  DecodedLercData? _elevationData;
  DecodedLercData? _hillshadeData;
  final ValueNotifier<double> _referenceAltitude = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _terrainResolution = ValueNotifier<double>(1.0);
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadElevationData();
  }

  Future<void> _loadElevationData() async {
    try {
      // Initialize the LERC decoder
      await LercDecoder.initialize();
      
      // Load elevation data
      final elevationBytes = await rootBundle.load(
        'assets/ETOPO_2022_v1_30s_N90W180_landmass_optimized_elevation.lerc2',
      );
      
      final elevationData = await LercDecoder.decode(
        elevationBytes.buffer.asUint8List(),
      );
      
      setState(() {
        _elevationData = elevationData;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading terrain data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terrain Visualization'),
        actions: [
          PopupMenuButton<TerrainColorMode>(
            onSelected: (TerrainColorMode mode) {
              LercTileProvider.setColorMode(mode);
              setState(() {});
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: TerrainColorMode.gradient,
                child: Text('Gradient Mode'),
              ),
              const PopupMenuItem(
                value: TerrainColorMode.discrete,
                child: Text('Discrete Mode'),
              ),
            ],
          )
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildAltitudeControls(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage.isNotEmpty) {
      return Center(child: Text(_errorMessage));
    }
    
    if (_elevationData == null) {
      return const Center(child: Text('No terrain data available'));
    }
    
    return FlutterMap(
      options: MapOptions(
        center: LatLng(0, 0),
        zoom: 2,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        _buildTerrainLayer(),
      ],
    );
  }

  Widget _buildTerrainLayer() {
    if (_elevationData == null) return const SizedBox();
    
    return ValueListenableBuilder<double>(
      valueListenable: _referenceAltitude,
      builder: (context, altitude, child) {
        return TileLayer(
          tileProvider: LercTileProvider(
            data: _elevationData!,
            referenceAltitude: altitude,
            warningAltitude: 15000,
            minElevation: _elevationData!.minValue,
            terrainResolution: _terrainResolution.value,
            onElevationRead: (elevation) {
              // Handle elevation data for UI if needed
            },
          ),
          tileDisplay: const TileDisplay.instantaneous(),
        );
      },
    );
  }

  Widget _buildAltitudeControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Reference Altitude: ${_referenceAltitude.value.toStringAsFixed(0)} meters'),
          Slider(
            value: _referenceAltitude.value,
            min: -1000,
            max: 10000,
            onChanged: (value) {
              _referenceAltitude.value = value;
            },
          ),
          Text('Terrain Resolution: ${_terrainResolution.value.toStringAsFixed(1)}x'),
          Slider(
            value: _terrainResolution.value,
            min: 0.5,
            max: 2.0,
            onChanged: (value) {
              _terrainResolution.value = value;
            },
          ),
        ],
      ),
    );
  }
}
```

## Troubleshooting Common Issues

**Documentation References:**
- [Platform Specific Implementation](platform_specific_implementation.md) - Platform-specific details
- [Memory Management](memory_management.md) - Handling native memory
- [Performance Optimization Techniques](performance_optimization_techniques.md) - Performance improvements
- [Altitude-Based Terrain Coloring](altitude_based_terrain_coloring.md) - Coloring issues
- [Flutter Map Terrain Layer](flutter_map_terrain_layer.md) - Map integration

### Native Library Loading

1. **Android Library Path Issues**:
   - Check that the `liblerc_wrapper.so` is correctly placed in `android/app/src/main/jniLibs/[ABI]/`
   - Verify that CMake is properly configured in Gradle
   - Reference [Platform Specific Implementation](platform_specific_implementation.md) for Android details

2. **iOS Library Issues**:
   - Ensure the framework is properly embedded in the app
   - Check that the proper architectures are compiled (arm64 for device, x86_64 for simulator)
   - Verify code signing settings
   - See [Platform Specific Implementation](platform_specific_implementation.md) for iOS-specific details

### Memory Management

1. **Native Memory Leaks**:
   - Ensure all allocated memory is freed with appropriate `free` functions
   - Test with large datasets to verify memory handling
   - Use platform-specific tools to detect leaks
   - Follow [Memory Management](memory_management.md) for best practices

2. **Performance Issues**:
   - Use isolates for background processing
   - Implement caching for decoded data and rendered tiles
   - Optimize tile size and resolution for smooth performance
   - Reference [Performance Optimization Techniques](performance_optimization_techniques.md) and [Multithreaded Decoding](multithreaded_decoding.md)

### Rendering Problems

1. **Color Mapping Issues**:
   - Verify altitude bucketing and color gradients
   - Adjust the reference altitude logic
   - Test with various elevation ranges
   - See [Altitude-Based Terrain Coloring](altitude_based_terrain_coloring.md) and [Altitude Bucketing](altitude_bucketing.md)

2. **Misaligned Terrain**:
   - Check coordinate conversion logic
   - Verify the mapping of LERC data to map tiles
   - Test with known reference points
   - Reference [Flutter Map Terrain Layer](flutter_map_terrain_layer.md) and [Flutter Map Tile Provider](flutter_map_tile_provider.md)

## Next Steps for Advanced Features

**Documentation References:**
- [Hillshading Support](hillshading_support.md) - Detailed hillshade implementation
- [LERC Data Caching](lerc_data_caching.md) - Advanced caching strategies
- [Throttling and Debouncing](throttling_and_debouncing.md) - Performance improvements
- [Enhanced Visualization UI Controls](enhanced_visualization_ui_controls.md) - Advanced UI
- [Multiple Terrain Rendering Modes](multiple_terrain_rendering_modes.md) - Different rendering options
- [Custom Terrain Data Sources](custom_terrain_data_sources.md) - Using different data sources

1. **Add Hillshade Integration**:
   - Load and decode hillshade LERC data
   - Integrate hillshade rendering with elevation coloring
   - Add controls to adjust hillshade intensity
   - Reference [Hillshading Support](hillshading_support.md) for detailed implementation

2. **Implement Data Caching**:
   - Create persistent cache for decoded LERC data
   - Implement tile caching to avoid redundant calculations
   - Follow [LERC Data Caching](lerc_data_caching.md) for implementation details
   - See [Offline Terrain Data](offline_terrain_data.md) for persistent storage strategies

3. **Add Performance Optimizations**:
   - Implement throttling for map interactions
   - Add level of detail based on zoom level
   - Optimize memory usage for large datasets
   - Use [Throttling and Debouncing](throttling_and_debouncing.md) and [Performance Optimization Techniques](performance_optimization_techniques.md)

4. **Enhance User Controls**:
   - Add UI for switching between rendering modes
   - Implement color customization
   - Add options for data overlays
   - Reference [Enhanced Visualization UI Controls](enhanced_visualization_ui_controls.md) and [Multiple Terrain Rendering Modes](multiple_terrain_rendering_modes.md)

## Implementation Process Overview

To successfully implement the LERC terrain visualization in your Flutter project, follow this recommended sequence:

1. **Start with understanding project structure** - See [Project Structure](project_structure.md)
2. **Set up the native LERC library** - Reference [LERC Integration](lerc_integration.md) and [LERC Source Directory](lerc_source_directory.md)
3. **Implement the C++ wrapper** - Use [C++ Wrapper Implementation](cpp_wrapper_implementation.md)
4. **Configure build system** - Follow [CMake Configuration](cmake_configuration.md)
5. **Create platform-specific code** - See [Platform Specific Implementation](platform_specific_implementation.md)
6. **Build Dart FFI bindings** - Reference [Dart FFI Bindings](dart_ffi_bindings.md) and [Dart FFI Integration](dart_ffi_integration.md)
7. **Create the core decoder** - Follow [Basic LERC Decoding](basic_lerc_decoding.md) and [Raw Elevation Data Processing](raw_elevation_data_processing.md)
8. **Implement visualization** - Use [Terrain Visualization Techniques](terrain_visualization_techniques.md) and [Flutter Map Terrain Layer](flutter_map_terrain_layer.md)
9. **Add advanced features** - Reference specific advanced feature documentation as needed

## Conclusion

This guide provides a comprehensive approach to implementing LERC-based terrain visualization in Flutter by referencing the available documentation files throughout the implementation process. By following these steps and consulting the referenced documentation for detailed implementation information, you can effectively integrate native LERC decoding with Flutter's rendering capabilities to create performant, cross-platform terrain visualization applications.
