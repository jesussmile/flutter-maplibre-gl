// Demonstration of real-time color-changing PNG symbols based on proximity
// Shows how to use dynamic icon colors for safety-critical aviation displays

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'page.dart';

class ColorChangingPngSymbols extends ExamplePage {
  const ColorChangingPngSymbols({Key? key})
      : super(const Icon(Icons.palette), 'Color-Changing PNG Symbols',
            key: key);

  @override
  Widget build(BuildContext context) {
    return const ColorChangingPngSymbolsBody();
  }
}

class ColorChangingPngSymbolsBody extends StatefulWidget {
  const ColorChangingPngSymbolsBody({Key? key}) : super(key: key);

  @override
  State<ColorChangingPngSymbolsBody> createState() =>
      _ColorChangingPngSymbolsBodyState();
}

class _ColorChangingPngSymbolsBodyState
    extends State<ColorChangingPngSymbolsBody> {
  MapLibreMapController? controller;
  static const LatLng center = LatLng(37.7749, -122.4194);

  // Animation and proximity variables
  Timer? _animationTimer;
  double _currentRotation = 0.0;
  bool _isClimbing = true;
  bool _isAnimating = false;
  double _proximityDistance = 8.0; // nautical miles
  bool _proximityWarning = false;

  // Multiple aircraft for demonstration
  final List<Map<String, dynamic>> _aircraftData = [
    {
      'id': 'UAL123',
      'callsign': 'UAL123',
      'altitude': '35K',
      'lat': 37.7749,
      'lng': -122.4194,
      'rotation': 45.0,
      'isClimbing': true,
      'proximityDistance': 8.0,
    },
    {
      'id': 'DAL456',
      'callsign': 'DAL456',
      'altitude': '28K',
      'lat': 37.7849,
      'lng': -122.4094,
      'rotation': 180.0,
      'isClimbing': false,
      'proximityDistance': 3.0,
    },
    {
      'id': 'SWA789',
      'callsign': 'SWA789',
      'altitude': '42K',
      'lat': 37.7649,
      'lng': -122.4294,
      'rotation': 270.0,
      'isClimbing': true,
      'proximityDistance': 1.5,
    },
  ];

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  void _onStyleLoaded() {
    _setupColorChangingSymbols();
  }

  /// Get aircraft icon color based on proximity distance
  String _getAircraftColor(double proximityDistance) {
    if (proximityDistance < 2.0) {
      return '#FF0000'; // Red - Critical proximity (<2nm)
    } else if (proximityDistance < 5.0) {
      return '#FFA500'; // Orange - Warning proximity (2-5nm)
    } else if (proximityDistance < 10.0) {
      return '#FFFF00'; // Yellow - Caution proximity (5-10nm)
    } else {
      return '#00FF00'; // Green - Safe distance (>10nm)
    }
  }

  /// Get arrow icon color based on proximity and climb state
  String _getArrowColor(double proximityDistance, bool isClimbing) {
    if (proximityDistance < 2.0) {
      return '#FF0000'; // Red arrows for critical proximity
    } else if (isClimbing) {
      return '#00FF00'; // Green for climbing
    } else {
      return '#FF4500'; // Orange-red for descending
    }
  }

  /// Get proximity status text and color
  Map<String, dynamic> _getProximityStatus(double distance) {
    if (distance < 2.0) {
      return {'text': 'CRITICAL', 'color': Colors.red, 'icon': '🚨'};
    } else if (distance < 5.0) {
      return {'text': 'WARNING', 'color': Colors.orange, 'icon': '⚠️'};
    } else if (distance < 10.0) {
      return {'text': 'CAUTION', 'color': Colors.yellow[700], 'icon': '⚡'};
    } else {
      return {'text': 'SAFE', 'color': Colors.green, 'icon': '✅'};
    }
  }

  /// Setup color-changing PNG symbols
  Future<void> _setupColorChangingSymbols() async {
    if (controller == null) return;

    try {
      // Clean up any existing sources
      try {
        await controller!.removeSource('color-aircraft-source');
      } catch (e) {
        // Source doesn't exist, which is fine
      }

      // Create GeoJSON with multiple aircraft
      final geoJson = _buildGeoJsonData();

      // Add GeoJSON source
      await controller!.addGeoJsonSource('color-aircraft-source', geoJson);
      print('✅ Added color-changing aircraft source');

      // Add PNG-based rotatable symbol layers with color support
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'color-aircraft-source',
        baseLayerId: 'color-aircraft-symbols',
        aircraftIconPath: 'traffic.png',
        arrowIconPath: 'arrow.png',
        aircraftIconSize: 0.16,
        arrowIconSize: 0.13,
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 70.0,
        },
      );

      print('✅ Successfully added color-changing PNG symbols');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Color-changing PNG symbols loaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Start the proximity simulation
      _startProximitySimulation();
    } catch (e) {
      print('❌ Error setting up color-changing symbols: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Build GeoJSON data with color properties
  Map<String, dynamic> _buildGeoJsonData() {
    final features = _aircraftData.map((aircraft) {
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [aircraft['lng'], aircraft['lat']],
        },
        'properties': {
          'rotation': aircraft['rotation'],
          'topLabel': aircraft['altitude'],
          'bottomLabel': aircraft['callsign'],
          'isClimbing': aircraft['isClimbing'],
          'labelSize': 14.0,
          'labelColor': '#000000',
          'triangleOpacity': 1.0,
          'arrowOpacity': 1.0,
          'aircraftIconColor': _getAircraftColor(aircraft['proximityDistance']),
          'arrowIconColor': _getArrowColor(
              aircraft['proximityDistance'], aircraft['isClimbing']),
        },
      };
    }).toList();

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// Start proximity simulation with real-time updates
  void _startProximitySimulation() {
    _animationTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      setState(() {
        // Simulate changing proximity for each aircraft
        for (int i = 0; i < _aircraftData.length; i++) {
          final aircraft = _aircraftData[i];

          // Different simulation patterns for each aircraft
          switch (i) {
            case 0: // UAL123 - slow oscillation between safe and warning
              aircraft['proximityDistance'] =
                  5.0 + 4.0 * sin(timer.tick * 0.05);
              aircraft['rotation'] = (aircraft['rotation'] + 1.0) % 360.0;
              break;
            case 1: // DAL456 - critical proximity warning
              aircraft['proximityDistance'] = 1.5 + 1.0 * sin(timer.tick * 0.1);
              aircraft['rotation'] = (aircraft['rotation'] + 2.0) % 360.0;
              if (timer.tick % 50 == 0)
                aircraft['isClimbing'] = !aircraft['isClimbing'];
              break;
            case 2: // SWA789 - rapid proximity changes
              aircraft['proximityDistance'] =
                  2.0 + 8.0 * (sin(timer.tick * 0.08) + 1) / 2;
              aircraft['rotation'] = (aircraft['rotation'] + 1.5) % 360.0;
              break;
          }
        }

        // Update proximity warning state
        _proximityWarning = _aircraftData
            .any((aircraft) => aircraft['proximityDistance'] < 5.0);
      });

      // Update the map with new data
      _updateAircraftData();
    });

    setState(() {
      _isAnimating = true;
    });
  }

  /// Stop proximity simulation
  void _stopProximitySimulation() {
    _animationTimer?.cancel();
    _animationTimer = null;
    setState(() {
      _isAnimating = false;
    });
  }

  /// Update aircraft data on the map
  Future<void> _updateAircraftData() async {
    if (controller == null) return;

    try {
      final updatedGeoJson = _buildGeoJsonData();
      await controller!
          .setGeoJsonSource('color-aircraft-source', updatedGeoJson);
    } catch (e) {
      print('❌ Error updating aircraft data: $e');
    }
  }

  /// Manually change proximity for demonstration
  void _changeProximityMode() {
    setState(() {
      for (final aircraft in _aircraftData) {
        // Cycle through proximity levels
        if (aircraft['proximityDistance'] > 10.0) {
          aircraft['proximityDistance'] = 1.0; // Critical
        } else if (aircraft['proximityDistance'] > 5.0) {
          aircraft['proximityDistance'] = 12.0; // Safe
        } else if (aircraft['proximityDistance'] > 2.0) {
          aircraft['proximityDistance'] = 8.0; // Caution
        } else {
          aircraft['proximityDistance'] = 3.5; // Warning
        }
      }
    });
    _updateAircraftData();
  }

  @override
  void dispose() {
    _stopProximitySimulation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Color-Changing PNG Symbols'),
        backgroundColor: _proximityWarning ? Colors.red : Colors.blue,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: _proximityWarning ? Colors.red.shade50 : Colors.blue.shade50,
            child: Column(
              children: [
                Text(
                  _proximityWarning
                      ? '🚨 PROXIMITY WARNING 🚨'
                      : '✈️ Real-Time Color Demo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _proximityWarning ? Colors.red : Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aircraft icons change color based on proximity distance:\n'
                  '🔴 Red: Critical (<2nm) | 🟠 Orange: Warning (2-5nm)\n'
                  '🟡 Yellow: Caution (5-10nm) | 🟢 Green: Safe (>10nm)',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _isAnimating
                          ? _stopProximitySimulation
                          : _startProximitySimulation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isAnimating ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child:
                          Text(_isAnimating ? '⏹️ Stop Demo' : '▶️ Start Demo'),
                    ),
                    ElevatedButton(
                      onPressed: _changeProximityMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🎨 Change Colors'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Aircraft status display
                Wrap(
                  spacing: 8,
                  children: _aircraftData.map((aircraft) {
                    final status =
                        _getProximityStatus(aircraft['proximityDistance']);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: status['color'],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${status['icon']} ${aircraft['callsign']}: ${aircraft['proximityDistance'].toStringAsFixed(1)}nm',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: MapLibreMap(
              initialCameraPosition: const CameraPosition(
                target: center,
                zoom: 11.0,
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
