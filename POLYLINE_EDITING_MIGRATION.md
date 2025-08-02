# Migration Guide: Adding Interactive Polyline Editing

This guide helps you migrate existing MapLibre GL Flutter applications to support interactive polyline editing.

## Overview

✅ **Production Ready Feature** - The Interactive Polyline Editing feature is fully implemented with real native gesture detection, cross-platform consistency, and comprehensive testing. 

The feature is fully backward compatible. Existing polylines will continue to work without changes, and editing is opt-in through new optional properties.

## Migration Steps

### Step 1: Update Dependencies

Ensure you're using a version of `maplibre_gl` that includes the complete polyline editing implementation:

```yaml
# pubspec.yaml
dependencies:
  maplibre_gl: ^0.20.0  # Replace with actual version supporting real editing
```

Run `flutter pub get` to update dependencies.

**✅ What's Included:**
- Real native gesture detection on Android and iOS
- Actual break point creation and dragging
- Complete method channel integration
- Production-ready error handling
- Cross-platform visual consistency

### Step 2: Identify Polylines to Make Editable

Review your existing code and identify which polylines should support editing:

**Before (Non-editable polylines):**
```dart
// Existing static route display
final route = await controller.addLine(
  LineOptions(
    geometry: [
      LatLng(37.7749, -122.4194),
      LatLng(40.7128, -74.0060),
    ],
    lineColor: '#0066CC',
    lineWidth: 4.0,
  ),
);
```

**After (Editable polylines):**
```dart
// Same route, now editable
final route = await controller.addLine(
  LineOptions(
    geometry: [
      LatLng(37.7749, -122.4194),
      LatLng(40.7128, -74.0060),
    ],
    lineColor: '#0066CC',
    lineWidth: 4.0,
    // New editing properties
    editable: true,
    editingCallbacks: PolylineEditingCallbacks(
      onPolylineBroken: _handleRouteBreak,
      onPolylineModified: _handleRouteModify,
      onEditingError: _handleEditingError,
    ),
    // Optional visual customization
    breakPointColor: '#FF0000',
    breakPointRadius: 10.0,
    previewLineColor: '#00FF00',
    previewLineOpacity: 0.8,
  ),
);
```

### Step 3: Implement Callback Handlers

Add callback methods to handle editing events:

```dart
class _MyMapPageState extends State<MyMapPage> {
  // ... existing code ...

  // New callback handlers
  void _handleRouteBreak(String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    print('Route $lineId was broken into ${segment1.length} + ${segment2.length} segments');
    
    // Update your application state
    _updateRouteInDatabase(lineId, segment1, segment2);
    
    // Refresh UI if needed
    setState(() {
      // Update any relevant state
    });
  }

  void _handleRouteModify(String lineId, List<LatLng> newCoordinates) {
    print('Route $lineId was modified: ${newCoordinates.length} points');
    
    // Save updated coordinates
    _saveUpdatedRoute(lineId, newCoordinates);
    
    // Recalculate any derived data (distance, time, etc.)
    _recalculateRouteMetrics(lineId, newCoordinates);
  }

  void _handleEditingError(String lineId, String error) {
    print('Editing error on route $lineId: $error');
    
    // Show user-friendly error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to edit route: $error')),
    );
  }
}
```

### Step 4: Add UI Controls (Optional)

You may want to add UI controls to enable/disable editing:

```dart
class EditableRouteWidget extends StatefulWidget {
  @override
  _EditableRouteWidgetState createState() => _EditableRouteWidgetState();
}

class _EditableRouteWidgetState extends State<EditableRouteWidget> {
  bool _editingEnabled = false;
  MapLibreMapController? _controller;
  String? _routeId;

  // ... existing map setup code ...

  Widget _buildEditingControls() {
    return Row(
      children: [
        Text('Enable Editing: '),
        Switch(
          value: _editingEnabled,
          onChanged: (enabled) async {
            setState(() {
              _editingEnabled = enabled;
            });
            
            if (_controller != null && _routeId != null) {
              await _controller!.enablePolylineEditing(_routeId!, enabled);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: MapLibreMap(
            // ... existing map configuration ...
          ),
        ),
        _buildEditingControls(),
      ],
    );
  }
}
```

## Common Migration Scenarios

### Scenario 1: Flight Planning App

**Original Code:**
```dart
class FlightPlannerOld {
  Future<void> displayFlightPlan(FlightPlan plan) async {
    for (final route in plan.routes) {
      await controller.addLine(
        LineOptions(
          geometry: route.waypoints.map((w) => w.coordinate).toList(),
          lineColor: route.color,
          lineWidth: 3.0,
        ),
      );
    }
  }
}
```

**Migrated Code:**
```dart
class FlightPlannerNew {
  Future<void> displayFlightPlan(FlightPlan plan) async {
    for (final route in plan.routes) {
      final line = await controller.addLine(
        LineOptions(
          geometry: route.waypoints.map((w) => w.coordinate).toList(),
          lineColor: route.color,
          lineWidth: 3.0,
          // Enable editing for user routes, not ATC restrictions
          editable: route.type == RouteType.user,
          editingCallbacks: route.type == RouteType.user 
            ? PolylineEditingCallbacks(
                onPolylineBroken: (id, seg1, seg2) => _addWaypoint(route, seg1.last),
                onPolylineModified: (id, coords) => _updateFlightPlan(route, coords),
                onEditingError: (id, error) => _showPlanningError(error),
              )
            : null,
          breakPointColor: '#FF6600',
          previewLineColor: '#FFB366',
        ),
      );
      
      // Store line ID for later reference
      route.lineId = line.id;
    }
  }

  void _addWaypoint(FlightRoute route, LatLng position) {
    // Add waypoint at break position
    final waypoint = Waypoint.fromCoordinate(position);
    route.waypoints.add(waypoint);
    
    // Recalculate flight plan
    FlightCalculator.recalculate(route);
  }
}
```

### Scenario 2: Delivery Route App

**Original Code:**
```dart
class DeliveryRouteDisplay {
  Future<void> showDeliveryRoutes(List<DeliveryRoute> routes) async {
    for (final route in routes) {
      await controller.addLine(
        LineOptions(
          geometry: route.stops.map((stop) => stop.location).toList(),
          lineColor: route.status == RouteStatus.completed ? '#00AA00' : '#0066CC',
          lineWidth: 4.0,
        ),
      );
    }
  }
}
```

**Migrated Code:**
```dart
class DeliveryRouteDisplay {
  Future<void> showDeliveryRoutes(List<DeliveryRoute> routes) async {
    for (final route in routes) {
      await controller.addLine(
        LineOptions(
          geometry: route.stops.map((stop) => stop.location).toList(),
          lineColor: route.status == RouteStatus.completed ? '#00AA00' : '#0066CC',
          lineWidth: 4.0,
          // Only allow editing of active routes
          editable: route.status == RouteStatus.active,
          editingCallbacks: route.status == RouteStatus.active
            ? PolylineEditingCallbacks(
                onPolylineModified: (id, coords) => _optimizeDeliveryRoute(route, coords),
                onEditingError: (id, error) => _handleOptimizationError(route, error),
              )
            : null,
        ),
      );
    }
  }

  void _optimizeDeliveryRoute(DeliveryRoute route, List<LatLng> newCoordinates) {
    // Recalculate optimal delivery sequence
    final optimizedStops = RouteOptimizer.optimizeStops(route.stops, newCoordinates);
    
    // Update route
    route.stops = optimizedStops;
    
    // Notify delivery team
    DeliveryService.updateRoute(route);
  }
}
```

### Scenario 3: GPS Tracking App

**Original Code:**
```dart
class GPSTracker {
  Line? _currentTrack;

  Future<void> startTracking() async {
    // Create initial track
    _currentTrack = await controller.addLine(
      LineOptions(
        geometry: [_currentLocation],
        lineColor: '#FF0000',
        lineWidth: 3.0,
      ),
    );
  }

  Future<void> updateTrack(LatLng newLocation) async {
    if (_currentTrack != null) {
      final currentPath = await controller.getLineLatLngs(_currentTrack!);
      currentPath.add(newLocation);
      
      await controller.updateLine(
        _currentTrack!,
        LineOptions(geometry: currentPath),
      );
    }
  }
}
```

**Migrated Code:**
```dart
class GPSTracker {
  Line? _currentTrack;
  bool _allowTrackEditing = false;

  Future<void> startTracking() async {
    // Create initial track
    _currentTrack = await controller.addLine(
      LineOptions(
        geometry: [_currentLocation],
        lineColor: '#FF0000',
        lineWidth: 3.0,
        // Enable editing after tracking is complete
        editable: false, // Will be enabled later
      ),
    );
  }

  Future<void> stopTracking() async {
    if (_currentTrack != null) {
      // Enable editing of completed track
      await controller.enablePolylineEditing(_currentTrack!.id, true);
      
      // Update with editing callbacks
      await controller.updateLine(
        _currentTrack!,
        LineOptions(
          editingCallbacks: PolylineEditingCallbacks(
            onPolylineModified: _handleTrackModification,
            onPolylineBroken: _handleTrackSplit,
          ),
        ),
      );
    }
  }

  void _handleTrackModification(String lineId, List<LatLng> newCoordinates) {
    // Recalculate track statistics
    final distance = TrackAnalyzer.calculateDistance(newCoordinates);
    final duration = TrackAnalyzer.estimateDuration(newCoordinates);
    
    // Update track in database
    TrackDatabase.updateTrack(lineId, newCoordinates, distance, duration);
  }

  void _handleTrackSplit(String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    // Split track into two separate activities
    TrackDatabase.splitTrack(lineId, segment1, segment2);
  }
}
```

## Platform Considerations

### Android-Only Features
If your app was Android-only, no changes needed - editing will work automatically.

### iOS-Only Features
If your app was iOS-only, no changes needed - editing will work automatically.

### Web Platform Support
If your app supported web, polylines will remain non-editable on web platform but won't cause errors:

```dart
class CrossPlatformRouteEditor {
  Future<void> addRoute(List<LatLng> coordinates) async {
    await controller.addLine(
      LineOptions(
        geometry: coordinates,
        lineColor: '#0066CC',
        lineWidth: 4.0,
        // Editing will be ignored on web, works on mobile
        editable: true,
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineModified: _handleModification,
        ),
      ),
    );
  }

  void _handleModification(String lineId, List<LatLng> coordinates) {
    // This callback will only fire on Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      // Handle modification
      _updateRoute(lineId, coordinates);
    }
  }
}
```

## Performance Migration

### For Apps with Many Polylines

If your app displays many polylines, consider selective editing:

```dart
class PerformanceMigratedApp {
  static const int MAX_EDITABLE_ROUTES = 5;
  
  Future<void> displayRoutes(List<Route> routes) async {
    for (int i = 0; i < routes.length; i++) {
      final route = routes[i];
      
      await controller.addLine(
        LineOptions(
          geometry: route.coordinates,
          lineColor: route.color,
          lineWidth: 3.0,
          // Only make first few routes editable for performance
          editable: i < MAX_EDITABLE_ROUTES,
          editingCallbacks: i < MAX_EDITABLE_ROUTES 
            ? PolylineEditingCallbacks(
                onPolylineModified: (id, coords) => _updateRoute(id, coords),
              )
            : null,
        ),
      );
    }
  }
}
```

### For Apps with Complex Polylines

Simplify complex polylines before enabling editing:

```dart
class ComplexRouteMigration {
  static const int MAX_POINTS_FOR_EDITING = 500;
  static const double SIMPLIFICATION_TOLERANCE = 0.001;

  Future<void> addComplexRoute(List<LatLng> originalRoute) async {
    List<LatLng> routeForDisplay = originalRoute;
    
    // Simplify if too complex for editing
    if (originalRoute.length > MAX_POINTS_FOR_EDITING) {
      routeForDisplay = RouteSimplifier.simplify(
        originalRoute,
        tolerance: SIMPLIFICATION_TOLERANCE,
      );
    }

    await controller.addLine(
      LineOptions(
        geometry: routeForDisplay,
        lineColor: '#0066CC',
        lineWidth: 4.0,
        editable: true,
        editingCallbacks: PolylineEditingCallbacks(
          onPolylineModified: (id, coords) {
            // Expand simplified coordinates back for storage
            final expandedCoords = RouteExpander.expand(coords, originalRoute);
            _saveExpandedRoute(id, expandedCoords);
          },
        ),
      ),
    );
  }
}
```

## Testing Migration

### Update Existing Tests

Add tests for new editing functionality:

```dart
// Before: Basic polyline test
testWidgets('displays route correctly', (WidgetTester tester) async {
  await tester.pumpWidget(MyRouteApp());
  await tester.pumpAndSettle();
  
  // Verify route is displayed
  expect(find.byType(MapLibreMap), findsOneWidget);
});

// After: Include editing test
testWidgets('displays editable route correctly', (WidgetTester tester) async {
  await tester.pumpWidget(MyRouteApp());
  await tester.pumpAndSettle();
  
  // Verify route is displayed
  expect(find.byType(MapLibreMap), findsOneWidget);
  
  // Test editing functionality (requires test hooks)
  final routeApp = tester.widget<MyRouteApp>(find.byType(MyRouteApp));
  expect(routeApp.isEditingEnabled, isTrue);
});
```

## Migration Checklist

- [ ] Updated to compatible MapLibre GL version
- [ ] Identified polylines that should be editable
- [ ] Added `editable: true` to relevant LineOptions
- [ ] Implemented callback handlers for editing events
- [ ] Added UI controls for enabling/disabling editing (if needed)
- [ ] Tested on both Android and iOS platforms
- [ ] Verified web platform compatibility (graceful degradation)
- [ ] Updated performance optimizations for complex polylines
- [ ] Added tests for new editing functionality
- [ ] Updated documentation and user guides

## Rollback Plan

If you need to rollback the migration:

1. **Remove editing properties:**
   ```dart
   // Change from:
   LineOptions(
     geometry: coordinates,
     editable: true,
     editingCallbacks: callbacks,
   )
   
   // Back to:
   LineOptions(
     geometry: coordinates,
   )
   ```

2. **Remove callback methods:** Delete the callback handler methods you added.

3. **Remove UI controls:** Remove any editing-related UI components.

4. **Downgrade dependency:** Revert to previous MapLibre GL version if needed.

The migration is designed to be safe and reversible, with no breaking changes to existing functionality.

## Support and Troubleshooting

### Common Issues

1. **Editing not working:** Ensure `editable: true` is set and platform is Android/iOS
2. **Performance issues:** Consider simplifying complex polylines or limiting editable routes
3. **Callback not firing:** Verify callbacks are properly assigned and not null
4. **Visual issues:** Check break point styling properties for visibility

### Getting Help

- Check the API reference documentation
- Review the usage guide examples
- Search existing issues on GitHub
- Create new issue with reproduction steps

This migration guide should help you smoothly upgrade your existing MapLibre GL Flutter application to support interactive polyline editing while maintaining backward compatibility.