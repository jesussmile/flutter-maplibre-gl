# Method Channel Integration for Polyline Editing

This document explains how the Android polyline editing implementation integrates with Flutter through method channels.

## Overview

The polyline editing functionality is integrated with Flutter through the MapLibreMapController's method channel handler. When Flutter calls polyline editing methods, they are routed to the native Android implementation.

## Method Channel Handlers

The following method channel handlers are implemented in `MapLibreMapController.java`:

### `line#enableEditing`

Enables or disables interactive editing for a specific polyline.

**Parameters:**
- `lineId` (String): ID of the polyline to enable/disable editing for
- `enabled` (boolean): Whether to enable or disable editing

**Implementation:**
```java
case "line#enableEditing":
  String lineId = call.argument("lineId");
  Boolean enabled = call.argument("enabled");
  if (lineId != null && enabled != null && polylineEditingManager != null) {
    polylineEditingManager.enableLineEditing(lineId, enabled);
    result.success(null);
  } else {
    result.error("INVALID_ARGUMENTS", "lineId and enabled are required", null);
  }
```

### `line#setEditingStyle`

Sets the visual styling for polyline editing operations.

**Parameters:**
- `style` (Map<String, Object>): Style configuration containing:
  - `breakPointColor`: Color of break point markers
  - `breakPointRadius`: Size of break point markers  
  - `previewLineColor`: Color of preview lines during dragging
  - `previewLineOpacity`: Opacity of preview lines

**Implementation:**
```java
case "line#setEditingStyle":
  Map<String, Object> style = call.arguments();
  if (style != null && polylineEditingManager != null) {
    polylineEditingManager.setEditingStyle(style);
    if (polylineRenderer != null) {
      polylineRenderer.updateStyle(style);
    }
    result.success(null);
  }
```

### `line#isEditable`

Checks whether interactive editing is currently enabled for a specific polyline.

**Parameters:**
- `lineId` (String): ID of the polyline to check

**Returns:**
- `boolean`: Whether editing is enabled for the polyline

**Implementation:**
```java
case "line#isEditable":
  String lineId = call.argument("lineId");
  if (lineId != null && polylineEditingManager != null) {
    boolean isEditable = polylineEditingManager.isLineEditable(lineId);
    result.success(isEditable);
  }
```

## Callback Integration

The Android implementation sends callbacks to Flutter through the method channel when editing events occur:

### `polylineEditing#onBroken`

Called when a polyline is broken into two segments.

**Parameters:**
- `lineId` (String): ID of the polyline that was broken
- `segment1` (List<List<Double>>): Coordinates of the first segment
- `segment2` (List<List<Double>>): Coordinates of the second segment

### `polylineEditing#onModified`

Called when a polyline's coordinates are modified through dragging.

**Parameters:**
- `lineId` (String): ID of the polyline that was modified
- `coordinates` (List<List<Double>>): New coordinates of the polyline

### `polylineEditing#onError`

Called when an error occurs during polyline editing.

**Parameters:**
- `lineId` (String): ID of the polyline where the error occurred
- `error` (String): Error message

## Component Integration

The method channel handlers interact with the following components:

1. **PolylineEditingManager**: Manages editing state and configuration
2. **PolylineGestureDetector**: Handles gesture recognition and triggers callbacks
3. **PolylineBreakPointSystem**: Manages break point creation and manipulation
4. **EditablePolylineRenderer**: Provides visual feedback during editing

## Initialization

The polyline editing components are initialized in the `onMapReady` method:

```java
@Override
public void onMapReady(MapLibreMap mapLibreMap) {
  // ... existing initialization ...
  
  // Initialize polyline editing manager
  polylineEditingManager = new PolylineEditingManager(mapLibreMap);
  
  // Initialize polyline break point system
  polylineBreakPointSystem = new PolylineBreakPointSystem(mapLibreMap);
  
  // Initialize polyline renderer
  polylineRenderer = new EditablePolylineRenderer(mapLibreMap);
  
  // Initialize polyline gesture detector
  polylineGestureDetector = new PolylineGestureDetector(
      mapLibreMap, 
      polylineEditingManager, 
      polylineBreakPointSystem,
      polylineRenderer,
      new PolylineGestureListener()
  );
}
```

## Error Handling

All method channel handlers include comprehensive error handling:

- **Invalid Arguments**: Returns `INVALID_ARGUMENTS` error when required parameters are missing
- **Native Errors**: Returns `NATIVE_ERROR` when native operations fail
- **Null Checks**: Verifies that required components are initialized before use

## Flutter Integration

On the Flutter side, the LineManager automatically registers editable lines with the polyline editing manager when they are added with `editable: true` in their LineOptions.

The integration ensures that:
1. Editable lines are automatically registered when added
2. Editing is disabled when lines are removed
3. Style changes are applied when lines are updated
4. Callbacks are properly routed to the line's editing callbacks