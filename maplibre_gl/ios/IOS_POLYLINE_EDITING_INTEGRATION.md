# iOS Polyline Editing Integration

This document describes the iOS implementation of interactive polyline editing for the MapLibre Flutter plugin.

## Overview

The iOS polyline editing implementation provides equivalent functionality to the Android version, allowing users to interactively edit polylines by long pressing to create break points and dragging them to modify the polyline path.

## Architecture

The iOS implementation consists of four main components:

### 1. PolylineEditingManager.swift

Manages the editing state and configuration for all polylines on the map.

**Key Features:**
- Tracks which polylines are editable
- Stores editing configuration and style
- Provides methods to enable/disable editing for specific polylines
- Manages global editing style settings

**Main Methods:**
- `enableLineEditing(lineId:enabled:)` - Enable/disable editing for a polyline
- `setEditingStyle(style:)` - Configure visual styling
- `isLineEditable(lineId:)` - Check if a polyline is editable
- `updateLineCoordinates(lineId:coordinates:)` - Update polyline coordinates

### 2. PolylineGestureHandler.swift

Handles gesture recognition using UILongPressGestureRecognizer and UIPanGestureRecognizer.

**Key Features:**
- Long press detection on polylines using MLNMapView hit testing
- Drag gesture handling with real-time coordinate updates
- Coordinate calculations using CoreLocation for geometric operations
- Haptic feedback integration for enhanced user experience

**Gesture Flow:**
1. Long press detected → Find nearest editable polyline → Create break point
2. Pan gesture begins → Check if dragging a break point → Start drag operation
3. Pan gesture changes → Update break point position → Show preview line
4. Pan gesture ends → Finalize coordinates → Notify delegate

### 3. PolylineBreakPointSystem.swift

Manages break points and provides geometric calculations.

**Key Features:**
- Break point creation using MLNAnnotation objects
- Polyline splitting logic compatible with MLNPolyline geometry
- Geometric utility methods for distance calculations and coordinate validation
- Break point tracking and management

**Geometric Calculations:**
- Haversine formula for distance calculations
- Nearest point on line segment calculations
- Polyline length and simplification algorithms
- Coordinate validation and bounds checking

### 4. EditablePolylineRenderer.swift

Manages visual feedback using MLNAnnotationView customization.

**Key Features:**
- Break point marker styling and rendering
- Preview line rendering during drag operations with MLNPolyline styling
- Visual state management for active editing sessions
- Smooth Core Animation transitions for editing operations

**Visual Elements:**
- Break point markers with customizable color, size, and border
- Preview lines with configurable color, opacity, and width
- Animated break point appearance and scaling effects

## Integration with MapLibreMapController

The polyline editing components are integrated into the main `MapLibreMapController.swift`:

### Initialization

Components are initialized in the `mapView(_:didFinishLoading:)` delegate method:

```swift
private func initializePolylineEditing() {
    polylineEditingManager = PolylineEditingManager(mapView: mapView)
    polylineBreakPointSystem = PolylineBreakPointSystem(mapView: mapView)
    polylineRenderer = EditablePolylineRenderer(mapView: mapView)
    polylineRenderer?.initialize()
    
    if let editingManager = polylineEditingManager,
       let breakPointSystem = polylineBreakPointSystem,
       let renderer = polylineRenderer {
        polylineGestureHandler = PolylineGestureHandler(
            mapView: mapView,
            editingManager: editingManager,
            breakPointSystem: breakPointSystem,
            renderer: renderer
        )
        polylineGestureHandler?.delegate = self
    }
}
```

### Method Channel Integration

The following method channel handlers are implemented:

#### `line#enableEditing`
- **Parameters:** `lineId` (String), `enabled` (Bool)
- **Function:** Enables or disables editing for a specific polyline
- **Implementation:** Calls `PolylineEditingManager.enableLineEditing()`

#### `line#setEditingStyle`
- **Parameters:** `style` (Dictionary)
- **Function:** Sets visual styling for editing operations
- **Implementation:** Updates both `PolylineEditingManager` and `EditablePolylineRenderer`

#### `line#isEditable`
- **Parameters:** `lineId` (String)
- **Returns:** Boolean indicating if the polyline is editable
- **Implementation:** Calls `PolylineEditingManager.isLineEditable()`

### Callback Integration

The iOS implementation sends callbacks to Flutter through the method channel:

#### `polylineEditing#onBroken`
Called when a polyline is broken into two segments.

#### `polylineEditing#onModified`
Called when a polyline's coordinates are modified through dragging.

#### `polylineEditing#onError`
Called when an error occurs during polyline editing.

## Platform-Specific Features

### Haptic Feedback
The iOS implementation includes haptic feedback using `UIImpactFeedbackGenerator` when break points are created, providing tactile feedback to enhance the user experience.

### Core Animation
Smooth animations are implemented using Core Animation for break point appearance and scaling effects.

### MLNMapView Integration
The implementation leverages MLNMapView's native coordinate conversion methods and hit testing capabilities for accurate gesture recognition.

## Configuration

### Default Style Settings
```swift
private func setupDefaultStyle() {
    globalEditingStyle = [
        "breakPointColor": "#FF0000",
        "breakPointRadius": 8.0,
        "breakPointBorderColor": "#FFFFFF",
        "breakPointBorderWidth": 2.0,
        "previewLineColor": "#00FF00",
        "previewLineOpacity": 0.7,
        "previewLineWidth": 3.0,
        "enableHapticFeedback": true
    ]
}
```

### Gesture Configuration
- Long press minimum duration: 0.5 seconds
- Hit test tolerance: 20.0 points
- Simultaneous gesture recognition enabled

## Error Handling

The iOS implementation includes comprehensive error handling:

- **Invalid Arguments:** Returns `INVALID_ARGUMENTS` FlutterError
- **Not Initialized:** Returns `NOT_INITIALIZED` FlutterError when components aren't ready
- **Native Errors:** Returns `NATIVE_ERROR` FlutterError for native operation failures

## Testing

Unit tests are provided for the core components:

- `PolylineEditingManagerTests.swift` - Tests editing manager functionality
- `PolylineBreakPointSystemTests.swift` - Tests geometric calculations and break point management

## Performance Considerations

- Efficient hit testing using spatial indexing
- Coordinate validation to prevent invalid operations
- Memory management for break points and visual elements
- Optimized rendering using MLNShapeSource updates

## Compatibility

- **iOS Version:** iOS 9.0+
- **MapLibre iOS SDK:** Compatible with current MapLibre iOS SDK version
- **Swift Version:** Swift 5.0+
- **Xcode:** Xcode 12.0+

## Future Enhancements

Potential improvements for future versions:

1. **Multi-touch Support:** Support for editing multiple polylines simultaneously
2. **Undo/Redo:** Implementation of editing history and undo functionality
3. **Snapping:** Snap break points to nearby features or grid
4. **Advanced Gestures:** Support for pinch-to-scale and rotation gestures
5. **Performance Optimization:** Further optimization for complex polylines with many points