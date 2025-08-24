import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class USStateLabelsPage extends ExamplePage {
  const USStateLabelsPage({super.key})
      : super(const Icon(Icons.label), 'US State Labels with Styling');

  @override
  Widget build(BuildContext context) => const _USStateLabelsMap();
}

class _USStateLabelsMap extends StatefulWidget {
  const _USStateLabelsMap();

  @override
  State<_USStateLabelsMap> createState() => _USStateLabelsMapState();
}

class StateLabel {
  final String name;
  final LatLng position;
  final Color color;
  final String abbreviation;

  const StateLabel({
    required this.name,
    required this.position,
    required this.color,
    required this.abbreviation,
  });
}

class _USStateLabelsMapState extends State<_USStateLabelsMap> {
  MapLibreMapController? _mapController;
  Timer? _updateTimer;
  Map<String, Offset> _labelPositions = {};
  double _currentZoom = 4.0;

  // US center
  static const _initialCamera = CameraPosition(
    target: LatLng(39.8283, -98.5795),
    zoom: 4.0,
  );

  // Sample US states with their approximate center coordinates
  final List<StateLabel> _stateLabels = const [
    StateLabel(
      name: 'California',
      abbreviation: 'CA',
      position: LatLng(36.7783, -119.4179),
      color: Color(0xFF2196F3),
    ),
    StateLabel(
      name: 'Texas',
      abbreviation: 'TX',
      position: LatLng(31.9686, -99.9018),
      color: Color(0xFFFF5722),
    ),
    StateLabel(
      name: 'Florida',
      abbreviation: 'FL',
      position: LatLng(27.7663, -81.6868),
      color: Color(0xFF4CAF50),
    ),
    StateLabel(
      name: 'New York',
      abbreviation: 'NY',
      position: LatLng(42.1657, -74.9481),
      color: Color(0xFF9C27B0),
    ),
    StateLabel(
      name: 'Illinois',
      abbreviation: 'IL',
      position: LatLng(40.3363, -89.0022),
      color: Color(0xFFFF9800),
    ),
    StateLabel(
      name: 'Pennsylvania',
      abbreviation: 'PA',
      position: LatLng(41.2033, -77.1945),
      color: Color(0xFF607D8B),
    ),
    StateLabel(
      name: 'Ohio',
      abbreviation: 'OH',
      position: LatLng(40.3888, -82.7649),
      color: Color(0xFFE91E63),
    ),
    StateLabel(
      name: 'Georgia',
      abbreviation: 'GA',
      position: LatLng(33.0406, -83.6431),
      color: Color(0xFF795548),
    ),
    StateLabel(
      name: 'North Carolina',
      abbreviation: 'NC',
      position: LatLng(35.5397, -79.8431),
      color: Color(0xFF009688),
    ),
    StateLabel(
      name: 'Michigan',
      abbreviation: 'MI',
      position: LatLng(43.3266, -84.5361),
      color: Color(0xFF3F51B5),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startPositionUpdates();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startPositionUpdates() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateLabelPositions();
    });
  }

  Future<void> _updateLabelPositions() async {
    if (_mapController == null || !mounted) return;

    final newPositions = <String, Offset>{};

    for (final state in _stateLabels) {
      try {
        final screenPoint =
            await _mapController!.toScreenLocation(state.position);
        newPositions[state.abbreviation] =
            Offset(screenPoint.x.toDouble(), screenPoint.y.toDouble());
      } catch (e) {
        // Handle conversion errors
      }
    }

    if (mounted) {
      setState(() {
        _labelPositions = newPositions;
      });
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _updateLabelPositions();

    // Listen for camera changes
    controller.addListener(() {
      _updateLabelPositions();
    });
  }

  Widget _buildStateLabel(StateLabel state, double zoom) {
    // Scale label based on zoom level
    final double scale = (zoom / 4.0).clamp(0.6, 1.4);
    final double fontSize = (14 * scale).clamp(10.0, 18.0);
    final double padding = (12 * scale).clamp(8.0, 16.0);
    final double circleSize = (24 * scale).clamp(18.0, 32.0);

    return Transform.scale(
      scale: scale,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.5),
        decoration: BoxDecoration(
          color: state.color.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20 * scale),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4 * scale,
              offset: Offset(0, 2 * scale),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(circleSize / 2),
              ),
              child: Center(
                child: Text(
                  state.abbreviation,
                  style: TextStyle(
                    color: state.color,
                    fontSize: (10 * scale).clamp(8.0, 14.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            Text(
              state.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('US State Labels with Styling'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
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
          // Overlay state labels
          ..._stateLabels.map((state) {
            final position = _labelPositions[state.abbreviation];
            if (position == null) return const SizedBox.shrink();

            // Calculate if the label should be visible
            final screenSize = MediaQuery.of(context).size;
            final isVisible = position.dx >= -150 &&
                position.dx <= screenSize.width + 150 &&
                position.dy >= -40 &&
                position.dy <= screenSize.height + 40;

            if (!isVisible) return const SizedBox.shrink();

            return Positioned(
              left: position.dx - 75, // Center the label
              top: position.dy - 20, // Offset above the point
              child: _buildStateLabel(state, _currentZoom),
            );
          }),
          // Legend
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'State Labels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Interactive styling example\nwith rounded containers',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'State Abbreviation',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Instructions
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade700.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Zoom and pan the map to see styled state labels with rounded containers and color coding',
                style: TextStyle(
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
