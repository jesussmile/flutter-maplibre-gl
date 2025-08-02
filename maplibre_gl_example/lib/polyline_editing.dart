// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class PolylineEditingPage extends ExamplePage {
  const PolylineEditingPage({super.key})
      : super(const Icon(Icons.edit_road), 'Interactive Polyline Editing');

  @override
  Widget build(BuildContext context) {
    return const PolylineEditingBody();
  }
}

class PolylineEditingBody extends StatefulWidget {
  const PolylineEditingBody({super.key});

  @override
  State<StatefulWidget> createState() => PolylineEditingBodyState();
}

class PolylineEditingBodyState extends State<PolylineEditingBody> {
  MapLibreMapController? controller;

  // Single blue polyline for testing
  // Blue route: West to East United States
  static const List<LatLng> _blueRoute = [
    LatLng(37.7749, -122.4194), // San Francisco, CA (West US)
    LatLng(40.7128, -74.0060), // New York, NY (East US)
  ];

  Line? _blueLine;

  // Markers for start and end points
  Circle? _startMarker; // San Francisco (start of blue)
  Circle? _endMarker; // New York (end of blue)

  // Track active break points
  final Map<String, Circle> _activeBreakPoints = {};

  final List<String> _eventLog = [];
  bool _blueEditingEnabled = true;

  // Current route coordinates (can be modified)
  List<LatLng> _currentBlueRoute = List.from(_blueRoute);

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
    // Add line tap listener to handle polyline interactions
    controller.onLineTapped.add(_onLineTapped);
  }

  @override
  void dispose() {
    controller?.onLineTapped.remove(_onLineTapped);
    super.dispose();
  }

  void _logEvent(String event) {
    setState(() {
      _eventLog.insert(
          0, '${DateTime.now().toString().substring(11, 19)}: $event');
      // Keep only last 10 events
      if (_eventLog.length > 10) {
        _eventLog.removeLast();
      }
    });
  }

  // Handle line tap events for creating break points
  void _onLineTapped(Line line) async {
    if (line.id == _blueLine?.id && _blueEditingEnabled) {
      _logEvent('Tapped on blue line - creating break point');
      // The actual break point creation is handled by the native polyline editing system
      // This tap is just for logging - the native gesture detector handles the actual editing
    }
  }

  // Note: The polyline editing events are handled by the controller's built-in callbacks
  // as set up in the controller.dart file (lines 189-228)
  // These events are automatically triggered when users interact with editable polylines

  Future<void> _onStyleLoadedCallback() async {
    if (controller == null) return;

    try {
      // Add blue route with editing callbacks
      _blueLine = await controller!.addLine(
        LineOptions(
          geometry: _currentBlueRoute,
          lineColor: '#0000FF', // Blue
          lineWidth: 4.0,
          editable: true,
          editingCallbacks: PolylineEditingCallbacks(
            onPolylineBroken: _onPolylineBroken,
            onPolylineModified: _onPolylineModified,
            onEditingError: _onEditingError,
          ),
        ),
      );

      // Enable editing for blue line by default
      // Note: Even though LineManager should handle this automatically when editable: true,
      // we need the explicit call for now until the automatic integration is working properly
      if (_blueEditingEnabled && _blueLine != null) {
        await controller!.enablePolylineEditing(_blueLine!, true);
      }

      // Add circular markers at start and end points
      _startMarker = await controller!.addCircle(
        CircleOptions(
          geometry: const LatLng(37.7749, -122.4194), // San Francisco (start)
          circleRadius: 8.0,
          circleColor: '#FFFFFF',
          circleStrokeColor: '#000000',
          circleStrokeWidth: 2.0,
        ),
      );

      _endMarker = await controller!.addCircle(
        CircleOptions(
          geometry: const LatLng(40.7128, -74.0060), // New York (end)
          circleRadius: 8.0,
          circleColor: '#FFFFFF',
          circleStrokeColor: '#000000',
          circleStrokeWidth: 2.0,
        ),
      );

      // Set initial editing style with orange preview lines
      await controller!.setPolylineEditingStyle(
        const PolylineEditingStyle(
          breakPointColor: '#FF6600', // Orange break points for visibility
          breakPointRadius: 12.0, // Larger break points for easier dragging
          breakPointBorderColor: '#FFFFFF', // White border for contrast
          breakPointBorderWidth: 2.0, // Border width
          previewLineColor:
              '#FF6600', // Orange preview lines matching breakpoint
          previewLineOpacity: 0.7, // Semi-transparent for visual feedback
          previewLineWidth: 3.0, // Visible width for preview line
          enableHapticFeedback: true, // Keep haptic feedback
        ),
      );

      _logEvent(
          'Added blue polyline with start and end markers and editing callbacks');
    } catch (e) {
      _logEvent('Error adding blue route: $e');
    }
  }

  // Callback handlers for polyline editing events
  // Update blue line when broken into segments
  void _onPolylineBroken(
      String lineId, List<LatLng> segment1, List<LatLng> segment2) {
    _logEvent('FLUTTER: Polyline broken callback received for $lineId');
    _logEvent(
        'FLUTTER: Segment1 has ${segment1.length} points, Segment2 has ${segment2.length} points');

    // Update current blue route with the new segments
    setState(() {
      _currentBlueRoute = List.from(segment1)..addAll(segment2);

      if (_blueLine != null) {
        // Update blue line geometry to reflect new path
        controller!
            .updateLine(_blueLine!, LineOptions(geometry: _currentBlueRoute));
      }
    });
  }

  void _onPolylineModified(String lineId, List<LatLng> newCoordinates) {
    _logEvent('FLUTTER: Polyline modified callback received for $lineId');
    _logEvent('FLUTTER: New coordinates have ${newCoordinates.length} points');

    // Update current blue route with the modified coordinates
    setState(() {
      _currentBlueRoute = List.from(newCoordinates);

      if (_blueLine != null) {
        // Update blue line geometry to reflect real-time changes
        controller!
            .updateLine(_blueLine!, LineOptions(geometry: _currentBlueRoute));
      }
    });
  }

  void _onEditingError(String lineId, String error) {
    _logEvent('FLUTTER: Editing error for $lineId: $error');
  }

  Future<void> _toggleBlueEditing() async {
    if (controller == null || _blueLine == null) return;

    setState(() {
      _blueEditingEnabled = !_blueEditingEnabled;
    });

    try {
      await controller!.enablePolylineEditing(_blueLine!, _blueEditingEnabled);
      _logEvent(
          'Blue Route editing ${_blueEditingEnabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _logEvent('Error toggling Blue Route editing: $e');
    }
  }

  Future<void> _resetBlueRoute() async {
    if (controller == null) return;

    // Remove existing blue line
    if (_blueLine != null) {
      await controller!.removeLine(_blueLine!);
      _blueLine = null;
    }

    // Remove existing markers
    if (_startMarker != null) {
      await controller!.removeCircle(_startMarker!);
      _startMarker = null;
    }
    if (_endMarker != null) {
      await controller!.removeCircle(_endMarker!);
      _endMarker = null;
    }

    // Reset blue route coordinates to original
    _currentBlueRoute = List.from(_blueRoute);

    // Reset state
    setState(() {
      _blueEditingEnabled = true;
      _eventLog.clear();
    });

    // Re-add blue route with original path
    await _onStyleLoadedCallback();
    _logEvent('Reset blue route to original path');
  }

  Future<void> _testEditingFeatures() async {
    if (controller == null) return;

    // Test if editing features are available for blue line
    if (_blueLine != null) {
      try {
        final isEditable = await controller!.isPolylineEditable(_blueLine!);
        _logEvent(
            'Blue Route is currently ${isEditable ? 'editable' : 'not editable'}');
      } catch (e) {
        _logEvent('Error checking if Blue Route is editable: $e');
      }
    }

    // Test setting editing style with visible preview lines
    try {
      final useRedBreakPoints = DateTime.now().millisecondsSinceEpoch.isEven;
      final color = useRedBreakPoints ? '#FF0000' : '#FF6600';
      await controller!.setPolylineEditingStyle(
        PolylineEditingStyle(
          breakPointColor: color,
          breakPointRadius: 14.0,
          breakPointBorderColor: '#FFFFFF',
          breakPointBorderWidth: 3.0,
          previewLineColor: color, // Match preview line color to breakpoint
          previewLineOpacity: 0.7, // Semi-transparent preview lines
          previewLineWidth: 3.0, // Visible preview line width
          enableHapticFeedback: true,
        ),
      );
      _logEvent(
          'Updated editing style with ${useRedBreakPoints ? 'red' : 'orange'} break points and preview lines');
    } catch (e) {
      _logEvent('Error setting editing style: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // Map Container
        SizedBox(
          height: 400.0,
          child: MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoadedCallback,
            initialCameraPosition: const CameraPosition(
              target: LatLng(50.0, -30.0), // Center between US and Europe
              zoom: 2.5,
            ),
          ),
        ),

        // Instructions
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Colors.blue.shade50,
          child: const Text(
            'Polyline Editing with Two-Segment Preview Lines\n'
            '• BLUE LINE: West US to East US (San Francisco to New York)\n'
            '• WHITE CIRCLES: Start and end points\n'
            '\nLONG PRESS anywhere on the blue line to create a break point\n'
            'DRAG the orange break point to redirect the path\n'
            'TWO ORANGE PREVIEW LINES connect both ends to the break point',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),

        // Control Buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              // Blue Route Toggle Button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 30,
                        height: 4,
                        color: const Color(0xFF0000FF), // Blue
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _toggleBlueEditing,
                        style: TextButton.styleFrom(
                          backgroundColor: _blueEditingEnabled
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          _blueEditingEnabled
                              ? 'Blue Line\nEditable'
                              : 'Blue Line\nDisabled',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: _testEditingFeatures,
                    child: const Text('Test Features'),
                  ),
                  TextButton(
                    onPressed: _resetBlueRoute,
                    child: const Text('Reset Blue Route'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Event Log
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Log:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _eventLog.isEmpty
                      ? const Text(
                          'No events yet. Try long pressing on routes to create break points!',
                          style: TextStyle(
                              fontStyle: FontStyle.italic, color: Colors.grey),
                        )
                      : ListView.builder(
                          itemCount: _eventLog.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                _eventLog[index],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
