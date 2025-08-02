# Interactive Polyline Editing API Reference

This document provides comprehensive API reference for the Interactive Polyline Editing feature in the MapLibre GL Flutter plugin.

## Overview

The Interactive Polyline Editing feature enables users to modify polylines on maps through native gesture recognition. Users can long press on any point along a polyline to break it into segments, then drag the break point to create new routing paths.

**Status:** ✅ **Production Ready** - Real interactive implementation with native gesture detection, cross-platform consistency, and comprehensive testing completed.

**Platform Support:** Android and iOS only (native implementation required)

## Core Classes

### LineOptions (Extended)

Extended `LineOptions` class with editing capabilities.

```dart
class LineOptions {
  // Existing properties...
  final bool? editable;
  final PolylineEditingCallbacks? editingCallbacks;
  
  // Visual styling for editing
  final String? breakPointColor;
  final double? breakPointRadius;
  final String? previewLineColor;
  final double? previewLineOpacity;
}
```

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `editable` | `bool?` | `false` | Whether the polyline can be edited interactively |
| `editingCallbacks` | `PolylineEditingCallbacks?` | `null` | Callbacks for editing events |
| `breakPointColor` | `String?` | `"#FF0000"` | Color of break point markers (hex format) |
| `breakPointRadius` | `double?` | `8.0` | Radius of break point markers in pixels |
| `previewLineColor` | `String?` | `"#00FF00"` | Color of preview line during drag operations |
| `previewLineOpacity` | `double?` | `0.7` | Opacity of preview line (0.0 to 1.0) |

#### Example

```dart
final editableLineOptions = LineOptions(
  geometry: [
    LatLng(37.7749, -122.4194), // San Francisco
    LatLng(40.7128, -74.0060),  // New York
  ],
  lineColor: '#0066CC',
  lineWidth: 4.0,
  editable: true,
  breakPointColor: '#FF6600',
  breakPointRadius: 12.0,
  previewLineColor: '#00CC66',
  previewLineOpacity: 0.8,
  editingCallbacks: PolylineEditingCallbacks(
    onPolylineBroken: (lineId, segment1, segment2) {
      print('Polyline $lineId broken into ${segment1.length} + ${segment2.length} segments');
    },
    onPolylineModified: (lineId, newCoordinates) {
      print('Polyline $lineId modified: ${newCoordinates.length} points');
    },
  ),
);
```

### PolylineEditingCallbacks

Callback interface for handling editing events.

```dart
class PolylineEditingCallbacks {
  const PolylineEditingCallbacks({
    this.onPolylineBroken,
    this.onPolylineModified,
    this.onEditingError,
  });

  final void Function(String lineId, List<LatLng> segment1, List<LatLng> segment2)? onPolylineBroken;
  final void Function(String lineId, List<LatLng> newCoordinates)? onPolylineModified;
  final void Function(String lineId, String error)? onEditingError;
}
```

#### Callbacks

##### `onPolylineBroken`
Called when a polyline is broken into two segments.

**Parameters:**
- `lineId` (`String`): Unique identifier of the polyline
- `segment1` (`List<LatLng>`): Coordinates of the first segment
- `segment2` (`List<LatLng>`): Coordinates of the second segment

**Usage:**
```dart
onPolylineBroken: (lineId, segment1, segment2) {
  // Handle polyline breaking
  print('Line $lineId broken: ${segment1.length} + ${segment2.length} points');
  
  // Update your application state
  updateRouteSegments(lineId, segment1, segment2);
},
```

##### `onPolylineModified`
Called when a polyline's coordinates are modified through dragging.

**Parameters:**
- `lineId` (`String`): Unique identifier of the polyline
- `newCoordinates` (`List<LatLng>`): Updated coordinates of the polyline

**Usage:**
```dart
onPolylineModified: (lineId, newCoordinates) {
  // Handle coordinate updates
  print('Line $lineId modified: ${newCoordinates.length} total points');
  
  // Save updated route
  saveRouteCoordinates(lineId, newCoordinates);
},
```

##### `onEditingError`
Called when an error occurs during editing operations.

**Parameters:**
- `lineId` (`String`): Unique identifier of the polyline
- `error` (`String`): Error description

**Usage:**
```dart
onEditingError: (lineId, error) {
  // Handle editing errors
  print('Editing error on $lineId: $error');
  
  // Show user-friendly error message
  showErrorMessage('Failed to edit route: $error');
},
```

### PolylineBreakPoint

Represents a break point on a polyline during editing.

```dart
class PolylineBreakPoint {
  const PolylineBreakPoint({
    required this.id,
    required this.parentLineId,
    required this.coordinate,
    required this.segmentIndex,
    required this.distanceAlongSegment,
    required this.isDragging,
  });

  final String id;
  final String parentLineId;
  final LatLng coordinate;
  final int segmentIndex;
  final double distanceAlongSegment;
  final bool isDragging;
}
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique identifier for the break point |
| `parentLineId` | `String` | ID of the polyline this break point belongs to |
| `coordinate` | `LatLng` | Current coordinate of the break point |
| `segmentIndex` | `int` | Index of the polyline segment where break occurred |
| `distanceAlongSegment` | `double` | Distance along segment (0.0 to 1.0) |
| `isDragging` | `bool` | Whether the break point is currently being dragged |

### PolylineEditingSession

Tracks the state of an active editing session.

```dart
class PolylineEditingSession {
  const PolylineEditingSession({
    required this.lineId,
    required this.breakPoint,
    required this.originalCoordinates,
    required this.segment1Coordinates,
    required this.segment2Coordinates,
    required this.startTime,
  });

  final String lineId;
  final PolylineBreakPoint breakPoint;
  final List<LatLng> originalCoordinates;
  final List<LatLng> segment1Coordinates;
  final List<LatLng> segment2Coordinates;
  final DateTime startTime;
}
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `lineId` | `String` | ID of the polyline being edited |
| `breakPoint` | `PolylineBreakPoint` | Active break point |
| `originalCoordinates` | `List<LatLng>` | Original polyline coordinates |
| `segment1Coordinates` | `List<LatLng>` | First segment coordinates |
| `segment2Coordinates` | `List<LatLng>` | Second segment coordinates |
| `startTime` | `DateTime` | When the editing session started |

### PolylineEditingStyle

Configuration for visual appearance during editing.

```dart
class PolylineEditingStyle {
  const PolylineEditingStyle({
    this.breakPointColor = '#FF0000',
    this.breakPointRadius = 8.0,
    this.breakPointBorderColor = '#FFFFFF',
    this.breakPointBorderWidth = 2.0,
    this.previewLineColor = '#00FF00',
    this.previewLineOpacity = 0.7,
    this.previewLineWidth = 3.0,
    this.enableHapticFeedback = true,
  });

  final String breakPointColor;
  final double breakPointRadius;
  final String breakPointBorderColor;
  final double breakPointBorderWidth;
  final String previewLineColor;
  final double previewLineOpacity;
  final double previewLineWidth;
  final bool enableHapticFeedback;
}
```

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `breakPointColor` | `String` | `"#FF0000"` | Color of break point markers |
| `breakPointRadius` | `double` | `8.0` | Radius of break point markers |
| `breakPointBorderColor` | `String` | `"#FFFFFF"` | Border color of break points |
| `breakPointBorderWidth` | `double` | `2.0` | Border width of break points |
| `previewLineColor` | `String` | `"#00FF00"` | Color of preview line during drag |
| `previewLineOpacity` | `double` | `0.7` | Opacity of preview line (0.0-1.0) |
| `previewLineWidth` | `double` | `3.0` | Width of preview line in pixels |
| `enableHapticFeedback` | `bool` | `true` | Whether to provide haptic feedback |

## Controller Extensions

### MapLibreMapController Extensions

New methods added to `MapLibreMapController` for polyline editing.

#### `enablePolylineEditing`

Enable or disable editing for a specific polyline.

```dart
Future<void> enablePolylineEditing(String lineId, bool enabled);
```

**Parameters:**
- `lineId` (`String`): ID of the polyline to modify
- `enabled` (`bool`): Whether editing should be enabled

**Example:**
```dart
// Enable editing
await controller.enablePolylineEditing('route-1', true);

// Disable editing
await controller.enablePolylineEditing('route-1', false);
```

#### `setPolylineEditingStyle`

Configure global editing style for all editable polylines.

```dart
Future<void> setPolylineEditingStyle(PolylineEditingStyle style);
```

**Parameters:**
- `style` (`PolylineEditingStyle`): Style configuration

**Example:**
```dart
final style = PolylineEditingStyle(
  breakPointColor: '#FFFF00',
  breakPointRadius: 12.0,
  previewLineColor: '#0000FF',
  previewLineOpacity: 0.8,
  enableHapticFeedback: true,
);

await controller.setPolylineEditingStyle(style);
```

#### `isPolylineEditable`

Check whether a polyline is currently editable.

```dart
Future<bool> isPolylineEditable(String lineId);
```

**Parameters:**
- `lineId` (`String`): ID of the polyline to check

**Returns:**
- `Future<bool>`: Whether the polyline is editable

**Example:**
```dart
final isEditable = await controller.isPolylineEditable('route-1');
if (isEditable) {
  print('Route 1 can be edited');
}
```

## Error Handling

### Error Types

The editing system can encounter various types of errors:

#### Gesture Recognition Errors
- **Invalid Touch Location**: Touch doesn't intersect with editable polyline
- **Handling**: Silently ignored, no visual feedback

#### Geometric Calculation Errors
- **Polyline Too Short**: Polyline has insufficient points for breaking
- **Handling**: Error callback triggered with descriptive message

#### Platform Integration Errors
- **Native SDK Errors**: MapLibre SDK operations fail
- **Handling**: Error callback triggered, graceful degradation

### Error Callback Example

```dart
final callbacks = PolylineEditingCallbacks(
  onEditingError: (lineId, error) {
    switch (error) {
      case 'POLYLINE_TOO_SHORT':
        showUserMessage('Route is too short to edit');
        break;
      case 'GEOMETRIC_CALCULATION_FAILED':
        showUserMessage('Unable to calculate break point');
        break;
      case 'NATIVE_SDK_ERROR':
        showUserMessage('Map editing temporarily unavailable');
        break;
      default:
        showUserMessage('Editing error: $error');
    }
  },
);
```

## Platform-Specific Notes

### Android Implementation ✅ **Fully Implemented**
- Real `PolylineEditingManager.java` for comprehensive state management
- Native `OnMapLongClickListener` for precise long press detection
- `SymbolLayer` break point markers with real-time dragging
- Geometric calculations for polyline intersection and distance
- Complete integration with MapLibre Android SDK gesture system

### iOS Implementation ✅ **Fully Implemented**
- Real `PolylineEditingManager.swift` with MLNMapView integration
- `UILongPressGestureRecognizer` and `UIPanGestureRecognizer` for gestures
- `MLNAnnotation` objects for break point visualization
- Core Animation transitions and haptic feedback via Taptic Engine
- Complete method channel integration with Flutter layer

### Web Platform
- Interactive polyline editing is **not supported** on web platform
- Feature gracefully degrades - polylines remain non-editable
- No errors thrown when editing properties are used

## Performance Considerations

### Large Polylines
- Polylines with 1000+ points may experience performance impact
- Consider implementing point simplification for complex routes
- Use reasonable break point detection thresholds

### Memory Management
- Editing sessions are automatically cleaned up when complete
- Break point markers are removed when editing ends
- No manual cleanup required in most cases

### Optimization Tips
```dart
// For large polylines, consider simplifying geometry
final simplifiedRoute = simplifyPolyline(complexRoute, tolerance: 0.001);

// Use appropriate styling for performance
final efficientStyle = PolylineEditingStyle(
  breakPointRadius: 8.0,  // Reasonable size
  previewLineWidth: 3.0,  // Not too thick
  enableHapticFeedback: Platform.isIOS, // Only where supported
);
```

## Migration Guide

### From Non-Editable Polylines

To add editing to existing polylines:

```dart
// Before (non-editable)
final lineOptions = LineOptions(
  geometry: routeCoordinates,
  lineColor: '#0066CC',
  lineWidth: 4.0,
);

// After (editable)
final lineOptions = LineOptions(
  geometry: routeCoordinates,
  lineColor: '#0066CC',
  lineWidth: 4.0,
  editable: true,  // Enable editing
  editingCallbacks: PolylineEditingCallbacks(
    onPolylineBroken: handlePolylineBreak,
    onPolylineModified: handlePolylineModify,
  ),
);
```

### Backward Compatibility
- All existing polyline functionality remains unchanged
- New editing properties are optional and default to non-editable
- No breaking changes to existing API

## Troubleshooting

### Common Issues

#### Editing Not Working
- Ensure `editable: true` is set in `LineOptions`
- Verify platform is Android or iOS (not web)
- Check that callbacks are properly configured

#### Visual Feedback Missing
- Verify break point styling properties are set
- Check that preview line colors are visible against map background
- Ensure adequate break point radius for touch targets

#### Performance Issues
- Reduce polyline complexity for large routes
- Optimize break point detection sensitivity
- Consider disabling haptic feedback if not needed

### Debug Information

Enable verbose logging for troubleshooting:

```dart
// Enable debug logging (implementation-specific)
MapLibreMap.enablePolylineEditingDebug = true;
```

## Best Practices

### User Experience
1. **Clear Visual Feedback**: Use contrasting colors for break points and preview lines
2. **Haptic Feedback**: Enable on iOS for better touch feedback
3. **Error Handling**: Provide clear user messages for editing errors
4. **Performance**: Test with realistic polyline sizes and complexities

### Code Organization
1. **Centralized Callbacks**: Create reusable callback handlers
2. **State Management**: Track editing state in your application
3. **Error Recovery**: Implement graceful error handling
4. **Testing**: Include editing scenarios in your test suite

### Example Implementation

```dart
class RouteEditingManager {
  static final PolylineEditingCallbacks callbacks = PolylineEditingCallbacks(
    onPolylineBroken: _handlePolylineBreak,
    onPolylineModified: _handlePolylineModify,
    onEditingError: _handleEditingError,
  );

  static void _handlePolylineBreak(String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    // Update route database
    RouteDatabase.splitRoute(lineId, segment1, segment2);
    
    // Notify UI
    EventBus.instance.fire(RouteModifiedEvent(lineId));
  }

  static void _handlePolylineModify(String lineId, List<LatLng> newCoordinates) {
    // Save updated coordinates
    RouteDatabase.updateRoute(lineId, newCoordinates);
    
    // Recalculate route metrics
    RouteCalculator.updateMetrics(lineId, newCoordinates);
  }

  static void _handleEditingError(String lineId, String error) {
    // Log error
    Logger.error('Route editing failed', {'lineId': lineId, 'error': error});
    
    // Show user notification
    NotificationService.showError('Unable to edit route: $error');
  }
}
```

This API reference provides comprehensive documentation for implementing interactive polyline editing in your MapLibre GL Flutter applications.