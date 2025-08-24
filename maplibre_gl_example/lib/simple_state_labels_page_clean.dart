import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class StateLocation {
  final String name;
  final String abbreviation;
  final LatLng coordinates;
  final Color color;

  StateLocation(this.name, this.abbreviation, this.coordinates, this.color);
}

class SimpleStateLabelsPage extends ExamplePage {
  const SimpleStateLabelsPage({super.key})
      : super(const Icon(Icons.location_on), 'Native State Labels');

  @override
  Widget build(BuildContext context) => const _SimpleStateLabelsMap();
}

class _SimpleStateLabelsMap extends StatefulWidget {
  const _SimpleStateLabelsMap();

  @override
  State<_SimpleStateLabelsMap> createState() => _SimpleStateLabelsMapState();
}

class _SimpleStateLabelsMapState extends State<_SimpleStateLabelsMap> {
  MapLibreMapController? _mapController;
  final Map<String, StateLocation> _symbolToStateMap = {};
  bool _isStressTesting = false;
  int _stressTestSymbolCount = 0;
  final Random _random = Random();

  // US center
  static const _initialCamera = CameraPosition(
    target: LatLng(39.8283, -98.5795),
    zoom: 4.0,
  );

  // State locations with their coordinates
  final List<StateLocation> _stateLocations = [
    StateLocation('California', 'CA', LatLng(36.7783, -119.4179), Colors.blue),
    StateLocation('Texas', 'TX', LatLng(31.9686, -99.9018), Colors.red),
    StateLocation('Florida', 'FL', LatLng(27.7663, -82.6404), Colors.green),
    StateLocation('New York', 'NY', LatLng(42.1657, -74.9481), Colors.purple),
    StateLocation('Illinois', 'IL', LatLng(40.3363, -89.0022), Colors.orange),
    StateLocation('Pennsylvania', 'PA', LatLng(40.5908, -77.2098), Colors.teal),
    StateLocation('Ohio', 'OH', LatLng(40.3888, -82.7649), Colors.indigo),
    StateLocation('Georgia', 'GA', LatLng(33.0406, -83.6431), Colors.pink),
    StateLocation(
        'North Carolina', 'NC', LatLng(35.5175, -80.8031), Colors.cyan),
    StateLocation('Michigan', 'MI', LatLng(43.3266, -84.5361), Colors.amber),
  ];

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;

    // Add symbol tap handler
    controller.onSymbolTapped.add(_onSymbolTapped);

    // Wait a bit for the map to fully load
    await Future.delayed(const Duration(milliseconds: 500));

    // Generate custom widget images for each state
    await _generateStateImages();

    // Add symbols with custom images for each state
    await _addStateSymbols();
  }

  Future<void> _generateStateImages() async {
    if (_mapController == null) return;

    for (int i = 0; i < _stateLocations.length; i++) {
      final state = _stateLocations[i];
      final imageBytes = await _createWidgetImage(state);

      // Add the custom image to the map style
      await _mapController!
          .addImage('state-${state.abbreviation.toLowerCase()}', imageBytes);
    }
  }

  Future<Uint8List> _createWidgetImage(StateLocation state) async {
    // Create a simple container with the state info that can be easily converted to image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // First, measure the text to determine chip size
    final nameTextPainter = TextPainter(
      text: TextSpan(
        text: state.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    nameTextPainter.layout();

    final abbreviationTextPainter = TextPainter(
      text: TextSpan(
        text: state.abbreviation,
        style: TextStyle(
          color: state.color,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    abbreviationTextPainter.layout();

    // Calculate dynamic chip dimensions
    const double circleRadius = 22;
    const double horizontalPadding = 20;
    const double spaceBetween = 14;
    const double verticalPadding = 16;

    final double chipWidth = horizontalPadding +
        (circleRadius * 2) +
        spaceBetween +
        nameTextPainter.width +
        horizontalPadding;
    final double chipHeight = verticalPadding * 2 +
        (nameTextPainter.height > circleRadius * 2
            ? nameTextPainter.height
            : circleRadius * 2);

    // Paint the background with rounded corners
    final backgroundPaint = Paint()
      ..color = state.color.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final double radius = chipHeight / 2;

    final rect = Rect.fromLTWH(0, 0, chipWidth, chipHeight);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Draw shadow
    final shadowRect = rect.translate(0, 3);
    final shadowRRect =
        RRect.fromRectAndRadius(shadowRect, Radius.circular(radius));
    canvas.drawRRect(shadowRRect, shadowPaint);

    // Draw background
    canvas.drawRRect(rrect, backgroundPaint);

    // Draw border
    canvas.drawRRect(rrect, borderPaint);

    // Draw the circle for abbreviation
    final circlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final circleCenter =
        Offset(horizontalPadding + circleRadius, chipHeight / 2);
    canvas.drawCircle(circleCenter, circleRadius, circlePaint);

    // Draw abbreviation text centered in circle
    abbreviationTextPainter.paint(
      canvas,
      Offset(circleCenter.dx - abbreviationTextPainter.width / 2,
          circleCenter.dy - abbreviationTextPainter.height / 2),
    );

    // Draw state name text
    final nameX = horizontalPadding + (circleRadius * 2) + spaceBetween;
    final nameY = chipHeight / 2 - nameTextPainter.height / 2;
    nameTextPainter.paint(canvas, Offset(nameX, nameY));

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(chipWidth.toInt(), chipHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<void> _addStateSymbols() async {
    if (_mapController == null) return;

    // Add symbols for each state location using custom images
    for (int i = 0; i < _stateLocations.length; i++) {
      final state = _stateLocations[i];

      final symbol = await _mapController!.addSymbol(
        SymbolOptions(
          geometry: state.coordinates,
          iconImage: 'state-${state.abbreviation.toLowerCase()}',
          iconSize: 1.0,
          iconAnchor: 'center',
          iconOffset: const Offset(0, 0),
        ),
      );

      // Store the mapping for tap handling
      _symbolToStateMap[symbol.id] = state;
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final state = _symbolToStateMap[symbol.id];
    if (state != null) {
      _showStateInfo(state);
    }
  }

  void _showStateInfo(StateLocation state) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: state.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    state.abbreviation,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Coordinates:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        const Text('Latitude: ',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          state.coordinates.latitude.toStringAsFixed(4),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text('Longitude: ',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          state.coordinates.longitude.toStringAsFixed(4),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(state.coordinates, 6.0),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: state.color,
                foregroundColor: Colors.white,
              ),
              child: const Text('Zoom to Location'),
            ),
          ],
        );
      },
    );
  }

  // OPTIMIZED Stress test methods
  Future<void> _generateTemplateImages() async {
    if (_mapController == null) return;

    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.deepOrange,
      Colors.deepPurple,
      Colors.lightBlue,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.brown,
      Colors.grey,
    ];

    for (int i = 0; i < colors.length; i++) {
      final templateState = StateLocation(
        'Template',
        '${i + 1}'.padLeft(2, '0'),
        LatLng(0, 0), // Coordinates don't matter for templates
        colors[i],
      );

      final imageBytes = await _createWidgetImage(templateState);
      await _mapController!.addImage('template-$i', imageBytes);
    }

    print('📸 Generated ${colors.length} template images for reuse');
  }

  Future<void> _runStressTest() async {
    if (_mapController == null || _isStressTesting) return;

    setState(() {
      _isStressTesting = true;
      _stressTestSymbolCount = 0;
    });

    final stopwatch = Stopwatch()..start();

    try {
      print('🚀 Starting OPTIMIZED stress test: 10,000 random chips...');

      // OPTIMIZATION 1: Create only template images instead of unique ones
      print('📸 Generating template chip images...');
      await _generateTemplateImages();

      // Generate random state data for stress testing
      final stressTestStates = _generateRandomStates(10000);

      print('🎯 Adding symbols to map (using templates)...');

      // OPTIMIZATION 2: Batch symbol additions
      final symbolOptionsList = <SymbolOptions>[];
      final symbolDataList = <Map<String, dynamic>>[];

      for (int i = 0; i < stressTestStates.length; i++) {
        final state = stressTestStates[i];

        // Use template images instead of unique ones
        final templateIndex = i % 18; // 18 different colors/templates

        symbolOptionsList.add(SymbolOptions(
          geometry: state.coordinates,
          iconImage: 'template-$templateIndex',
          iconSize: 0.6, // Smaller for better performance
          iconAnchor: 'center',
          iconOffset: const Offset(0, 0),
        ));

        symbolDataList.add({'stateData': state, 'index': i});

        // Update progress every 2000 symbols
        if ((i + 1) % 2000 == 0) {
          print('Prepared ${i + 1}/10,000 symbols...');
          setState(() {
            _stressTestSymbolCount = i + 1;
          });
        }
      }

      // OPTIMIZATION 3: Batch add symbols (much faster!)
      print('🚀 Batch adding all symbols...');
      final symbols =
          await _mapController!.addSymbols(symbolOptionsList, symbolDataList);

      // Store mappings for tap handling
      for (int i = 0; i < symbols.length; i++) {
        final symbol = symbols[i];
        final stateData = symbolDataList[i]['stateData'] as StateLocation;
        _symbolToStateMap[symbol.id] = stateData;
      }

      stopwatch.stop();
      print('✅ OPTIMIZED stress test completed!');
      print(
          '⏱️  Total time: ${stopwatch.elapsedMilliseconds}ms (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      print('📊 Created 10,000 symbols using template optimization');

      // Show completion dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Optimized Stress Test Complete!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✅ Created 10,000 symbols using templates'),
                Text(
                    '⏱️ Time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'),
                Text(
                    '🚀 ${(10000 / (stopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(0)} symbols/second'),
                const SizedBox(height: 8),
                const Text('Much faster using template images!'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Stress test failed: $e');
    } finally {
      setState(() {
        _isStressTesting = false;
      });
    }
  }

  List<StateLocation> _generateRandomStates(int count) {
    final states = <StateLocation>[];
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.deepOrange,
      Colors.deepPurple,
      Colors.lightBlue,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.brown,
      Colors.grey,
    ];

    final cityNames = [
      'Tokyo',
      'Delhi',
      'Shanghai',
      'São Paulo',
      'Mexico City',
      'Cairo',
      'Mumbai',
      'Beijing',
      'Dhaka',
      'Osaka',
      'New York',
      'Karachi',
      'Buenos Aires',
      'Chongqing',
      'Istanbul',
      'Kolkata',
      'Manila',
      'Lagos',
      'Rio de Janeiro',
      'Tianjin',
      'Kinshasa',
      'Guangzhou',
      'Los Angeles',
      'Moscow',
      'Shenzhen',
      'Lahore',
      'Bangalore',
      'Paris',
      'Bogotá',
      'Jakarta',
      'Chennai',
      'Lima',
      'Bangkok',
      'Seoul',
      'Nagoya',
      'Hyderabad',
      'London',
      'Tehran',
      'Chicago',
      'Chengdu',
    ];

    for (int i = 0; i < count; i++) {
      // Generate random coordinates (latitude: -90 to 90, longitude: -180 to 180)
      final lat = _random.nextDouble() * 180 - 90; // -90 to 90
      final lng = _random.nextDouble() * 360 - 180; // -180 to 180

      final cityName = cityNames[_random.nextInt(cityNames.length)];
      final abbreviation = '${(i + 1).toString().padLeft(2, '0')}';
      final color = colors[_random.nextInt(colors.length)];

      states.add(StateLocation(
        '$cityName $abbreviation',
        abbreviation,
        LatLng(lat, lng),
        color,
      ));
    }

    return states;
  }

  Future<void> _clearStressTest() async {
    if (_mapController == null) return;

    print('🧹 Clearing stress test symbols...');
    await _mapController!.clearSymbols();

    // Re-add original state symbols
    await _generateStateImages();
    await _addStateSymbols();

    setState(() {
      _stressTestSymbolCount = 0;
    });

    print('✅ Cleared stress test, restored original symbols');
  }

  @override
  void dispose() {
    _mapController?.onSymbolTapped.remove(_onSymbolTapped);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native State Labels'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          // Stress test button
          IconButton(
            icon: const Icon(Icons.speed),
            onPressed: _isStressTesting ? null : _runStressTest,
            tooltip: 'Run Stress Test (10K chips)',
          ),
          // Clear stress test button
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _isStressTesting ? null : _clearStressTest,
            tooltip: 'Clear Stress Test',
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (_mapController != null) {
                await _mapController!.clearSymbols();
                await _generateStateImages();
                await _addStateSymbols();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: 'https://demotiles.maplibre.org/style.json',
            initialCameraPosition: _initialCamera,
            onMapCreated: _onMapCreated,
            myLocationEnabled: false,
            compassEnabled: true,
            tiltGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
          ),
          // Floating info panel
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Native Map Labels',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isStressTesting) ...[
                    const Text(
                      'Running Stress Test...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 200, // Fixed width for progress bar
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.grey.shade300,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.red.shade600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Symbols: $_stressTestSymbolCount/10,000',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'GPU-accelerated symbols\nthat move with the map',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed,
                            size: 16, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        const Text(
                          'GPU Accelerated',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Bottom instructions
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isStressTesting
                    ? 'Stress test in progress... Creating 10,000 random chips worldwide!'
                    : 'Tap any state label to see info. Use the speed icon (⚡) to run a 10K chip stress test!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
