# LERC (Limited Error Raster Compression) Library Integration

This document provides a detailed overview of how the Esri LERC library is integrated into the FlightCanvas Terrain plugin.

## Overview of LERC

LERC (Limited Error Raster Compression) is a powerful and fast image format for storing and transmitting raster data. It was developed by Esri and is optimized for geospatial data such as elevation models. The key features of LERC include:

- Lossy compression with user-controlled maximum error per pixel
- Very fast encoding and decoding
- Support for masks (nodata values)
- Support for different data types (int, float, double)
- Compact file sizes with excellent compression ratios

## LERC Library Structure

The LERC library is included as source code in the project under the `lerc-master` directory. The library follows this structure:

```
lerc-master/
├── CMakeLists.txt              # LERC's CMake configuration
├── src/
│   └── LercLib/                # Core LERC implementation
│       ├── include/            # Public API headers
│       │   ├── Lerc_c_api.h    # C API for LERC
│       │   └── Lerc_types.h    # Type definitions
│       ├── Lerc1Decode/        # LERC version 1 decoder
│       └── [Core LERC files]   # Implementation files
└── [Other LERC resources]
```

### Key LERC Components

1. **C API (`Lerc_c_api.h`)**
   - Provides C-compatible functions for encoding and decoding LERC data
   - Used by the wrapper to interact with the library

2. **Core Implementation Files**
   - `Lerc.cpp` and `Lerc2.cpp`: Main implementation for different LERC versions
   - `BitMask.cpp`: Handling of nodata masks
   - `BitStuffer2.cpp`: Bit-level compression algorithms
   - `Huffman.cpp`: Huffman coding implementation
   - `RLE.cpp`: Run-length encoding implementation
   - `fpl_*.cpp`: Additional compression and processing algorithms

## Integration with Flutter Plugin

### 1. CMake Integration

The LERC library is built as a static library and linked to the plugin's shared library through CMake. The main `CMakeLists.txt` file in the project root configures both libraries:

```cmake
# Create LERC library as a static library
add_library(lerc STATIC ${LERC_SOURCES})
target_include_directories(lerc PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
)

# Create the wrapper library that links to LERC
add_library(lerc_wrapper SHARED "src/lerc_wrapper.cpp")
target_link_libraries(lerc_wrapper PRIVATE lerc)
```

Instead of using LERC's own CMake configuration, the project directly compiles the necessary LERC source files. This approach:
- Simplifies cross-platform builds for mobile platforms
- Allows fine-grained control over compilation settings
- Avoids issues with CMake version incompatibilities

### 2. C++ Wrapper Implementation

A custom C++ wrapper (`lerc_wrapper.cpp` and `lerc_wrapper.h`) provides a simplified interface to the LERC library. This wrapper:

1. Exposes a C-compatible API for FFI use from Dart
2. Simplifies and standardizes the LERC API for the plugin's needs
3. Handles memory management and error handling

Key functions in the wrapper:

- `lerc_wrapper_initialize()`: Initialize the library
- `lerc_wrapper_get_info()`: Extract metadata from LERC data (dimensions, value range)
- `lerc_wrapper_decode()`: Decode LERC data into a double array
- Memory management functions for freeing allocated resources

The wrapper also defines a `LercInfo` struct that contains essential metadata about the LERC data:

```cpp
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t numBands;
    uint32_t numValidPixels;
    double minValue;
    double maxValue;
    double noDataValue;
} LercInfo;
```

### 3. Platform-Specific Integration

#### Android Integration

For Android, the native libraries are built using CMake integrated with the Android Gradle build system:

1. Android's `build.gradle.kts` configures CMake for native builds
2. CMake compiles the LERC library and wrapper as a shared library
3. The compiled libraries are placed in `android/app/src/main/jniLibs/[ABI]/liblerc_wrapper.so`
4. The Android plugin uses JNI to load and access the native library

#### iOS Integration

iOS integration is more complex due to Apple's platform constraints:

1. A custom build script (`compile_lerc_ios.sh`) compiles the LERC library for iOS architectures:
   - Compiles each LERC source file for arm64 (device) and x86_64 (simulator)
   - Creates a static library (`liblerc.a`) with all architectures

2. An Objective-C++ wrapper (`LercWrapper.mm`) provides the bridge between:
   - The C++ LERC library
   - The iOS plugin system
   - The Dart FFI interface

3. The compiled libraries are integrated via CocoaPods into the iOS build

## Data Flow from LERC to Dart

The process of decoding LERC data flows through several layers:

1. **Dart Layer**: `LercDecoder` class in `lib/src/lerc_decoder.dart`
   - Loads LERC data from assets or network
   - Uses FFI to call native functions
   - Executes decoding in a separate isolate for performance

2. **FFI Bindings**: Generated from `lerc_wrapper.h` using `ffigen`
   - Maps C functions and structures to Dart equivalents
   - Handles memory management between Dart and native code

3. **C++ Wrapper**: `lerc_wrapper.cpp`
   - Provides a simplified interface to the LERC library
   - Manages memory allocation and deallocation
   - Handles type conversion between LERC and the wrapper API

4. **LERC Library**: Native C++ code in `lerc-master`
   - Performs actual decompression of LERC data
   - Highly optimized C++ implementation

## Internal LERC Decoding Process

The LERC decoding process inside the native library involves these steps:

1. **Read LERC Header**: Extract information about data dimensions, type, and compression
2. **Parse Metadata**: Process LERC-specific metadata like masks and versions
3. **Decompress Blocks**: LERC stores data in blocks that are individually compressed
4. **Apply Masks**: Handle nodata/masked values if present
5. **Return Data**: Convert to the requested data type (float or double)

The decoding process uses several algorithms including:
- Bit unpacking for simple blocks
- Huffman decoding for entropy-coded blocks
- Run-length decoding for repeating values
- Special handling for constant blocks (blocks with the same value)

## Memory Management

Proper memory management is crucial when working with native code:

1. **Native Allocation**: 
   - C++ wrapper allocates memory for decoded data and metadata
   - Uses standard C++ `new` and `delete` operators

2. **Memory Transfer**: 
   - Pointers to allocated memory are passed to Dart via FFI
   - Dart code accesses the memory directly via typed data views

3. **Cleanup**:
   - Explicit free functions (`lerc_wrapper_free_info`, `lerc_wrapper_free_data`)
   - Called from Dart via FFI to release native memory
   - Also handled in isolate error handling paths to prevent leaks

## Performance Considerations

Several techniques are employed to optimize performance:

1. **Isolate-based Processing**:
   - Decoding happens in a separate Dart isolate to avoid blocking the UI thread
   - Results are communicated back to the main isolate via ports

2. **Direct Memory Access**:
   - Data is decoded directly to native memory and accessed via Dart typed data
   - Minimizes copying of large data arrays

3. **Optimized Decoding**:
   - LERC itself is highly optimized for fast decoding
   - The wrapper minimizes additional overhead

## Testing and Debugging

Testing the LERC integration involves:

1. **Test Data**: Sample LERC files in the `assets/` directory
2. **Native Debugging**: Platform-specific native debuggers (Android Studio, Xcode)
3. **Dart Integration Tests**: Tests for the Dart FFI bindings and decoder

## Conclusion

The LERC library integration in the FlightCanvas Terrain plugin demonstrates how to effectively bridge native C++ libraries with Flutter applications through FFI. The approach balances performance, cross-platform compatibility, and developer experience to deliver high-performance terrain visualization capabilities.