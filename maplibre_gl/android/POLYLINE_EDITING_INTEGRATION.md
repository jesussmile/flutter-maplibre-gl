# Android Polyline Editing Integration

This document describes the integration between the Android native polyline editing implementation and the Flutter method channels.

## Method Channel Handlers

The Android implementation provides the following method channel handlers in `MapLibreMapController.java`:

### `line#enableEditing`

Enables or disables interactive editing for a specific polyline.

**Parameters:**
- `lineId` (String): The ID of the polyline to modify
- `enabled` (Boolean): Whether editing should be enabled

**Example:**
```dart
await mapController.enablePolylineEditing(line, true);
```

**Android Handler:**
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
  break;
```

### `line#setEditingStyle`

Sets the visual styling for polyline editing operations.

**Parameters:**
- Style map containing styling properties:
  - `breakPointColor` (String): Hex color for break point markers
  - `breakPointRadius` (Double): Radius of break point markers in pixels
  - `breakPointBorderColor` (String): Hex color for break point borders
  - `breakPointBorderWidth` (Double): Width of break point borders in pixels
  - `previewLineColor` (String): Hex color for preview lines
  - `previewLineOpacity` (Double): Opacity of preview lines (0.0-1.0)
  - `previewLineWidth` (Double): Width of preview lines in pixels
  - `enableHapticFeedback` (Boolean): Whether to enable haptic feedback

**Example:**
```dart
await mapController.setPolylineEditingStyle(PolylineEditingStyle(
  breakPointColor: '#FF0000',
  breakPointRadius: 8.0,
  previewLineColor: '#00FF00',
  previewLineOpacity: 0.7,
));
```

**Android Handler:**
```java
case "line#setEditingStyle":
  Map<String, Object> style = call.arguments();
  if (style != null && polylineEditingManager != null) {
    polylineEditingManager.setEditingStyle(style);
    if (polylineRenderer != null) {
      polylineRenderer.updateStyle(style);
    }
    result.success(null);
  } else {
    result.error("INVALID_ARGUMENTS", "style is required", null);
  }
  break;
```

### `line#isEditable`

Checks whether a polyline is currently editable.

**Parameters:**
- `lineId` (String): The ID of the polyline to check

**Returns:**
- `Boolean`: true if the polyline is editable, false otherwise

**Example:**
```dart
bool isEditable = await mapController.isPolylineEditable(line);
```

**Android Handler:**
```java
case "line#isEditable":
  String lineId = call.argument("lineId");
  if (lineId != null && polylineEditingManager != null) {
    boolean isEditable = polylineEditingManager.isLineEditable(lineId);
    result.success(isEditable);
  } else {
    result.error("INVALID_ARGUMENTS", "lineId is required", null);
  }
  break;
```

## Callback Methods

The Android implementation sends callbacks to Flutter using the following method channel invocations:

### `polylineEditing#onBroken`

Called when a polyline is broken into two segments by a long press gesture.

**Parameters:**
- `lineId` (String): The ID of the polyline that was broken
- `segment1` (List<List<Double>>): Coordinates of the first segment
- `segment2` (List<List<Double>>): Coordinates of the second segment

**Coordinate Format:**
Each coordinate is represented as `[latitude, longitude]`.

**Example Callback Data:**
```json
{
  "lineId": "polyline-123",
  "segment1": [
    [37.7749, -122.4194],
    [37.7799, -122.4144]
  ],
  "segment2": [
    [37.7799, -122.4144],
    [37.7849, -122.4094]
  ]
}
```

**Android Implementation:**
```java
public void onPolylineBroken(@NonNull String lineId, @NonNull LatLng breakPoint, 
                            @NonNull List<LatLng> segment1, @NonNull List<LatLng> segment2) {
  List<List<Double>> segment1Coords = convertLatLngListToCoordinates(segment1);
  List<List<Double>> segment2Coords = convertLatLngListToCoordinates(segment2);
  
  Map<String, Object> arguments = new HashMap<>();
  arguments.put("lineId", lineId);
  arguments.put("segment1", segment1Coords);
  arguments.put("segment2", segment2Coords);
  
  methodChannel.invokeMethod("polylineEditing#onBroken", arguments);
}
```

### `polylineEditing#onModified`

Called when a polyline's coordinates are modified through dragging.

**Parameters:**
- `lineId` (String): The ID of the polyline that was modified
- `coordinates` (List<List<Double>>): The updated coordinates of the polyline

**Example Callback Data:**
```json
{
  "lineId": "polyline-123",
  "coordinates": [
    [37.7749, -122.4194],
    [37.7799, -122.4144],
    [37.7849, -122.4094]
  ]
}
```

**Android Implementation:**
```java
public void onPolylineModified(@NonNull String lineId, @NonNull List<LatLng> newCoordinates) {
  List<List<Double>> coordinates = convertLatLngListToCoordinates(newCoordinates);
  
  Map<String, Object> arguments = new HashMap<>();
  arguments.put("lineId", lineId);
  arguments.put("coordinates", coordinates);
  
  methodChannel.invokeMethod("polylineEditing#onModified", arguments);
}
```

### `polylineEditing#onError`

Called when an error occurs during polyline editing.

**Parameters:**
- `lineId` (String): The ID of the polyline where the error occurred
- `error` (String): A descriptive error message

**Example Callback Data:**
```json
{
  "lineId": "polyline-123",
  "error": "Failed to calculate intersection"
}
```

**Android Implementation:**
```java
public void onPolylineEditingError(@NonNull String lineId, @NonNull String error) {
  Map<String, Object> arguments = new HashMap<>();
  arguments.put("lineId", lineId);
  arguments.put("error", error);
  
  methodChannel.invokeMethod("polylineEditing#onError", arguments);
}
```

## Data Conversion

### LatLng to Coordinate Array

The Android implementation converts `LatLng` objects to coordinate arrays for Flutter compatibility:

```java
private List<List<Double>> convertLatLngListToCoordinates(@NonNull List<LatLng> latLngs) {
  List<List<Double>> coordinates = new ArrayList<>();
  for (LatLng latLng : latLngs) {
    List<Double> coord = new ArrayList<>();
    coord.add(latLng.getLatitude());
    coord.add(latLng.getLongitude());
    coordinates.add(coord);
  }
  return coordinates;
}
```

### Error Handling

All method channel handlers include proper error handling:

- **Invalid Arguments**: Returns `INVALID_ARGUMENTS` error when required parameters are missing
- **Null Checks**: Validates that required objects (editing manager, renderer) are initialized
- **Exception Handling**: Catches and logs exceptions during processing

## Integration Flow

1. **Flutter Layer**: User calls editing methods on `MapLibreMapController`
2. **Method Channel**: Flutter sends method call to Android via platform channel
3. **Android Handler**: `MapLibreMapController.onMethodCall()` processes the request
4. **Native Processing**: Android editing components perform the requested operation
5. **Callback**: Android sends results back to Flutter via method channel callbacks
6. **Flutter Callback**: Flutter layer triggers appropriate callback functions

## Visual Feedback Integration

The Android implementation automatically manages visual feedback:

- **Break Point Markers**: Shown when polylines are broken
- **Preview Lines**: Displayed during drag operations
- **Style Updates**: Applied when editing style is changed
- **Cleanup**: Visual elements are automatically cleaned up on completion or error

## Testing

The integration includes comprehensive tests:

- **Method Channel Tests**: Verify correct parameter handling and response formatting
- **Callback Tests**: Ensure callbacks are triggered with correct data
- **Error Handling Tests**: Validate error scenarios are properly handled
- **Data Integrity Tests**: Confirm coordinate conversion maintains accuracy

## Performance Considerations

- **Efficient Updates**: Visual feedback uses optimized GeoJsonSource updates
- **Memory Management**: Proper cleanup of editing sessions and visual elements
- **Thread Safety**: All operations are performed on the main thread
- **Batch Operations**: Multiple coordinate updates are batched for efficiency