import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'page.dart';

class ADSBTrafficPage extends ExamplePage {
  const ADSBTrafficPage({super.key})
      : super(const Icon(Icons.flight), 'ADSB Traffic');

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
  bool _iconLoaded = false;

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
      final heading = random.nextDouble() * 360;
      final headingRad = heading * math.pi / 180; // Convert to radians
      final speed = 0.001; // Movement speed

      final aircraft = AircraftTraffic(
        id: 'AC${index.toString().padLeft(3, '0')}',
        callsign: 'UAL${100 + index}',
        position: LatLng(
          _initialCenter.latitude + (random.nextDouble() - 0.5) * 0.2,
          _initialCenter.longitude + (random.nextDouble() - 0.5) * 0.2,
        ),
        heading: heading,
        altitude: (25000 + random.nextInt(15000)).toDouble(),
        speed: (350 + random.nextInt(200)).toDouble(),
        verticalRate: (random.nextDouble() - 0.5) * 2000,
        aircraftType: _getRandomAircraftType(random),
        velocity: LatLng(
          math.cos(headingRad) * speed, // X velocity based on heading
          math.sin(headingRad) * speed, // Y velocity based on heading
        ),
      );
      print(
          'Generated aircraft ${aircraft.id} at ${aircraft.position.latitude}, ${aircraft.position.longitude}, heading: ${aircraft.heading.toStringAsFixed(1)}°');
      return aircraft;
    });
    print(
        'Generated ${_aircraftList.length} aircraft with heading-based movement');
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

  void _onFeatureTappedHandler(dynamic featureId, math.Point<double> point,
      LatLng latLng, String layerId) {
    _onFeatureTapped(layerId, featureId?.toString(), latLng);
  }

  void _onStyleLoaded() {
    setState(() {
      _isLoaded = true;
    });
    _loadTrafficIcon();
  }

  Future<void> _loadTrafficIcon() async {
    if (controller == null) return;

    try {
      // Load traffic icon
      final trafficBytes = await rootBundle.load('assets/traffic.png');
      final trafficList = trafficBytes.buffer.asUint8List();
      await controller!.addImage('traffic-icon', trafficList);

      // Load arrow icon for climb/descend indicators
      final arrowBytes = await rootBundle.load('assets/arrow.png');
      final arrowList = arrowBytes.buffer.asUint8List();
      await controller!.addImage('arrow-icon', arrowList);

      // Skip composite symbols - use hybrid approach only
      // await _createCompositeAviationSymbols();

      _iconLoaded = true;
      print('Traffic and arrow icons loaded successfully for hybrid approach');
      _addTrafficLayer();
    } catch (e) {
      print('Error loading icons: $e');
      _showErrorSnackBar('Failed to load icons: $e');
    }
  }

  Future<void> _createCompositeAviationSymbols() async {
    // Create composite aviation symbols for different climb/descend states
    await _createCompositeSymbol('aviation-climbing', isClimbing: true);
    await _createCompositeSymbol('aviation-descending', isClimbing: false);
    print(
        'Created composite aviation symbols for climbing and descending states');
  }

  Future<void> _createCompositeSymbol(String symbolId,
      {required bool isClimbing}) async {
    try {
      // Create a composite image using Flutter Canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Larger canvas size for better visibility
      const size = Size(240, 180); // Increased from 160x120
      const center = Offset(
          90, 90); // Aircraft center position (adjusted for larger canvas)

      // Load and decode the traffic icon
      final trafficBytes = await rootBundle.load('assets/traffic.png');
      final trafficCodec =
          await ui.instantiateImageCodec(trafficBytes.buffer.asUint8List());
      final trafficFrame = await trafficCodec.getNextFrame();
      final trafficImage = trafficFrame.image;

      // Load and decode the arrow icon
      final arrowBytes = await rootBundle.load('assets/arrow.png');
      final arrowCodec =
          await ui.instantiateImageCodec(arrowBytes.buffer.asUint8List());
      final arrowFrame = await arrowCodec.getNextFrame();
      final arrowImage = arrowFrame.image;

      // Draw larger traffic icon in center
      const trafficSize = 48.0; // Increased from 32.0
      final trafficRect = Rect.fromCenter(
        center: center,
        width: trafficSize,
        height: trafficSize,
      );
      canvas.drawImageRect(
        trafficImage,
        Rect.fromLTWH(0, 0, trafficImage.width.toDouble(),
            trafficImage.height.toDouble()),
        trafficRect,
        Paint(),
      );

      // Draw larger arrow to the right
      const arrowSize = 24.0; // Increased from 16.0
      final arrowCenter = Offset(center.dx + 70,
          center.dy); // 70 pixels to the right (increased from 50)
      final arrowRect = Rect.fromCenter(
        center: arrowCenter,
        width: arrowSize,
        height: arrowSize,
      );

      // Rotate arrow based on climb/descend state
      canvas.save();
      canvas.translate(arrowCenter.dx, arrowCenter.dy);
      canvas.rotate(isClimbing ? 0 : math.pi); // 0 for up, π for down
      canvas.translate(-arrowCenter.dx, -arrowCenter.dy);

      canvas.drawImageRect(
        arrowImage,
        Rect.fromLTWH(
            0, 0, arrowImage.width.toDouble(), arrowImage.height.toDouble()),
        arrowRect,
        Paint()
          ..colorFilter = const ColorFilter.mode(Colors.green, BlendMode.srcIn),
      );
      canvas.restore();

      // Add larger text labels (altitude above, callsign below)
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );

      // Larger altitude label (placeholder - will be dynamic)
      textPainter.text = TextSpan(
        text: 'ALT',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16, // Increased from 12
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 3, // Increased shadow
              offset: Offset(1.5, 1.5),
            ),
          ],
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas,
          Offset(center.dx - textPainter.width / 2,
              center.dy - 50)); // Moved further up

      // Larger callsign label (placeholder - will be dynamic)
      textPainter.text = TextSpan(
        text: 'UAL',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16, // Increased from 12
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 3, // Increased shadow
              offset: Offset(1.5, 1.5),
            ),
          ],
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas,
          Offset(center.dx - textPainter.width / 2,
              center.dy + 35)); // Moved further down

      // Convert to image
      final picture = recorder.endRecording();
      final image =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final imageBytes = byteData!.buffer.asUint8List();

      // Register with MapLibre
      await controller!.addImage(symbolId, imageBytes);

      print(
          'Created larger composite symbol: $symbolId (${isClimbing ? "climbing" : "descending"})');

      // Clean up
      picture.dispose();
      image.dispose();
      trafficImage.dispose();
      arrowImage.dispose();
    } catch (e) {
      print('Error creating composite symbol $symbolId: $e');
      throw e;
    }
  }

  Future<void> _addTrafficLayer() async {
    if (controller == null || !_isLoaded || !_iconLoaded) return;

    try {
      // Create GeoJSON source with aircraft data
      final geojsonData = _createTrafficGeoJSONMap();

      print(
          'Adding hybrid aviation symbols with ${_aircraftList.length} aircraft');

      await controller!.addGeoJsonSource(_trafficSourceId, geojsonData);

      // Aircraft icon layer (rotates with heading)
      await controller!.addSymbolLayer(
        _trafficSourceId,
        '${_trafficLayerId}_aircraft',
        const SymbolLayerProperties(
          iconImage: 'traffic-icon',
          iconSize: 0.1, // Much smaller - reduced from 0.15 to 0.1
          iconColor: "#FFFFFF",
          iconOpacity: 1.0,
          iconRotate: ["get", "heading"], // Aircraft rotates with heading
          iconRotationAlignment: "map", // Rotate with map
          iconPitchAlignment: "viewport",
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: true,
      );

      // Callsign labels (stay horizontal)
      await controller!.addSymbolLayer(
        _trafficSourceId,
        '${_trafficLayerId}_callsigns',
        const SymbolLayerProperties(
          textField: ["get", "callsign"],
          textSize: 14.0, // Larger text
          textColor: "#FFFFFF",
          textHaloColor: "#000000",
          textHaloWidth: 3.0,
          textOffset: [0, 4.5], // Further below aircraft
          textRotationAlignment: "viewport", // Stay horizontal
          textPitchAlignment: "viewport",
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        enableInteraction: true,
      );

      // Altitude labels (stay horizontal)
      await controller!.addSymbolLayer(
        _trafficSourceId,
        '${_trafficLayerId}_altitudes',
        const SymbolLayerProperties(
          textField: [
            "concat",
            [
              "round",
              ["get", "altitude"]
            ],
            "ft"
          ],
          textSize: 14.0, // Larger text
          textColor: "#FFFFFF",
          textHaloColor: "#000000",
          textHaloWidth: 3.0,
          textOffset: [0, -4.5], // Further above aircraft
          textRotationAlignment: "viewport", // Stay horizontal
          textPitchAlignment: "viewport",
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        enableInteraction: true,
      );

      // Climb/descend arrows (stay horizontal, positioned to the right)
      await controller!.addSymbolLayer(
        _trafficSourceId,
        '${_trafficLayerId}_arrows',
        const SymbolLayerProperties(
          iconImage: 'arrow-icon',
          iconSize: 0.08, // Smaller arrows - reduced from 0.15 to 0.08
          iconColor: "#00FF00",
          iconOpacity: 1.0,
          iconRotate: [
            "case",
            ["get", "isClimbing"],
            0, // 0° for climbing (up)
            180 // 180° for descending (down)
          ],
          iconOffset: [35, 0], // Fixed position to the right
          iconRotationAlignment: "viewport", // Stay aligned to screen
          iconPitchAlignment: "viewport",
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: true,
      );

      print(
          'ADSB hybrid aviation symbols added successfully - aircraft rotates, labels stay horizontal');
    } catch (e) {
      print('Error adding ADSB hybrid aviation symbols: $e');
      _showErrorSnackBar('Failed to add aviation symbols: $e');
    }
  }

  Map<String, dynamic> _createTrafficGeoJSONMap() {
    final features = _aircraftList.map((aircraft) {
      // Calculate if aircraft is climbing or descending based on altitude trend
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final cycle = (currentTime / 3000) % 2; // 3 second cycle
      final isClimbing = cycle < 1; // Climbing in first half of cycle

      return {
        'type': 'Feature',
        'id': aircraft.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [
            aircraft.position.longitude,
            aircraft.position.latitude
          ],
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
          'isClimbing': isClimbing, // For composite symbol selection
        },
      };
    }).toList();

    // Debug: Print first aircraft info
    if (_aircraftList.isNotEmpty) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final cycle = (currentTime / 3000) % 2;
      final isClimbing = cycle < 1;
      print(
          'Sample aircraft heading: ${_aircraftList.first.heading}°, ${isClimbing ? "climbing" : "descending"}, composite symbol approach');
    }

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
      await controller!
          .setLayerVisibility('${_trafficLayerId}_aircraft', _showTraffic);
      await controller!
          .setLayerVisibility('${_trafficLayerId}_callsigns', _showTraffic);
      await controller!
          .setLayerVisibility('${_trafficLayerId}_altitudes', _showTraffic);
      await controller!
          .setLayerVisibility('${_trafficLayerId}_arrows', _showTraffic);
    } catch (e) {
      print('Error toggling hybrid aviation symbol visibility: $e');
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
    _animationTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (timer) {
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
      // Calculate movement based on heading direction
      final headingRad = aircraft.heading * math.pi / 180; // Convert to radians
      final speed = 0.001; // Movement speed

      // Update position based on heading direction (aircraft moves in direction it's pointing)
      aircraft.position = LatLng(
        aircraft.position.latitude + math.cos(headingRad) * speed,
        aircraft.position.longitude + math.sin(headingRad) * speed,
      );

      // Always animate altitude (climb 1000ft, then descend 1000ft in a loop)
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final cycle = (currentTime / 3000) % 2; // 3 second cycle, 0-2 range
      final baseAltitude = 25000 +
          (aircraft.id.hashCode %
              15000); // Each aircraft has different base altitude

      if (cycle < 1) {
        // Climbing phase (0 to 1): add up to 1000ft
        aircraft.altitude = baseAltitude + (cycle * 1000);
      } else {
        // Descending phase (1 to 2): remove up to 1000ft
        aircraft.altitude = baseAltitude + ((2 - cycle) * 1000);
      }

      // Occasionally change heading only
      if (random.nextDouble() < 0.1) {
        final oldHeading = aircraft.heading;

        // Update heading
        aircraft.heading += (random.nextDouble() - 0.5) * 30;
        aircraft.heading = aircraft.heading % 360;
        if (aircraft.heading < 0) aircraft.heading += 360;

        // Update velocity to match new heading
        final newHeadingRad = aircraft.heading * math.pi / 180;
        aircraft.velocity = LatLng(
          math.cos(newHeadingRad) * speed,
          math.sin(newHeadingRad) * speed,
        );

        // Debug: Print changes for first aircraft
        if (aircraft.id == 'AC000') {
          print(
              'Aircraft ${aircraft.id}: heading ${oldHeading.toStringAsFixed(1)}° → ${aircraft.heading.toStringAsFixed(1)}°, altitude: ${aircraft.altitude.toStringAsFixed(0)}ft (cycle: ${cycle.toStringAsFixed(2)})');
        }
      }

      // Keep aircraft within bounds by turning them around
      if (aircraft.position.latitude < _initialCenter.latitude - 0.15 ||
          aircraft.position.latitude > _initialCenter.latitude + 0.15 ||
          aircraft.position.longitude < _initialCenter.longitude - 0.15 ||
          aircraft.position.longitude > _initialCenter.longitude + 0.15) {
        // Turn aircraft around by changing heading
        aircraft.heading = (aircraft.heading + 180) % 360;
        final newHeadingRad = aircraft.heading * math.pi / 180;
        aircraft.velocity = LatLng(
          math.cos(newHeadingRad) * speed,
          math.sin(newHeadingRad) * speed,
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
      print('Error updating composite traffic layer: $e');
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
    if ((layerId == '${_trafficLayerId}_aircraft' ||
            layerId == '${_trafficLayerId}_callsigns' ||
            layerId == '${_trafficLayerId}_altitudes' ||
            layerId == '${_trafficLayerId}_arrows') &&
        featureId != null) {
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
            Text(
                'Vertical Rate: ${aircraft.verticalRate.toStringAsFixed(0)} ft/min'),
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
                          onPressed:
                              _isLoaded ? _toggleTrafficVisibility : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _showTraffic ? Colors.green : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          child: Text(_showTraffic ? 'Hide' : 'Show'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed:
                              _isLoaded ? _toggleMovementSimulation : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _simulateMovement ? Colors.orange : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
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
  double altitude; // Made mutable for animation
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
