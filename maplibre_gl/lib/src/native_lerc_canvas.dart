part of '../maplibre_gl.dart';

/// Method channel handler for Native LERC Canvas Layer
/// This integrates with the MapLibre GL plugin's method channel system
class NativeLercCanvas {
  // Track native layer instances
  static final Map<String, NativeLercCanvasLayer> _layers = {};

  /// Creates a new native LERC canvas layer
  /// Must be called with a MapLibreMapController to access the correct method channel
  static Future<NativeLercCanvasLayer> createLayer({
    required MapLibreMapController controller,
    required String layerId,
    required List<double> elevationData,
    required int width,
    required int height,
    required List<double> bounds, // [west, south, east, north] = [minLon, minLat, maxLon, maxLat]
    required double referenceAltitude,
    required double warningAltitude,
  }) async {
    debugPrint('🏔️ Creating native LERC canvas layer: $layerId');

    // Call native initialize method through the map controller's platform interface
    await controller._maplibrePlatform.initializeNativeLercCanvas(
      layerId: layerId,
      elevationData: elevationData,
      width: width,
      height: height,
      bounds: bounds,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
    );

    // Create and track layer instance
    final layer = NativeLercCanvasLayer._(
      controller: controller,
      layerId: layerId,
      width: width,
      height: height,
      elevationData: elevationData,
      bounds: bounds,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
    );

    _layers[layerId] = layer;
    
    debugPrint('✅ Native LERC canvas layer created: $layerId (${width}x$height)');
    return layer;
  }

  /// Gets an existing layer by ID
  static NativeLercCanvasLayer? getLayer(String layerId) {
    return _layers[layerId];
  }

  /// Removes and disposes a layer
  static Future<void> removeLayer(String layerId) async {
    final layer = _layers[layerId];
    if (layer != null) {
      await layer.dispose();
      _layers.remove(layerId);
    }
  }

  /// Gets all active layers
  static Map<String, NativeLercCanvasLayer> get activeLayers => Map.unmodifiable(_layers);
}

/// Represents a native LERC canvas layer on the map
class NativeLercCanvasLayer {
  final MapLibreMapController _controller;
  final String layerId;
  final int width;
  final int height;
  final List<double> elevationData;
  final List<double> bounds;
  
  double _referenceAltitude;
  double _warningAltitude;
  bool _isDisposed = false;

  NativeLercCanvasLayer._({
    required MapLibreMapController controller,
    required this.layerId,
    required this.width,
    required this.height,
    required this.elevationData,
    required this.bounds,
    required double referenceAltitude,
    required double warningAltitude,
  }) : _controller = controller,
       _referenceAltitude = referenceAltitude,
       _warningAltitude = warningAltitude;

  /// Current reference altitude in feet
  double get referenceAltitude => _referenceAltitude;

  /// Current warning altitude in feet  
  double get warningAltitude => _warningAltitude;

  /// Whether this layer has been disposed
  bool get isDisposed => _isDisposed;

  /// Updates altitude thresholds (triggers instant re-rendering)
  Future<void> updateAltitudes({
    required double referenceAltitude,
    required double warningAltitude,
  }) async {
    if (_isDisposed) {
      throw StateError('Cannot update altitudes on disposed layer: $layerId');
    }

    debugPrint('⚡ Updating altitudes for native LERC layer: $layerId');
    debugPrint('📊 New altitudes - ref: ${referenceAltitude}ft, warn: ${warningAltitude}ft');

    // Call native update method through the map controller's platform interface
    await _controller._maplibrePlatform.updateNativeLercCanvasAltitudes(
      layerId: layerId,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
    );

    // Update local state
    _referenceAltitude = referenceAltitude;
    _warningAltitude = warningAltitude;

    debugPrint('✅ Altitudes updated instantly for layer: $layerId');
  }

  /// Disposes the native layer and frees resources
  Future<void> dispose() async {
    if (_isDisposed) {
      debugPrint('⚠️ Layer already disposed: $layerId');
      return;
    }

    debugPrint('🗑️ Disposing native LERC canvas layer: $layerId');

    try {
      // Call native dispose method through the map controller's platform interface
      await _controller._maplibrePlatform.disposeNativeLercCanvas(layerId);

      _isDisposed = true;
      debugPrint('✅ Native LERC canvas layer disposed: $layerId');
    } catch (e) {
      debugPrint('❌ Error disposing layer $layerId: $e');
      _isDisposed = true; // Mark as disposed even if native call failed
      rethrow;
    }
  }

  /// Gets basic information about this layer
  Map<String, dynamic> get info => {
    'layerId': layerId,
    'width': width,
    'height': height,
    'bounds': bounds,
    'referenceAltitude': referenceAltitude,
    'warningAltitude': warningAltitude,
    'isDisposed': isDisposed,
    'elevationDataSize': elevationData.length,
  };

  @override
  String toString() {
    return 'NativeLercCanvasLayer($layerId: ${width}x$height, ref: ${referenceAltitude}ft, warn: ${warningAltitude}ft, disposed: $isDisposed)';
  }
}

/// Helper class for creating LERC canvas layers with builder pattern
class NativeLercCanvasLayerBuilder {
  String? _layerId;
  List<double>? _elevationData;
  int? _width;
  int? _height;
  List<double>? _bounds;
  double? _referenceAltitude;
  double? _warningAltitude;

  /// Sets the layer ID (must be unique)
  NativeLercCanvasLayerBuilder layerId(String layerId) {
    _layerId = layerId;
    return this;
  }

  /// Sets the elevation data grid
  NativeLercCanvasLayerBuilder elevationData(List<double> data) {
    _elevationData = data;
    return this;
  }

  /// Sets the grid dimensions
  NativeLercCanvasLayerBuilder dimensions(int width, int height) {
    _width = width;
    _height = height;
    return this;
  }

  /// Sets the geographic bounds [west, south, east, north] = [minLon, minLat, maxLon, maxLat]
  NativeLercCanvasLayerBuilder bounds(List<double> bounds) {
    _bounds = bounds;
    return this;
  }

  /// Sets the altitude thresholds in feet
  NativeLercCanvasLayerBuilder altitudes(double referenceAltitude, double warningAltitude) {
    _referenceAltitude = referenceAltitude;
    _warningAltitude = warningAltitude;
    return this;
  }

  /// Builds and creates the native layer
  Future<NativeLercCanvasLayer> build() async {
    // Validate required parameters
    if (_layerId == null) throw ArgumentError('layerId is required');
    if (_elevationData == null) throw ArgumentError('elevationData is required');
    if (_width == null) throw ArgumentError('width is required');
    if (_height == null) throw ArgumentError('height is required');
    if (_bounds == null) throw ArgumentError('bounds is required');
    if (_referenceAltitude == null) throw ArgumentError('referenceAltitude is required');
    if (_warningAltitude == null) throw ArgumentError('warningAltitude is required');

    // Validate data consistency
    if (_elevationData!.length != _width! * _height!) {
      throw ArgumentError('Elevation data length (${_elevationData!.length}) must equal width * height ($_width * $_height = ${_width! * _height!})');
    }

    if (_bounds!.length != 4) {
      throw ArgumentError('Bounds must have exactly 4 elements [west, south, east, north] = [minLon, minLat, maxLon, maxLat]');
    }

    // Note: The builder pattern doesn't work well with the controller requirement
    // Use NativeLercCanvas.createLayer directly instead
    throw UnsupportedError('Use NativeLercCanvas.createLayer directly with a MapLibreMapController');
  }
}
