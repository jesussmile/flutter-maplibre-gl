# Multithreaded LERC Decoding with Dart Isolates

This document provides a comprehensive explanation of how the FlightCanvas Terrain plugin implements multithreaded LERC decoding using Dart isolates to improve performance and maintain UI responsiveness.

## Overview

Decoding LERC (Limited Error Raster Compression) terrain data is a computationally intensive task that can block the main UI thread if performed synchronously. The FlightCanvas Terrain plugin addresses this by implementing a multithreaded decoding approach using Dart isolates, which allows the decoding process to run on separate threads without affecting the UI responsiveness.

## Key Components

The multithreaded LERC decoding implementation consists of several key components:

1. **LercIsolateDecoder**: A high-level class that manages isolate creation, communication, and coordination
2. **Isolate Communication Protocol**: Message passing system between the main isolate and worker isolates
3. **Native Code Integration**: FFI bindings that allow isolates to access native C++ code
4. **Memory Management**: Techniques for efficient memory handling across isolate boundaries
5. **Terrain Cache**: A system for efficiently storing and retrieving decoded terrain data

## Isolate Architecture

### LercIsolateDecoder Class

The `LercIsolateDecoder` class (`lib/src/lerc_isolate.dart`) serves as the main entry point for multithreaded LERC decoding. It provides:

- Static methods for initializing the decoder and creating isolates
- Communication channels between the main thread and worker isolates
- Error handling and resource management for isolates

```dart
class LercIsolateDecoder {
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static bool _isInitialized = false;
  
  // Initialize the decoder in the isolate
  static Future<void> initialize() async { ... }
  
  // Decode LERC data in a separate isolate
  static Future<DecodedLercData> decode(Uint8List bytes) async { ... }
  
  // Isolate worker function
  static Future<void> _isolateFunction(IsolateMessage message) async { ... }
  
  // Cleanup resources
  static void dispose() { ... }
}
```

### Message Protocol

Communication between isolates is facilitated through a well-defined message protocol using `SendPort` and `ReceivePort` objects:

```dart
enum MessageType { decode, initialize }

class IsolateMessage {
  final MessageType type;
  final Uint8List? bytes;
  final SendPort sendPort;

  IsolateMessage(this.type, this.sendPort, {this.bytes});
}
```

This protocol enables:
- Sending LERC data to worker isolates
- Receiving decoded results back to the main isolate
- Handling errors that occur during decoding
- Coordinating initialization across isolates

## Implementation Details

### Initialization Process

The initialization process ensures that both the main isolate and worker isolates have properly initialized the native LERC decoder:

1. The `LercIsolateDecoder.initialize()` method is called from the main thread
2. A worker isolate is spawned with an initialization message
3. The worker isolate sets up a `ReceivePort` and sends its `SendPort` back to the main isolate
4. The worker isolate initializes the `LercDecoder` to load and prepare the native library
5. The main isolate stores the worker's `SendPort` for future communication

```dart
static Future<void> initialize() async {
  if (_isInitialized) return;
  if (_initCompleter != null) {
    await _initCompleter!.future;
    return;
  }

  _initCompleter = Completer<void>();
  try {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateFunction,
      IsolateMessage(MessageType.initialize, receivePort.sendPort),
    );

    _sendPort = await receivePort.first as SendPort;
    _isInitialized = true;
    _initCompleter!.complete();
  } catch (e) {
    debugPrint('Error initializing LERC decoder: $e');
    _initCompleter!.completeError(e);
    rethrow;
  }
}
```

### Decoding Process

The decoding process occurs entirely in the worker isolate:

1. The main thread calls `LercIsolateDecoder.decode(bytes)` with the LERC data
2. A `ReceivePort` is created for receiving the result
3. An `IsolateMessage` with the LERC bytes is sent to the worker isolate
4. The worker isolate processes the message and performs the decoding:
   - Extracts LERC data from the message
   - Calls native C++ functions via FFI to decode the data
   - Handles memory allocation and deallocation
   - Creates a `DecodedLercData` object with the results
5. The worker sends the result back to the main isolate
6. The main isolate completes the Future with the decoded data

```dart
static Future<DecodedLercData> decode(Uint8List bytes) async {
  if (!_isInitialized) {
    throw Exception('LercIsolateDecoder not initialized');
  }

  final receivePort = ReceivePort();
  _sendPort!.send(
    IsolateMessage(MessageType.decode, receivePort.sendPort, bytes: bytes),
  );

  try {
    final result = await receivePort.first;
    if (result is Exception) {
      throw result;
    }
    return result as DecodedLercData;
  } finally {
    receivePort.close();
  }
}
```

### Worker Isolate Function

The worker isolate function handles incoming messages and performs the actual decoding:

```dart
static Future<void> _isolateFunction(IsolateMessage message) async {
  final receivePort = ReceivePort();
  message.sendPort.send(receivePort.sendPort);

  // Initialize LERC decoder in the isolate
  await LercDecoder.initialize();

  await for (final IsolateMessage msg in receivePort.cast<IsolateMessage>()) {
    try {
      if (msg.type == MessageType.decode && msg.bytes != null) {
        final decodedData = await LercDecoder.decode(msg.bytes!);
        msg.sendPort.send(decodedData);
      }
    } catch (e) {
      msg.sendPort.send(Exception('Failed to decode LERC data: $e'));
    }
  }
}
```

## Native Code Integration in Isolates

Each isolate has its own memory heap and must independently load the native LERC library:

1. The `LercDecoder.initialize()` method is called in both main and worker isolates
2. Each isolate loads the appropriate platform-specific native library:
   - Android: `'liblerc_wrapper.so'`
   - iOS: `'lerc_wrapper'` via `DynamicLibrary.process()`
3. Each isolate initializes the LERC wrapper using the FFI bindings
4. The isolates can then independently call native functions without blocking each other

This approach ensures thread safety when working with the native code, as each isolate has its own instance of the native library.

## Memory Management

Working with large terrain datasets requires careful memory management:

1. **Temporary Buffers**: Created and destroyed during the decoding process
   ```dart
   // Allocate memory for input data
   final inputPtr = malloc<Uint8>(bytes.length);
   final inputArray = inputPtr.asTypedList(bytes.length);
   inputArray.setAll(0, bytes);
   
   // Ensure memory is freed even if errors occur
   try {
     // Decoding logic here
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

2. **Data Transfer**: Only the final decoded data is transferred between isolates
3. **Garbage Collection**: Isolates help with memory management by allowing chunks of the application to be separately garbage collected
4. **Resource Cleanup**: Explicit cleanup in the `dispose()` method ensures that isolates are properly terminated and resources released

## Terrain Cache Implementation

The `TerrainCache` class (`lib/src/terrain_cache.dart`) works in conjunction with the isolate-based decoder to efficiently manage decoded terrain data:

1. **Memory Cache**: Maintains a limited number of recently decoded terrain levels in memory 
2. **Disk Cache**: Stores processed terrain data on disk for quick access without re-decoding
3. **Optimized Storage**: Only stores elevation points that are relevant for each altitude level, significantly reducing memory and storage requirements
4. **Asynchronous Processing**: Uses the isolate-based decoder for all LERC decoding operations

```dart
Future<void> initialize(Uint8List lercBytes) async {
  // Setup cache and initialize the isolate decoder
  await _setupCacheDirectory();
  await LercIsolateDecoder.initialize();
  
  // Decode first to get metadata
  final firstData = await LercIsolateDecoder.decode(_lercBytes!);
  
  // Process different altitude levels asynchronously
  for (double altitude = minAltitude; altitude <= maxAltitude; altitude += altitudeStep) {
    final decodedData = await LercIsolateDecoder.decode(_lercBytes!);
    await _saveToDisk(altitude, decodedData);
  }
}
```

## Performance Considerations

The multithreaded design provides several performance benefits:

1. **UI Responsiveness**: By moving decoding off the main thread, the UI remains responsive during intensive operations
2. **Parallel Processing**: On multi-core devices, work can be distributed across CPU cores
3. **Progressive Loading**: The implementation supports progressive loading of terrain data, showing lower resolutions while higher-resolution data is still being processed
4. **Cached Results**: Processed results are cached to avoid redundant decoding operations
5. **Memory Efficiency**: By processing in separate isolates, memory can be released immediately after use

## Error Handling

Robust error handling is implemented throughout the isolate communication process:

1. **Initialization Retries**: The native library initialization includes retry logic to handle timing-related issues
2. **Message-based Error Propagation**: Errors in the worker isolate are properly propagated back to the main isolate
3. **Resource Cleanup**: All resources are properly cleaned up, even in error scenarios

## Usage Example

Here's how the multithreaded decoding is used in the application:

```dart
// Initialize the isolate decoder once at startup
await LercIsolateDecoder.initialize();

// Later, decode LERC data without blocking the UI
try {
  final decodedData = await LercIsolateDecoder.decode(lercBytes);
  
  // Use the decoded terrain data
  renderTerrain(decodedData);
} catch (e) {
  handleError(e);
}
```

## Conclusion

The multithreaded LERC decoding implementation in FlightCanvas Terrain demonstrates an efficient approach to handling computationally intensive operations in Flutter applications. By using Dart isolates, the plugin maintains UI responsiveness while processing large terrain datasets, and through careful memory management and caching strategies, it optimizes performance even on resource-constrained mobile devices.
