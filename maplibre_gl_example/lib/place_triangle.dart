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
        const TriangleOptions(triangleSize: 10),
      );
    }
    setState(() {
      _selectedTriangle = triangle;
    });
    _updateSelectedTriangle(
      const TriangleOptions(
        triangleSize: 20,
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
          triangleSize: 15.0,
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

  Future<void> _changeTriangleSize() async {
    var current = _selectedTriangle!.options.triangleSize;
    current ??= 5;
    _updateSelectedTriangle(
      TriangleOptions(triangleSize: current == 25.0 ? 5.0 : current + 5.0),
    );
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                          ElevatedButton(
                            onPressed: (_selectedTriangle == null) ? null : _changeTriangleSize,
                            child: const Text('Size'),
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
                        '• Tap "Add" to create triangles in a circular pattern\n'
                        '• Tap triangles on the map to select them\n'
                        '• Use property buttons to modify selected triangles\n'
                        '• Drag triangles when draggable is enabled',
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
