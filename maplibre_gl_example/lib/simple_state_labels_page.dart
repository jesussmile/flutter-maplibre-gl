import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class SimpleStateLabelsPage extends ExamplePage {
  const SimpleStateLabelsPage({super.key})
      : super(const Icon(Icons.location_on), 'Simple State Labels');

  @override
  Widget build(BuildContext context) => const _SimpleStateLabelsMap();
}

class _SimpleStateLabelsMap extends StatefulWidget {
  const _SimpleStateLabelsMap();

  @override
  State<_SimpleStateLabelsMap> createState() => _SimpleStateLabelsMapState();
}

class _SimpleStateLabelsMapState extends State<_SimpleStateLabelsMap> {
  // US center
  static const _initialCamera = CameraPosition(
    target: LatLng(39.8283, -98.5795),
    zoom: 4.0,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple State Labels'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: 'https://demotiles.maplibre.org/style.json',
            initialCameraPosition: _initialCamera,
            onMapCreated: (controller) {},
            myLocationEnabled: false,
            compassEnabled: true,
            tiltGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
          ),
          // Static positioned labels as examples
          const Positioned(
            left: 100,
            top: 200,
            child: _StaticLabel(
              name: 'California',
              abbreviation: 'CA',
              color: Color(0xFF2196F3),
            ),
          ),
          const Positioned(
            left: 300,
            top: 350,
            child: _StaticLabel(
              name: 'Texas',
              abbreviation: 'TX',
              color: Color(0xFFFF5722),
            ),
          ),
          const Positioned(
            left: 500,
            top: 450,
            child: _StaticLabel(
              name: 'Florida',
              abbreviation: 'FL',
              color: Color(0xFF4CAF50),
            ),
          ),
          const Positioned(
            left: 250,
            top: 150,
            child: _StaticLabel(
              name: 'New York',
              abbreviation: 'NY',
              color: Color(0xFF9C27B0),
            ),
          ),
          const Positioned(
            left: 200,
            top: 250,
            child: _StaticLabel(
              name: 'Illinois',
              abbreviation: 'IL',
              color: Color(0xFFFF9800),
            ),
          ),
          // Floating controls
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
                    'Label Styles Demo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Different styling examples\nfor map labels',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LabelStyleExample(
                        color: Colors.blue,
                        text: 'Type 1',
                      ),
                      const SizedBox(width: 8),
                      _LabelStyleExample(
                        color: Colors.red,
                        text: 'Type 2',
                      ),
                    ],
                  ),
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
              child: const Text(
                'This is a simple demonstration of styled labels with rounded containers positioned over a MapLibre map',
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

class _StaticLabel extends StatelessWidget {
  final String name;
  final String abbreviation;
  final Color color;

  const _StaticLabel({
    required this.name,
    required this.abbreviation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                abbreviation,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelStyleExample extends StatelessWidget {
  final Color color;
  final String text;

  const _LabelStyleExample({
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
