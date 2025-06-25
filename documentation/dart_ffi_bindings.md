# Dart FFI Bindings Generation with ffigen

This document details the setup and usage of the `ffigen` package to automatically generate Dart FFI (Foreign Function Interface) bindings from C header files in the FlightCanvas Terrain plugin.

## Overview

Foreign Function Interface (FFI) allows Dart code to call functions in native libraries directly. To avoid writing FFI bindings manually, the plugin uses `ffigen`, a binding generator that creates Dart FFI code from C header files.

The FFI bindings connect the high-level Dart code with the low-level C++ LERC wrapper, allowing Flutter to access the native terrain decoding functionality efficiently.

## Setup and Configuration

### 1. Development Dependencies

The `ffigen` package is added as a development dependency in `pubspec.yaml`:

```yaml
dev_dependencies:
  ffigen: ^18.0.0
```

### 2. ffigen Configuration

The configuration for generating bindings can be specified in two ways:

#### Option 1: Within `pubspec.yaml`

```yaml
# Add ffigen configuration
ffigen:
  name: LercBindings
  description: Bindings for LERC decoder
  output: 'lib/src/bindings/lerc_bindings.dart'
  headers:
    entry-points:
      - 'src/lerc_wrapper.h'
    include-directives:
      - 'src/lerc_wrapper.h'
  compiler-opts:
    - '-I.'
    - '-Ilerc-master/src'
    - '-x'
    - 'c'
    - '-DLERC_STATIC'
```

#### Option 2: Separate `ffigen.yaml` File

For more complex configurations, a separate YAML file is used:

```yaml
name: LercBindings
description: Bindings for LERC decoder
output: 'lib/src/bindings/lerc_bindings.dart'
headers:
  entry-points:
    - 'src/lerc_wrapper.h'
  include-directives:
    - 'src/lerc_wrapper.h'
compiler-opts:
  - '-I.'
  - '-Ilerc-master/src'
  # macOS-specific includes for development
  - '-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include'
  # iOS-specific includes for development
  - '-I/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/include'
  - '-x'
  - 'c'
  - '-DLERC_STATIC'
preamble: |
  // ignore_for_file: unused_element, unused_field, camel_case_types, non_constant_identifier_names, unused_import
comments:
  style: any
  length: full
structs:
  include:
    - 'LercInfo'
functions:
  include:
    - 'lerc_.*'
```

### 3. Header File for Bindings

Bindings are generated from `src/lerc_wrapper.h`, which defines:

```cpp
// C-compatible header with extern "C" for cross-language compatibility
#ifdef __cplusplus
extern "C" {
#endif

// Structure to hold LERC data information
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t numBands;
    uint32_t numValidPixels;
    double minValue;
    double maxValue;
    double noDataValue;
} LercInfo;

// Function declarations with C-compatible types
bool lerc_wrapper_initialize(void);
LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size);
double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info);
void lerc_wrapper_free_info(LercInfo* info);
void lerc_wrapper_free_data(double* data);

#ifdef __cplusplus
}
#endif
```

## Generating Bindings

### Command Line Generation

To generate the bindings, run:

```bash
flutter pub run ffigen --config ffigen.yaml
```

If the configuration is in `pubspec.yaml`, simply run:

```bash
flutter pub run ffigen
```

### Build Integration

The bindings generation can be integrated into the build process:

- For development, it's typically run manually when the C API changes
- For CI/CD, it can be added as a pre-build step

## Generated Bindings

The generated `lib/src/bindings/lerc_bindings.dart` file includes:

```dart
// Auto-generated file with class that wraps the native library
class LercBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  LercBindings(ffi.DynamicLibrary dynamicLibrary) : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  LercBindings.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup)
      : _lookup = lookup;
      
  // Generated function bindings with proper type mappings
  bool lerc_wrapper_initialize() {
    return _lerc_wrapper_initialize();
  }

  late final _lerc_wrapper_initializePtr =
      _lookup<ffi.NativeFunction<ffi.Bool Function()>>('lerc_wrapper_initialize');
  late final _lerc_wrapper_initialize =
      _lerc_wrapper_initializePtr.asFunction<bool Function()>();
      
  // Additional functions and struct definitions
  // ...
}

// Generated struct class that maps to the C struct
class LercInfo extends ffi.Struct {
  @ffi.Uint32()
  external int width;

  @ffi.Uint32()
  external int height;
  
  // Additional fields
  // ...
}
```

## Using the Generated Bindings

The bindings are used in `lib/src/lerc_decoder.dart`:

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'bindings/lerc_bindings.dart';

class LercDecoder {
  // Load the appropriate native library based on platform
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('liblerc_wrapper.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
  
  // Create bindings instance
  static final _bindings = LercBindings(_loadLibrary());
  
  // Use the FFI bindings to call native functions
  static Future<DecodedLercData> decode(Uint8List bytes) async {
    // Implementation using FFI bindings
    // ...
  }
}
```

### Memory Management with FFI

The generated bindings require careful memory management:

1. **Allocation**: Native memory is allocated by C functions like `lerc_wrapper_decode`
2. **Access**: Dart accesses this memory via pointers and views
3. **Deallocation**: Native memory must be explicitly freed using functions like `lerc_wrapper_free_data`

Example memory management pattern:

```dart
// Allocate native memory for the bytes
final Pointer<Uint8> buffer = malloc<Uint8>(bytes.length);
// Copy Dart bytes to native memory
final pointerList = buffer.asTypedList(bytes.length);
pointerList.setAll(0, bytes);

try {
  // Use the native buffer
  final result = _bindings.lerc_wrapper_decode(buffer, bytes.length, infoPtr);
  // Process result...
} finally {
  // Free the allocated memory
  malloc.free(buffer);
  _bindings.lerc_wrapper_free_data(dataPtr);
}
```

## Handling Platform Differences

The FFI bindings handle platform differences in several ways:

1. **Library Loading**: Different methods for loading the native library per platform:
   - Android: `DynamicLibrary.open("liblerc_wrapper.so")`
   - iOS: `DynamicLibrary.process()`

2. **Compiler Options**: Platform-specific include paths are specified in `ffigen.yaml`:
   ```yaml
   compiler-opts:
     # macOS-specific includes for development
     - '-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include'
     # iOS-specific includes for development
     - '-I/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/include'
   ```

## Testing the FFI Bindings

Testing the FFI bindings involves:

1. **Unit Tests**: Test that the bindings can be loaded and functions can be called
2. **Integration Tests**: Test the complete flow from Dart, through FFI, to native code and back
3. **Error Handling Tests**: Verify proper error handling for invalid inputs or memory issues

## Updating Bindings

When the native API (`lerc_wrapper.h`) changes:

1. Update the header file with new functions or structures
2. Re-run the ffigen command to regenerate bindings
3. Update Dart code that uses the bindings to handle any API changes

## Troubleshooting Common Issues

### 1. Symbol Not Found Errors

If running the app results in "Symbol not found" errors:

- Verify that the native library is correctly built and packaged
- Check that function names in the header match the actual implementation
- Ensure the library loading method matches the platform requirements

### 2. Type Conversion Issues

For incorrect behavior due to type mismatches:

- Check that C types are correctly mapped to Dart types
- Pay special attention to pointer types and memory layouts
- Consider explicit annotations in the header or ffigen config

### 3. Memory Leaks

If the application uses increasing memory over time:

- Ensure all allocated native memory is freed
- Use try/finally blocks to guarantee cleanup
- Consider using allocation tracking tools during development

## Conclusion

The `ffigen` package significantly simplifies the process of creating Dart FFI bindings for the native LERC library. It eliminates the need for manual binding creation, reduces potential errors, and makes it easier to update bindings as the native API evolves.

By generating type-safe bindings automatically from C header files, the FlightCanvas Terrain plugin achieves efficient and reliable communication between Dart and the native LERC decoding functionality.
