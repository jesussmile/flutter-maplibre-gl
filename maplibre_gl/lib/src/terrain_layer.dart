part of '../maplibre_gl.dart';

/// A terrain layer that uses native LERC decoding for elevation data
class TerrainLayer {
  final String id;
  final String sourceId;
  final Map<String, dynamic> properties;

  const TerrainLayer({
    required this.id,
    required this.sourceId,
    this.properties = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': 'raster',
      'source': sourceId,
      'paint': properties,
    };
  }
}

/// Native LERC-based terrain tile provider
class LercTerrainTileProvider {
  final String _baseUrl;
  final Map<String, String> _headers;
  final ColorScheme _colorScheme;

  const LercTerrainTileProvider({
    required String baseUrl,
    Map<String, String> headers = const {},
    ColorScheme colorScheme = ColorScheme.terrain,
  })  : _baseUrl = baseUrl,
        _headers = headers,
        _colorScheme = colorScheme;

  /// Download and decode LERC terrain tile
  Future<Uint8List?> getTile(int x, int y, int z) async {
    try {
      // Construct tile URL
      final url = _baseUrl
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString())
          .replaceAll('{z}', z.toString());

      // Download LERC data
      final response = await _downloadLercData(url);
      if (response == null) return null;

      // Decode using native LERC decoder
      final decodedData = await LercDecoder.decode(response);
      if (decodedData == null) return null;

      // Convert elevation data to image
      return await _elevationToImage(decodedData);
    } catch (e) {
      print('Error getting LERC tile: $e');
      return null;
    }
  }

  Future<Uint8List?> _downloadLercData(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = await HttpClient().getUrl(uri);

      // Add headers
      _headers.forEach((key, value) {
        request.headers.add(key, value);
      });

      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        return Uint8List.fromList(bytes);
      }
    } catch (e) {
      print('Error downloading LERC data: $e');
    }
    return null;
  }

  Future<Uint8List> _elevationToImage(DecodedLercData data) async {
    final width = data.info.width;
    final height = data.info.height;
    final elevations = data.data;

    // Calculate color mapping
    final minElevation = data.info.minValue;
    final maxElevation = data.info.maxValue;
    final elevationRange = maxElevation - minElevation;

    if (elevationRange == 0) {
      // Handle flat terrain
      final singleColor = _colorScheme.getColor(0.5);
      return await _createSolidColorImage(width, height, singleColor);
    }

    // Create image data
    final imageData = Uint8List(width * height * 4); // RGBA

    for (int i = 0; i < elevations.length; i++) {
      final elevation = elevations[i];
      final normalizedElevation = (elevation - minElevation) / elevationRange;
      final color = _colorScheme.getColor(normalizedElevation);

      final pixelIndex = i * 4;
      imageData[pixelIndex] = color.red;
      imageData[pixelIndex + 1] = color.green;
      imageData[pixelIndex + 2] = color.blue;
      imageData[pixelIndex + 3] = color.alpha;
    }

    // Convert to PNG
    final completer = Completer<Uint8List>();
    ui.decodeImageFromPixels(
      imageData,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) async {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        completer.complete(byteData!.buffer.asUint8List());
      },
    );

    return completer.future;
  }

  Future<Uint8List> _createSolidColorImage(
      int width, int height, ui.Color color) async {
    final imageData = Uint8List(width * height * 4);
    for (int i = 0; i < width * height; i++) {
      final pixelIndex = i * 4;
      imageData[pixelIndex] = color.red;
      imageData[pixelIndex + 1] = color.green;
      imageData[pixelIndex + 2] = color.blue;
      imageData[pixelIndex + 3] = color.alpha;
    }

    final completer = Completer<Uint8List>();
    ui.decodeImageFromPixels(
      imageData,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) async {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        completer.complete(byteData!.buffer.asUint8List());
      },
    );

    return completer.future;
  }
}

/// Color schemes for terrain visualization
enum ColorScheme {
  terrain,
  grayscale,
  hypsometric,
}

extension ColorSchemeExtension on ColorScheme {
  ui.Color getColor(double normalizedValue) {
    final clamped = normalizedValue.clamp(0.0, 1.0);

    switch (this) {
      case ColorScheme.terrain:
        return _getTerrainColor(clamped);
      case ColorScheme.grayscale:
        return _getGrayscaleColor(clamped);
      case ColorScheme.hypsometric:
        return _getHypsometricColor(clamped);
    }
  }

  ui.Color _getTerrainColor(double value) {
    // Terrain color scheme: blue (low) -> green -> yellow -> red -> white (high)
    if (value <= 0.2) {
      // Blue to green
      final t = value / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFF0066CC), // Blue
        const ui.Color(0xFF00AA00), // Green
        t,
      )!;
    } else if (value <= 0.4) {
      // Green to yellow
      final t = (value - 0.2) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFF00AA00), // Green
        const ui.Color(0xFFFFFF00), // Yellow
        t,
      )!;
    } else if (value <= 0.6) {
      // Yellow to orange
      final t = (value - 0.4) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFFFFFF00), // Yellow
        const ui.Color(0xFFFF8800), // Orange
        t,
      )!;
    } else if (value <= 0.8) {
      // Orange to red
      final t = (value - 0.6) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFFFF8800), // Orange
        const ui.Color(0xFFFF0000), // Red
        t,
      )!;
    } else {
      // Red to white
      final t = (value - 0.8) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFFFF0000), // Red
        const ui.Color(0xFFFFFFFF), // White
        t,
      )!;
    }
  }

  ui.Color _getGrayscaleColor(double value) {
    final intensity = (value * 255).round();
    return ui.Color.fromARGB(255, intensity, intensity, intensity);
  }

  ui.Color _getHypsometricColor(double value) {
    // Traditional hypsometric tinting
    if (value <= 0.1) {
      // Deep blue (below sea level/water)
      return const ui.Color(0xFF000080);
    } else if (value <= 0.2) {
      // Blue to light blue
      final t = (value - 0.1) / 0.1;
      return ui.Color.lerp(
        const ui.Color(0xFF000080), // Deep blue
        const ui.Color(0xFF4080FF), // Light blue
        t,
      )!;
    } else if (value <= 0.3) {
      // Light blue to green
      final t = (value - 0.2) / 0.1;
      return ui.Color.lerp(
        const ui.Color(0xFF4080FF), // Light blue
        const ui.Color(0xFF40FF40), // Green
        t,
      )!;
    } else if (value <= 0.5) {
      // Green to yellow-green
      final t = (value - 0.3) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFF40FF40), // Green
        const ui.Color(0xFF80FF40), // Yellow-green
        t,
      )!;
    } else if (value <= 0.7) {
      // Yellow-green to yellow
      final t = (value - 0.5) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFF80FF40), // Yellow-green
        const ui.Color(0xFFFFFF40), // Yellow
        t,
      )!;
    } else if (value <= 0.9) {
      // Yellow to brown
      final t = (value - 0.7) / 0.2;
      return ui.Color.lerp(
        const ui.Color(0xFFFFFF40), // Yellow
        const ui.Color(0xFF804020), // Brown
        t,
      )!;
    } else {
      // Brown to white (snow)
      final t = (value - 0.9) / 0.1;
      return ui.Color.lerp(
        const ui.Color(0xFF804020), // Brown
        const ui.Color(0xFFFFFFFF), // White
        t,
      )!;
    }
  }
}
