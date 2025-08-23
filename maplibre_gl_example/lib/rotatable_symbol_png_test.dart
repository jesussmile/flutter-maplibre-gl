// Test example demonstrating the new addRotatableSymbolPngLayers method
// This shows how to use PNG assets instead of programmatically created symbols

import 'dart:async';
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

  /// Update aircraft data on the map
  Future<void> _updateAircraftData() async {
    if (controller == null) return;

    try {
      // Update the GeoJSON source with new rotation values
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
                  '• Aircraft PNG icon (0.15 scale - smaller, better balance)\n'
                  '• Arrow PNG status indicators (80.0 offset - far right, no overlap)\n'
                  '• Text labels (altitude/callsign - always horizontal)\n'
                  '• Aircraft icon 0.15 scale, arrow 0.12 scale (smaller arrow)\n'
                  '• Slower animation: 150ms interval, 2° steps (was 50ms, 4°)\n'
                  '• Arrow positioned very far right at 80.0 offset',
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
                const SizedBox(height: 4),
                // Status text
                Text(
                  'Current Rotation: ${_currentRotation.toStringAsFixed(0)}° | '
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
