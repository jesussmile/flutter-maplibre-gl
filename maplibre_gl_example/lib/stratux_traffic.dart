// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'page.dart';

class StratuxTrafficPage extends ExamplePage {
  const StratuxTrafficPage({super.key})
      : super(const Icon(Icons.flight), 'Stratux Traffic');

  @override
  Widget build(BuildContext context) {
    return const StratuxTrafficBody();
  }
}

class TrafficInfo {
  final int icaoAddress;
  final LatLng position;
  final double altitude;
  final double speed;
  final double track;
  final double verticalVelocity;
  final String? tail;
  final DateTime lastSeen;

  TrafficInfo({
    required this.icaoAddress,
    required this.position,
    required this.altitude,
    required this.speed,
    required this.track,
    required this.verticalVelocity,
    this.tail,
    required this.lastSeen,
  });

  factory TrafficInfo.fromJson(Map<String, dynamic> json) {
    // Safe conversion from any numeric type to double
    double toDouble(dynamic value) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Safe conversion from any numeric type to int
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return TrafficInfo(
      icaoAddress: toInt(json['Icao_addr']),
      position: LatLng(
        toDouble(json['Lat']),
        toDouble(json['Lng']),
      ),
      altitude: toDouble(json['Alt']),
      speed: toDouble(json['Speed']),
      track: toDouble(json['Track']),
      verticalVelocity: toDouble(json['Vvel']),
      tail: json['Tail']?.toString(),
      lastSeen: DateTime.now(),
    );
  }

  // Get color based on vertical velocity
  Color get color {
    if (verticalVelocity > 300) {
      return Colors.green;
    } else if (verticalVelocity < -300) {
      return Colors.red;
    } else {
      return Colors.blue;
    }
  }
}

class StratuxTrafficBody extends StatefulWidget {
  const StratuxTrafficBody({super.key});

  @override
  State<StratuxTrafficBody> createState() => _StratuxTrafficBodyState();
}

class _StratuxTrafficBodyState extends State<StratuxTrafficBody> {
  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(37.7749, -122.4194), // San Francisco
    zoom: 10.0,
  );

  MapLibreMapController? _mapController;
  final Map<int, TrafficInfo> _trafficData = {};
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String _stratuxIp = '192.168.10.1';
  bool _showTraffic = true;
  Timer? _cleanupTimer;
  Timer? _updateMarkersTimer;

  // Map to track symbols by ICAO address
  final Map<int, Symbol> _trafficSymbols = {};

  // Flag to track if icon has been loaded
  bool _iconLoaded = false;

  final TextEditingController _ipController =
      TextEditingController(text: '192.168.10.1');

  @override
  void initState() {
    super.initState();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupStaleTraffic();
    });
    _updateMarkersTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isConnected && _showTraffic && _iconLoaded) {
        _updateTrafficMarkers();
      }
    });
  }

  @override
  void dispose() {
    _disconnect();
    _cleanupTimer?.cancel();
    _updateMarkersTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  void _connect() {
    _stratuxIp = _ipController.text;
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://$_stratuxIp/traffic'),
      );
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data is Map<String, dynamic>) {
              _processTrafficData(data);
            }
          } catch (e) {
            debugPrint('Error processing traffic data: $e');
          }
        },
        onDone: () {
          setState(() {
            _isConnected = false;
          });
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          setState(() {
            _isConnected = false;
          });
        },
      );
      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      debugPrint('Connection error: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    setState(() {
      _isConnected = false;
    });
  }

  void _processTrafficData(Map<String, dynamic> data) {
    try {
      if (data.containsKey('Icao_addr') &&
          data.containsKey('Lat') &&
          data.containsKey('Lng')) {
        final trafficInfo = TrafficInfo.fromJson(data);
        setState(() {
          _trafficData[trafficInfo.icaoAddress] = trafficInfo;
        });
      }
    } catch (e) {
      debugPrint('Error processing traffic data: $e');
    }
  }

  Future<void> _onStyleLoaded() async {
    // Enable icons to overlap one another
    await _mapController!.setSymbolIconAllowOverlap(true);
    // Permit other symbols to render even when colliding with icons
    await _mapController!.setSymbolIconIgnorePlacement(true);
    // Allow text labels to overlap
    await _mapController!.setSymbolTextAllowOverlap(true);
    // Permit other symbols regardless of text collisions
    await _mapController!.setSymbolTextIgnorePlacement(true);
    // Now load your custom icon
    await _loadCustomIcon();
  }

  void _cleanupStaleTraffic() {
    final now = DateTime.now();
    final keysToRemove = <int>[];

    for (final entry in _trafficData.entries) {
      final diff = now.difference(entry.value.lastSeen);
      if (diff.inSeconds > 60) {
        keysToRemove.add(entry.key);
      }
    }

    if (keysToRemove.isNotEmpty) {
      setState(() {
        for (final key in keysToRemove) {
          _trafficData.remove(key);
          // Also remove the symbol if it exists
          if (_trafficSymbols.containsKey(key)) {
            _mapController?.removeSymbol(_trafficSymbols[key]!);
            _trafficSymbols.remove(key);
          }
        }
      });
    }
  }

  void _toggleTrafficVisibility() {
    setState(() {
      _showTraffic = !_showTraffic;
      if (!_showTraffic) {
        _removeAllSymbols();
      } else {
        _updateTrafficMarkers();
      }
    });
  }

  void _removeAllSymbols() {
    if (_mapController != null) {
      for (final symbol in _trafficSymbols.values) {
        _mapController!.removeSymbol(symbol);
      }
      _trafficSymbols.clear();
    }
  }

  Future<void> _updateTrafficMarkers() async {
    if (_mapController == null || !_showTraffic || !_iconLoaded) return;

    try {
      // Process each traffic item
      for (final traffic in _trafficData.values) {
        // Check if we already have a symbol for this traffic
        if (_trafficSymbols.containsKey(traffic.icaoAddress)) {
          // Update existing symbol position and properties
          await _mapController!.updateSymbol(
            _trafficSymbols[traffic.icaoAddress]!,
            SymbolOptions(
              geometry: traffic.position,
              iconRotate: traffic.track,
              iconColor: _colorToString(traffic.color),
              textField:
                  '${traffic.tail ?? 'N/A'} ${(traffic.altitude / 100).round() * 100}ft',
            ),
          );
        } else {
          // Create a new symbol for this traffic
          final symbol = await _mapController!.addSymbol(
            SymbolOptions(
              geometry: traffic.position,
              iconSize: 0.3,
              iconImage: 'plane-icon',
              iconRotate: traffic.track,
              iconColor: _colorToString(traffic.color),
              textField:
                  '${traffic.tail ?? 'N/A'} ${(traffic.altitude / 100).round() * 100}ft',
              textOffset: const Offset(0, 1.5),
              textSize: 10,
              textColor: '#FFFFFF',
              textHaloColor: '#000000',
              textHaloWidth: 1,
            ),
          );
          _trafficSymbols[traffic.icaoAddress] = symbol;
        }
      }

      // Check for symbols that no longer have corresponding traffic data
      final symbolsToRemove = <int>[];
      for (final icao in _trafficSymbols.keys) {
        if (!_trafficData.containsKey(icao)) {
          symbolsToRemove.add(icao);
        }
      }

      // Remove symbols for traffic that no longer exists
      for (final icao in symbolsToRemove) {
        await _mapController!.removeSymbol(_trafficSymbols[icao]!);
        _trafficSymbols.remove(icao);
      }
    } catch (e) {
      debugPrint('Error updating traffic markers: $e');
    }
  }

  String _colorToString(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  Future<void> _loadCustomIcon() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/plane2.png');
      final Uint8List list = bytes.buffer.asUint8List();
      await _mapController!.addImage('plane-icon', list);
      _iconLoaded = true;
    } catch (e) {
      debugPrint('Error loading plane icon: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Stratux IP',
                      hintText: '192.168.10.1',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : _connect,
                  child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                      _showTraffic ? Icons.visibility : Icons.visibility_off),
                  onPressed: _toggleTrafficVisibility,
                  tooltip: _showTraffic ? 'Hide Traffic' : 'Show Traffic',
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                MapLibreMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _mapController!.onSymbolTapped.add(_onSymbolTapped);
                  },
                  onStyleLoadedCallback: () {
                    _onStyleLoaded();
                    // _loadCustomIcon();
                  },
                  initialCameraPosition: _kInitialPosition,
                  styleString: MapLibreStyles.demo,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aircraft Count: ${_trafficData.length}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                                width: 12, height: 12, color: Colors.green),
                            const SizedBox(width: 4),
                            const Text('Climbing'),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                                width: 12, height: 12, color: Colors.blue),
                            const SizedBox(width: 4),
                            const Text('Level'),
                          ],
                        ),
                        Row(
                          children: [
                            Container(width: 12, height: 12, color: Colors.red),
                            const SizedBox(width: 4),
                            const Text('Descending'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSymbolTapped(Symbol symbol) {
    // You can show more details about the traffic when tapped
    final properties = symbol.options.toJson();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Traffic: ${properties['textField']}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
