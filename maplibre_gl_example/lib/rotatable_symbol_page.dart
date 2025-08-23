// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class RotatableSymbolPage extends ExamplePage {
  const RotatableSymbolPage({super.key})
      : super(const Icon(Icons.flight), 'Rotatable symbol widget');

  @override
  Widget build(BuildContext context) {
    return const RotatableSymbolBody();
  }
}

class RotatableSymbolBody extends StatefulWidget {
  const RotatableSymbolBody({super.key});

  @override
  State<StatefulWidget> createState() => RotatableSymbolBodyState();
}

class RotatableSymbolBodyState extends State<RotatableSymbolBody> {
  RotatableSymbolBodyState();

  static const LatLng center = LatLng(37.7749, -122.4194); // San Francisco

  MapLibreMapController? controller;
  int _aircraftCount = 0;
  Timer? _animationTimer;
  bool _isAnimating = false;
  bool _layersInitialized =
      false; // Track if rotatable symbol layers have been added

  final List<Map<String, dynamic>> _aircraftData = [];

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  void _onStyleLoaded() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          const Text("Style loaded - Add aircraft to see rotatable symbols"),
      backgroundColor: Theme.of(context).primaryColor,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  void _addAircraft() async {
    if (controller == null) return;

    _aircraftCount++;

    // Use fixed position for testing - exactly at map center
    final lat = center.latitude;
    final lng = center.longitude;
    final rotation = 0.0; // Starting rotation
    final altitude = 15000 +
        (Random().nextDouble() * 20000)
            .round(); // Random altitude between 15k-35k ft
    final isClimbing = Random().nextBool(); // Random initial climbing state

    // Generate simple callsign
    final callsign = 'TEST$_aircraftCount';

    final aircraftInfo = {
      'id': 'aircraft-$_aircraftCount',
      'lat': lat,
      'lng': lng,
      'rotation': rotation,
      'altitude': altitude,
      'callsign': callsign,
      'isClimbing': isClimbing,
      'speed': 2.0, // Rotation speed (degrees per frame)
    };

    _aircraftData.add(aircraftInfo);

    print(
        'Added aircraft at EXACT CENTER: lat: ${aircraftInfo['lat']}, lng: ${aircraftInfo['lng']}, callsign: ${aircraftInfo['callsign']}');
    print('Map center is: lat: ${center.latitude}, lng: ${center.longitude}');

    // Update the aircraft source (this handles both add and update logic)
    await _updateAircraftSource();

    // Add the rotatable symbol layers only if not already initialized
    if (!_layersInitialized) {
      try {
        await controller!.addRotatableSymbolLayers(
          sourceId: 'aircraft-source',
          baseLayerId: 'aircraft-symbols',
          enableInteraction: true,
          config: {
            'topLabelOffset': -2.5,
            'bottomLabelOffset': 2.5,
            'arrowOffsetX': 25.0,
          },
        );

        _layersInitialized = true; // Mark as initialized

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Added aircraft with rotatable symbol layers"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error adding rotatable symbol: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Added aircraft ${aircraftInfo['callsign']}"),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _removeAircraft() async {
    if (controller == null || _aircraftData.isEmpty) return;

    _aircraftData.removeLast();
    await _updateAircraftSource();

    if (_aircraftData.isEmpty) {
      _aircraftCount = 0;
    }
  }

  void _clearAircraft() async {
    if (controller == null) return;

    _aircraftData.clear();
    _aircraftCount = 0;
    _layersInitialized = false; // Reset layers flag
    await _updateAircraftSource();
  }

  /// Test the new PNG-based rotatable symbol layers
  void _testPngSymbols() async {
    if (controller == null) return;

    try {
      // Clear existing aircraft
      _aircraftData.clear();
      _aircraftCount = 0;
      _layersInitialized = false;
      await _updateAircraftSource();

      // Add test aircraft for PNG symbols
      final testAircraft = {
        'lat': center.latitude,
        'lng': center.longitude,
        'rotation': 45.0,
        'altitude': 35000,
        'callsign': 'TEST123',
        'isClimbing': true,
        'speed': 2.0,
      };

      _aircraftData.add(testAircraft);
      await _updateAircraftSource();

      // Use the NEW PNG-based rotatable symbol layers method
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'aircraft-source',
        baseLayerId: 'aircraft-png-symbols',
        aircraftIconPath: 'traffic.png', // PNG asset for aircraft
        arrowIconPath: 'arrow.png', // PNG asset for arrows
        aircraftIconSize: 0.1, // Small aircraft icon
        arrowIconSize: 0.2, // Small arrow icon
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 20.0,
        },
      );

      _layersInitialized = true;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("✅ PNG rotatable symbols added successfully!"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ));

      print('✅ Successfully tested PNG-based rotatable symbol layers');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("❌ PNG symbols failed: $e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));

      print('❌ Error testing PNG rotatable symbol layers: $e');

      // Fallback to text-based symbols
      try {
        await controller!.addRotatableSymbolLayers(
          sourceId: 'aircraft-source',
          baseLayerId: 'aircraft-text-symbols',
          enableInteraction: true,
          config: {
            'topLabelOffset': -2.5,
            'bottomLabelOffset': 2.5,
            'arrowOffsetX': 25.0,
          },
        );

        _layersInitialized = true;

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("⚠️ Fallback to text symbols successful"),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ));
      } catch (fallbackError) {
        print('❌ Fallback also failed: $fallbackError');
      }
    }
  }

  void _toggleAnimation() {
    setState(() {
      _isAnimating = !_isAnimating;
    });

    if (_isAnimating) {
      _startAnimation();
    } else {
      _stopAnimation();
    }
  }

  void _startAnimation() {
    _animationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _updateAircraftAnimations();
    });
  }

  void _stopAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
  }

  void _updateAircraftAnimations() {
    if (_aircraftData.isEmpty) return;

    for (var aircraft in _aircraftData) {
      // Update rotation (simulate heading changes) - smoother rotation
      aircraft['rotation'] =
          (aircraft['rotation'] + aircraft['speed'] * 2.0) % 360;

      // More frequent climb/descent changes for better visibility
      if (Random().nextDouble() < 0.05) {
        // 5% chance per frame
        aircraft['isClimbing'] = !aircraft['isClimbing'];
      }

      // Realistic altitude changes based on climbing/descending
      if (aircraft['isClimbing']) {
        aircraft['altitude'] = (aircraft['altitude'] + 50).clamp(1000, 45000);
      } else {
        aircraft['altitude'] = (aircraft['altitude'] - 50).clamp(1000, 45000);
      }

      // Occasionally change altitude target to create more dynamic movement
      if (Random().nextDouble() < 0.01) {
        // 1% chance per frame
        aircraft['altitude'] = (Random().nextDouble() * 40000 + 5000).round();
      }
    }

    _updateAircraftSource();
  }

  Future<void> _updateAircraftSource() async {
    if (controller == null) return;

    final features = _aircraftData.map((aircraft) {
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [aircraft['lng'], aircraft['lat']],
        },
        'properties': {
          'rotation': aircraft['rotation'], // Use animated rotation
          'topLabel': '${aircraft['altitude']}', // Show altitude
          'bottomLabel': aircraft['callsign'], // Show callsign
          'isClimbing': aircraft['isClimbing'], // Use animated climbing status
          'triangleSize': 1.0, // Large size for visibility
          'labelSize': 16.0, // Large font size
          'arrowSize': 1.2, // Large arrow size
          'labelColor': '#FF0000', // Red for visibility
          'triangleOpacity': 1.0,
          'arrowOpacity': 1.0,
        },
      };
    }).toList();

    final geoJson = {
      'type': 'FeatureCollection',
      'features': features,
    };

    print('=== GeoJSON DATA ===');
    print('Features count: ${features.length}');
    print('GeoJSON: $geoJson');
    print('==================');

    try {
      if (_aircraftData.isNotEmpty) {
        // Check if layers have been initialized to determine add vs update
        if (!_layersInitialized) {
          // First time adding aircraft - add the source
          await controller!.addGeoJsonSource('aircraft-source', geoJson);
          print('Added new GeoJSON source with ${features.length} aircraft');
        } else {
          // Layers already initialized - update existing source
          await controller!.setGeoJsonSource('aircraft-source', geoJson);
          print(
              'Updated existing GeoJSON source with ${features.length} aircraft');
        }
      } else {
        // Remove source if no aircraft
        try {
          await controller!.removeSource('aircraft-source');
          print('Removed GeoJSON source (no aircraft)');
        } catch (e) {
          // Source might not exist, ignore error
          print('Could not remove source (might not exist): $e');
        }
      }
    } catch (e) {
      print('Error updating aircraft source: $e');
      // If adding failed, the source might already exist, try updating instead
      if (_aircraftData.isNotEmpty && e.toString().contains('already exists')) {
        try {
          await controller!.setGeoJsonSource('aircraft-source', geoJson);
          print('Fallback: Updated existing source after add failed');
        } catch (e2) {
          print('Fallback update also failed: $e2');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                Text(
                  'Rotatable Symbol Widget Demo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Each aircraft symbol consists of:\n'
                  '• Triangle (rotates with heading)\n'
                  '• Top label (altitude, always horizontal)\n'
                  '• Bottom label (callsign, always horizontal)\n'
                  '• Side arrow (climb/descend, always upright)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Aircraft count: $_aircraftCount',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _testPngSymbols,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('🧪 Test PNG Symbols'),
                ),
              ],
            ),
          ),
          Expanded(
            child: MapLibreMap(
              initialCameraPosition: const CameraPosition(
                target: center,
                zoom: 13.0, // Increased zoom for better visibility
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "add",
            onPressed: _addAircraft,
            tooltip: 'Add aircraft',
            backgroundColor: Colors.green,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "remove",
            onPressed: _removeAircraft,
            tooltip: 'Remove aircraft',
            backgroundColor: Colors.orange,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "clear",
            onPressed: _clearAircraft,
            tooltip: 'Clear all aircraft',
            backgroundColor: Colors.red,
            child: const Icon(Icons.clear),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "animate",
            onPressed: _toggleAnimation,
            tooltip: _isAnimating ? 'Stop animation' : 'Start animation',
            backgroundColor: _isAnimating ? Colors.purple : Colors.blue,
            child: Icon(_isAnimating ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}
