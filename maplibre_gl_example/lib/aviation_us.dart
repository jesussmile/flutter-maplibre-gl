import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'page.dart';

class AviationUSPage extends ExamplePage {
  const AviationUSPage({super.key})
      : super(const Icon(Icons.flight_takeoff), 'Aviation (US) – offline');

  @override
  Widget build(BuildContext context) => const _AviationUSMap();
}

class _AviationUSMap extends StatefulWidget {
  const _AviationUSMap();

  @override
  State<_AviationUSMap> createState() => _AviationUSMapState();
}

class _AviationUSMapState extends State<_AviationUSMap> {
  String? _stylePath;
  String? _pmtilesPath;
  bool _missingPMTiles = false;

  // Lower 48 center-ish
  static const _initialCamera = CameraPosition(
    target: LatLng(39.5, -98.35),
    zoom: 4.0,
  );

  @override
  void initState() {
    super.initState();
    _prepareStyle();
  }

  Future<void> _prepareStyle() async {
    final docs = await getApplicationDocumentsDirectory();
    final stylesDir = Directory('${docs.path}/styles');
    await stylesDir.create(recursive: true);

    // Target Documents path for the PMTiles
    final pmtiles = File('${docs.path}/us.pmtiles');
    _pmtilesPath = pmtiles.path;

    // Try to copy from bundled assets on first run
    if (!(await pmtiles.exists())) {
      try {
        final data = await rootBundle.load('assets/basemaps/us.pmtiles');
        await pmtiles.writeAsBytes(data.buffer.asUint8List());
      } catch (_) {
        // Asset not present; leave as-is and show hint
      }
    }

    _missingPMTiles = !(await pmtiles.exists());

    // Build a minimal aviation-leaning style that emphasizes runways/taxiways and aerodromes.
    final style = _buildStyleJson(
      pmtilesUrl: 'pmtiles://${pmtiles.path}',
    );

    final styleFile = File('${stylesDir.path}/aviation_us.json');
    await styleFile.writeAsString(style);

    if (!mounted) return;
    setState(() => _stylePath = styleFile.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_stylePath == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final body = MapLibreMap(
      styleString: _stylePath!,
      initialCameraPosition: _initialCamera,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Aviation (US) – offline')),
      body: Stack(
        children: [
          body,
          if (_missingPMTiles)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                color: Colors.black.withOpacity(0.75),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Missing us.pmtiles in app Documents.\n'
                    'Place a US basemap PMTiles file at:\n\n'
                    '${_pmtilesPath ?? ''}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildStyleJson({required String pmtilesUrl}) {
    // Minimal style using Protomaps v4-ish schema: earth, landuse, roads, water.
    // No glyphs/sprite to avoid network usage; also no symbol layers for now.
    return '''
{
  "version": 8,
  "name": "Aviation Light (US)",
  "sources": {
    "basemap": {
      "type": "vector",
      "attribution": "© OpenStreetMap contributors, Protomaps",
      "url": "$pmtilesUrl"
    }
  },
  "layers": [
    { "id": "background", "type": "background", "paint": { "background-color": "#fbfbfb" } },

    { "id": "earth", "type": "fill", "source": "basemap", "source-layer": "earth",
      "paint": { "fill-color": "#eef0f2" } },

    { "id": "water", "type": "fill", "source": "basemap", "source-layer": "water",
      "paint": { "fill-color": "#c6deff" } },

    { "id": "landcover", "type": "fill", "source": "basemap", "source-layer": "landcover",
      "paint": {
        "fill-color": ["match", ["get","kind"],
          "grassland", "#e9f6e8",
          "forest", "#e1f0e1",
          "scrub", "#eef6e6",
          "farmland", "#f3f7e7",
          "urban_area", "#ececec",
          "#f1f1f1"
        ],
        "fill-opacity": ["interpolate", ["linear"], ["zoom"], 5, 1, 8, 0.6]
      }
    },

    { "id": "landuse_aerodrome", "type": "fill", "source": "basemap", "source-layer": "landuse",
      "filter": ["==", ["get","kind"], "aerodrome"],
      "paint": { "fill-color": "#e6ebf5", "fill-opacity": 0.8 } },

    { "id": "runway_fill", "type": "fill", "source": "basemap", "source-layer": "landuse",
      "filter": ["in", ["get","kind"], ["literal", ["runway","taxiway"]]],
      "paint": { "fill-color": "#f2f3f6" } },

    { "id": "runway_line", "type": "line", "source": "basemap", "source-layer": "roads",
      "filter": ["==", ["get","kind_detail"], "runway"],
      "paint": {
        "line-color": "#f2f3f6",
        "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 10, 0.5, 13, 3, 16, 12]
      }
    },

    { "id": "taxiway_line", "type": "line", "source": "basemap", "source-layer": "roads",
      "minzoom": 13,
      "filter": ["==", ["get","kind_detail"], "taxiway"],
      "paint": {
        "line-color": "#e9e9ed",
        "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 13, 0.25, 14, 1.5, 16, 6]
      }
    },

    { "id": "roads_major", "type": "line", "source": "basemap", "source-layer": "roads",
      "filter": ["in", ["get","kind"], ["literal", ["highway","major_road"]]],
      "paint": { "line-color": "#b8c0cc", "line-width": ["interpolate", ["linear"], ["zoom"], 6, 0.6, 10, 1.2, 14, 3] }
    },

    { "id": "roads_minor", "type": "line", "source": "basemap", "source-layer": "roads",
      "filter": ["==", ["get","kind"], "minor_road"],
      "paint": { "line-color": "#cdd3dd", "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.2, 14, 1.5] }
    }
  ]
}
''';
  }
}
