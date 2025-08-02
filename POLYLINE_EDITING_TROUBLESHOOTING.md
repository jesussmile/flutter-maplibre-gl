# Interactive Polyline Editing Troubleshooting Guide

This guide helps diagnose and resolve common issues with the Interactive Polyline Editing feature.

✅ **Production Ready Implementation** - This troubleshooting guide covers the fully implemented, production-ready interactive polyline editing feature with real native gesture detection and cross-platform support.

## Current Implementation Status

### What Works ✅
- **Long Press Detection**: Creates orange break point markers at touch location
- **Real-time Dragging**: Break point visual follows finger during drag operations
- **Coordinate Updates**: Real-time coordinate updates sent to Flutter during drag
- **Line Structure**: Maintains proper start → break point → end line structure
- **Cross-Platform**: Consistent behavior on Android and iOS
- **Memory Management**: Proper cleanup of break points and editing sessions
- **Error Handling**: Comprehensive error detection and reporting

### Implementation Details
- **iOS**: Uses UILongPressGestureRecognizer + UIPanGestureRecognizer with MLNCircleStyleLayer break points
- **Android**: Uses OnMapLongClickListener + gesture detection with SymbolLayer break points
- **Coordinate Structure**: Always 3 points during editing: [start, current_break_point, end]
- **Visual Feedback**: Orange circle that moves with drag, no conflicting preview lines

## Quick Diagnostics

### Is Editing Working?

Run this quick test to verify basic functionality:

```dart
// Add this test method to your app
Future<void> testPolylineEditing() async {
  final testRoute = [
    LatLng(37.7749, -122.4194),
    LatLng(37.7849, -122.4094),
  ];

  final line = await controller!.addLine(
    LineOptions(
      geometry: testRoute,
      lineColor: '#FF0000',
      lineWidth: 5.0,
      editable: true,
      editingCallbacks: PolylineEditingCallbacks(
        onPolylineBroken: (id, seg1, seg2) => print('✅ Break working: $id'),
        onPolylineModified: (id, coords) => print('✅ Modify working: $id'),
        onEditingError: (id, error) => print('❌ Error: $id - $error'),
      ),
    ),
  );

  print('Test polyline added: ${line.id}');
  print('Try long pressing on the red line to test editing');
}
```

## Common Issues and Solutions

### 1. Editing Not Working

#### Issue: Long press doesn't create break points

**Symptoms:**
- Long pressing on polyline does nothing
- No visual feedback appears
- Callbacks are not triggered

**Diagnosis:**
```dart
// Add debugging to verify setup
final lineOptions = LineOptions(
  geometry: coordinates,
  lineColor: '#FF0000',
  lineWidth: 4.0,
  editable: true, // ✅ Must be true
  editingCallbacks: PolylineEditingCallbacks( // ✅ Must be provided
    onPolylineBroken: (id, seg1, seg2) {
      print('DEBUG: Break callback triggered');
    },
    onEditingError: (id, error) {
      print('DEBUG: Error - $error'); // Check for errors
    },
  ),
);
```

**Solutions:**

1. **Verify `editable: true`:**
   ```dart
   // Wrong
   LineOptions(geometry: coords, lineColor: '#FF0000')
   
   // Correct
   LineOptions(
     geometry: coords, 
     lineColor: '#FF0000',
     editable: true, // Must be explicitly set
   )
   ```

2. **Check platform support:**
   ```dart
   import 'dart:io';
   
   if (Platform.isAndroid || Platform.isIOS) {
     // Editing supported
   } else {
     print('WARNING: Polyline editing only works on Android/iOS');
   }
   ```

3. **Verify callback assignment:**
   ```dart
   // Wrong - callbacks are null
   LineOptions(editable: true)
   
   // Correct - callbacks provided
   LineOptions(
     editable: true,
     editingCallbacks: PolylineEditingCallbacks(
       onPolylineBroken: _handleBreak,
       onPolylineModified: _handleModify,
     ),
   )
   ```

### 2. Visual Feedback Issues

#### Issue: Orange break point not visible or not moving

**Symptoms:**
- Long press creates break point but orange circle is not visible
- Break point circle appears but doesn't move during drag operations
- Drag operations work but without visual feedback

**Diagnosis:**
```dart
// Check break point styling
final debugStyle = PolylineEditingStyle(
  breakPointColor: '#FFFF00', // Bright yellow
  breakPointRadius: 15.0,     // Large size
  breakPointBorderColor: '#000000', // Black border
  breakPointBorderWidth: 3.0, // Thick border
);

await controller.setPolylineEditingStyle(debugStyle);
```

**Solutions:**

1. **Adjust break point colors:**
   ```dart
   LineOptions(
     editable: true,
     breakPointColor: '#FF0000', // Bright red
     breakPointRadius: 12.0,     // Larger size
   )
   ```

2. **Check against map background:**
   ```dart
   // For dark maps
   final darkMapStyle = PolylineEditingStyle(
     breakPointColor: '#FFFFFF',      // White
     breakPointBorderColor: '#000000', // Black border
   );
   
   // For light maps
   final lightMapStyle = PolylineEditingStyle(
     breakPointColor: '#000000',      // Black
     breakPointBorderColor: '#FFFFFF', // White border
   );
   ```

3. **Verify preview line visibility:**
   ```dart
   LineOptions(
     editable: true,
     previewLineColor: '#00FF00',  // Bright green
     previewLineOpacity: 0.9,      // High opacity
     previewLineWidth: 6.0,        // Thicker line
   )
   ```

### 3. Performance Issues

#### Issue: Lag during editing operations

**Symptoms:**
- Slow response to touch gestures
- Choppy drag animations
- App freezes during editing

**Diagnosis:**
```dart
// Check polyline complexity
void diagnosePerformance(List<LatLng> coordinates) {
  print('Polyline points: ${coordinates.length}');
  
  if (coordinates.length > 1000) {
    print('WARNING: Polyline too complex for smooth editing');
  }
  
  // Check coordinate precision
  final precisionCheck = coordinates.take(5).map((coord) =>
    'Lat: ${coord.latitude.toStringAsFixed(6)}, '
    'Lng: ${coord.longitude.toStringAsFixed(6)}'
  ).join('\n');
  
  print('Coordinate precision:\n$precisionCheck');
}
```

**Solutions:**

1. **Simplify complex polylines:**
   ```dart
   List<LatLng> simplifyForEditing(List<LatLng> coordinates) {
     if (coordinates.length <= 500) return coordinates;
     
     // Use Douglas-Peucker or similar algorithm
     return DouglasPeucker.simplify(coordinates, tolerance: 0.001);
   }
   
   final simplifiedCoords = simplifyForEditing(originalCoordinates);
   ```

2. **Limit concurrent editable polylines:**
   ```dart
   class PerformanceManager {
     static const int MAX_EDITABLE_LINES = 3;
     static int _editableCount = 0;
     
     static bool canMakeEditable() {
       return _editableCount < MAX_EDITABLE_LINES;
     }
     
     static void addEditableLine() {
       _editableCount++;
     }
     
     static void removeEditableLine() {
       _editableCount--;
     }
   }
   ```

3. **Optimize styling:**
   ```dart
   // Performance-optimized styling
   final efficientStyle = PolylineEditingStyle(
     breakPointRadius: 8.0,         // Not too large
     previewLineWidth: 3.0,         // Reasonable width
     enableHapticFeedback: false,   // Reduce processing
   );
   ```

### 4. Callback Issues

#### Issue: Callbacks not being triggered

**Symptoms:**
- Editing gestures work visually but callbacks don't fire
- No application state updates

**Diagnosis:**
```dart
// Add debug callbacks
final debugCallbacks = PolylineEditingCallbacks(
  onPolylineBroken: (id, seg1, seg2) {
    print('🔥 BREAK: $id, segments: ${seg1.length}, ${seg2.length}');
    // Your actual callback logic here
  },
  onPolylineModified: (id, coords) {
    print('🔄 MODIFY: $id, points: ${coords.length}');
    // Your actual callback logic here
  },
  onEditingError: (id, error) {
    print('❌ ERROR: $id - $error');
    // Your actual error handling here
  },
);
```

**Solutions:**

1. **Verify callback assignment:**
   ```dart
   // Wrong - creating callbacks but not using them
   final callbacks = PolylineEditingCallbacks(...);
   LineOptions(editable: true) // callbacks not assigned
   
   // Correct
   final callbacks = PolylineEditingCallbacks(...);
   LineOptions(
     editable: true,
     editingCallbacks: callbacks, // Must assign
   )
   ```

2. **Check for null callbacks:**
   ```dart
   void _handleBreak(String id, List<LatLng> seg1, List<LatLng> seg2) {
     if (seg1.isEmpty || seg2.isEmpty) {
       print('WARNING: Empty segments received');
       return;
     }
     
     // Process break
   }
   ```

3. **Verify callback function signatures:**
   ```dart
   // Wrong signature
   void _handleBreak(String id) { ... }
   
   // Correct signature
   void _handleBreak(String id, List<LatLng> seg1, List<LatLng> seg2) { ... }
   ```

### Platform-Specific Issues

#### Issue: Different behavior on Android vs iOS

**Symptoms:**
- Works on one platform but not the other
- Different visual appearance between platforms

**Status:** ✅ **Both platforms fully implemented** with cross-platform consistency testing completed.

**Diagnosis:**
```dart
// Platform-specific debugging
void debugPlatformDifferences() {
  if (Platform.isAndroid) {
    print('Running on Android - Real OnMapLongClickListener + SymbolLayer markers');
  } else if (Platform.isIOS) {
    print('Running on iOS - Real UILongPressGestureRecognizer + MLNAnnotation');
  } else {
    print('Running on ${Platform.operatingSystem} - editing not supported');
  }
}
```

**Solutions:**

1. **Platform-specific styling:**
   ```dart
   PolylineEditingStyle getPlatformStyle() {
     if (Platform.isIOS) {
       return PolylineEditingStyle(
         enableHapticFeedback: true,
         breakPointRadius: 12.0, // Larger for iOS touch targets
       );
     } else {
       return PolylineEditingStyle(
         enableHapticFeedback: false,
         breakPointRadius: 10.0,
       );
     }
   }
   ```

2. **Handle platform differences in callbacks:**
   ```dart
   void _handlePlatformSpecificEditing(String id, List<LatLng> coords) {
     if (Platform.isIOS) {
       // iOS-specific handling
       IOSRouteManager.updateRoute(id, coords);
     } else if (Platform.isAndroid) {
       // Android-specific handling
       AndroidRouteManager.updateRoute(id, coords);
     }
   }
   ```

### 6. Memory Issues

#### Issue: Memory leaks or excessive memory usage

**Symptoms:**
- App memory usage grows over time
- App crashes with out-of-memory errors

**Diagnosis:**
```dart
// Monitor memory usage
class MemoryMonitor {
  static void logMemoryUsage(String context) {
    // Add memory monitoring code
    print('Memory check at $context');
  }
}

// In your editing callbacks
void _handleModify(String id, List<LatLng> coords) {
  MemoryMonitor.logMemoryUsage('before modify');
  
  // Your handling code
  
  MemoryMonitor.logMemoryUsage('after modify');
}
```

**Solutions:**

1. **Clean up editing sessions:**
   ```dart
   class EditingSessionManager {
     static final Map<String, PolylineEditingSession> _sessions = {};
     
     static void startSession(String lineId, PolylineEditingSession session) {
       _sessions[lineId] = session;
     }
     
     static void endSession(String lineId) {
       _sessions.remove(lineId);
     }
     
     static void cleanupOldSessions() {
       final now = DateTime.now();
       _sessions.removeWhere((id, session) {
         return now.difference(session.startTime).inMinutes > 30;
       });
     }
   }
   ```

2. **Limit coordinate precision:**
   ```dart
   List<LatLng> optimizeCoordinates(List<LatLng> coords) {
     return coords.map((coord) => LatLng(
       double.parse(coord.latitude.toStringAsFixed(6)),
       double.parse(coord.longitude.toStringAsFixed(6)),
     )).toList();
   }
   ```

## Error Messages

### Common Error Messages and Solutions

#### "POLYLINE_TOO_SHORT"
```dart
// Solution: Check minimum polyline length
if (coordinates.length < 2) {
  print('Cannot make polyline editable: needs at least 2 points');
  return;
}
```

#### "GEOMETRIC_CALCULATION_FAILED"
```dart
// Solution: Validate coordinate ranges
bool validateCoordinates(List<LatLng> coords) {
  for (final coord in coords) {
    if (coord.latitude < -90 || coord.latitude > 90) return false;
    if (coord.longitude < -180 || coord.longitude > 180) return false;
  }
  return true;
}
```

#### "NATIVE_SDK_ERROR"
```dart
// Solution: Implement retry mechanism
Future<void> addLineWithRetry(LineOptions options, {int maxRetries = 3}) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      await controller.addLine(options);
      return;
    } catch (e) {
      if (i == maxRetries - 1) rethrow;
      await Future.delayed(Duration(milliseconds: 500));
    }
  }
}
```

## Debug Tools

### Enable Debug Logging

```dart
// Add to your app initialization
void enablePolylineEditingDebug() {
  // This would be implementation-specific
  // MapLibreMap.enableDebugLogging = true;
  
  // For now, use manual debugging
  debugPrint('Polyline editing debug mode enabled');
}
```

### Debug Information Widget

```dart
class EditingDebugWidget extends StatefulWidget {
  final MapLibreMapController controller;
  
  const EditingDebugWidget({Key? key, required this.controller}) : super(key: key);

  @override
  _EditingDebugWidgetState createState() => _EditingDebugWidgetState();
}

class _EditingDebugWidgetState extends State<EditingDebugWidget> {
  List<String> debugMessages = [];

  void addDebugMessage(String message) {
    setState(() {
      debugMessages.insert(0, '${DateTime.now().toString().substring(11, 19)}: $message');
      if (debugMessages.length > 20) {
        debugMessages.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Debug Log:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              itemCount: debugMessages.length,
              itemBuilder: (context, index) {
                return Text(
                  debugMessages[index],
                  style: TextStyle(color: Colors.green, fontSize: 10, fontFamily: 'monospace'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

## Performance Profiling

### Measure Editing Performance

```dart
class EditingPerformanceProfiler {
  static final Stopwatch _stopwatch = Stopwatch();
  static final Map<String, int> _timings = {};

  static void startTiming(String operation) {
    _stopwatch.reset();
    _stopwatch.start();
  }

  static void endTiming(String operation) {
    _stopwatch.stop();
    _timings[operation] = _stopwatch.elapsedMilliseconds;
    print('⏱️ $operation took ${_stopwatch.elapsedMilliseconds}ms');
  }

  static void printProfile() {
    print('=== Editing Performance Profile ===');
    _timings.forEach((operation, time) {
      print('$operation: ${time}ms');
    });
  }
}

// Usage in callbacks
void _handleModify(String id, List<LatLng> coords) {
  EditingPerformanceProfiler.startTiming('polyline_modify');
  
  // Your modification handling code
  _processModification(id, coords);
  
  EditingPerformanceProfiler.endTiming('polyline_modify');
}
```

## Getting Help

If these troubleshooting steps don't resolve your issue:

1. **Enable debug logging** and capture the output
2. **Create a minimal reproduction case**
3. **Document your platform and version info**
4. **Include relevant code snippets**
5. **Check existing GitHub issues** for similar problems
6. **Create a new issue** with detailed information

### Issue Template

When reporting issues, include:

```
**Environment:**
- Flutter version:
- MapLibre GL version:
- Platform (Android/iOS):
- Device/Simulator:

**Problem:**
- What you expected to happen:
- What actually happened:
- Steps to reproduce:

**Code:**
```dart
// Minimal reproduction code
```

**Debug Output:**
```
// Console output, error messages, etc.
```
```

This troubleshooting guide should help you quickly identify and resolve most issues with the Interactive Polyline Editing feature.