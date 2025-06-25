# Basic LERC Decoding Implementation in Dart via FFI

This document details the implementation of the basic LERC (Limited Error Raster Compression) decoding functionality in Dart using Foreign Function Interface (FFI) in the FlightCanvas Terrain plugin.

## Overview

The FlightCanvas Terrain plugin integrates the LERC decoder by using Dart FFI to call native C++ functions. This approach combines the performance of native code for computationally intensive decoding with the flexibility of Dart for application logic and UI.

The basic LERC decoding implementation in Dart has three main components:
1. The Dart interface class (`LercDecoder`)
2. FFI bindings setup and management
3. Isolate-based processing for background execution

## The LercDecoder Class

The `LercDecoder` class provides a clean and easy-to-use API for the Flutter application, hiding the complexity of FFI and native code interactions.

### Core Public API

```dart
class LercDecoder {
  /// Initialize the native LERC decoder library
  /// Must be called before any decoding operations
  static Future<void> initialize() async;
  
  /// Decode LERC-compressed data into elevation values
  /// Returns a DecodedLercData object containing the elevation grid
  static Future<DecodedLercData> decode(Uint8List bytes) async;
}
```

### Key Design Patterns

1. **Static Factory Methods**: The class uses static methods to provide a clean interface without requiring instantiation.
2. **Asynchronous Processing**: All operations are asynchronous to prevent blocking the UI thread.
3. **Singleton Library Loading**: The native library is loaded once and reused for multiple decode operations.
4. **Isolate-Based Processing**: Heavy computation is moved to a separate isolate.

## FFI Bindings Setup

### Initialization Process

The initialization process involves these steps:

1. **Dynamic Library Loading**:
   ```dart
   // Platform-specific library loading
   if (Platform.isAndroid) {
     _dylib = DynamicLibrary.open('liblerc_wrapper.so');
   } else if (Platform.isIOS) {
     _dylib = DynamicLibrary.process();
     
     // iOS-specific plugin initialization
     if (_useSimplePlugin) {
       final simplePluginInit = _dylib!.lookupFunction<
           Void Function(), void Function()>('lerc_wrapper_plugin_init');
       simplePluginInit();
     }
   }
   ```

2. **Bindings Creation**:
   ```dart
   _bindings = LercBindings(_dylib!);
   ```

3. **Native Library Initialization**:
   ```dart
   if (!_bindings.lerc_wrapper_initialize()) {
     throw Exception('Failed to initialize LERC decoder');
   }
   ```

4. **Error Handling and Retries**:
   The initialization process includes retry logic to handle potential timing issues when loading the native library, especially on iOS:
   ```dart
   int retries = 0;
   bool initSuccess = false;
   
   while (!initSuccess && retries < _maxInitRetries) {
     try {
       // Initialization code
       initSuccess = true;
     } catch (e) {
       await Future.delayed(Duration(milliseconds: 500));
       retries++;
     }
   }
   ```

## LERC Decoding Process

### The Main Decode Function

The main `decode` method orchestrates the decoding process:

```dart
static Future<DecodedLercData> decode(Uint8List bytes) async {
  if (!_initialized) {
    await initialize();
  }

  final receivePort = ReceivePort();
  
  // Spawn isolate for decoding
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
```

### Isolate-based Decoding

The actual decoding happens in a separate isolate to prevent blocking the UI thread:

```dart
static void _isolateFunction(_IsolateData isolateData) {
  try {
    // Initialize bindings in isolate
    DynamicLibrary dylib = /* platform-specific loading */;
    final bindings = LercBindings(dylib);
    bindings.lerc_wrapper_initialize();

    // Prepare input data
    final bytes = isolateData.bytes;
    final inputPtr = malloc<Uint8>(bytes.length);
    final inputArray = inputPtr.asTypedList(bytes.length);
    inputArray.setAll(0, bytes);

    // Decode steps
    Pointer<LercInfo> infoPtr = bindings.lerc_wrapper_get_info(inputPtr.cast(), bytes.length);
    Pointer<Double> dataPtr = bindings.lerc_wrapper_decode(inputPtr.cast(), bytes.length, infoPtr);
    
    // Create Dart object from native data
    final info = infoPtr.ref;
    final numPixels = info.width * info.height;
    final data = Float64List.fromList(dataPtr.asTypedList(numPixels));
    
    // Return result
    final result = DecodedLercData(
      data,
      info.width,
      info.height,
      info.minValue,
      info.maxValue,
    );
    
    isolateData.sendPort.send(_IsolateMessage.success(result));
  } 
  finally {
    // Memory cleanup
    malloc.free(inputPtr);
    if (infoPtr != nullptr) bindings.lerc_wrapper_free_info(infoPtr);
    if (dataPtr != nullptr) bindings.lerc_wrapper_free_data(dataPtr);
  }
}
```

## Memory Management

The implementation carefully manages memory to prevent leaks:

1. **Native Memory Allocation**: Native memory is allocated using Dart's `malloc` utility:
   ```dart
   final inputPtr = malloc<Uint8>(bytes.length);
   ```

2. **Data Transfer**: Data is copied from Dart to native memory:
   ```dart
   final inputArray = inputPtr.asTypedList(bytes.length);
   inputArray.setAll(0, bytes);
   ```

3. **Native Memory Access**: Native data is accessed through typed views:
   ```dart
   final data = Float64List.fromList(dataPtr.asTypedList(numPixels));
   ```

4. **Memory Cleanup**: Native memory is explicitly freed, even in error cases:
   ```dart
   malloc.free(inputPtr);
   if (infoPtr != nullptr) bindings.lerc_wrapper_free_info(infoPtr);
   if (dataPtr != nullptr) bindings.lerc_wrapper_free_data(dataPtr);
   ```

## Data Representation

### The DecodedLercData Class

The `DecodedLercData` class represents the decoded elevation data:

```dart
class DecodedLercData {
  final Float64List data;
  final int width;
  final int height;
  final double minValue;
  final double maxValue;

  DecodedLercData(this.data, this.width, this.height, this.minValue, this.maxValue);

  bool isValid() => data.isNotEmpty && width > 0 && height > 0;

  double getElevation(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.nan;
    return data[y * width + x];
  }

  Float64List getRegion(int startX, int startY, int regionWidth, int regionHeight) {
    // Extract a rectangular region of data
    // ...
  }
}
```

Key features of this class:
1. **Raw Data Access**: Via the `data` property (a flat array of elevation values)
2. **Grid Dimensions**: `width` and `height` properties
3. **Value Range**: `minValue` and `maxValue` for data normalization
4. **Convenience Methods**: Like `getElevation()` and `getRegion()`

## Error Handling

The implementation includes comprehensive error handling at multiple levels:

1. **Native Function Errors**: Checked through return values and error codes:
   ```dart
   if (!_bindings.lerc_wrapper_initialize()) {
     throw Exception('Failed to initialize LERC decoder');
   }
   ```

2. **Memory Allocation Failures**: Handled through null checks:
   ```dart
   if (infoPtr == nullptr) {
     throw Exception('Failed to get LERC info');
   }
   ```

3. **Isolate Communication**: Wrapped in a message structure:
   ```dart
   class _IsolateMessage {
     final bool success;
     final dynamic data;
     final String? error;

     _IsolateMessage.success(this.data) : success = true, error = null;
     _IsolateMessage.error(this.error) : success = false, data = null;
   }
   ```

4. **Propagation to Caller**: Errors from the isolate are propagated back to the caller:
   ```dart
   if (!result.success) {
     throw Exception(result.error);
   }
   ```

## Platform-Specific Considerations

### Android Implementation

For Android:
- Uses explicit library loading: `DynamicLibrary.open('liblerc_wrapper.so')`
- The `.so` file is packaged in the APK's `jniLibs` directory

### iOS Implementation

For iOS:
- Uses process-embedded library: `DynamicLibrary.process()`
- Has an additional plugin initialization function for simpler C integration
- Contains additional error handling for iOS-specific issues

### Handling Unsupported Platforms

A fallback implementation is provided for unsupported platforms:

```dart
class UnsupportedPlatformLercDecoder {
  static Future<void> initialize() async {
    throw UnsupportedError('This app only supports Android and iOS platforms');
  }

  static Future<DecodedLercData> decode(Uint8List bytes) async {
    throw UnsupportedError('This app only supports Android and iOS platforms');
  }
}
```

## Performance Optimizations

Several performance optimizations are implemented:

1. **Background Processing**: Decoding happens in a separate isolate to keep the UI responsive
2. **Direct Memory Access**: Native memory is accessed directly via typed views to minimize copying
3. **Memory Reuse**: The native library is loaded once and reused for multiple decoding operations
4. **Error Recovery**: Multiple initialization attempts with exponential backoff for transient errors

## Testing

Testing the LERC decoding implementation involves:

1. **Unit Tests**: Testing the Dart API with sample LERC files
2. **Integration Tests**: Testing the complete flow from file loading to decoded data
3. **Performance Tests**: Measuring decoding time and memory usage
4. **Error Handling Tests**: Ensuring proper handling of corrupted or invalid LERC data

## Usage Example

```dart
try {
  // Initialize the decoder
  await LercDecoder.initialize();
  
  // Load LERC data (from network, assets, or file)
  final ByteData byteData = await rootBundle.load('assets/elevation.lerc2');
  final Uint8List bytes = byteData.buffer.asUint8List();
  
  // Decode the data
  DecodedLercData elevationData = await LercDecoder.decode(bytes);
  
  // Use the decoded data
  if (elevationData.isValid()) {
    double elevation = elevationData.getElevation(100, 100);
    print('Elevation at (100, 100): $elevation meters');
    
    // Extract a region for detailed processing
    Float64List regionData = elevationData.getRegion(50, 50, 100, 100);
    // Process region data...
  }
} catch (e) {
  print('Error decoding LERC data: $e');
}
```

## Conclusion

The basic LERC decoding implementation in Dart via FFI provides a robust and efficient way to decode LERC-compressed terrain data in Flutter applications. The design balances performance, memory efficiency, and a clean API while handling platform-specific differences and error cases appropriately.

The implementation serves as a foundation for more advanced terrain visualization features built on top of the decoded elevation data.
