// ignore_for_file: unnecessary_getters_setters

part of '../maplibre_gl_platform_interface.dart';

/// The default instance of [MapLibrePlatform] to use.
typedef OnPlatformViewCreatedCallback = void Function(int);

abstract class MapLibrePlatform {
  static MapLibreMethodChannel? _instance;

  /// The default instance of [MapLibrePlatform] to use.
  ///
  /// Defaults to [MapLibreMethodChannel].
  ///
  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [MapLibrePlatform] when they register themselves.
  static MapLibrePlatform Function() createInstance =
      () => _instance ?? MapLibreMethodChannel();

  final onInfoWindowTappedPlatform = ArgumentCallbacks<String>();

  final onFeatureTappedPlatform = ArgumentCallbacks<Map<String, dynamic>>();

  final onFeatureDraggedPlatform = ArgumentCallbacks<Map<String, dynamic>>();

  final onCameraMoveStartedPlatform = ArgumentCallbacks<void>();

  final onCameraMovePlatform = ArgumentCallbacks<CameraPosition>();

  final onCameraIdlePlatform = ArgumentCallbacks<CameraPosition?>();

  final onMapStyleLoadedPlatform = ArgumentCallbacks<void>();

  final onMapClickPlatform = ArgumentCallbacks<Map<String, dynamic>>();

  final onMapLongClickPlatform = ArgumentCallbacks<Map<String, dynamic>>();

  final onCameraTrackingChangedPlatform =
      ArgumentCallbacks<MyLocationTrackingMode>();

  final onCameraTrackingDismissedPlatform = ArgumentCallbacks<void>();

  final onMapIdlePlatform = ArgumentCallbacks<void>();

  final onUserLocationUpdatedPlatform = ArgumentCallbacks<UserLocation>();

  final onTwoFingerHoldGesturePlatform =
      ArgumentCallbacks<Map<String, dynamic>>();

  // Native measurement callbacks
  final onNativeMeasurementStart = ArgumentCallbacks<Map<String, dynamic>>();
  final onNativeMeasurementUpdate = ArgumentCallbacks<Map<String, dynamic>>();
  final onNativeMeasurementEnd = ArgumentCallbacks<Map<String, dynamic>>();

  // Polyline editing callbacks
  final onPolylineBrokenPlatform = ArgumentCallbacks<Map<String, dynamic>>();
  final onPolylineModifiedPlatform = ArgumentCallbacks<Map<String, dynamic>>();
  final onPolylineEditingErrorPlatform =
      ArgumentCallbacks<Map<String, dynamic>>();

  Future<void> initPlatform(int id);
  Widget buildView(
      Map<String, dynamic> creationParams,
      OnPlatformViewCreatedCallback onPlatformViewCreated,
      Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers);
  Future<CameraPosition?> updateMapOptions(Map<String, dynamic> optionsUpdate);
  Future<bool?> animateCamera(CameraUpdate cameraUpdate, {Duration? duration});
  Future<bool?> moveCamera(CameraUpdate cameraUpdate);
  Future<void> updateMyLocationTrackingMode(
      MyLocationTrackingMode myLocationTrackingMode);

  Future<void> matchMapLanguageWithDeviceDefault();

  void resizeWebMap();
  void forceResizeWebMap();

  Future<void> updateContentInsets(EdgeInsets insets, bool animated);
  Future<void> setMapLanguage(String language);
  Future<void> setTelemetryEnabled(bool enabled);

  Future<bool> getTelemetryEnabled();
  Future<List> queryRenderedFeatures(
      Point<double> point, List<String> layerIds, List<Object>? filter);

  Future<List> queryRenderedFeaturesInRect(
      Rect rect, List<String> layerIds, String? filter);

  Future<List> querySourceFeatures(
      String sourceId, String? sourceLayerId, List<Object>? filter);
  Future invalidateAmbientCache();
  Future clearAmbientCache();
  Future<LatLng?> requestMyLocationLatLng();

  Future<LatLngBounds> getVisibleRegion();

  Future<void> addImage(String name, Uint8List bytes, [bool sdf = false]);

  Future<void> addImageSource(
      String imageSourceId, Uint8List bytes, LatLngQuad coordinates);

  Future<void> updateImageSource(
      String imageSourceId, Uint8List? bytes, LatLngQuad? coordinates);

  Future<void> addLayer(String imageLayerId, String imageSourceId,
      double? minzoom, double? maxzoom);

  Future<void> addLayerBelow(String imageLayerId, String imageSourceId,
      String belowLayerId, double? minzoom, double? maxzoom);

  Future<void> removeLayer(String imageLayerId);

  Future<List> getLayerIds();

  Future<List> getSourceIds();

  Future<void> setFilter(String layerId, dynamic filter);

  Future<dynamic> getFilter(String layerId);

  Future<Point> toScreenLocation(LatLng latLng);

  Future<List<Point>> toScreenLocationBatch(Iterable<LatLng> latLngs);

  Future<LatLng> toLatLng(Point screenLocation);

  Future<double> getMetersPerPixelAtLatitude(double latitude);

  Future<void> addGeoJsonSource(String sourceId, Map<String, dynamic> geojson,
      {String? promoteId});

  Future<void> setGeoJsonSource(String sourceId, Map<String, dynamic> geojson);

  Future<void> setCameraBounds({
    required double west,
    required double north,
    required double south,
    required double east,
    required int padding,
  });

  Future<void> setFeatureForGeoJsonSource(
      String sourceId, Map<String, dynamic> geojsonFeature);

  Future<void> removeSource(String sourceId);

  Future<void> addSymbolLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction});

  Future<void> addLineLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction});

  Future<void> setLayerProperties(
      String layerId, Map<String, dynamic> properties);

  Future<void> addCircleLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction});

  Future<void> addFillLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction});

  Future<void> addFillExtrusionLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction});

  Future<void> addRasterLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom});

  Future<void> addHillshadeLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom});

  Future<void> addHeatmapLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom});

  Future<void> addSource(String sourceId, SourceProperties properties);

  Future<void> setLayerVisibility(String layerId, bool visible);

  // Native Image Overlay Controls
  Future<void> addImageOverlayControls(
      String overlayId, List<List<double>> coordinates, bool editMode);
  Future<void> updateImageOverlayControls(
      String overlayId, List<List<double>> coordinates, bool editMode);
  Future<void> removeImageOverlayControls(String overlayId);
  Future<void> handleImageOverlayGesture(String overlayId, String gestureType,
      double screenX, double screenY, double deltaX, double deltaY);
  Future<void> setImageOverlayControlsSensitivity(
      String overlayId, double sensitivity);

  Future<void> enableTwoFingerHoldGestureDetection(bool enabled);

  // Native measurement methods
  Future<void> enableNativeMeasurement(bool enabled);
  Future<void> setNativeMeasurementStyle({
    required String lineColor,
    required double lineWidth,
    required double lineOpacity,
    required String endpointColor,
    required double endpointRadius,
  });
  Future<void> clearNativeMeasurement();
  Future<void> ensureMeasurementLayersOnTop();

  // Polyline editing methods
  Future<void> enableLineEditing(String lineId, bool enabled, [List<LatLng>? coordinates]);
  Future<void> setLineEditingStyle(Map<String, dynamic> style);
  Future<bool> isLineEditable(String lineId);

  @mustCallSuper
  void dispose() {
    // clear all callbacks to avoid cyclic refs
    onInfoWindowTappedPlatform.clear();
    onFeatureTappedPlatform.clear();
    onFeatureDraggedPlatform.clear();
    onCameraMoveStartedPlatform.clear();
    onCameraMovePlatform.clear();
    onCameraIdlePlatform.clear();
    onMapStyleLoadedPlatform.clear();

    onMapClickPlatform.clear();
    onMapLongClickPlatform.clear();
    onCameraTrackingChangedPlatform.clear();
    onCameraTrackingDismissedPlatform.clear();
    onMapIdlePlatform.clear();
    onUserLocationUpdatedPlatform.clear();
    onTwoFingerHoldGesturePlatform.clear();
    onNativeMeasurementStart.clear();
    onNativeMeasurementUpdate.clear();
    onNativeMeasurementEnd.clear();
    onPolylineBrokenPlatform.clear();
    onPolylineModifiedPlatform.clear();
    onPolylineEditingErrorPlatform.clear();
  }
}
