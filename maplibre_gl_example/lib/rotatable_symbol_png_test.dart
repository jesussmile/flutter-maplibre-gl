// Test example demonstrating the new addRotatableSymbolPngLayers method
// This shows how to use PNG assets instead of programmatically created symbols

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  /// Get aircraft icon path based on proximity distance (with black outline preserved)
  String _getAircraftIconPath() {
    String iconPath;
    if (_proximityDistance < 2.0) {
      iconPath = 'traffic_red.png'; // Red - Critical proximity (<2nm)
    } else if (_proximityDistance < 5.0) {
      iconPath = 'traffic_yellow.png'; // Yellow - Warning proximity (2-5nm)
    } else if (_proximityDistance < 10.0) {
      iconPath = 'traffic_blue.png'; // Blue - Caution proximity (5-10nm)
    } else {
      iconPath = 'traffic_green.png'; // Green - Safe distance (>10nm)
    }
    print(
        '🛩️ Aircraft icon for ${_proximityDistance.toStringAsFixed(1)}nm: $iconPath');
    return iconPath;
  }

  /// Get aircraft icon color (fallback for simple icons)
  String _getAircraftColor() {
    if (_proximityDistance < 2.0) {
      return '#FF0000'; // Red - Critical proximity (<2nm)
    } else if (_proximityDistance < 5.0) {
      return '#FFA500'; // Orange - Warning proximity (2-5nm)
    } else if (_proximityDistance < 10.0) {
      return '#FFFF00'; // Yellow - Caution proximity (5-10nm)
    } else {
      return '#00FF00'; // Green - Safe distance (>10nm)
    }
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

  /// Test PNG-based rotatable symbol layers using a simple working approach
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
              'proximityDistance': _proximityDistance, // For dynamic PNG swapping
              'topLabel': '35K',
              'bottomLabel': 'UAL123',
              'isClimbing': _isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleSize': 0.15,
              'arrowSize': 0.08,
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
              'proximityDistance': _proximityDistance + 2.0, // Different proximity for second aircraft
              'topLabel': '28K',
              'bottomLabel': 'DAL456',
              'isClimbing': !_isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleSize': 0.15,
              'arrowSize': 0.08,
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
            },
          },
        ],
      };

      // Add GeoJSON source
      await controller!.addGeoJsonSource('aircraft-png-source', geoJson);
      print('✅ Added GeoJSON source for PNG test');

      // Use the working addRotatableSymbolPngLayers method with correct properties
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'aircraft-png-source',
        baseLayerId: 'aircraft-png-symbol',
        aircraftIconPath: 'traffic.png', // Use single icon for now
        arrowIconPath: 'arrow.png',
        aircraftIconSize: 0.15,
        arrowIconSize: 0.08,
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 350.0,
        },
      );
      
      // Now test PNG swapping by updating the aircraft icon
      await _loadCurrentProximityPng();

      print('✅ Successfully added rotatable symbol layers with PNG icon replacement');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PNG icon replacement working! Try "Test Colors" button'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Error testing rotatable symbol layers: $e');
      print('🔍 Error details: ${e.toString()}');

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
        _proximityDistance = 8.0; // Caution - Blue
      } else {
        _proximityDistance = 3.5; // Warning - Yellow
      }
    });

    _updateAircraftData();
    print(
        '🎨 Color test: ${_proximityDistance.toStringAsFixed(1)}nm - Icon: ${_getAircraftIconPath()}');
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

  /// Clean up existing layers and sources
  Future<void> _cleanupExistingLayers() async {
    if (controller == null) return;
    
    final layerIds = [
      'aircraft-png-symbol',
      'aircraft-png-symbol-triangle',
      'aircraft-png-symbol-top-label', 
      'aircraft-png-symbol-bottom-label',
      'aircraft-png-symbol-arrow',
      'aircraft-text-symbol',
      'aircraft-text-symbol-triangle',
      'aircraft-text-symbol-top-label',
      'aircraft-text-symbol-bottom-label', 
      'aircraft-text-symbol-arrow'
    ];
    
    // Remove layers first
    for (final layerId in layerIds) {
      try {
        await controller!.removeLayer(layerId);
        print('🧹 Removed layer: $layerId');
      } catch (e) {
        // Layer doesn't exist, which is fine
      }
    }
    
    // Remove sources
    try {
      await controller!.removeSource('aircraft-png-source');
      print('🧹 Removed source: aircraft-png-source');
    } catch (e) {
      // Source doesn't exist, which is fine
    }
  }
  
  /// Load all PNG icons into MapLibre style
  Future<void> _loadAllPngIcons() async {
    if (controller == null) return;
    
    final iconAssets = [
      'traffic_red.png',
      'traffic_yellow.png', 
      'traffic_blue.png',
      'traffic_green.png',
      'arrow.png'
    ];
    
    // For now, we don't need to manually load icons as addRotatableSymbolPngLayers handles this
    print('ℹ️ PNG icons will be loaded automatically by addRotatableSymbolPngLayers');
  }
  
  /// Load the current proximity-based PNG and update triangle icon
  Future<void> _loadCurrentProximityPng() async {
    if (controller == null) return;
    
    try {
      // Get the appropriate PNG asset for current proximity
      final currentPngPath = _getAircraftIconPath();
      print('🖼️ Loading PNG asset: $currentPngPath');
      
      // Load the PNG asset as bytes
      final bytes = await rootBundle.load('assets/$currentPngPath');
      
      // Replace the triangle icon with our colored PNG
      await controller!.addImage('maplibre-triangle-icon', bytes.buffer.asUint8List());
      print('✅ Updated triangle icon with: $currentPngPath');
      
    } catch (e) {
      print('❌ Error loading PNG assets: $e');
    }
  }
  
  /// Update the triangle icon with new proximity-based PNG
  Future<void> _updateProximityPng() async {
    if (controller == null) return;
    
    try {
      // Get the new PNG for current proximity
      final newPngPath = _getAircraftIconPath();
      print('🔄 Updating triangle icon to: $newPngPath');
      
      // Load the new PNG asset
      final bytes = await rootBundle.load('assets/$newPngPath');
      
      // Update the triangle icon in MapLibre style
      await controller!.addImage('maplibre-triangle-icon', bytes.buffer.asUint8List());
      print('✅ Updated triangle icon to: $newPngPath');
      
    } catch (e) {
      print('❌ Error updating PNG: $e');
    }
  }
  
  /// Create simple arrow icons programmatically
  Future<void> _createArrowIcons() async {
    // For now, we'll use the PNG arrow or create simple colored rectangles
    // This can be expanded to create programmatic arrows if needed
    print('ℹ️ Using PNG arrow from assets');
  }
  
  /// Create all symbol layers using standard MapLibre methods
  Future<void> _createSymbolLayers() async {
    if (controller == null) return;
    
    final sourceId = 'aircraft-png-source';
    final baseLayerId = 'aircraft-png-symbol';
    
    // Create separate layers for each color variant
    final colorVariants = {
      'red': 'traffic_red.png',
      'yellow': 'traffic_yellow.png', 
      'blue': 'traffic_blue.png',
      'green': 'traffic_green.png',
    };
    
    // Create a layer for each color variant
    for (final entry in colorVariants.entries) {
      final color = entry.key;
      final assetPath = entry.value;
      
      try {
        await controller!.addRotatableSymbolPngLayers(
          sourceId: sourceId,
          baseLayerId: '$baseLayerId-$color',
          aircraftIconPath: assetPath,
          arrowIconPath: 'arrow.png',
          aircraftIconSize: 0.15,
          arrowIconSize: 0.08,
          enableInteraction: true,
          config: {
            'topLabelOffset': -2.5,
            'bottomLabelOffset': 2.5,
            'arrowOffsetX': 350.0,
          },
        );
        print('✅ Created PNG symbol layer for $color using $assetPath');
        
        // Initially hide all layers except green (safe)
        if (color != 'green') {
          await controller!.setLayerVisibility('$baseLayerId-$color', false);
          await controller!.setLayerVisibility('$baseLayerId-$color-top-label', false);
          await controller!.setLayerVisibility('$baseLayerId-$color-bottom-label', false);
          await controller!.setLayerVisibility('$baseLayerId-$color-arrow', false);
        }
        
      } catch (e) {
        print('❌ Error creating layer for $color: $e');
      }
    }
    
    print('✅ Created multiple PNG symbol layers with visibility control');
  }
  
  /// Update layer visibility based on proximity distance
  Future<void> _updateLayerVisibilityForProximity() async {
    if (controller == null) return;
    
    final baseLayerId = 'aircraft-png-symbol';
    final colorVariants = ['red', 'yellow', 'blue', 'green'];
    
    // Determine which color should be visible
    String activeColor;
    if (_proximityDistance < 2.0) {
      activeColor = 'red';
    } else if (_proximityDistance < 5.0) {
      activeColor = 'yellow';
    } else if (_proximityDistance < 10.0) {
      activeColor = 'blue';
    } else {
      activeColor = 'green';
    }
    
    // Update visibility for all color variants
    for (final color in colorVariants) {
      final isVisible = (color == activeColor);
      
      try {
        await controller!.setLayerVisibility('$baseLayerId-$color', isVisible);
        await controller!.setLayerVisibility('$baseLayerId-$color-top-label', isVisible);
        await controller!.setLayerVisibility('$baseLayerId-$color-bottom-label', isVisible);
        await controller!.setLayerVisibility('$baseLayerId-$color-arrow', isVisible);
      } catch (e) {
        print('❌ Error updating visibility for $color: $e');
      }
    }
    
    print('🎨 Updated layer visibility - Active: $activeColor for ${_proximityDistance.toStringAsFixed(1)}nm');
  }

  /// Update the aircraft icon path method to return the icon name for dynamic selection
  String _getAircraftIconName() {
    String iconName;
    if (_proximityDistance < 2.0) {
      iconName = 'traffic_red'; // Red - Critical proximity (<2nm)
    } else if (_proximityDistance < 5.0) {
      iconName = 'traffic_yellow'; // Yellow - Warning proximity (2-5nm) 
    } else if (_proximityDistance < 10.0) {
      iconName = 'traffic_blue'; // Blue - Caution proximity (5-10nm)
    } else {
      iconName = 'traffic_green'; // Green - Safe distance (>10nm)
    }
    print('🛮 Aircraft icon for ${_proximityDistance.toStringAsFixed(1)}nm: $iconName');
    return iconName;
  }

  /// Update aircraft data on the map and PNG icons
  Future<void> _updateAircraftData() async {
    if (controller == null) return;

    try {
      // Update the PNG icon first
      await _updateProximityPng();
      
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
              'proximityDistance': _proximityDistance, // For dynamic PNG swapping
              'topLabel': '35K',
              'bottomLabel': 'UAL123',
              'isClimbing': _isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleSize': 0.15,
              'arrowSize': 0.08,
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
              'proximityDistance': _proximityDistance + 2.0, // Different proximity for second aircraft
              'topLabel': '28K',
              'bottomLabel': 'DAL456',
              'isClimbing': !_isClimbing,
              'labelSize': 14.0,
              'labelColor': '#000000',
              'triangleSize': 0.15,
              'arrowSize': 0.08,
              'triangleOpacity': 1.0,
              'arrowOpacity': 1.0,
            },
          },
        ],
      };

      await controller!.setGeoJsonSource('aircraft-png-source', updatedGeoJson);
      print('🔄 Updated aircraft data - Distance: ${_proximityDistance.toStringAsFixed(1)}nm, Icon: ${_getAircraftIconPath()}');
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
                  'Testing PNG Icon Replacement for aviation symbols:\n'
                  '• Standard rotatable symbol layers (working triangles)\n'
                  '• Dynamic PNG replacement of triangle icon\n'
                  '• Real-time icon swapping based on proximity\n'
                  '• Preserved black outlines (no SDF tinting)\n'
                  '• Proximity colors: Red(<2nm), Yellow(2-5nm), Blue(5-10nm), Green(>10nm)\n'
                  '• Use "Test Colors" button to see PNG swapping!',
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
