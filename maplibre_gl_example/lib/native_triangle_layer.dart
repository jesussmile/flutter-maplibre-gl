// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class NativeTriangleLayerPage extends ExamplePage {
  const NativeTriangleLayerPage({super.key})
      : super(const Icon(Icons.change_history), 'Native triangle layer');

  @override
  Widget build(BuildContext context) {
    return const NativeTriangleLayerBody();
  }
}

class NativeTriangleLayerBody extends StatefulWidget {
  const NativeTriangleLayerBody({super.key});

  @override
  State<NativeTriangleLayerBody> createState() => NativeTriangleLayerBodyState();
}

class NativeTriangleLayerBodyState extends State<NativeTriangleLayerBody> {
  NativeTriangleLayerBodyState();

  static const LatLng center = LatLng(-33.86711, 151.1947171);

  MapLibreMapController? controller;
  bool _triangleLayerAdded = false;
  final List<Map<String, dynamic>> _trianglePoints = [];
  int _pointCount = 0;

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
  }

  void _onStyleLoadedCallback() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Style loaded - Ready to add native triangle layers!"),
      backgroundColor: Theme.of(context).primaryColor,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _addTriangleLayer() async {
    if (controller == null || _triangleLayerAdded) return;

    try {
      // Create initial triangle points around the center
      _generateInitialTrianglePoints();

      // Add GeoJSON source with triangle points
      final geoJsonSource = {
        "type": "FeatureCollection",
        "features": _trianglePoints.map((point) => {
          "type": "Feature",
          "id": point["id"],
          "properties": {
            "id": point["id"],
            "size": point["size"],
            "color": point["color"],
          },
          "geometry": {
            "type": "Point",
            "coordinates": [point["lng"], point["lat"]]
          }
        }).toList()
      };

      await controller!.addGeoJsonSource("triangle-source", geoJsonSource);

      // Add native triangle layer with properties
      await controller!.addTriangleLayer(
        "triangle-source",
        "native-triangle-layer",
        TriangleLayerProperties(
          // Basic triangle styling
          triangleSize: [
            "case",
            ["has", "size"],
            ["get", "size"],
            15.0  // default size
          ],
          triangleColor: [
            "case",
            ["has", "color"],
            ["get", "color"],
            "#FF6B35"  // default color
          ],
          triangleOpacity: 0.8,
          
          // Triangle stroke
          triangleStrokeWidth: 2.0,
          triangleStrokeColor: "#FFFFFF",
          triangleStrokeOpacity: 0.9,
          
          // Triangle blur for smooth edges
          triangleBlur: 0.0,
          
          // Rotation (0 degrees = pointing up)
          triangleRotation: 0.0,
          
          // Pitch and rotation alignment
          trianglePitchAlignment: "viewport",
          triangleRotationAlignment: "viewport",
          
          // Translation
          triangleTranslate: [0, 0],
          triangleTranslateAnchor: "map",
          
          // Pitch scaling
          trianglePitchScale: "map",
          
          // Visibility
          visibility: "visible",
        ),
        enableInteraction: true,
      );

      setState(() {
        _triangleLayerAdded = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Native triangle layer added successfully!"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to add triangle layer: $e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _generateInitialTrianglePoints() {
    _trianglePoints.clear();
    _pointCount = 8;
    
    final colors = [
      "#FF6B35", "#F7931E", "#FFD23F", "#06FFA5", 
      "#118AB2", "#073B4C", "#8E44AD", "#E74C3C"
    ];
    
    for (int i = 0; i < _pointCount; i++) {
      final angle = (i * 360 / _pointCount) * (3.14159 / 180);
      final radius = 0.02; // ~2km radius
      
      _trianglePoints.add({
        "id": "triangle_${i + 1}",
        "lat": center.latitude + radius * sin(angle),
        "lng": center.longitude + radius * cos(angle),
        "size": 15.0 + (i * 3), // Varying sizes
        "color": colors[i % colors.length],
      });
    }
  }

  Future<void> _addRandomTrianglePoint() async {
    if (controller == null || !_triangleLayerAdded) return;

    try {
      _pointCount++;
      final colors = [
        "#FF6B35", "#F7931E", "#FFD23F", "#06FFA5", 
        "#118AB2", "#073B4C", "#8E44AD", "#E74C3C"
      ];
      
      // Generate random position within 3km of center
      final angle = (DateTime.now().millisecondsSinceEpoch % 360) * (3.14159 / 180);
      final radius = 0.01 + (DateTime.now().millisecondsSinceEpoch % 20) / 1000; // 1-3km
      
      final newPoint = {
        "id": "triangle_$_pointCount",
        "lat": center.latitude + radius * sin(angle),
        "lng": center.longitude + radius * cos(angle),
        "size": 12.0 + (DateTime.now().millisecondsSinceEpoch % 15), // 12-27 size
        "color": colors[_pointCount % colors.length],
      };
      
      _trianglePoints.add(newPoint);

      // Update GeoJSON source
      final geoJsonSource = {
        "type": "FeatureCollection",
        "features": _trianglePoints.map((point) => {
          "type": "Feature",
          "id": point["id"],
          "properties": {
            "id": point["id"],
            "size": point["size"],
            "color": point["color"],
          },
          "geometry": {
            "type": "Point",
            "coordinates": [point["lng"], point["lat"]]
          }
        }).toList()
      };

      await controller!.setGeoJsonSource("triangle-source", geoJsonSource);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Added triangle point: ${newPoint['id']}"),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to add triangle point: $e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _updateTriangleProperties() async {
    if (controller == null || !_triangleLayerAdded) return;

    try {
      // Update triangle layer properties with new styling
      await controller!.setLayerProperties(
        "native-triangle-layer", 
        TriangleLayerProperties(
          triangleSize: [
            "interpolate",
            ["linear"],
            ["zoom"],
            8, 8,
            12, 20,
            16, 40
          ], // Size based on zoom
          triangleColor: [
            "interpolate",
            ["linear"],
            ["get", "size"],
            10, "#4264fb", // Blue for small
            20, "#f7931e", // Orange for medium  
            30, "#ff1744"  // Red for large
          ], // Color based on size
          triangleRotation: [
            "*",
            ["get", "size"],
            3  // Rotation based on size
          ],
          triangleBlur: 0.5, // Add some blur
        )
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Updated triangle layer properties!"),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to update properties: $e"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  Future<void> _removeTriangleLayer() async {
    if (controller == null || !_triangleLayerAdded) return;

    try {
      await controller!.removeLayer("native-triangle-layer");
      await controller!.removeSource("triangle-source");
      
      setState(() {
        _triangleLayerAdded = false;
        _trianglePoints.clear();
        _pointCount = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Removed native triangle layer"),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to remove triangle layer: $e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: SizedBox(
            height: 400.0,
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoadedCallback,
              initialCameraPosition: const CameraPosition(
                target: center,
                zoom: 11.0,
              ),
              // CRITICAL: Enable native triangle layers experimental feature
              experimentalFeatures: MapLibreExperimentalFeatures.triangles,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Feature status
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Native Triangle Layer (TAS-19)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This example uses the native triangle layer implementation\\n'
                        'with GPU shaders (OpenGL ES/Metal) - NOT triangle annotations!\\n'
                        'Features: data-driven styling, expressions, layer properties.',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                // Main action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: !_triangleLayerAdded ? _addTriangleLayer : null,
                          heroTag: "add_layer",
                          tooltip: 'Add native triangle layer',
                          backgroundColor: !_triangleLayerAdded ? Colors.blue : Colors.grey,
                          child: const Icon(Icons.layers),
                        ),
                        const SizedBox(height: 8),
                        const Text("Add Layer", style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: _triangleLayerAdded ? _addRandomTrianglePoint : null,
                          heroTag: "add_point",
                          tooltip: 'Add triangle point',
                          backgroundColor: _triangleLayerAdded ? Colors.green : Colors.grey,
                          child: const Icon(Icons.add_location),
                        ),
                        const SizedBox(height: 8),
                        const Text("Add Point", style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: _triangleLayerAdded ? _updateTriangleProperties : null,
                          heroTag: "update_props",
                          tooltip: 'Update layer properties',
                          backgroundColor: _triangleLayerAdded ? Colors.purple : Colors.grey,
                          child: const Icon(Icons.tune),
                        ),
                        const SizedBox(height: 8),
                        const Text("Update Style", style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: _triangleLayerAdded ? _removeTriangleLayer : null,
                          heroTag: "remove_layer",
                          tooltip: 'Remove triangle layer',
                          backgroundColor: _triangleLayerAdded ? Colors.red : Colors.grey,
                          child: const Icon(Icons.layers_clear),
                        ),
                        const SizedBox(height: 8),
                        const Text("Remove", style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Technical details
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Native Layer Implementation Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '\u2022 Layer Type: Native GPU shader-based triangle layer\\n'
                        '\u2022 Source: GeoJSON FeatureCollection with Point geometries\\n'  
                        '\u2022 Properties: Data-driven expressions (size, color, rotation)\\n'
                        '\u2022 Platform: Custom OpenGL ES layer (iOS/Android)\\n'
                        '\u2022 Status: Layer added: ',
                        style: TextStyle(fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Text('\u2022 Status: Layer added: ', style: TextStyle(fontSize: 12)),
                          Text(
                            _triangleLayerAdded ? 'YES' : 'NO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _triangleLayerAdded ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('\u2022 Triangle points: ', style: TextStyle(fontSize: 12)),
                          Text(
                            '${_trianglePoints.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Instructions:\\n'
                        '1. Tap "Add Layer" to create the native triangle layer\\n'
                        '2. Tap "Add Point" to add more triangle points\\n'
                        '3. Tap "Update Style" to see data-driven styling\\n'
                        '4. Zoom to see triangles scale with map',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
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

