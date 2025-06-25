# FlightCanvas Terrain Plugin: Project Structure Documentation

This document provides an overview of the FlightCanvas Terrain plugin's project structure, focusing on how native code is integrated with the Flutter application.

## Overview

FlightCanvas Terrain is a Flutter plugin for efficiently rendering terrain elevation data using the Limited Error Raster Compression (LERC) format. It integrates native C++ code (primarily the LERC library) with Flutter through FFI (Foreign Function Interface) to provide high-performance terrain visualization capabilities on both Android and iOS platforms.

## Directory Structure

The project follows a standard Flutter plugin structure with additional components for native code integration:

```
flightcanvas_terrain/
├── android/                  # Android platform-specific code
│   ├── app/                  # Android app implementation
│   └── build.gradle.kts      # Android build configuration
├── assets/                   # Terrain data files (.lerc2)
├── build/                    # Build artifacts (generated)
├── ios/                      # iOS platform-specific code
│   ├── Classes/              # Objective-C++ wrapper implementation
│   │   ├── LercWrapper.h     # iOS wrapper header
│   │   ├── LercWrapper.mm    # iOS wrapper implementation
│   │   └── ...
│   ├── compile_lerc_ios.sh   # iOS native library build script
│   ├── Libraries/            # Compiled libraries for iOS
│   └── ...
├── lerc-master/              # LERC library source code
│   ├── src/                  # LERC source files
│   └── ...
├── lib/                      # Dart/Flutter code
│   ├── main.dart             # Main application entry point
│   ├── lerc_decoder.dart     # API export file
│   └── src/
│       ├── lerc_decoder.dart # Core Dart implementation
│       ├── bindings/         # FFI bindings
│       └── ...
├── src/                      # Native C++ wrapper code
│   ├── lerc_wrapper.cpp      # C++ implementation
│   └── lerc_wrapper.h        # C++ header with FFI-compatible interface
├── CMakeLists.txt            # CMake build configuration for native code
├── pubspec.yaml              # Flutter project configuration
└── ffigen.yaml               # FFI bindings generation configuration
```

## Key Components

### 1. Native Code Implementation

#### LERC Library
- Located in `lerc-master/` directory
- Contains the core LERC compression/decompression algorithms in C++
- Provides functions for working with compressed raster data

#### C++ Wrapper
- Located in `src/lerc_wrapper.cpp` and `src/lerc_wrapper.h`
- Provides a C-compatible interface to the LERC library functions
- Defines structures (`LercInfo`) and functions for FFI interoperability
- Key functions include:
  - `lerc_wrapper_initialize()`
  - `lerc_wrapper_get_info()`
  - `lerc_wrapper_decode()`
  - Memory management functions

#### Platform-specific Integration

**iOS:**
- Objective-C++ wrapper in `ios/Classes/LercWrapper.mm`
- Uses a custom build script (`compile_lerc_ios.sh`) to compile the LERC library for iOS
- Outputs a static library (`Libraries/liblerc.a`) and framework

**Android:**
- Integration through CMake and Gradle
- Native library (`liblerc_wrapper.so`) is compiled and packaged in the APK
- Output directory: `android/app/src/main/jniLibs/`

### 2. Build System

#### CMake Configuration
- `CMakeLists.txt` defines how to build the native libraries
- Configures the LERC library as a static library (`lerc`)
- Creates the wrapper as a shared library (`lerc_wrapper`)
- Sets platform-specific options for Android and iOS output

#### iOS Build Process
- Uses custom scripts to compile for iOS architectures (arm64, x86_64)
- Outputs a static library for integration into iOS framework

#### Android Build Process
- Uses CMake integrated with Gradle
- Outputs shared libraries for different Android ABIs

### 3. Dart/Flutter Integration

#### FFI Bindings
- Generated using `ffigen` package (configuration in `ffigen.yaml`)
- Output file: `lib/src/bindings/lerc_bindings.dart`
- Provides Dart types that map to C types and functions

#### Core Implementation
- `lib/src/lerc_decoder.dart` provides the Dart API for LERC decoding
- Uses FFI to call native functions
- Implements isolate-based multi-threading for performance
- Provides data structures for working with decoded elevation data

#### Flutter UI Components
- Custom Flutter map layers for rendering terrain
- Implementation of terrain visualization with various settings
- Optimizations for performance (throttling, caching, etc.)

## Data Flow

1. LERC compressed data is loaded from assets or network
2. Data is passed to the native decoder via FFI
3. The native C++ code uses the LERC library to decode the data
4. Decoded elevation data is returned to Dart/Flutter
5. The Flutter application renders the terrain using the elevation data

## Dependencies

- `flutter_map`: Base mapping library
- `latlong2`: Geographical coordinate handling
- `ffi`: Dart bindings to native code
- `ffigen`: Tool for generating FFI bindings
- The Esri LERC library (included in source)

## Build and Compilation

The project uses a combination of tools for compiling the native code:

1. CMake for overall native code compilation
2. Platform-specific tools:
   - Android: Gradle + CMake + NDK
   - iOS: Custom scripts + Xcode build tools
3. The FFI bindings are generated during development using the `ffigen` tool

## Asset Management

The application includes terrain data files in the `assets/` directory:
- Elevation data: ETOPO_2022_v1_30s_N90W180_landmass_optimized_elevation.lerc2
- Hillshade data: ETOPO_2022_v1_30s_N90W180_landmass_optimized_hillshade.lerc2
