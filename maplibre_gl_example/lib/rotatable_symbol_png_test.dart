// Test example demonstrating the new addRotatableSymbolPngLayers method
// This shows how to use PNG assets instead of programmatically created symbols

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'page.dart';

class RotatableSymbolPngTest extends ExamplePage {
  const RotatableSymbolPngTest({Key? key})
      : super(const Icon(Icons.ac_unit), 'PNG Rotatable Symbols Test',
            key: key);

  @override
  Widget build(BuildContext context) {
    return const RotatableSymbolPngTestBody();
  }
}

class RotatableSymbolPngTestBody extends StatefulWidget {
  const RotatableSymbolPngTestBody({Key? key}) : super(key: key);

  @override
  State<RotatableSymbolPngTestBody> createState() =>
      _RotatableSymbolPngTestBodyState();
}

class _RotatableSymbolPngTestBodyState
    extends State<RotatableSymbolPngTestBody> {
  MapLibreMapController? controller;
  static const LatLng center = LatLng(37.7749, -122.4194);

  // Animation control variables
  Timer? _animationTimer;
  double _currentRotation = 45.0;
  bool _isClimbing = true;
  bool _isAnimating = false;

  // Proximity simulation variables for color changes
  double _proximityDistance = 5.0; // nautical miles
  bool _proximityWarning = false;

  // Animation speed controls - slower per user request
  static const Duration _animationInterval =
      Duration(milliseconds: 150); // Slower: was 50ms
  static const double _rotationStep = 2.0; // Slower: was 4 degrees

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  void _onStyleLoaded() {
    _testPngSymbolLayers();
  }

  /// Get aircraft icon color based on proximity distance
  String _getAircraftColor() {
    String color;
    if (_proximityDistance < 2.0) {
      color = '#FF0000'; // Red - Critical proximity (<2nm)
    } else if (_proximityDistance < 5.0) {
      color = '#FFA500'; // Orange - Warning proximity (2-5nm)
    } else if (_proximityDistance < 10.0) {
      color = '#FFFF00'; // Yellow - Caution proximity (5-10nm)
    } else {
      color = '#00FF00'; // Green - Safe distance (>10nm)
    }
    print(
        '🎨 Aircraft color for ${_proximityDistance.toStringAsFixed(1)}nm: $color');
    return color;
  }

  /// Get arrow icon color based on proximity and climb state
  String _getArrowColor() {
    String color;
    if (_proximityDistance < 2.0) {
      color = '#FF0000'; // Red arrows for critical proximity
    } else if (_isClimbing) {
      color = '#00FF00'; // Green for climbing
    } else {
      color = '#FF4500'; // Orange-red for descending
    }
    print(
        '🎨 Arrow color for ${_proximityDistance.toStringAsFixed(1)}nm, climbing=$_isClimbing: $color');
    return color;
  }

  /// Simulate proximity changes based on rotation for demo
  void _simulateProximityChange() {
    setState(() {
      // Simulate varying proximity (1-15 nautical miles) using sine wave
      _proximityDistance =
          1.0 + (14.0 * (sin(_currentRotation * 0.02) + 1) / 2);
      _proximityWarning = _proximityDistance < 5.0;
    });
  }

  /// Test the new PNG-based rotatable symbol layers
  Future<void> _testPngSymbolLayers() async {
    if (controller == null) return;

    try {
      // Clean up any existing sources to prevent duplicates
      try {
        await controller!.removeSource('aircraft-png-source');
        print('🧹 Cleaned up existing source');
      } catch (e) {
        // Source doesn't exist, which is fine
        print('ℹ️ No existing source to clean up');
      }

      // Create test aircraft data with dynamic rotation
      final geoJson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude, center.latitude],
            },
            'properties': {
              'rotation': _currentRotation,
              'topLabel': '35K',
              'bottomLabel': 'UAL123',
              'isClimbing': _isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
              'aircraftIconColor':
                  _getAircraftColor(), // Dynamic proximity-based color
              'arrowIconColor': _getArrowColor(), // Dynamic arrow color
            },
          },
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude + 0.01, center.latitude + 0.01],
            },
            'properties': {
              'rotation': _currentRotation +
                  90.0, // Different rotation for second aircraft
              'topLabel': '28K',
              'bottomLabel': 'DAL456',
              'isClimbing': !_isClimbing, // Opposite climb state
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
              'aircraftIconColor': '#00FFFF', // Cyan for second aircraft
              'arrowIconColor':
                  !_isClimbing ? '#00FF00' : '#FF4500', // Opposite of first
            },
          },
        ],
      };

      // Add GeoJSON source
      await controller!.addGeoJsonSource('aircraft-png-source', geoJson);
      print('✅ Added GeoJSON source for PNG test');

      // Test the new PNG-based rotatable symbol layers with correct asset paths
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'aircraft-png-source',
        baseLayerId: 'aircraft-png-symbol',
        aircraftIconPath:
            'traffic.png', // Flutter asset path (MapLibre resolves automatically)
        arrowIconPath:
            'arrow.png', // Flutter asset path (MapLibre resolves automatically)
        aircraftIconSize:
            0.10, // Smaller aircraft icon size for better proportions
        arrowIconSize: 0.08, // Much smaller arrow icon to reduce visual weight
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX':
              400.0, // Moved much further right to completely avoid overlap
        },
      );

      print('✅ Successfully added PNG-based rotatable symbol layers');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PNG-based rotatable symbols added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Error testing PNG rotatable symbol layers: $e');
      print('🔍 Error details: ${e.toString()}');

      // Try to provide more specific error information
      if (e.toString().contains('Failed to load PNG asset')) {
        print(
            '📁 Asset loading issue - checking if assets are properly declared in pubspec.yaml');
        print('📝 Expected asset paths: traffic.png, arrow.png');
      } else if (e
          .toString()
          .contains('Source aircraft-png-source already exists')) {
        print('🔄 Duplicate source error - cleaning up and retrying...');
        // Try cleanup and retry once
        try {
          await controller!.removeSource('aircraft-png-source');
          await Future.delayed(const Duration(milliseconds: 100));
          return _testPngSymbolLayers(); // Retry
        } catch (cleanupError) {
          print('⚠️ Cleanup failed: $cleanupError');
        }
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );

      // Fallback to text-based symbols for comparison
      _testFallbackTextSymbols();
    }
  }

  /// Fallback test using the original text-based rotatable symbol layers
  Future<void> _testFallbackTextSymbols() async {
    if (controller == null) return;

    try {
      await controller!.addRotatableSymbolLayers(
        sourceId: 'aircraft-png-source',
        baseLayerId: 'aircraft-text-symbol',
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 25.0, // Offset more to avoid overlap
        },
      );

      print(
          '✅ Successfully added text-based rotatable symbol layers (fallback)');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text-based rotatable symbols added as fallback'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print('❌ Error adding fallback text symbols: $e');
    }
  }

  /// Start continuous rotation animation (slower speed)
  void _startAnimation() {
    if (_animationTimer != null) return; // Already running

    setState(() {
      _isAnimating = true;
    });

    _animationTimer = Timer.periodic(_animationInterval, (timer) {
      setState(() {
        _currentRotation = (_currentRotation + _rotationStep) % 360.0;

        // Toggle climb/descent state every 5 seconds (slower)
        if (_currentRotation % 30.0 < _rotationStep) {
          _isClimbing = !_isClimbing;
          print(
              '🔄 Aircraft climb state changed: ${_isClimbing ? "climbing" : "descending"}');
        }

        // Simulate proximity changes for color demo
        _simulateProximityChange();
      });

      // Update the map with new rotation
      _updateAircraftData();
    });

    print('▶️ Started slower rotation animation');
  }

  /// Stop rotation animation
  void _stopAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;

    setState(() {
      _isAnimating = false;
    });

    print('⏹️ Stopped rotation animation');
  }

  /// Manually rotate aircraft by 45 degrees
  void _manualRotateAircraft() {
    setState(() {
      _currentRotation = (_currentRotation + 45.0) % 360.0;
    });

    _updateAircraftData();
    print('🔄 Manual rotation: ${_currentRotation.toStringAsFixed(0)}°');
  }

  /// Test color changing by cycling through proximity distances
  void _testColorChanges() {
    setState(() {
      // Cycle through different proximity distances to show color changes
      if (_proximityDistance > 10.0) {
        _proximityDistance = 1.0; // Critical - Red
      } else if (_proximityDistance > 5.0) {
        _proximityDistance = 12.0; // Safe - Green
      } else if (_proximityDistance > 2.0) {
        _proximityDistance = 8.0; // Caution - Yellow
      } else {
        _proximityDistance = 3.5; // Warning - Orange
      }
    });

    _updateAircraftData();
    print(
        '🎨 Color test: ${_proximityDistance.toStringAsFixed(1)}nm - Color: ${_getAircraftColor()}');
  }

  /// Test with simple colored rectangles instead of PNG assets
  Future<void> _testSimpleColorIcons() async {
    if (controller == null) return;

    try {
      // Create simple test data
      final geoJson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude, center.latitude],
            },
            'properties': {
              'rotation': _currentRotation,
              'topLabel': '35K',
              'bottomLabel': 'TEST',
              'isClimbing': _isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
              'aircraftIconColor': _getAircraftColor(),
              'arrowIconColor': _getArrowColor(),
            },
          },
        ],
      };

      // Clean up and add source
      try {
        await controller!.removeSource('test-color-source');
      } catch (e) {}

      await controller!.addGeoJsonSource('test-color-source', geoJson);
      print('✅ Added test color source');

      // Use simple colored rectangle icons
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'test-color-source',
        baseLayerId: 'test-color-symbols',
        aircraftIconPath:
            'test-color-icon', // Will use programmatically created icon
        arrowIconPath: 'test-color-icon',
        aircraftIconSize: 0.5,
        arrowIconSize: 0.3,
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 80.0,
        },
      );

      print('✅ Added test color symbol layers');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test color icons loaded - try changing colors!'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      print('❌ Error with test color icons: $e');
    }
  }

  /// Update aircraft data on the map
  Future<void> _updateAircraftData() async {
    if (controller == null) return;

    try {
      // Update the GeoJSON source with new rotation values and colors
      final updatedGeoJson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude, center.latitude],
            },
            'properties': {
              'rotation': _currentRotation,
              'topLabel': '35K',
              'bottomLabel': 'UAL123',
              'isClimbing': _isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
              'aircraftIconColor':
                  _getAircraftColor(), // Dynamic proximity-based color
              'arrowIconColor': _getArrowColor(), // Dynamic arrow color
            },
          },
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude + 0.01, center.latitude + 0.01],
            },
            'properties': {
              'rotation': _currentRotation + 90.0,
              'topLabel': '28K',
              'bottomLabel': 'DAL456',
              'isClimbing': !_isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
              'aircraftIconColor': '#00FFFF', // Cyan for second aircraft
              'arrowIconColor':
                  !_isClimbing ? '#00FF00' : '#FF4500', // Opposite of first
            },
          },
        ],
      };

      await controller!.setGeoJsonSource('aircraft-png-source', updatedGeoJson);
    } catch (e) {
      print('❌ Error updating aircraft data: $e');
    }
  }

  @override
  void dispose() {
    _stopAnimation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PNG Rotatable Symbols Test'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                const Text(
                  'Aviation PNG Symbol Testing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Testing addRotatableSymbolPngLayers for aviation symbols:\n'
                  '• Aircraft PNG icon with REAL-TIME COLOR TINTING\n'
                  '• Arrow PNG status indicators (color-coded)\n'
                  '• Text labels (altitude/callsign - always horizontal)\n'
                  '• Proximity-based colors: Red(<2nm), Orange(2-5nm), Yellow(5-10nm), Green(>10nm)\n'
                  '• Use custom PNG assets with proper contours for best results\n'
                  '• Use "Test Colors" button to cycle through proximity colors!',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // First row: Test buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _testPngSymbolLayers,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Test PNG Symbols'),
                    ),
                    ElevatedButton(
                      onPressed: _testFallbackTextSymbols,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Test Text Fallback'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Second row: Animation controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isAnimating ? _stopAnimation : _startAnimation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isAnimating ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isAnimating
                          ? '⏹️ Stop Animation'
                          : '▶️ Start Animation'),
                    ),
                    ElevatedButton(
                      onPressed: _manualRotateAircraft,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🔄 Rotate +45°'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Third row: Color testing
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _testColorChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(int.parse(
                                _getAircraftColor().substring(1),
                                radix: 16) +
                            0xFF000000),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🎨 Test Colors'),
                    ),
                    ElevatedButton(
                      onPressed: _testSimpleColorIcons,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🟩 Simple Icons'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Status text
                Text(
                  'Current Rotation: ${_currentRotation.toStringAsFixed(0)}° | '
                  'Proximity: ${_proximityDistance.toStringAsFixed(1)}nm | '
                  'Color: ${_getAircraftColor()} | '
                  'State: ${_isClimbing ? "Climbing ✈️⬆️" : "Descending ✈️⬇️"} | '
                  'Animation: ${_isAnimating ? "Running" : "Stopped"}',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: MapLibreMap(
              initialCameraPosition: const CameraPosition(
                target: center,
                zoom: 12.0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
            ),
          ),
        ],
      ),
    );
  }
}
