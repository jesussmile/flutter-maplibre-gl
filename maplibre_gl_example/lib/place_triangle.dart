// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class PlaceTrianglePage extends ExamplePage {
  const PlaceTrianglePage({super.key})
      : super(const Icon(Icons.change_history), 'Place triangle');

  @override
  Widget build(BuildContext context) {
    return const PlaceTriangleBody();
  }
}

class PlaceTriangleBody extends StatefulWidget {
  const PlaceTriangleBody({super.key});

  @override
  State<StatefulWidget> createState() => PlaceTriangleBodyState();
}

class PlaceTriangleBodyState extends State<PlaceTriangleBody> {
  PlaceTriangleBodyState();

  static const LatLng center = LatLng(-33.86711, 151.1947171);

  MapLibreMapController? controller;
  int _triangleCount = 0;
  Triangle? _selectedTriangle;

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
    controller.onTriangleTapped.add(_onTriangleTapped);
  }

  void _onStyleLoadedCallback() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Style loaded"),
      backgroundColor: Theme.of(context).primaryColor,
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  void dispose() {
    controller?.onTriangleTapped.remove(_onTriangleTapped);
    super.dispose();
  }

  void _onTriangleTapped(Triangle triangle) {
    if (_selectedTriangle != null) {
      _updateSelectedTriangle(
        const TriangleOptions(triangleSize: 1.0),
      );
    }
    setState(() {
      _selectedTriangle = triangle;
    });
    _updateSelectedTriangle(
      const TriangleOptions(
        triangleSize: 1.5,
      ),
    );
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Selected triangle ${triangle.id}"),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 1),
    ));
  }

  void _updateSelectedTriangle(TriangleOptions changes) {
    controller!.updateTriangle(_selectedTriangle!, changes);
  }

  void _add() {
    final colors = [
      "#FF6B35", "#F7931E", "#FFD23F", "#06FFA5", 
      "#118AB2", "#073B4C", "#8E44AD", "#E74C3C"
    ];
    
    controller!.addTriangle(
      TriangleOptions(
          geometry: LatLng(
            center.latitude + sin(_triangleCount * pi / 6.0) / 20.0,
            center.longitude + cos(_triangleCount * pi / 6.0) / 20.0,
          ),
          triangleColor: colors[_triangleCount % colors.length],
          triangleSize: 1.0,
          triangleOpacity: 0.8,
          triangleStrokeWidth: 2.0,
          triangleStrokeColor: "#FFFFFF",
          triangleStrokeOpacity: 0.9,
          draggable: true),
    );
    setState(() {
      _triangleCount += 1;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Added triangle $_triangleCount"),
      backgroundColor: Colors.blue,
      duration: const Duration(seconds: 1),
    ));
  }

  void _remove() {
    if (_selectedTriangle == null) return;
    
    final triangleId = _selectedTriangle!.id;
    controller!.removeTriangle(_selectedTriangle!);
    setState(() {
      _selectedTriangle = null;
      _triangleCount -= 1;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Removed triangle $triangleId"),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 1),
    ));
  }

  void _changePosition() {
    final current = _selectedTriangle!.options.geometry!;
    final offset = Offset(
      center.latitude - current.latitude,
      center.longitude - current.longitude,
    );
    _updateSelectedTriangle(
      TriangleOptions(
        geometry: LatLng(
          center.latitude + offset.dy,
          center.longitude + offset.dx,
        ),
      ),
    );
  }

  void _changeDraggable() {
    var draggable = _selectedTriangle!.options.draggable;
    draggable ??= false;
    _updateSelectedTriangle(
      TriangleOptions(
        draggable: !draggable,
      ),
    );
  }

  Future<void> _getLatLng() async {
    final latLng = await controller!.getTriangleLatLng(_selectedTriangle!);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(latLng.toString()),
      ),
    );
  }

  void _changeTriangleStrokeOpacity() {
    var current = _selectedTriangle!.options.triangleStrokeOpacity;
    current ??= 1.0;

    _updateSelectedTriangle(
      TriangleOptions(triangleStrokeOpacity: current < 0.1 ? 1.0 : current * 0.75),
    );
  }

  void _changeTriangleStrokeWidth() {
    var current = _selectedTriangle!.options.triangleStrokeWidth;
    current ??= 0;
    _updateSelectedTriangle(
        TriangleOptions(triangleStrokeWidth: current == 0 ? 5.0 : 0));
  }

  Future<void> _changeTriangleStrokeColor() async {
    var current = _selectedTriangle!.options.triangleStrokeColor;
    current ??= "#FFFFFF";

    _updateSelectedTriangle(
      TriangleOptions(
          triangleStrokeColor: current == "#FFFFFF" ? "#FF0000" : "#FFFFFF"),
    );
  }

  Future<void> _changeTriangleOpacity() async {
    var current = _selectedTriangle!.options.triangleOpacity;
    current ??= 1.0;

    _updateSelectedTriangle(
      TriangleOptions(triangleOpacity: current < 0.1 ? 1.0 : current * 0.75),
    );
  }

  Future<void> _increaseTriangleSize() async {
    var current = _selectedTriangle!.options.triangleSize;
    current ??= 1.0;
    final newSize = (current + 0.5).clamp(1.0, 4.0); // Min 1, Max 4, increment by 0.5
    _updateSelectedTriangle(
      TriangleOptions(triangleSize: newSize),
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Triangle size increased to ${newSize.toStringAsFixed(1)}"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ));
    }
  }
  
  Future<void> _decreaseTriangleSize() async {
    var current = _selectedTriangle!.options.triangleSize;
    current ??= 1.0;
    final newSize = (current - 0.5).clamp(1.0, 4.0); // Min 1, Max 4, increment by 0.5
    _updateSelectedTriangle(
      TriangleOptions(triangleSize: newSize),
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Triangle size decreased to ${newSize.toStringAsFixed(1)}"),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _changeTriangleColor() async {
    var current = _selectedTriangle!.options.triangleColor;
    current ??= "#FF0000";

    _updateSelectedTriangle(
      const TriangleOptions(triangleColor: "#FFFF00"),
    );
  }

  Future<void> _clearTriangles() async {
    if (controller == null) return;

    try {
      await controller!.clearTriangles();
      setState(() {
        _selectedTriangle = null;
        _triangleCount = 0;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Cleared all triangles"),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to clear triangles: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }
  
  Future<void> _stressTest20k() async {
    if (controller == null) return;
    
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("🌍 Creating 80,000 triangles around the world... Please wait"),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ));
      
      final startTime = DateTime.now();
      
      // Create 80,000 triangles randomly distributed across the entire world
      const int totalTriangles = 80000;
      final random = Random();
      final colors = [
        "#FF6B35", "#F7931E", "#FFD23F", "#06FFA5", 
        "#118AB2", "#073B4C", "#8E44AD", "#E74C3C",
        "#FF5733", "#C70039", "#900C3F", "#581845",
        "#3498DB", "#9B59B6", "#E67E22", "#F39C12",
        "#27AE60", "#16A085", "#34495E", "#7F8C8D"
      ];
      
      // Prepare all triangle options in batch - randomly distributed worldwide
      final List<TriangleOptions> triangleOptionsList = [];
      
      for (int i = 0; i < totalTriangles; i++) {
        // Generate random coordinates covering the entire world
        // Latitude: -90 to +90 degrees
        // Longitude: -180 to +180 degrees
        final double lat = (random.nextDouble() * 180.0) - 90.0;  // -90 to +90
        final double lng = (random.nextDouble() * 360.0) - 180.0; // -180 to +180
        
        // Random size variation for visual diversity
        final double size = 0.8 + (random.nextDouble() * 0.4); // 0.8 to 1.2
        
        // Random opacity for visual variety
        final double opacity = 0.6 + (random.nextDouble() * 0.3); // 0.6 to 0.9
        
        triangleOptionsList.add(
          TriangleOptions(
            geometry: LatLng(lat, lng),
            triangleColor: colors[i % colors.length],
            triangleSize: size,
            triangleOpacity: opacity,
            triangleStrokeWidth: 0.3, // Very thin stroke for performance
            triangleStrokeColor: "#FFFFFF",
            triangleStrokeOpacity: 0.7,
            draggable: false, // Disable dragging for performance
          ),
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("🌐 Prepared $totalTriangles triangles worldwide, now adding to map..."),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ));
      }
      
      // Add all triangles at once using batch method - MUCH FASTER!
      final triangles = await controller!.addTriangles(triangleOptionsList);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      setState(() {
        _triangleCount = triangles.length;
        _selectedTriangle = null; // Clear selection
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            "🚀 Global stress test complete!\n"
            "Created ${triangles.length} triangles worldwide in ${duration.inMilliseconds}ms\n"
            "Average: ${(duration.inMilliseconds / triangles.length).toStringAsFixed(3)}ms per triangle\n"
            "Zoom out to see triangles around the world!"
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Global stress test failed: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
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
                zoom: 12.0,
              ),
              experimentalFeatures: MapLibreExperimentalFeatures.triangles,
              annotationOrder: const [
                AnnotationType.triangle,
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Feature flag status
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Experimental Triangle Layers',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This example uses the experimental triangle feature flag.\n'
                        'When disabled, triangles fall back to orange circles.\n'
                        'Set MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS=true to enable.',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                // Main action buttons
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 16.0,
                  runSpacing: 16.0,
                  children: [
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: (_triangleCount >= 12) ? null : _add,
                          heroTag: "add_triangle",
                          tooltip: 'Add triangle',
                          backgroundColor: (_triangleCount >= 12) ? Colors.grey : null,
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        const Text("Add", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: (_selectedTriangle != null) ? _remove : null,
                          heroTag: "remove_triangle",
                          tooltip: 'Remove selected triangle',
                          backgroundColor: (_selectedTriangle != null) ? Colors.red : Colors.grey,
                          child: const Icon(Icons.remove),
                        ),
                        const SizedBox(height: 8),
                        const Text("Remove", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: (_triangleCount > 0) ? _clearTriangles : null,
                          heroTag: "clear_triangles",
                          tooltip: 'Clear all triangles',
                          backgroundColor: (_triangleCount > 0) ? Colors.orange : Colors.grey,
                          child: const Icon(Icons.clear),
                        ),
                        const SizedBox(height: 8),
                        const Text("Clear", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: _stressTest20k,
                          heroTag: "stress_test",
                          tooltip: 'Global stress test: Create 80k triangles worldwide',
                          backgroundColor: Colors.purple.shade600,
                          child: const Icon(Icons.public, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text("Global", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Property modification buttons
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Triangle Properties (Selected: ${_selectedTriangle?.id ?? "None"})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          // Size controls with plus/minus buttons
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: (_selectedTriangle == null) ? null : _decreaseTriangleSize,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(40, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: const Icon(Icons.remove, size: 18),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Size: ${_selectedTriangle?.options.triangleSize?.toStringAsFixed(1) ?? "1.0"}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton(
                                onPressed: (_selectedTriangle == null) ? null : _increaseTriangleSize,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(40, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: const Icon(Icons.add, size: 18),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleColor,
                            child: const Text('Color'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleOpacity,
                            child: const Text('Opacity'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleStrokeWidth,
                            child: const Text('Stroke Width'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleStrokeColor,
                            child: const Text('Stroke Color'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleStrokeOpacity,
                            child: const Text('Stroke Opacity'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changePosition,
                            child: const Text('Position'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeDraggable,
                            child: const Text('Toggle Draggable'),
                          ),
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _getLatLng,
                            child: const Text('Get LatLng'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Status information
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
                        'Status:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Triangle count: $_triangleCount'),
                      Text(
                        'Selected: ${_selectedTriangle?.id ?? "None"}',
                        style: TextStyle(
                          color: _selectedTriangle != null ? Colors.green : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Instructions:\n'
                        '• Tap "Add" to create tiny triangles (size 1.0)\n'
                        '• Tap "Global" to create 80,000 triangles worldwide for stress testing\n'
                        '• Tap triangles on the map to select them\n'
                        '• Use +/- buttons to fine-tune size (1.0-4.0, step 0.5)\n'
                        '• Use other property buttons to modify triangles\n'
                        '• Zoom out after stress test to see triangles around the world\n'
                        '• Drag triangles when draggable is enabled (not in stress test)',
                        style: TextStyle(fontSize: 12),
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
