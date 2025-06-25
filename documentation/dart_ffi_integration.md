# Dart FFI Integration

This document explains how the FlightCanvas Terrain plugin integrates native C++ code with Flutter using Dart's Foreign Function Interface (FFI).

## Overview

Dart FFI (Foreign Function Interface) allows Dart code to call functions in native libraries written in languages like C or C++. In the FlightCanvas Terrain plugin, FFI is used to access the LERC decoder functionality implemented in native C++ code.

## FFI Components

The FFI integration consists of these key components:

1. **FFI Bindings**: Generated Dart code that maps to the C functions and structures
2. **Decoder Class**: Dart class that uses the bindings to provide a high-level API
3. **Isolate Processing**: Background processing to prevent UI blocking
4. **Memory Management**: Safe handling of native memory

## FFI Bindings Generation

The plugin uses the `ffigen` package to automatically generate Dart bindings from C header files. This process is configured in `ffigen.yaml`:

```yaml
# Configuration for FFI code generation
name: LercBindings
description: Bindings for LERC decoder
output: 'lib/src/bindings/lerc_bindings.dart'
headers:
  entry-points:
    - 'src/lerc_wrapper.h'
  include-directives:
    - 'src/lerc_wrapper.h'
```

This configuration:
- Sets the output class name to `LercBindings`
- Specifies the output file path
- Points to the C header file that defines the API
- Focuses only on the wrapper API, not the entire LERC library

The generated bindings look like this:

```dart
/// Bindings for LERC decoder
class LercBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  LercBindings(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  bool lerc_wrapper_initialize() {
    return _lerc_wrapper_initialize();
  }

  late final _lerc_wrapper_initializePtr =
      _lookup<ffi.NativeFunction<ffi.Bool Function()>>(
          'lerc_wrapper_initialize');
  late final _lerc_wrapper_initialize =
      _lerc_wrapper_initializePtr.asFunction<bool Function()>();

  // ... other functions ...
}

final class LercInfo extends ffi.Struct {
  @ffi.Uint32()
  external int width;

  @ffi.Uint32()
  external int height;

  // ... other fields ...
}
```

## Loading Native Libraries

The `LercDecoder` class handles loading the appropriate native library based on the platform:

```dart
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
}
```

Key points:
- Platform detection to determine the correct library path
- Different loading mechanisms for Android and iOS
  - Android: `DynamicLibrary.open()` to load a specific .so file
  - iOS: `DynamicLibrary.process()` to access symbols in the process
- Initialization of the LERC library through the bindings
- Error handling and retry logic

## Isolate-Based Processing

To prevent blocking the UI thread when decoding large terrain data, the plugin uses Dart isolates:

```dart
class _IsolateData {
  final Uint8List bytes;
  final SendPort sendPort;
  final String libraryPath;

  _IsolateData(this.bytes, this.sendPort, this.libraryPath);
}

static Future<DecodedLercData> decode(Uint8List bytes) async {
  if (!_initialized) {
    await initialize();
  }

  final receivePort = ReceivePort();
  // Determine library path...

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
    // Initialize, decode data, etc.
    
    // Create and return result
    isolateData.sendPort.send(_IsolateMessage.success(result));
  } catch (e) {
    isolateData.sendPort.send(_IsolateMessage.error(e.toString()));
  }
}
```

Key aspects:
- Data and context are passed to the isolate
- The isolate loads the native library independently
- Results are communicated back via send/receive ports
- Error handling with structured messages
- Proper cleanup of resources

## Native Memory Management

The plugin carefully manages native memory to prevent leaks:

```dart
// In the isolate function:
final bytes = isolateData.bytes;
final inputPtr = malloc<Uint8>(bytes.length);
final inputArray = inputPtr.asTypedList(bytes.length);
inputArray.setAll(0, bytes);

Pointer<LercInfo> infoPtr = nullptr;
Pointer<Double> dataPtr = nullptr;

try {
  infoPtr = bindings.lerc_wrapper_get_info(inputPtr.cast(), bytes.length);
  // ... use infoPtr ...
  
  dataPtr = bindings.lerc_wrapper_decode(
    inputPtr.cast(),
    bytes.length,
    infoPtr,
  );
  // ... use dataPtr ...
  
  // Create Dart data from native memory
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
```

Key memory management techniques:
- Using Dart's `malloc` for native memory allocation
- Creating typed views of native memory with `asTypedList`
- Copying data between Dart and native memory
- Explicitly freeing native resources with `malloc.free` and wrapper's free functions
- Using `try/finally` to ensure cleanup even on error paths

## Result Data Structure

The decoded data is returned in a structured Dart class:

```dart
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

  // Add method to get elevation at specific coordinates
  double getElevation(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.nan;
    return data[y * width + x];
  }

  // Add method to get a subregion of elevations
  Float64List getRegion(
    int startX,
    int startY,
    int regionWidth,
    int regionHeight,
  ) {
    // ... implementation ...
  }
}
```

This class:
- Stores the decoded elevation data as a flat `Float64List`
- Includes metadata about dimensions and value range
- Provides utility methods for accessing the data
- Offers region extraction for efficient rendering

## Handling Platform Differences

The plugin handles platform differences in several ways:

### 1. Library Loading

Android:
```dart
_dylib = DynamicLibrary.open('liblerc_wrapper.so');
```

iOS:
```dart
_dylib = DynamicLibrary.process();
```

### 2. Platform-Specific Initialization

```dart
if (Platform.isIOS && _useSimplePlugin) {
  try {
    final simplePluginInit = _dylib!
        .lookupFunction<Void Function(), void Function()>(
          'lerc_wrapper_plugin_init',
        );
    simplePluginInit();
  } catch (e) {
    // Fallback handling...
  }
}
```

### 3. Error Handling and Retries

```dart
int retries = 0;
bool initSuccess = false;

while (!initSuccess && retries < _maxInitRetries) {
  try {
    // Initialization code...
    initSuccess = true;
  } catch (e) {
    // Log and retry...
    await Future.delayed(Duration(milliseconds: 500));
    retries++;
  }
}
```

## Plugin Integration

The FFI functionality is integrated with the Flutter plugin system:

1. **pubspec.yaml Configuration**:
```yaml
flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true
      ios:
        ffiPlugin: true
```

2. **Platform-Specific Setup**:
   - Android: JNI libraries are included in APK
   - iOS: Frameworks are embedded in the application

3. **Flutter Asset Integration**:
```yaml
flutter:
  assets:
    - assets/ETOPO_2022_v1_30s_N90W180_landmass_optimized_elevation.lerc2
    - assets/ETOPO_2022_v1_30s_N90W180_landmass_optimized_hillshade.lerc2
```

## Performance Considerations

The FFI integration incorporates several performance optimizations:

1. **Isolate-based Processing**:
   - Prevents blocking the UI thread
   - Enables parallel decoding of multiple files

2. **Memory Efficiency**:
   - Direct access to native memory via typed views
   - Minimizes copying between Dart and native code

3. **Caching**:
   - Decoded data can be cached for reuse
   - Prevents redundant processing of the same files

4. **Error Resilience**:
   - Retry mechanisms for initialization
   - Graceful fallbacks for error conditions

## Testing and Debugging FFI

Testing and debugging FFI code requires special approaches:

1. **Crash Observation**:
   - Native crashes may not provide Dart stack traces
   - Platform-specific tools (Logcat, Console) help diagnose issues

2. **Memory Leak Detection**:
   - Tools like Valgrind (Android) or Instruments (iOS)
   - Explicit cleanup verification

3. **FFI-Specific Testing**:
   - Unit tests that verify binding correctness
   - Integration tests for end-to-end functionality

## Conclusion

The Dart FFI integration in the FlightCanvas Terrain plugin demonstrates a robust approach to integrating native C++ code with Flutter. By leveraging isolates for background processing and carefully managing memory, the plugin achieves high performance while maintaining stability across mobile platforms.