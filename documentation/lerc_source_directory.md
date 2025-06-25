# LERC Source Directory Usage

This document details how the LERC (Limited Error Raster Compression) source code, located in the `lerc-master` directory, is integrated and used in the FlightCanvas Terrain plugin.

## Source Directory Overview

The `lerc-master` directory contains the original Esri LERC library source code. This directory is structured as follows:

```
lerc-master/
├── CHANGELOG.md              # Version history and changes
├── CMakeLists.txt            # Original CMake configuration (not directly used)
├── LICENSE                   # License information
├── README.md                 # General information about LERC
├── src/
│   └── LercLib/              # Core implementation files
│       ├── include/          # Public API headers
│       │   ├── Lerc_c_api.h  # C-compatible API
│       │   └── Lerc_types.h  # Type definitions
│       ├── Lerc1Decode/      # LERC v1 decoding implementation
│       │   ├── BitStuffer.cpp
│       │   ├── BitStuffer.h
│       │   ├── CntZImage.cpp
│       │   └── CntZImage.h
│       ├── Lerc.cpp          # Main LERC implementation
│       ├── Lerc.h
│       ├── Lerc2.cpp         # LERC v2 implementation
│       ├── Lerc2.h
│       ├── Lerc_c_api_impl.cpp # Implementation of the C API
│       ├── BitMask.cpp       # Various utility classes
│       ├── BitMask.h
│       ├── BitStuffer2.cpp
│       ├── BitStuffer2.h
│       ├── Huffman.cpp
│       ├── Huffman.h
│       ├── RLE.cpp
│       ├── RLE.h
│       └── [additional utility files]
└── [other directories and files]
```

## Integration with the FlightCanvas Terrain Plugin

### 1. Source Files Selection

Instead of using the original CMakeLists.txt file from the LERC library, the FlightCanvas Terrain plugin explicitly lists the required LERC source files in its own CMakeLists.txt:

```cmake
# Add LERC source files
set(LERC_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc2.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc_c_api_impl.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/BitMask.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/BitStuffer2.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Huffman.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/RLE.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/fpl_Compression.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/fpl_EsriHuffman.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/fpl_Lerc2Ext.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/fpl_Predictor.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/fpl_UnitTypes.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode/BitStuffer.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode/CntZImage.cpp"
)
```

This approach allows the plugin to:
1. Select only the necessary source files
2. Maintain control over the build process
3. Easily update or modify the LERC implementation if needed

### 2. Android Integration

For Android, the LERC source files are directly referenced in the CMakeLists.txt file and compiled during the native build process. The Android Gradle build system triggers this compilation:

1. The `externalNativeBuild` block in `android/build.gradle.kts` points to the project's root CMakeLists.txt:
   ```kotlin
   externalNativeBuild {
       cmake {
           path = file("../CMakeLists.txt")
       }
   }
   ```

2. During the Android build, the CMake system compiles the LERC source files into a static library that is then linked with the wrapper library.

3. The resulting shared library (`liblerc_wrapper.so`) is packaged in the Android app under the `jniLibs` directory for each supported architecture (arm64-v8a, armeabi-v7a, x86, x86_64).

### 3. iOS Integration

For iOS, the integration is more complex and involves custom compilation scripts:

1. **Custom Build Script**: The `ios/compile_lerc_ios.sh` script handles compiling the LERC library for iOS:

   ```bash
   # Collect LERC source files from lerc-master directory
   LERC_SOURCES=()
   LERC_SOURCES+=("${LERC_SRC}/LercLib/Lerc.cpp")
   LERC_SOURCES+=("${LERC_SRC}/LercLib/Lerc2.cpp")
   # ... other source files ...

   # Compile library for each architecture
   for ARCH in $ARCHS; do
     # ... compilation commands using the collected source files ...
   done

   # Create fat library
   xcrun -sdk iphoneos lipo -create $(find ${BUILD_DIR} -name "liblerc.a") -output "Libraries/liblerc.a"
   ```

2. **Static Library Creation**: The script compiles the LERC source files directly into a static library (`liblerc.a`) that is then used by the iOS plugin.

3. **Integration with Objective-C++**: The `ios/Classes/LercWrapper.mm` file includes headers from the LERC source directory:
   ```objectivec++
   #import "../../lerc-master/src/LercLib/include/Lerc_c_api.h"
   ```
   This allows the iOS wrapper to call functions from the LERC C API.

### 4. Header Files Usage

The plugin primarily interacts with the LERC library through its C API (`Lerc_c_api.h`). This header file provides C-compatible functions that are easier to use with FFI:

```cpp
// In lerc_wrapper.cpp
#include "Lerc_c_api.h"

// ...
lerc_status status = lerc_getBlobInfo(
    buffer,
    static_cast<unsigned int>(size),
    infoArray,
    dataRangeArray,
    10,
    3
);
```

The key headers from the LERC library used by the plugin include:
- `Lerc_c_api.h`: Provides the C-compatible API functions
- `Lerc_types.h`: Defines types and structures used by the C API

### 5. Integration with Custom Wrapper

The plugin doesn't use the LERC library directly from Dart. Instead, it creates a custom C++ wrapper (`src/lerc_wrapper.cpp`) that interfaces with the LERC C API:

```cpp
// Call the LERC C API function for decoding
lerc_status status = lerc_decode(
    buffer,
    static_cast<unsigned int>(size),
    0,
    nullptr,
    1,
    info->width,
    info->height,
    1,
    6,  // data type = float
    floatData
);
```

This wrapper simplifies the API and provides additional functionality specific to the Flutter plugin's needs.

## Version Management

The LERC library included in the project is version 4.0.0, as specified in `lerc-master/src/LercLib/include/Lerc_c_api.h`:

```c
#define LERC_VERSION_MAJOR 4
#define LERC_VERSION_MINOR 0
#define LERC_VERSION_PATCH 0
```

This version supports LERC format versions 1 and 2, with various compression algorithms optimized for raster data.

## Source Code Modifications

The LERC source code is used without modifications in the FlightCanvas Terrain plugin. Instead of altering the source code, the plugin:

1. Selectively includes only the necessary files
2. Provides a custom wrapper to adapt the API for the plugin's needs
3. Uses custom build scripts to integrate the code into the mobile platforms

This approach maintains compatibility with the original LERC library while allowing for tailored integration into the Flutter plugin environment.

## Conclusion

The `lerc-master` directory serves as the source for the LERC compression/decompression functionality in the FlightCanvas Terrain plugin. Rather than using it as a precompiled library or submodule, the plugin directly incorporates the source files into its own build process. This approach provides maximum control over the integration while ensuring that the full capabilities of the LERC library are available to the plugin.

The integration is carefully managed through custom CMake configurations and build scripts, resulting in platform-specific native libraries that are then accessed from Dart via FFI. This strategy effectively bridges the gap between the high-performance C++ LERC implementation and the Flutter application, enabling efficient terrain data visualization on mobile devices.
