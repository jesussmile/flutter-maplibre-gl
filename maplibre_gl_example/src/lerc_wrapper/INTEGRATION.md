# LERC Terrain Integration Documentation

## Overview

This document outlines the integration of LERC (Limited Error Raster Compression) terrain visualization into the MapLibre GL Flutter example project. The implementation leverages existing LERC native code from the flightcanvas_terrain directory and the lerc-master source code to visualize terrain data on MapLibre maps.

## Implementation Details

### Directory Structure

The LERC integration is organized as follows:

```
maplibre_gl_example/
├── src/
│   └── lerc_wrapper/
│       ├── lerc_wrapper.h         # C API header for LERC wrapper
│       ├── lerc_wrapper.cpp       # C++ implementation of LERC wrapper
│       ├── include/               # Contains LERC C API headers
│       │   ├── Lerc_c_api.h
│       │   └── Lerc_types.h
│       └── CMakeLists.txt         # Build configuration for LERC wrapper
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── cpp/
│               │   ├── CMakeLists.txt      # Android CMake configuration
│               │   └── lerc_jni_bridge.cpp # JNI bridge for Android
│               └── java/
│                   └── org/
│                       └── maplibre/
│                           └── example/
│                               └── terrain/
│                                   ├── LercInfo.java           # LERC info Java class
│                                   ├── LercNativeLoader.java   # Native loader Java class
│                                   └── LercDecoderPlugin.java  # Flutter plugin bridge
└── ios/
    ├── LercWrapper/
    │   └── LercWrapper.podspec    # iOS pod specification
    └── Runner/
        └── lerc_wrapper/
            ├── LercDecoder.h      # Objective-C header
            ├── LercDecoder.m      # Objective-C implementation
            ├── LercDecoderPlugin.h # Flutter plugin header
            └── LercDecoderPlugin.m # Flutter plugin implementation

```

### Android Integration

1. **CMake Configuration**:
   - Created main CMakeLists.txt in android/app/src/main/cpp/ that includes the LERC wrapper library
   - Added JNI bridge (lerc_jni_bridge.cpp) for communication between Java and C++

2. **Java Classes**:
   - LercInfo: Java class representing LERC metadata
   - LercNativeLoader: JNI wrapper for native LERC functions
   - LercDecoderPlugin: Flutter method channel bridge for Dart

3. **Build.gradle Updates**:
   - Added externalNativeBuild configuration to include CMake
   - Set up proper C++ standard (C++14) and STL version

### iOS Integration

1. **Pod Configuration**:
   - Created LercWrapper.podspec to build the native LERC library
   - Set header search paths and compiler flags

2. **Objective-C Classes**:
   - LercDecoder: Objective-C wrapper around the LERC C API
   - LercDecoderPlugin: Flutter method channel bridge for Dart

3. **AppDelegate Updates**:
   - Added registration for the LERC plugin
   - Updated bridging header to expose Objective-C classes to Swift

### LERC Wrapper Adaptation

1. **Header Paths**:
   - Updated include paths in lerc_wrapper.cpp to use correct relative paths

2. **API Design**:
   - Maintained a clean C API for compatibility with Dart FFI
   - Functions include:
     - lerc_wrapper_initialize()
     - lerc_wrapper_get_info()
     - lerc_wrapper_decode()
     - lerc_wrapper_free_info()
     - lerc_wrapper_free_data()

## Next Steps

1. Generate Dart FFI bindings for the LERC wrapper
2. Create Dart classes to manage the decoded terrain data
3. Implement terrain visualization using MapLibre GL
4. Add UI controls for adjusting terrain visualization parameters

## Challenges and Solutions

1. **Challenge**: Ensure proper paths for LERC includes in different build environments.
   **Solution**: Used relative paths and proper CMake directory variables.

2. **Challenge**: Memory management across language boundaries.
   **Solution**: Implemented explicit free functions in the C API, with corresponding cleanup in Java/Objective-C.

3. **Challenge**: Making the native code accessible from Flutter.
   **Solution**: Created platform-specific plugins with method channel interfaces.
