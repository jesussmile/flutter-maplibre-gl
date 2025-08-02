# Interactive Polyline Editing Usage Guide

This guide provides practical examples and best practices for implementing interactive polyline editing in your MapLibre GL Flutter applications.

✅ **Real Implementation** - All features of interactive polyline editing are now production-ready, including real native gesture support, cross-platform consistency, and robust error handling.

## How It Works

### User Interaction Flow
1. **Long Press**: User long presses on any point along an editable polyline
2. **Break Point Creation**: An orange break point marker appears at the touch location
3. **Drag Operation**: User can drag the break point to reshape the line
4. **Real-time Updates**: The polyline updates in real-time, maintaining the path from start → break point → end
5. **Completion**: When user releases, the final coordinates are saved

### Technical Details
- Original 2-point line becomes a 3-point line: [start, break_point, end]
- Break point visual (orange circle) follows drag operations
- Real-time coordinate updates are sent to Flutter during dragging
- Original coordinates are preserved for proper line structure
- No conflicting preview lines - only the actual polyline updates

## Quick Start

### Basic Setup

1. **Add an editable polyline to your map:**

```dart
class MyMapPage extends StatefulWidget {
  @override
  _MyMapPageState createState() => _MyMapPageState();
}

class _MyMapPageState extends State<MyMapPage> {
  MapLibreMapController? controller;

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  Future<void> _onStyleLoaded() async {
    // Create editable flight route
    final route = [
      LatLng(37.7749, -122.4194), // San Francisco
      LatLng(40.7128, -74.0060),  // New York
      LatLng(51.5074, -0.1278),   // London
    ];

    await controller!.addLine(
      LineOptions(
        geometry: route,
        lineColor: '#0066CC',
        lineWidth: 4.0,
        editable: true, // Enable editing
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineBroken: (lineId, segment1, segment2) {
            print('Route broken: ${segment1.length} + ${segment2.length}');
          },
          onPolylineModified: (lineId, coordinates) {
            print('Route modified: ${coordinates.length} points');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapLibreMap(
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        initialCameraPosition: CameraPosition(
          target: LatLng(40.0, -40.0),
          zoom: 3.0,
        ),
      ),
    );
  }
}
```

### User Interaction

Users can now:
- **Long press** on any point along the blue route to create an orange break point
- **Drag** the orange break point to reshape the route
- See **real-time line updates** during drag operations - the line goes from start → break point → end
- **Release** to finalize the edit

## Common Use Cases

### 1. Flight Route Planning

Perfect for aviation apps where pilots need to modify flight paths:

```dart
class FlightRouteEditor extends StatefulWidget {
  final List<Airport> airports;
  
  const FlightRouteEditor({Key? key, required this.airports}) : super(key: key);

  @override
  _FlightRouteEditorState createState() => _FlightRouteEditorState();
}

class _FlightRouteEditorState extends State<FlightRouteEditor> {
  MapLibreMapController? controller;
  List<FlightRoute> routes = [];

  Future<void> _addFlightRoute(String departureICAO, String arrivalICAO) async {
    final departure = widget.airports.firstWhere((a) => a.icao == departureICAO);
    final arrival = widget.airports.firstWhere((a) => a.icao == arrivalICAO);
    
    final routeCoordinates = [
      LatLng(departure.latitude, departure.longitude),
      LatLng(arrival.latitude, arrival.longitude),
    ];

    final line = await controller!.addLine(
      LineOptions(
        geometry: routeCoordinates,
        lineColor: '#FF6600',
        lineWidth: 4.0,
        editable: true,
        breakPointColor: '#FF0000',
        breakPointRadius: 12.0,
        previewLineColor: '#FFB366',
        previewLineOpacity: 0.8,
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineBroken: _handleRouteBreak,
          onPolylineModified: _handleRouteModify,
          onEditingError: _handleRouteError,
        ),
      ),
    );

    setState(() {
      routes.add(FlightRoute(
        id: line.id,
        departure: departure,
        arrival: arrival,
        coordinates: routeCoordinates,
      ));
    });
  }

  void _handleRouteBreak(String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    // Break point created - this is called once when long press creates the break point
    final route = routes.firstWhere((r) => r.id == lineId);
    
    // The break point coordinate is the last point of segment1 (or first of segment2)
    final breakPoint = segment1.last;
    
    print('Break point created on route ${route.departure.icao} → ${route.arrival.icao}');
    print('Break point location: ${breakPoint.latitude}, ${breakPoint.longitude}');
    
    // Optionally add waypoint to flight plan
    _addWaypoint(route, breakPoint);
  }

  void _handleRouteModify(String lineId, List<LatLng> newCoordinates) {
    // Real-time coordinate updates during drag and final update on completion
    final routeIndex = routes.indexWhere((r) => r.id == lineId);
    if (routeIndex != -1) {
      // newCoordinates will always have 3 points: [start, current_break_point, end]
      final startPoint = newCoordinates[0];
      final breakPoint = newCoordinates[1];  // This is where the user is dragging
      final endPoint = newCoordinates[2];
      
      setState(() {
        routes[routeIndex] = routes[routeIndex].copyWith(
          coordinates: newCoordinates,
        );
      });
      
      // Recalculate flight plan with new break point
      _recalculateFlightPlan(routes[routeIndex]);
      
      // Update distance and time estimates
      _updateFlightMetrics(routes[routeIndex], breakPoint);
    }
  }

  void _handleRouteError(String lineId, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Route editing failed: $error')),
    );
  }
}
```

### 2. Delivery Route Optimization

For logistics and delivery applications:

```dart
class DeliveryRouteManager {
  final MapLibreMapController controller;
  final List<DeliveryStop> stops;
  
  DeliveryRouteManager(this.controller, this.stops);

  Future<void> createOptimizedRoute() async {
    // Create initial route through all stops
    final routeCoordinates = stops.map((stop) => 
      LatLng(stop.latitude, stop.longitude)
    ).toList();

    await controller.addLine(
      LineOptions(
        geometry: routeCoordinates,
        lineColor: '#00AA00',
        lineWidth: 3.0,
        editable: true,
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineModified: _optimizeRoute,
          onEditingError: _handleOptimizationError,
        ),
      ),
    );
  }

  void _optimizeRoute(String lineId, List<LatLng> newCoordinates) {
    // Real-time route optimization during drag operations
    // newCoordinates structure: [start, current_break_point, end]
    
    if (newCoordinates.length == 3) {
      final detourPoint = newCoordinates[1]; // The break point being dragged
      
      // Recalculate delivery times and distances with detour
      final optimizedRoute = RouteOptimizer.optimizeWithDetour(
        newCoordinates, 
        stops, 
        detourPoint
      );
      
      // Update delivery schedule in real-time
      DeliveryScheduler.updateSchedule(optimizedRoute);
      
      // Show estimated time impact to driver
      final timeImpact = calculateTimeImpact(originalRoute, optimizedRoute);
      _showTimeImpactToDriver(timeImpact);
    }
  }

  void _handleOptimizationError(String lineId, String error) {
    Logger.error('Route optimization failed', {'error': error});
    
    // Revert to previous route if possible
    _revertToPreviousRoute(lineId);
  }
}
```

### 3. Hiking Trail Editor

For outdoor and recreation apps:

```dart
class TrailEditor extends StatefulWidget {
  @override
  _TrailEditorState createState() => _TrailEditorState();
}

class _TrailEditorState extends State<TrailEditor> {
  MapLibreMapController? controller;
  Trail? currentTrail;
  bool isRecording = false;

  Future<void> _startTrailRecording() async {
    setState(() {
      isRecording = true;
      currentTrail = Trail(
        id: generateTrailId(),
        coordinates: [],
        difficulty: TrailDifficulty.moderate,
      );
    });
  }

  Future<void> _finishTrailRecording() async {
    if (currentTrail == null) return;

    // Make the recorded trail editable
    final line = await controller!.addLine(
      LineOptions(
        geometry: currentTrail!.coordinates,
        lineColor: '#8B4513', // Brown for trail
        lineWidth: 4.0,
        editable: true,
        breakPointColor: '#FFD700', // Gold break points
        breakPointRadius: 10.0,
        previewLineColor: '#DEB887',
        previewLineOpacity: 0.8,
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineBroken: _handleTrailSplit,
          onPolylineModified: _handleTrailModification,
          onEditingError: _handleTrailError,
        ),
      ),
    );

    setState(() {
      isRecording = false;
      currentTrail = currentTrail!.copyWith(lineId: line.id);
    });
  }

  void _handleTrailSplit(String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    // Trail was split - create two separate trail segments
    _createTrailSegment('${lineId}-1', segment1);
    _createTrailSegment('${lineId}-2', segment2);
    
    // Remove original trail
    controller!.removeLine(Line(id: lineId));
  }

  void _handleTrailModification(String lineId, List<LatLng> newCoordinates) {
    // Trail was modified - recalculate metrics in real-time
    // During drag: newCoordinates = [start, current_break_point, end]
    
    final distance = TrailCalculator.calculateDistance(newCoordinates);
    final elevation = TrailCalculator.calculateElevationGain(newCoordinates);
    final difficulty = TrailCalculator.assessDifficulty(distance, elevation);

    // Show real-time metrics to user during drag
    _updateTrailMetricsDisplay(distance, elevation, difficulty);

    setState(() {
      currentTrail = currentTrail!.copyWith(
        coordinates: newCoordinates,
        distance: distance,
        elevationGain: elevation,
        difficulty: difficulty,
      );
    });

    // Update trail database (consider debouncing for performance)
    _debouncedUpdate(() => TrailDatabase.updateTrail(currentTrail!));
  }

  void _handleTrailError(String lineId, String error) {
    // Handle trail editing errors gracefully
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Trail Editing Error'),
        content: Text('Unable to modify trail: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
```

## Advanced Configuration

### Custom Styling

Customize the appearance of editing elements:

```dart
class CustomStyledEditor {
  static const nightModeStyle = PolylineEditingStyle(
    breakPointColor: '#FFD700',      // Gold break points
    breakPointRadius: 14.0,          // Larger for night visibility
    breakPointBorderColor: '#000000', // Black border
    breakPointBorderWidth: 3.0,      // Thicker border
    previewLineColor: '#FFFFFF',     // White preview
    previewLineOpacity: 0.9,         // High opacity
    previewLineWidth: 5.0,           // Thicker preview
    enableHapticFeedback: true,      // Enhanced feedback
  );

  static const dayModeStyle = PolylineEditingStyle(
    breakPointColor: '#FF4444',      // Red break points
    breakPointRadius: 10.0,          // Standard size
    breakPointBorderColor: '#FFFFFF', // White border
    breakPointBorderWidth: 2.0,      // Standard border
    previewLineColor: '#44FF44',     // Green preview
    previewLineOpacity: 0.7,         // Standard opacity
    previewLineWidth: 3.0,           // Standard width
    enableHapticFeedback: false,     // Minimal feedback
  );

  static Future<void> applyStyle(
    MapLibreMapController controller,
    bool isDarkMode,
  ) async {
    final style = isDarkMode ? nightModeStyle : dayModeStyle;
    await controller.setPolylineEditingStyle(style);
  }
}
```

### Dynamic Editing Control

Enable/disable editing based on user permissions or context:

```dart
class RouteAccessManager {
  final MapLibreMapController controller;
  final Map<String, bool> editPermissions = {};

  RouteAccessManager(this.controller);

  Future<void> setRouteEditable(String routeId, bool editable) async {
    editPermissions[routeId] = editable;
    await controller.enablePolylineEditing(routeId, editable);
  }

  Future<void> updatePermissions(UserRole role) async {
    switch (role) {
      case UserRole.admin:
        // Admins can edit all routes
        for (final routeId in editPermissions.keys) {
          await setRouteEditable(routeId, true);
        }
        break;
      
      case UserRole.editor:
        // Editors can edit specific routes
        final editableRoutes = await getEditableRoutesForUser();
        for (final routeId in editPermissions.keys) {
          final canEdit = editableRoutes.contains(routeId);
          await setRouteEditable(routeId, canEdit);
        }
        break;
      
      case UserRole.viewer:
        // Viewers can't edit any routes
        for (final routeId in editPermissions.keys) {
          await setRouteEditable(routeId, false);
        }
        break;
    }
  }
}
```

### Performance Optimization

For applications with many or complex polylines:

```dart
class PerformanceOptimizedEditor {
  static const int MAX_POINTS_FOR_EDITING = 1000;
  static const double SIMPLIFICATION_TOLERANCE = 0.001;

  static Future<Line> addOptimizedEditableRoute(
    MapLibreMapController controller,
    List<LatLng> coordinates,
    String lineColor,
  ) async {
    // Simplify if too complex
    List<LatLng> optimizedCoordinates = coordinates;
    if (coordinates.length > MAX_POINTS_FOR_EDITING) {
      optimizedCoordinates = simplifyPolyline(
        coordinates,
        tolerance: SIMPLIFICATION_TOLERANCE,
      );
    }

    return await controller.addLine(
      LineOptions(
        geometry: optimizedCoordinates,
        lineColor: lineColor,
        lineWidth: 3.0,
        editable: true,
        // Use efficient styling
        breakPointRadius: 8.0,  // Not too large
        previewLineWidth: 3.0,  // Reasonable width
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineModified: (lineId, newCoords) {
            // Batch updates to avoid frequent redraws
            _batchUpdateRoute(lineId, newCoords);
          },
        ),
      ),
    );
  }

  static void _batchUpdateRoute(String lineId, List<LatLng> coordinates) {
    // Debounce updates to improve performance
    Timer(Duration(milliseconds: 500), () {
      RouteDatabase.updateRoute(lineId, coordinates);
    });
  }

  static List<LatLng> simplifyPolyline(List<LatLng> points, {required double tolerance}) {
    // Implement Douglas-Peucker algorithm or similar
    // This is a simplified example
    if (points.length <= 2) return points;
    
    List<LatLng> simplified = [points.first];
    
    for (int i = 1; i < points.length - 1; i += 2) {
      simplified.add(points[i]);
    }
    
    simplified.add(points.last);
    return simplified;
  }
}
```

## Error Handling Patterns

### Graceful Degradation

Handle errors elegantly without breaking user experience:

```dart
class RobustRouteEditor {
  final MapLibreMapController controller;
  final StreamController<String> errorStream = StreamController.broadcast();

  RobustRouteEditor(this.controller) {
    // Listen for errors and handle them
    errorStream.stream.listen(_handleGlobalError);
  }

  PolylineEditingCallbacks get robustCallbacks => PolylineEditingCallbacks(
    onEditingError: (lineId, error) {
      errorStream.add('$lineId: $error');
    },
    onPolylineBroken: (lineId, segment1, segment2) {
      try {
        _handlePolylineBreak(lineId, segment1, segment2);
      } catch (e) {
        errorStream.add('$lineId: Failed to process break - $e');
      }
    },
    onPolylineModified: (lineId, coordinates) {
      try {
        _handlePolylineModification(lineId, coordinates);
      } catch (e) {
        errorStream.add('$lineId: Failed to process modification - $e');
      }
    },
  );

  void _handleGlobalError(String error) {
    final parts = error.split(': ');
    final lineId = parts[0];
    final errorMessage = parts.length > 1 ? parts[1] : 'Unknown error';

    switch (errorMessage) {
      case 'POLYLINE_TOO_SHORT':
        _showUserMessage('Route is too short to modify');
        break;
      case 'GEOMETRIC_CALCULATION_FAILED':
        _disableEditingTemporarily(lineId);
        break;
      case 'NATIVE_SDK_ERROR':
        _restartEditingSystem();
        break;
      default:
        _logErrorForDebugging(lineId, errorMessage);
    }
  }

  void _showUserMessage(String message) {
    // Show non-blocking notification to user
    OverlayService.showToast(message);
  }

  void _disableEditingTemporarily(String lineId) async {
    await controller.enablePolylineEditing(lineId, false);
    
    // Re-enable after delay
    Timer(Duration(seconds: 5), () async {
      await controller.enablePolylineEditing(lineId, true);
    });
  }

  void _restartEditingSystem() {
    // Restart the editing system
    // Implementation depends on your architecture
  }

  void _logErrorForDebugging(String lineId, String error) {
    Logger.error('Polyline editing error', {
      'lineId': lineId,
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

## Testing Strategies

### Unit Testing Callbacks

Test your editing logic without the map:

```dart
class RouteEditorTest {
  group('Route editing callbacks', () {
    test('should handle polyline break correctly', () {
      final editor = RouteEditor();
      final segment1 = [LatLng(0, 0), LatLng(1, 1)];
      final segment2 = [LatLng(1, 1), LatLng(2, 2)];

      editor.handlePolylineBreak('test-route', segment1, segment2);

      expect(editor.routes['test-route'].segments, hasLength(2));
      expect(editor.routes['test-route'].segments[0], equals(segment1));
      expect(editor.routes['test-route'].segments[1], equals(segment2));
    });

    test('should validate coordinates on modification', () {
      final editor = RouteEditor();
      final invalidCoords = []; // Empty coordinates

      expect(
        () => editor.handlePolylineModification('test-route', invalidCoords),
        throwsA(isA<InvalidRouteException>()),
      );
    });
  });
}
```

### Integration Testing

Test the complete editing workflow:

```dart
testWidgets('polyline editing integration test', (WidgetTester tester) async {
  await tester.pumpWidget(MyRouteApp());
  
  // Wait for map to load
  await tester.pumpAndSettle();
  
  // Find the map widget
  final mapFinder = find.byType(MapLibreMap);
  expect(mapFinder, findsOneWidget);
  
  // Simulate long press on polyline
  await tester.longPress(mapFinder);
  await tester.pumpAndSettle();
  
  // Verify break point is created
  // Note: This requires custom test hooks in your implementation
  expect(find.byKey(Key('break-point')), findsOneWidget);
  
  // Simulate drag gesture
  await tester.drag(find.byKey(Key('break-point')), Offset(50, 50));
  await tester.pumpAndSettle();
  
  // Verify route was modified
  final routeEditor = tester.widget<RouteEditor>(find.byType(RouteEditor));
  expect(routeEditor.hasModifiedRoutes, isTrue);
});
```

## Best Practices Summary

1. **User Experience**
   - Provide clear visual feedback during editing
   - Use appropriate colors and sizes for break points
   - Enable haptic feedback on supported platforms

2. **Performance**
   - Simplify complex polylines before enabling editing
   - Batch coordinate updates to avoid frequent redraws
   - Use reasonable styling parameters

3. **Error Handling**
   - Implement comprehensive error callbacks
   - Provide graceful degradation for edge cases
   - Log errors for debugging without breaking UX

4. **Code Organization**
   - Create reusable callback handlers
   - Separate editing logic from UI components
   - Use consistent naming conventions

5. **Testing**
   - Test callback logic independently
   - Include integration tests for complete workflows
   - Verify error handling scenarios

This guide provides the foundation for implementing robust interactive polyline editing in your MapLibre GL Flutter applications. Adapt the examples to fit your specific use case and requirements.