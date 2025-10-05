// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

/// Example demonstrating native-side pill/lozenge style labels.
///
/// This example shows how to create professional aviation-style labels with:
/// - Unified rounded rectangle backgrounds (pill/lozenge shape)
/// - Custom colors for background and text
/// - Dynamic label generation from data
///
/// **Use Case**: This technique solves the limitation of MapLibre GL's text halos,
/// which create per-glyph backgrounds (blocky individual letters) instead of
/// unified backgrounds. By generating bitmaps natively with Android Canvas API,
/// we achieve smooth, professional pill-style labels.
///
/// **How it works**:
/// 1. Flutter calls native method `style#createPillLabel` with label parameters
/// 2. Native Android code uses Canvas API to draw rounded rectangle + text
/// 3. Bitmap is added to MapLibre style using `style.addImage()`
/// 4. Flutter references the bitmap in a SymbolLayer using `iconImage`
class PillLabelExample extends ExamplePage {
  const PillLabelExample({Key? key})
      : super(const Icon(Icons.label), 'Native Pill Labels', key: key);

  @override
  Widget build(BuildContext context) {
    return const PillLabelBody();
  }
}

class PillLabelBody extends StatefulWidget {
  const PillLabelBody({Key? key}) : super(key: key);

  @override
  State createState() => PillLabelBodyState();
}

class PillLabelBodyState extends State<PillLabelBody> {
  MapLibreMapController? _mapController;
  bool _labelsVisible = false;
  int _labelCount = 0;

  // Sample airspace data for demonstration
  final List<Map<String, dynamic>> _sampleAirspaceData = [
    {
      'name': 'DALLAS B',
      'coordinates': [-96.8, 32.9],
      'text': 'DALLAS B: 11000-0',
      'backgroundColor': '#0066FF',
      'textColor': '#FFFFFF',
    },
    {
      'name': 'FORT WORTH C',
      'coordinates': [-97.3, 32.7],
      'text': 'FORT WORTH C: 5000-1200',
      'backgroundColor': '#00CC66',
      'textColor': '#FFFFFF',
    },
    {
      'name': 'ALLIANCE D',
      'coordinates': [-97.3, 32.98],
      'text': 'ALLIANCE D: 2500-0',
      'backgroundColor': '#FF6600',
      'textColor': '#FFFFFF',
    },
    {
      'name': 'ADDISON D',
      'coordinates': [-96.84, 32.97],
      'text': 'ADDISON D: 3000-0',
      'backgroundColor': '#9933FF',
      'textColor': '#FFFFFF',
    },
    {
      'name': 'MEACHAM D',
      'coordinates': [-97.36, 32.82],
      'text': 'MEACHAM D: 2500-0',
      'backgroundColor': '#FF3366',
      'textColor': '#FFFFFF',
    },
  ];

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoadedCallback() {
    debugPrint('✅ Style loaded - ready to add pill labels');
  }

  /// Toggle pill labels visibility
  Future<void> _togglePillLabels() async {
    if (_mapController == null) return;

    setState(() {
      _labelsVisible = !_labelsVisible;
    });

    if (_labelsVisible) {
      await _addPillLabels();
    } else {
      await _removePillLabels();
    }
  }

  /// Add pill labels using native bitmap generation
  Future<void> _addPillLabels() async {
    if (_mapController == null) return;

    try {
      debugPrint('🏷️ Adding native pill labels...');

      // Generate pill label bitmaps natively for each airspace
      for (int i = 0; i < _sampleAirspaceData.length; i++) {
        final data = _sampleAirspaceData[i];
        final imageName = 'pill-label-$i';

        // Call native method to create pill label bitmap
        await _mapController!.createPillLabel(
          name: imageName,
          text: data['text'],
          backgroundColor: data['backgroundColor'],
          textColor: data['textColor'],
          textSize: 14.0,
          paddingHorizontal: 12.0,
          paddingVertical: 6.0,
          cornerRadius: 8.0,
        );
      }

      // WORKAROUND: Use addSymbol() for each feature instead of addSymbolLayer()
      // This works because individual Symbols CAN reference images from createPillLabel()
      // but SymbolLayers CANNOT (MapLibre layer initialization issue with method channel images)
      debugPrint(
          '📍 Adding ${_sampleAirspaceData.length} pill labels using addSymbol() approach');

      for (int i = 0; i < _sampleAirspaceData.length; i++) {
        final data = _sampleAirspaceData[i];
        final coordinates = data['coordinates'] as List<dynamic>;

        await _mapController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(coordinates[1], coordinates[0]), // lat, lon
            iconImage: 'pill-label-$i',
            iconSize:
                0.5, // Smaller size since bitmaps are already scaled for density
          ),
        );
      }

      debugPrint(
          '✅ Added ${_sampleAirspaceData.length} pill labels using individual Symbols');

      setState(() {
        _labelCount = _sampleAirspaceData.length;
      });

      debugPrint('✅ Added ${_sampleAirspaceData.length} native pill labels');
    } catch (e) {
      debugPrint('❌ Error adding pill labels: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding labels: $e')),
      );
    }
  }

  /// Remove pill labels
  Future<void> _removePillLabels() async {
    if (_mapController == null) return;

    try {
      // Remove all symbols (includes pill labels)
      await _mapController!.clearSymbols();

      setState(() {
        _labelCount = 0;
      });

      debugPrint('✅ Removed pill labels');
    } catch (e) {
      debugPrint('❌ Error removing pill labels: $e');
    }
  }

  /// Add circular airspace labels (demonstration of circular label feature)
  Future<void> _addCircleLabels() async {
    if (_mapController == null) return;

    try {
      debugPrint('🔵 Creating circular airspace labels...');

      // Sample circular airspace data
      final List<Map<String, dynamic>> _circularAirspaceData = [
        {
          'text': 'RESTRICTED R-2508',
          'coordinates': [-97.0, 32.8], // lon, lat (Fort Worth area)
          'radius': 40.0,
          'color': '#FF0000', // Red for restricted areas
          'topArc': true,
          'roundedEdges': false, // Straight edges for restricted areas
        },
        {
          'text': 'MOA WHISKEY 174',
          'coordinates': [-97.1, 32.7],
          'radius': 45.0,
          'color': '#0066FF', // Blue for MOAs
          'topArc': false, // Text on bottom
          'roundedEdges': true, // Rounded edges for MOAs
        },
        {
          'text': 'PROHIBITED P-40',
          'coordinates': [-97.05, 32.75],
          'radius': 35.0,
          'color': '#990000', // Dark red for prohibited
          'topArc': true,
          'roundedEdges': false, // Straight edges for prohibited
        },
        {
          'text': 'ALERT AREA A-632',
          'coordinates': [-96.95, 32.85],
          'radius': 50.0,
          'color': '#FF6600', // Orange for alert areas
          'topArc': false,
          'roundedEdges': true, // Rounded edges for alert areas
        },
      ];

      // Create circular label bitmaps on native side
      for (int i = 0; i < _circularAirspaceData.length; i++) {
        final data = _circularAirspaceData[i];

        await _mapController!.createCircleLabel(
          name: 'circle-label-$i',
          text: data['text'],
          radius: data['radius'],
          circleColor: data['color'],
          circleStrokeWidth: 3.0,
          textColor: '#FFFFFF',
          textSize: 16.0, // Increased from 12.0 for better visibility
          topArc: data['topArc'],
          roundedEdges: data['roundedEdges'], // Control pill edge style
        );
      }

      debugPrint(
          '✅ Created ${_circularAirspaceData.length} circular label bitmaps');

      // Add circular labels using addSymbol()
      debugPrint(
          '📍 Adding ${_circularAirspaceData.length} circular labels using addSymbol() approach');

      for (int i = 0; i < _circularAirspaceData.length; i++) {
        final data = _circularAirspaceData[i];
        final coordinates = data['coordinates'] as List<dynamic>;

        await _mapController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(coordinates[1], coordinates[0]), // lat, lon
            iconImage: 'circle-label-$i',
            iconSize: 0.5, // Scaled for density
          ),
        );
      }

      debugPrint(
          '✅ Added ${_circularAirspaceData.length} circular labels using individual Symbols');

      setState(() {
        _labelCount += _circularAirspaceData.length;
      });

      debugPrint(
          '✅ Added ${_circularAirspaceData.length} native circular labels');
    } catch (e) {
      debugPrint('❌ Error adding circular labels: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding circular labels: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Label Examples'),
        backgroundColor: Colors.blue[800],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoadedCallback,
            initialCameraPosition: const CameraPosition(
              target: LatLng(32.85, -97.1),
              zoom: 9.0,
            ),
            styleString: 'https://demotiles.maplibre.org/style.json',
            myLocationEnabled: false,
            trackCameraPosition: true,
          ),
          // Info panel
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              color: Colors.white.withOpacity(0.95),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Native Pill Labels',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${_labelsVisible ? "Visible" : "Hidden"}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Labels: $_labelCount',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Demonstrates pill labels\nand circular labels with\ncurved text generated\non native side',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Control buttons
          Positioned(
            bottom: 32,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'pillLabelToggleButton', // Unique hero tag
                  onPressed: _togglePillLabels,
                  backgroundColor:
                      _labelsVisible ? Colors.red[600] : Colors.blue[600],
                  icon: Icon(
                    _labelsVisible ? Icons.visibility_off : Icons.label,
                  ),
                  label: Text(_labelsVisible ? 'Hide Pill' : 'Show Pill'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'circleLabelAddButton', // Unique hero tag
                  onPressed: _addCircleLabels,
                  backgroundColor: Colors.green[600],
                  icon: const Icon(Icons.circle_outlined),
                  label: const Text('Add Circles'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
