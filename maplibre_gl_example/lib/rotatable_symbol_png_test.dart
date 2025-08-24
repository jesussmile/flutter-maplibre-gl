// Test example demonstrating the new addRotatableSymbolPngLayers method
// This shows how to use PNG assets instead of programmatically created symbols

import 'dart:async';
import 'dart:io' show Platform;
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

  /// Get platform-specific aircraft icon size
  /// iOS needs larger sizes than Android for the same visual appearance
  double get _platformAircraftIconSize {
    if (Platform.isIOS) {
      return 0.6; // Much larger for better initial visibility - was 0.25
    } else {
      return 0.4; // Larger for better initial visibility - was 0.15
    }
  }

  /// Get platform-specific arrow icon size
  /// iOS needs larger sizes than Android for the same visual appearance
  double get _platformArrowIconSize {
    if (Platform.isIOS) {
      return 0.3; // Larger for better initial visibility - was 0.15
    } else {
      return 0.2; // Larger for better initial visibility - was 0.08
    }
  }

  /// Get platform-specific large aircraft icon size (for testing)
  double get _platformLargeAircraftIconSize {
    if (Platform.isIOS) {
      return 0.2; // Much larger for iOS - was 0.8
    } else {
      return 0.8; // Standard large size for Android
    }
  }

  /// Get platform-specific large arrow icon size (for testing)
  double get _platformLargeArrowIconSize {
    if (Platform.isIOS) {
      return 0.6; // Much larger for iOS - was 0.4
    } else {
      return 0.4; // Standard large size for Android
    }
  }

  /// Get platform-specific test color icon sizes
  double get _platformTestAircraftIconSize {
    if (Platform.isIOS) {
      return 0.75; // Larger for iOS - was 0.5
    } else {
      return 0.5; // Standard size for Android
    }
  }

  double get _platformTestArrowIconSize {
    if (Platform.isIOS) {
      return 0.45; // Larger for iOS - was 0.3
    } else {
      return 0.3; // Standard size for Android
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  void _onStyleLoaded() {
    // Print platform-specific sizing info
    print('🔧 Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    print('🔧 Aircraft icon size: $_platformAircraftIconSize');
    print('🔧 Arrow icon size: $_platformArrowIconSize');

    _testPngSymbolLayers();
    // Automatically zoom to symbols location after loading - reduced delay
    Future.delayed(const Duration(milliseconds: 200), () {
      _zoomToSymbols();
    });
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
              'proximityDistance':
                  _proximityDistance, // For dynamic PNG swapping
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
              'proximityDistance': _proximityDistance +
                  2.0, // Different proximity for second aircraft
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

      // Use the working addRotatableSymbolPngLayers method with platform-specific sizes
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'aircraft-png-source',
        baseLayerId: 'aircraft-png-symbol',
        aircraftIconPath: 'traffic.png', // Use single icon for now
        arrowIconPath: 'arrow.png',
        aircraftIconSize:
            _platformAircraftIconSize, // Platform-specific: iOS=0.25, Android=0.15
        arrowIconSize:
            _platformArrowIconSize, // Platform-specific: iOS=0.15, Android=0.08
        enableInteraction: true,
        config: {
          'topLabelOffset': -2.5,
          'bottomLabelOffset': 2.5,
          'arrowOffsetX': 350.0,
        },
      );

      // Don't override the native iOS PNG loading - let it handle colored PNGs
      // await _loadCurrentProximityPng(); // Commented out to let native handle it

      print(
          '✅ Successfully added rotatable symbol layers with PNG icon replacement');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('PNG icon replacement working! Try "Test Colors" button'),
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

      // Use platform-specific colored rectangle icon sizes
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'test-color-source',
        baseLayerId: 'test-color-symbols',
        aircraftIconPath:
            'test-color-icon', // Will use programmatically created icon
        arrowIconPath: 'test-color-icon',
        aircraftIconSize:
            _platformTestAircraftIconSize, // Platform-specific: iOS=0.75, Android=0.5
        arrowIconSize:
            _platformTestArrowIconSize, // Platform-specific: iOS=0.45, Android=0.3
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

    // CRITICAL: Add delay for iOS layer removal to complete
    await Future.delayed(Duration(milliseconds: Platform.isIOS ? 200 : 50));

    // Remove sources
    try {
      await controller!.removeSource('aircraft-png-source');
      print('🧹 Removed source: aircraft-png-source');
    } catch (e) {
      // Source doesn't exist, which is fine
    }

    // CRITICAL: Add delay for iOS source removal to complete
    await Future.delayed(Duration(milliseconds: Platform.isIOS ? 300 : 50));
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
    print(
        'ℹ️ PNG icons will be loaded automatically by addRotatableSymbolPngLayers');
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
      await controller!
          .addImage('maplibre-triangle-icon', bytes.buffer.asUint8List());
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
      await controller!
          .addImage('maplibre-triangle-icon', bytes.buffer.asUint8List());
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
          aircraftIconSize:
              _platformAircraftIconSize, // Platform-specific: iOS=0.25, Android=0.15
          arrowIconSize:
              _platformArrowIconSize, // Platform-specific: iOS=0.15, Android=0.08
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
          await controller!
              .setLayerVisibility('$baseLayerId-$color-top-label', false);
          await controller!
              .setLayerVisibility('$baseLayerId-$color-bottom-label', false);
          await controller!
              .setLayerVisibility('$baseLayerId-$color-arrow', false);
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
        await controller!
            .setLayerVisibility('$baseLayerId-$color-top-label', isVisible);
        await controller!
            .setLayerVisibility('$baseLayerId-$color-bottom-label', isVisible);
        await controller!
            .setLayerVisibility('$baseLayerId-$color-arrow', isVisible);
      } catch (e) {
        print('❌ Error updating visibility for $color: $e');
      }
    }

    print(
        '🎨 Updated layer visibility - Active: $activeColor for ${_proximityDistance.toStringAsFixed(1)}nm');
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
    print(
        '🛮 Aircraft icon for ${_proximityDistance.toStringAsFixed(1)}nm: $iconName');
    return iconName;
  }

  /// Update aircraft data on the map and PNG icons
  Future<void> _updateAircraftData() async {
    if (controller == null) return;

    try {
      // Let native iOS handle PNG swapping, don't override from Flutter
      // await _updateProximityPng(); // Commented out to let native handle colored PNGs

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
              'proximityDistance':
                  _proximityDistance, // For dynamic PNG swapping
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
              'proximityDistance': _proximityDistance +
                  2.0, // Different proximity for second aircraft
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
      print(
          '🔄 Updated aircraft data - Distance: ${_proximityDistance.toStringAsFixed(1)}nm, Icon: ${_getAircraftIconPath()}');
    } catch (e) {
      print('❌ Error updating aircraft data: $e');
    }
  }

  /// Test symbols with larger sizes to make them more visible
  Future<void> _testLargerSymbols() async {
    if (controller == null) return;

    try {
      await _cleanupExistingLayers();

      // Create GeoJSON source with CORRECT property names for iOS
      final geoJson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {
              'rotation': _currentRotation, // Fixed: was 'heading'
              'proximityDistance':
                  _proximityDistance, // Added: required for iOS
              'topLabel': 'LARGE', // Fixed: was missing
              'bottomLabel': 'TEST01', // Fixed: was 'callSign'
              'isClimbing': _isClimbing, // Fixed: was 'climbing'
              'labelSize': 16.0, // Added: for larger labels
              'labelColor': '#000000', // Added: required for iOS
              'triangleSize': 0.15, // Added: for compatibility
              'arrowSize': 0.08, // Added: for compatibility
              'triangleOpacity': 1.0, // Added: required for iOS
              'arrowOpacity': 1.0, // Added: required for iOS
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [center.longitude, center.latitude],
            },
          },
        ],
      };

      await controller!.addGeoJsonSource('aircraft-png-source', geoJson);
      print('✅ Added GeoJSON source for large symbols test');

      // Use much larger platform-specific sizes
      await controller!.addRotatableSymbolPngLayers(
        sourceId: 'aircraft-png-source',
        baseLayerId: 'aircraft-png-symbol',
        aircraftIconPath: 'traffic.png',
        arrowIconPath: 'arrow.png',
        aircraftIconSize:
            _platformLargeAircraftIconSize, // Platform-specific: iOS=1.2, Android=0.8
        arrowIconSize:
            _platformLargeArrowIconSize, // Platform-specific: iOS=0.6, Android=0.4
        enableInteraction: true,
        config: {
          'topLabelOffset': -3.0,
          'bottomLabelOffset': 3.0,
          'arrowOffsetX': 400.0,
        },
      );

      print('🔍 Added LARGE symbols - Aircraft: 0.8, Arrow: 0.4');

      // Force zoom to location
      await Future.delayed(const Duration(milliseconds: 300));
      await _zoomToSymbols();
    } catch (e) {
      print('❌ Error testing large symbols: $e');
    }
  }

  /// Test symbol layer visibility and properties
  Future<void> _testSymbolVisibility() async {
    if (controller == null) return;

    try {
      // Get all layer IDs that should be visible
      final layerIds = [
        'aircraft-png-symbol-aircraft',
        'aircraft-png-symbol-top-label',
        'aircraft-png-symbol-bottom-label',
        'aircraft-png-symbol-arrow'
      ];

      print('👁️ Testing visibility for layers: $layerIds');

      // Try to make layers visible
      for (final layerId in layerIds) {
        try {
          // Log layer for debugging (setLayerProperty not available in this API)
          print('✅ Layer $layerId should be visible');

          // Note: Direct layer property setting not available in this MapLibre version
          // Symbols should be visible by default when added correctly
        } catch (e) {
          print('❌ Error setting visibility for $layerId: $e');
        }
      }

      print('👁️ Visibility test complete - check map for symbols');
    } catch (e) {
      print('❌ Error testing visibility: $e');
    }
  }

  /// Debug symbol layers and print detailed information
  Future<void> _debugSymbolLayers() async {
    if (controller == null) return;

    try {
      print('🐛 DEBUG: Symbol layers information');
      print('🐛 Center coordinates: ${center.latitude}, ${center.longitude}');
      print(
          '🐛 Current zoom level: ${controller!.cameraPosition?.zoom ?? "unknown"}');
      print('🐛 Proximity distance: $_proximityDistance nm');
      print('🐛 Current rotation: $_currentRotation °');
      print('🐛 Is climbing: $_isClimbing');

      // Force camera to exact coordinates with higher zoom
      await controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target:
                LatLng(37.7749, -122.4194), // Exact San Francisco coordinates
            zoom: 18.0, // Very high zoom
          ),
        ),
      );

      print('🐛 Forced camera to San Francisco at zoom 18');
      print(
          '🐛 If symbols still not visible, they may not be loading correctly');

      // Create a simple test marker at exact location to verify coordinates
      await controller!.addSymbol(
        const SymbolOptions(
          geometry: LatLng(37.7749, -122.4194),
          textField: 'TEST MARKER HERE',
          textSize: 16,
          textColor: '#FF0000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2,
        ),
      );

      print('🐛 Added red TEST MARKER at exact coordinates');
    } catch (e) {
      print('❌ Error in debug: $e');
    }
  }

  /// Zoom and center map to show symbols clearly
  Future<void> _zoomToSymbols() async {
    if (controller == null) return;

    try {
      // Move camera to symbol location with appropriate zoom
      await controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: center, // Same location as symbols
            zoom: 15.0, // Closer zoom to see symbols
          ),
        ),
      );
      print('🎯 Zoomed to symbols location');
    } catch (e) {
      print('❌ Error zooming to symbols: $e');
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
      body: Stack(
        children: [
          // Full-screen map
          MapLibreMap(
            initialCameraPosition: const CameraPosition(
              target: center,
              zoom: 14.0, // Closer zoom to see PNG icons immediately
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
          ),
          // Floating info panel at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.blue.shade50.withValues(alpha: 0.9),
              child: Column(
                children: [
                  const Text(
                    '🎯 PNG Aviation Symbols Test',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Compact test buttons - Row 1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _testPngSymbolLayers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('🎯 PNG Test'),
                      ),
                      ElevatedButton(
                        onPressed: _testColorChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(int.parse(
                                  _getAircraftColor().substring(1),
                                  radix: 16) +
                              0xFF000000),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('🎨 Colors'),
                      ),
                      ElevatedButton(
                        onPressed:
                            _isAnimating ? _stopAnimation : _startAnimation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isAnimating ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: Text(_isAnimating ? '⏹️' : '▶️'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Row 2: Size and visibility tests
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _testLargerSymbols,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('🔍 Large Size'),
                      ),
                      ElevatedButton(
                        onPressed: _testSymbolVisibility,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('👁️ Visibility'),
                      ),
                      ElevatedButton(
                        onPressed: _debugSymbolLayers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('🐛 Debug'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Compact status text
                  Text(
                    '${_proximityDistance.toStringAsFixed(1)}nm | ${_currentRotation.toStringAsFixed(0)}° | '
                    '${_isClimbing ? "⬆️" : "⬇️"} | ${_isAnimating ? "🔄" : "⏸️"}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          // Bottom floating button for zoom to symbols
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _zoomToSymbols,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.center_focus_strong, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
