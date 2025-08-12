import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'page.dart';

class ADSBTrafficPage extends ExamplePage {
  const ADSBTrafficPage({super.key}) : super(const Icon(Icons.flight), 'ADSB Traffic');

  @override
  Widget build(BuildContext context) {
    return const ADSBTrafficWidget();
  }
}

class ADSBTrafficWidget extends StatefulWidget {
  const ADSBTrafficWidget({super.key});

  @override
  State createState() => ADSBTrafficPageState();
}

class ADSBTrafficPageState extends State<ADSBTrafficWidget> {
  MapLibreMapController? controller;
  bool _isLoaded = false;
  bool _showTraffic = true;
  bool _simulateMovement = false;
  Timer? _animationTimer;
  
  // Sample ADSB traffic data
  List<AircraftTraffic> _aircraftList = [];
  
  static const _initialCenter = LatLng(37.7749, -122.4194); // San Francisco
  static const _trafficSourceId = 'adsb-traffic-source';
  static const _trafficLayerId = 'adsb-traffic-layer';

  @override
  void initState() {
    super.initState();
    _generateSampleTraffic();
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  void _generateSampleTraffic() {
    final random = math.Random();
    _aircraftList = List.generate(15, (index) {
      final aircraft = AircraftTraffic(
        id: 'AC${index.toString().padLeft(3, '0')}',
        callsign: 'UAL${100 + index}',
        position: LatLng(
          _initialCenter.latitude + (random.nextDouble() - 0.5) * 0.2,
          _initialCenter.longitude + (random.nextDouble() - 0.5) * 0.2,
        ),
        heading: random.nextDouble() * 360,
        altitude: (25000 + random.nextInt(15000)).toDouble(),
        speed: (350 + random.nextInt(200)).toDouble(),
        verticalRate: (random.nextDouble() - 0.5) * 2000,
        aircraftType: _getRandomAircraftType(random),
        velocity: LatLng(
          (random.nextDouble() - 0.5) * 0.002, // Small movement delta
          (random.nextDouble() - 0.5) * 0.002,
        ),
      );
      print('Generated aircraft ${aircraft.id} at ${aircraft.position.latitude}, ${aircraft.position.longitude}');
      return aircraft;
    });
    print('Generated ${_aircraftList.length} aircraft');
  }

  String _getRandomAircraftType(math.Random random) {
    const types = ['B737', 'A320', 'B777', 'A350', 'B787', 'CRJ9', 'E175'];
    return types[random.nextInt(types.length)];
  }

  void _onMapCreated(MapLibreMapController controller) {
    this.controller = controller;
    // Set up feature tap handling
    controller.onFeatureTapped.add(_onFeatureTappedHandler);
  }

  void _onFeatureTappedHandler(dynamic featureId, math.Point<double> point, LatLng latLng, String layerId) {
    _onFeatureTapped(layerId, featureId?.toString(), latLng);
  }

  void _onStyleLoaded() {
    setState(() {
      _isLoaded = true;
    });
    _addTrafficLayer();
  }

  Future<void> _addTrafficLayer() async {
    if (controller == null || !_isLoaded) return;

    try {
      // Create GeoJSON source with aircraft positions
      final geojsonData = _createTrafficGeoJSONMap();
      
      print('Adding GeoJSON source with ${_aircraftList.length} aircraft');
      print('Sample aircraft data: ${geojsonData['features']?.take(2)?.toList()}');
      
      await controller!.addGeoJsonSource(_trafficSourceId, geojsonData);

      // Use circle layer first to ensure visibility, then add symbol layer for arrows
      await controller!.addCircleLayer(
        _trafficSourceId,
        '${_trafficLayerId}_circles',
        const CircleLayerProperties(
          circleRadius: 8.0,
          circleColor: "#FF5722", // Orange circles for visibility
          circleStrokeWidth: 2.0,
          circleStrokeColor: "#D32F2F", // Red stroke
          circleOpacity: 0.9,
        ),
        enableInteraction: true,
      );

      // Add text labels for aircraft callsigns
      await controller!.addSymbolLayer(
        _trafficSourceId,
        '${_trafficLayerId}_labels',
        const SymbolLayerProperties(
          textField: ["get", "callsign"],
          textSize: 10.0,
          textColor: "#FFFFFF",
          textHaloColor: "#000000",
          textHaloWidth: 1.0,
          textOffset: [0, 1.5], // Offset text below the circle
        ),
        enableInteraction: true,
      );

      print('ADSB arrow layer added successfully with ${_aircraftList.length} aircraft');

    } catch (e) {
      print('Error adding ADSB arrow layer: $e');
      _showErrorSnackBar('Failed to add arrow layer: $e');
    }
  }

  Map<String, dynamic> _createTrafficGeoJSONMap() {
    final features = _aircraftList.map((aircraft) {
      return {
        'type': 'Feature',
        'id': aircraft.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [aircraft.position.longitude, aircraft.position.latitude],
        },
        'properties': {
          'id': aircraft.id,
          'callsign': aircraft.callsign,
          'heading': aircraft.heading,
          'altitude': aircraft.altitude,
          'speed': aircraft.speed,
          'verticalRate': aircraft.verticalRate,
          'aircraftType': aircraft.aircraftType,
          'category': _getAircraftCategory(aircraft.aircraftType),
        },
      };
    }).toList();

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  String _getAircraftCategory(String aircraftType) {
    if (['B777', 'A350', 'B787'].contains(aircraftType)) {
      return 'heavy';
    } else if (['CRJ9', 'E175'].contains(aircraftType)) {
      return 'light';
    }
    return 'medium';
  }

  Future<void> _toggleTrafficVisibility() async {
    if (controller == null) return;

    setState(() {
      _showTraffic = !_showTraffic;
    });

    try {
      await controller!.setLayerVisibility('${_trafficLayerId}_circles', _showTraffic);
      await controller!.setLayerVisibility('${_trafficLayerId}_labels', _showTraffic);
    } catch (e) {
      print('Error toggling traffic visibility: $e');
    }
  }

  void _toggleMovementSimulation() {
    setState(() {
      _simulateMovement = !_simulateMovement;
    });

    if (_simulateMovement) {
      _startMovementAnimation();
    } else {
      _stopMovementAnimation();
    }
  }

  void _startMovementAnimation() {
    _animationTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      _updateAircraftPositions();
      _updateTrafficLayer();
    });
  }

  void _stopMovementAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
  }

  void _updateAircraftPositions() {
    final random = math.Random();
    
    for (final aircraft in _aircraftList) {
      // Update position based on velocity
      aircraft.position = LatLng(
        aircraft.position.latitude + aircraft.velocity.latitude,
        aircraft.position.longitude + aircraft.velocity.longitude,
      );

      // Occasionally change heading and velocity
      if (random.nextDouble() < 0.1) {
        aircraft.heading += (random.nextDouble() - 0.5) * 30;
        aircraft.heading = aircraft.heading % 360;
        if (aircraft.heading < 0) aircraft.heading += 360;

        aircraft.velocity = LatLng(
          (random.nextDouble() - 0.5) * 0.002,
          (random.nextDouble() - 0.5) * 0.002,
        );
      }

      // Keep aircraft within bounds
      if (aircraft.position.latitude < _initialCenter.latitude - 0.15 ||
          aircraft.position.latitude > _initialCenter.latitude + 0.15 ||
          aircraft.position.longitude < _initialCenter.longitude - 0.15 ||
          aircraft.position.longitude > _initialCenter.longitude + 0.15) {
        // Reverse velocity to bounce back
        aircraft.velocity = LatLng(
          -aircraft.velocity.latitude,
          -aircraft.velocity.longitude,
        );
      }
    }
  }

  Future<void> _updateTrafficLayer() async {
    if (controller == null || !_isLoaded) return;

    try {
      final geojsonData = _createTrafficGeoJSONMap();
      await controller!.setGeoJsonSource(_trafficSourceId, geojsonData);
    } catch (e) {
      print('Error updating traffic layer: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onFeatureTapped(String layerId, String? featureId, LatLng position) {
    if ((layerId == '${_trafficLayerId}_circles' || layerId == '${_trafficLayerId}_labels') && featureId != null) {
      final aircraft = _aircraftList.firstWhere(
        (a) => a.id == featureId,
        orElse: () => _aircraftList.first,
      );
      _showAircraftInfo(aircraft);
    }
  }

  void _showAircraftInfo(AircraftTraffic aircraft) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aircraft ${aircraft.callsign}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aircraft ID: ${aircraft.id}'),
            Text('Type: ${aircraft.aircraftType}'),
            Text('Altitude: ${aircraft.altitude.toStringAsFixed(0)} ft'),
            Text('Speed: ${aircraft.speed.toStringAsFixed(0)} kt'),
            Text('Heading: ${aircraft.heading.toStringAsFixed(0)}°'),
            Text('Vertical Rate: ${aircraft.verticalRate.toStringAsFixed(0)} ft/min'),
            const SizedBox(height: 8),
            Text(
              'Position: ${aircraft.position.latitude.toStringAsFixed(4)}, '
              '${aircraft.position.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _focusOnAircraft(aircraft);
            },
            child: const Text('Focus'),
          ),
        ],
      ),
    );
  }

  void _focusOnAircraft(AircraftTraffic aircraft) {
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        aircraft.position,
        12.0,
      ),
    );
  }

  void _resetView() {
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        _initialCenter,
        10.0,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ADSB Traffic'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: 'https://demotiles.maplibre.org/style.json',
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            initialCameraPosition: const CameraPosition(
              target: _initialCenter,
              zoom: 10.0,
            ),
            experimentalFeatures: MapLibreExperimentalFeatures.triangles,
          ),
          // Control Panel
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ADSB Traffic Control',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: _isLoaded ? _toggleTrafficVisibility : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _showTraffic ? Colors.green : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          child: Text(_showTraffic ? 'Hide' : 'Show'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isLoaded ? _toggleMovementSimulation : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _simulateMovement ? Colors.orange : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          child: Text(_simulateMovement ? 'Stop' : 'Move'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _isLoaded ? _resetView : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: const Text('Reset View'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Stats Panel
          Positioned(
            top: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Traffic Stats',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Total Aircraft: ${_aircraftList.length}'),
                    Text('Visible: ${_showTraffic ? _aircraftList.length : 0}'),
                    Text('Moving: ${_simulateMovement ? "Yes" : "No"}'),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap aircraft for details',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_isLoaded)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Loading ADSB Traffic...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AircraftTraffic {
  final String id;
  final String callsign;
  LatLng position;
  double heading;
  final double altitude;
  final double speed;
  final double verticalRate;
  final String aircraftType;
  LatLng velocity;

  AircraftTraffic({
    required this.id,
    required this.callsign,
    required this.position,
    required this.heading,
    required this.altitude,
    required this.speed,
    required this.verticalRate,
    required this.aircraftType,
    required this.velocity,
  });
}
