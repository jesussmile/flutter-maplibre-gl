# CMake Configuration for FlightCanvas Terrain

This document details how CMake is configured to build the native components of the FlightCanvas Terrain plugin, with a focus on cross-platform compatibility for iOS and Android.

## Overview

The FlightCanvas Terrain plugin uses CMake to build native C++ code, specifically the LERC library and its wrapper. CMake provides a platform-independent way to describe the build process, which is then translated to platform-specific build systems (e.g., Makefiles for Android, Xcode projects for iOS).

## Main CMakeLists.txt

The main CMakeLists.txt file at the project root defines:
1. How to build the LERC library as a static library
2. How to build the wrapper library as a shared library
3. Platform-specific configurations for Android and iOS

```cmake
cmake_minimum_required(VERSION 3.10)
project(lerc_decoder)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add LERC source files
set(LERC_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc2.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc_c_api_impl.cpp"
    # ... other LERC source files ...
)

# Create LERC library
add_library(lerc STATIC ${LERC_SOURCES})
target_include_directories(lerc PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
)

# Create FFI wrapper library
add_library(lerc_wrapper SHARED "src/lerc_wrapper.cpp")
target_link_libraries(lerc_wrapper PRIVATE lerc)
target_include_directories(lerc_wrapper PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
)

# Platform-specific configurations
if(ANDROID)
    # Android configuration
    set_target_properties(lerc_wrapper PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/android/app/src/main/jniLibs/${ANDROID_ABI}"
        OUTPUT_NAME "lerc_wrapper"
        PREFIX "lib"
    )
elseif(IOS)
    # iOS configuration
    set_target_properties(lerc_wrapper PROPERTIES
        FRAMEWORK TRUE
        MACOSX_FRAMEWORK_IDENTIFIER com.example.lercwrapper
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/ios/Frameworks"
        OUTPUT_NAME "lerc_wrapper"
    )
    
    # iOS-specific compile flags
    target_compile_options(lerc_wrapper PRIVATE -fembed-bitcode)
    
    # Make it a universal binary
    set_target_properties(lerc_wrapper PROPERTIES
        XCODE_ATTRIBUTE_ARCHS "arm64"
        XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO
        XCODE_ATTRIBUTE_VALID_ARCHS "arm64"
    )
else()
    # Default configuration for other platforms
    message(WARNING "This project is primarily designed for Android and iOS. Other platforms may not work as expected.")
    set_target_properties(lerc_wrapper PROPERTIES OUTPUT_NAME "lerc_wrapper")
endif()
```

## Key Configuration Components

### 1. Project Settings

```cmake
cmake_minimum_required(VERSION 3.10)
project(lerc_decoder)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
```

These lines define:
- Minimum CMake version required (3.10)
- Project name (lerc_decoder)
- C++ standard to use (C++14)
- Enforcement of the specified C++ standard

### 2. LERC Library Configuration

```cmake
# Add LERC source files
set(LERC_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc.cpp"
    # ... other LERC source files ...
)

# Create LERC library
add_library(lerc STATIC ${LERC_SOURCES})
target_include_directories(lerc PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
)
```

This section:
- Lists all LERC source files that need to be compiled
- Creates a static library named `lerc`
- Sets up include directories for the library
- Uses absolute paths to ensure consistent builds across platforms

### 3. Wrapper Library Configuration

```cmake
# Create FFI wrapper library
add_library(lerc_wrapper SHARED "src/lerc_wrapper.cpp")
target_link_libraries(lerc_wrapper PRIVATE lerc)
target_include_directories(lerc_wrapper PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode"
)
```

This section:
- Creates a shared library named `lerc_wrapper`
- Links it against the static LERC library
- Sets up include directories for the wrapper
- Uses `PRIVATE` visibility for includes that are only needed during compilation

### 4. Platform-Specific Configurations

#### 4.1 Android Configuration

```cmake
if(ANDROID)
    set_target_properties(lerc_wrapper PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/android/app/src/main/jniLibs/${ANDROID_ABI}"
        OUTPUT_NAME "lerc_wrapper"
        PREFIX "lib"
    )
```

This section:
- Sets the output directory for the Android shared library based on the ABI
- The `${ANDROID_ABI}` variable is provided by the Android CMake toolchain
- Places the library in the standard location for Android JNI libraries
- Ensures the library has the standard "lib" prefix (e.g., `liblerc_wrapper.so`)

#### 4.2 iOS Configuration

```cmake
elseif(IOS)
    set_target_properties(lerc_wrapper PROPERTIES
        FRAMEWORK TRUE
        MACOSX_FRAMEWORK_IDENTIFIER com.example.lercwrapper
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/ios/Frameworks"
        OUTPUT_NAME "lerc_wrapper"
    )
    
    # iOS-specific compile flags
    target_compile_options(lerc_wrapper PRIVATE -fembed-bitcode)
    
    # Make it a universal binary
    set_target_properties(lerc_wrapper PROPERTIES
        XCODE_ATTRIBUTE_ARCHS "arm64"
        XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO
        XCODE_ATTRIBUTE_VALID_ARCHS "arm64"
    )
```

This section:
- Configures the library as an iOS framework
- Sets framework identifier and output location
- Adds bitcode embedding for App Store compliance
- Configures the library for arm64 architecture (iPhone/iPad devices)
- Disables "build for active architecture only" to ensure universal binary

## Integration with Platform Build Systems

### Android Integration

The Android build system integrates with CMake through the Gradle build system. The key configuration is in `android/build.gradle.kts`:

```kotlin
android {
    // ...
    externalNativeBuild {
        cmake {
            path = file("../CMakeLists.txt")
        }
    }
    defaultConfig {
        // ...
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared"
                )
            }
        }
    }
}
```

This configuration:
- Points Gradle to the CMake file in the project root
- Specifies which Android ABIs to build for
- Sets the C++ standard library to use (c++_shared)
- Passes additional arguments to CMake

### iOS Integration

For iOS, the integration is more complex:

1. **Custom Build Script**: The `ios/compile_lerc_ios.sh` script compiles the LERC library for iOS architectures.

2. **CocoaPods Integration**: The library is integrated via CocoaPods in `ios/FlightCanvasLercWrapper.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'FlightCanvasLercWrapper'
  s.version          = '0.1.0'
  s.summary          = 'LERC wrapper for FlightCanvas terrain rendering'
  # ...
  s.source_files     = 'Classes/**/*'
  s.vendored_libraries = 'Libraries/liblerc.a'
  # ...
end
```

3. **Framework Structure**: The compiled libraries are organized into an iOS framework structure.

## CMake Variables and Flags

Key variables and flags used in the CMake configuration:

| Variable/Flag | Purpose |
|---------------|---------|
| `CMAKE_CXX_STANDARD` | Sets the C++ standard (14) |
| `ANDROID_ABI` | Android architecture (arm64-v8a, etc.) |
| `LIBRARY_OUTPUT_DIRECTORY` | Where to place compiled libraries |
| `-fembed-bitcode` | Enable bitcode embedding for iOS |
| `XCODE_ATTRIBUTE_*` | Xcode-specific build settings |

## Build Process Flow

The build process follows these steps:

1. **CMake Generation**:
   - The platform build system (Gradle/Xcode) invokes CMake
   - CMake generates platform-specific build files

2. **Static Library Build**:
   - LERC source files are compiled into a static library
   - Compiler flags and include paths are applied

3. **Shared Library Build**:
   - The wrapper is compiled and linked against the static library
   - Platform-specific settings are applied

4. **Output Placement**:
   - Compiled libraries are placed in platform-specific locations
   - Android: `android/app/src/main/jniLibs/[ABI]/liblerc_wrapper.so`
   - iOS: `ios/Frameworks/lerc_wrapper.framework`

## Troubleshooting Common Issues

### 1. Architecture Mismatch

**Symptom**: The app crashes with "dlopen failed: cannot locate symbol" errors.

**Cause**: The library was built for a different CPU architecture than the device.

**Solution**: Ensure that the correct ABIs are specified in `android/build.gradle.kts` or the iOS architecture settings.

### 2. Symbol Not Found

**Symptom**: The app crashes with "symbol not found" errors.

**Cause**: The shared library is missing symbols or using incompatible C++ features.

**Solution**: Check the C++ standard library configuration and ensure all dependencies are correctly linked.

### 3. Library Not Found

**Symptom**: The app crashes with "library not found" errors.

**Cause**: The library is not in the expected location or has the wrong name.

**Solution**: Verify the output paths in CMake and ensure the library is correctly packaged in the app.

## Conclusion

The CMake configuration for FlightCanvas Terrain enables cross-platform native code integration with Flutter. It handles the complexities of building C++ code for different mobile platforms while maintaining a consistent build process. The configuration ensures that the LERC library and its wrapper are correctly built and made available to the Flutter application via FFI.