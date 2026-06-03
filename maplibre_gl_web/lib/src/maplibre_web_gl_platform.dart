part of '../maplibre_gl_web.dart';

class MapLibreMapController extends MapLibrePlatform
    implements MapLibreMapOptionsSink {
  late html.DivElement _mapElement;

  late Map<String, dynamic> _creationParams;
  late MapLibreMap _map;
  dynamic _draggedFeatureId;
  LatLng? _dragOrigin;
  LatLng? _dragPrevious;
  bool _dragEnabled = true;
  final _addedFeaturesByLayer = <String, FeatureCollection>{};

  final _interactiveFeatureLayerIds = <String>{};

  static const String _webMeasurementSourceId = 'web-measurement-source';
  static const String _webMeasurementLineCasingLayerId =
      'web-measurement-line-casing-layer';
  static const String _webMeasurementLineLayerId = 'web-measurement-line-layer';
  static const String _webMeasurementEndpointLayerId =
      'web-measurement-endpoint-layer';
  static const String _webMeasurementDistanceLayerId =
      'web-measurement-distance-layer';
  static const String _webMeasurementBearingLayerId =
      'web-measurement-bearing-layer';
  static const List<String> _webMeasurementLayerIds = [
    _webMeasurementLineCasingLayerId,
    _webMeasurementLineLayerId,
    _webMeasurementEndpointLayerId,
    _webMeasurementDistanceLayerId,
    _webMeasurementBearingLayerId,
  ];

  bool _webMeasurementEnabled = false;
  LatLng? _webMeasurementStart;
  LatLng? _webMeasurementEnd;
  DateTime? _webMeasurementStartedAt;
  String? _webMeasurementDragRole;
  Point<double>? _webMeasurementPendingClickPoint;
  LatLng? _webMeasurementPendingClickCoordinate;
  bool _webMeasurementPendingClickMoved = false;
  String _webMeasurementLineColor = '#E8604C';
  double _webMeasurementLineWidth = 4.0;
  double _webMeasurementLineOpacity = 0.9;
  String _webMeasurementEndpointColor = '#FFFFFF';
  double _webMeasurementEndpointRadius = 9.0;
  static const double _webMeasurementClickSlop = 8.0;

  static const String _webLineEditingSourceId = 'web-polyline-editing-source';
  static const String _webLineEditingPreviewCasingLayerId =
      'web-polyline-editing-preview-casing-layer';
  static const String _webLineEditingPreviewLayerId =
      'web-polyline-editing-preview-layer';
  static const String _webLineEditingCasingLayerId =
      'web-polyline-editing-breakpoint-casing-layer';
  static const String _webLineEditingPointLayerId =
      'web-polyline-editing-breakpoint-layer';
  static const List<String> _webLineEditingLayerIds = [
    _webLineEditingPreviewCasingLayerId,
    _webLineEditingPreviewLayerId,
    _webLineEditingCasingLayerId,
    _webLineEditingPointLayerId,
  ];

  final Map<String, _WebEditableLine> _webEditableLines = {};
  Map<String, dynamic> _webLineEditingStyle = {
    'breakPointColor': '#FFC857',
    'breakPointRadius': 12.0,
    'breakPointBorderColor': '#FFFFFF',
    'breakPointBorderWidth': 2.0,
    'previewLineColor': '#FFC857',
    'previewLineOpacity': 0.82,
    'previewLineWidth': 4.0,
  };
  _WebLineEditDrag? _webLineEditDrag;
  bool _suppressNextMapClick = false;

  bool _trackCameraPosition = false;
  GeolocateControl? _geolocateControl;
  LatLng? _myLastLocation;
  StreamSubscription<html.MouseEvent>? _canvasMouseDownSubscription;
  StreamSubscription<html.MouseEvent>? _canvasMouseMoveSubscription;
  StreamSubscription<html.MouseEvent>? _canvasMouseUpSubscription;

  String? _navigationControlPosition;
  NavigationControl? _navigationControl;
  AttributionControl? _attributionControl;
  Timer? lastResizeObserverTimer;

  @override
  Widget buildView(
      Map<String, dynamic> creationParams,
      OnPlatformViewCreatedCallback onPlatformViewCreated,
      Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers) {
    _creationParams = creationParams;
    _registerViewFactory(onPlatformViewCreated, hashCode);
    return HtmlElementView(
        viewType: 'plugins.flutter.io/maplibre_gl_$hashCode');
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(_canvasMouseDownSubscription?.cancel());
    unawaited(_canvasMouseMoveSubscription?.cancel());
    unawaited(_canvasMouseUpSubscription?.cancel());
    _map.remove();
  }

  void _registerViewFactory(Function(int) callback, int identifier) {
    ui_web.platformViewRegistry.registerViewFactory(
        'plugins.flutter.io/maplibre_gl_$identifier', (int viewId) {
      _mapElement = html.DivElement()
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.bottom = '0'
        ..style.left = '0'
        ..style.right = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      callback(viewId);
      return _mapElement;
    });
  }

  @override
  Future<void> initPlatform(int id) async {
    if (_creationParams.containsKey('initialCameraPosition')) {
      final camera = _creationParams['initialCameraPosition'];
      _dragEnabled = _creationParams['dragEnabled'] ?? true;

      _map = MapLibreMap(
        MapOptions(
          container: _mapElement,
          style: _creationParams['styleString'],
          center: LngLat(camera['target'][1], camera['target'][0]),
          zoom: camera['zoom'],
          bearing: camera['bearing'],
          pitch: camera['tilt'],
          preserveDrawingBuffer: _creationParams['webPreserveDrawingBuffer'],
          attributionControl: false, //avoid duplicate control
        ),
      );
      // Expose the raw MapLibre GL JS map instance on window for JS interop.
      // _map is a Dart wrapper; _map.jsObject is the actual maplibregl.Map.
      setProperty(html.window, 'maplibreMap', _map.jsObject);
      setProperty(html.window, 'map',
          _map.jsObject); // also set as 'map' for JS compatibility
      _map.on('style.load', _onStyleLoaded);
      _map.on('click', _onMapClick);
      // long click not available in web, so it is mapped to double click
      _map.on('dblclick', _onMapLongClick);
      _map.on('movestart', _onCameraMoveStarted);
      _map.on('move', _onCameraMove);
      _map.on('moveend', _onCameraIdle);
      _map.on('resize', (_) => _onMapResize());
      _map.on('styleimagemissing', _loadFromAssets);
      if (_dragEnabled) {
        _map.on('mousedown', _onMapMouseDown);
        _map.on('mouseup', _onMouseUp);
        _map.on('mousemove', _onMouseMove);
      }
      _attachCanvasPointerFallback();

      _initResizeObserver();
    }
    Convert.interpretMapLibreMapOptions(_creationParams['options'], this);
  }

  void _attachCanvasPointerFallback() {
    final canvas = _map.getCanvas();
    if (canvas is! html.Element) return;
    unawaited(_canvasMouseDownSubscription?.cancel());
    unawaited(_canvasMouseMoveSubscription?.cancel());
    unawaited(_canvasMouseUpSubscription?.cancel());
    _canvasMouseDownSubscription =
        canvas.onMouseDown.listen(_onCanvasMouseDown);
    _canvasMouseMoveSubscription =
        canvas.onMouseMove.listen(_onCanvasMouseMove);
    _canvasMouseUpSubscription = html.window.onMouseUp.listen(_onCanvasMouseUp);
  }

  void _initResizeObserver() {
    final resizeObserver = html.ResizeObserver((entries, observer) {
      // The resize observer might be called a lot of times when the user resizes the browser window with the mouse for example.
      // Due to the fact that the resize call is quite expensive it should not be called for every triggered event but only the last one, like "onMoveEnd".
      // But because there is no event type for the end, there is only the option to spawn timers and cancel the previous ones if they get overwritten by a new event.
      lastResizeObserverTimer?.cancel();
      lastResizeObserverTimer = Timer(const Duration(milliseconds: 50), () {
        _onMapResize();
      });
    });
    resizeObserver.observe(html.document.body!);
  }

  Future<void> _loadFromAssets(Event event) async {
    final imagePath = event.id;
    final bytes = await rootBundle.load(imagePath);
    await addImage(imagePath, bytes.buffer.asUint8List());
  }

  _onMouseDown(Event e) {
    final isDraggable = e.features[0].properties['draggable'];
    if (isDraggable != null && isDraggable) {
      // Prevent the default map drag behavior.
      e.preventDefault();
      _draggedFeatureId = e.features[0].id;
      _map.getCanvas().style.cursor = 'grabbing';
      final coords = e.lngLat;
      _dragOrigin = LatLng(coords.lat as double, coords.lng as double);

      if (_draggedFeatureId != null) {
        final current =
            LatLng(e.lngLat.lat.toDouble(), e.lngLat.lng.toDouble());
        final payload = {
          'id': _draggedFeatureId,
          'point': Point<double>(e.point.x.toDouble(), e.point.y.toDouble()),
          'origin': _dragOrigin,
          'current': current,
          'delta': const LatLng(0, 0),
          'eventType': 'start'
        };
        onFeatureDraggedPlatform(payload);
      }
    }
  }

  void _onMapMouseDown(Event e) {
    // Web measurement and route editing use DOM canvas mouse events below as
    // the single pointer input path. Handling the same mousedown here as well
    // double-applies click state on MapLibre GL JS.
  }

  void _onCanvasMouseDown(html.MouseEvent event) {
    final point = _mapPointFromMouseEvent(event);
    if (point == null) return;
    if (_tryStartWebMeasurementDragAt(point)) {
      event.preventDefault();
      return;
    }
    if (_tryStartWebLineEditDragAt(point)) {
      event.preventDefault();
      return;
    }
    if (_webMeasurementEnabled) {
      _webMeasurementPendingClickPoint = point;
      _webMeasurementPendingClickCoordinate = _unprojectPoint(point);
      _webMeasurementPendingClickMoved = false;
    }
  }

  void _onCanvasMouseMove(html.MouseEvent event) {
    final point = _mapPointFromMouseEvent(event);
    if (point == null) return;
    if (_webMeasurementDragRole != null) {
      event.preventDefault();
      _updateWebMeasurementDragAt(_unprojectPoint(point));
      return;
    }
    if (_webLineEditDrag != null) {
      event.preventDefault();
      _updateWebLineEditDragAt(_unprojectPoint(point));
      return;
    }
    final pendingPoint = _webMeasurementPendingClickPoint;
    if (pendingPoint != null &&
        _pointDistance(point, pendingPoint) > _webMeasurementClickSlop) {
      _webMeasurementPendingClickMoved = true;
    }
  }

  void _onCanvasMouseUp(html.MouseEvent event) {
    final point = _mapPointFromMouseEvent(event);
    if (point == null) return;
    if (_webMeasurementDragRole != null) {
      event.preventDefault();
      _finishWebMeasurementDragAt(_unprojectPoint(point));
      return;
    }
    if (_webLineEditDrag != null) {
      event.preventDefault();
      _finishWebLineEditDragAt(_unprojectPoint(point));
      return;
    }
    final pendingPoint = _webMeasurementPendingClickPoint;
    final pendingCoordinate = _webMeasurementPendingClickCoordinate;
    final pendingMoved = _webMeasurementPendingClickMoved ||
        (pendingPoint != null &&
            _pointDistance(point, pendingPoint) > _webMeasurementClickSlop);
    _clearWebMeasurementPendingClick();
    if (_webMeasurementEnabled && pendingCoordinate != null && !pendingMoved) {
      if (_handleWebMeasurementCoordinate(pendingCoordinate)) {
        event.preventDefault();
        _suppressNextMapClick = true;
      }
    }
  }

  _onMouseUp(Event e) {
    if (_draggedFeatureId != null) {
      final current = LatLng(e.lngLat.lat.toDouble(), e.lngLat.lng.toDouble());
      final payload = {
        'id': _draggedFeatureId,
        'point': Point<double>(e.point.x.toDouble(), e.point.y.toDouble()),
        'origin': _dragOrigin,
        'current': current,
        'delta': current - (_dragPrevious ?? _dragOrigin!),
        'eventType': 'end'
      };
      onFeatureDraggedPlatform(payload);
    }
    _draggedFeatureId = null;
    _dragPrevious = null;
    _dragOrigin = null;
    _map.getCanvas().style.cursor = '';
  }

  _onMouseMove(Event e) {
    if (_draggedFeatureId != null) {
      final current = LatLng(e.lngLat.lat.toDouble(), e.lngLat.lng.toDouble());
      final payload = {
        'id': _draggedFeatureId,
        'point': Point<double>(e.point.x.toDouble(), e.point.y.toDouble()),
        'origin': _dragOrigin,
        'current': current,
        'delta': current - (_dragPrevious ?? _dragOrigin!),
        'eventType': 'drag'
      };
      _dragPrevious = current;
      onFeatureDraggedPlatform(payload);
    }
  }

  @override
  Future<CameraPosition?> updateMapOptions(
      Map<String, dynamic> optionsUpdate) async {
    // FIX: why is called indefinitely? (map_ui page)
    Convert.interpretMapLibreMapOptions(optionsUpdate, this);
    return _getCameraPosition();
  }

  @override
  Future<bool?> animateCamera(CameraUpdate cameraUpdate,
      {Duration? duration}) async {
    final cameraOptions = Convert.toCameraOptions(cameraUpdate, _map);
    _map.flyTo(cameraOptions);
    return true;
  }

  @override
  Future<bool?> moveCamera(CameraUpdate cameraUpdate) async {
    final cameraOptions = Convert.toCameraOptions(cameraUpdate, _map);
    _map.jumpTo(cameraOptions);
    return true;
  }

  @override
  Future<void> updateMyLocationTrackingMode(
      MyLocationTrackingMode myLocationTrackingMode) async {
    setMyLocationTrackingMode(myLocationTrackingMode.index);
  }

  @override
  Future<void> matchMapLanguageWithDeviceDefault() async {
    // Fix in https://github.com/maplibre/flutter-maplibre-gl/issues/263
    // ignore: deprecated_member_use
    setMapLanguage(ui.window.locale.languageCode);
  }

  @override
  Future<void> setMapLanguage(String language) async {
    final layers = _map.getLayers();

    final languageRegex = RegExp("(name:[a-z]+)");

    final symbolLayers = layers.where((layer) => layer.type == "symbol");

    for (final layer in symbolLayers) {
      final dynamic properties = _map.getLayoutProperty(layer.id, 'text-field');

      if (properties == null) {
        continue;
      }

      // We could skip the current iteration, whenever there is not current language.
      if (!languageRegex.hasMatch(properties.toString())) {
        continue;
      }

      final newProperties = [
        "coalesce",
        ["get", "name:$language"],
        ["get", "name:latin"],
        ["get", "name"],
      ];

      _map.setLayoutProperty(layer.id, 'text-field', newProperties);
    }
  }

  @override
  Future<void> setTelemetryEnabled(bool enabled) async {
    print('Telemetry not available in web');
    return;
  }

  @override
  Future<bool> getTelemetryEnabled() async {
    print('Telemetry not available in web');
    return false;
  }

  @override
  Future<List> queryRenderedFeatures(
      Point<double> point, List<String> layerIds, List<Object>? filter) async {
    final options = <String, dynamic>{};
    if (layerIds.isNotEmpty) {
      options['layers'] = layerIds;
    }
    if (filter != null) {
      options['filter'] = filter;
    }

    // avoid issues with the js point type
    final pointAsList = [point.x, point.y];
    return _map
        .queryRenderedFeatures([pointAsList, pointAsList], options)
        .map((feature) => {
              'type': 'Feature',
              'id': feature.id,
              'geometry': {
                'type': feature.geometry.type,
                'coordinates': feature.geometry.coordinates,
              },
              'properties': feature.properties,
              'source': feature.source,
            })
        .toList();
  }

  @override
  Future<List> queryRenderedFeaturesInRect(
      Rect rect, List<String> layerIds, String? filter) async {
    final options = <String, dynamic>{};
    if (layerIds.isNotEmpty) {
      options['layers'] = layerIds;
    }
    if (filter != null) {
      options['filter'] = filter;
    }
    return _map
        .queryRenderedFeatures([
          [rect.left, rect.bottom],
          [rect.right, rect.top],
        ], options)
        .map((feature) => {
              'type': 'Feature',
              'id': feature.id,
              'geometry': {
                'type': feature.geometry.type,
                'coordinates': feature.geometry.coordinates,
              },
              'properties': feature.properties,
              'source': feature.source,
            })
        .toList();
  }

  @override
  Future<List> querySourceFeatures(
      String sourceId, String? sourceLayerId, List<Object>? filter) async {
    final parameters = <String, dynamic>{};

    if (sourceLayerId != null) {
      parameters['sourceLayer'] = sourceLayerId;
    }

    if (filter != null) {
      parameters['filter'] = filter;
    }
    print(parameters);

    return _map
        .querySourceFeatures(sourceId, parameters)
        .map((feature) => {
              'type': 'Feature',
              'id': feature.id,
              'geometry': {
                'type': feature.geometry.type,
                'coordinates': feature.geometry.coordinates,
              },
              'properties': feature.properties,
              'source': feature.source,
            })
        .toList();
  }

  @override
  Future invalidateAmbientCache() async {
    print('Offline storage not available in web');
  }

  @override
  Future clearAmbientCache() async {
    print('Offline storage not available in web');
  }

  @override
  Future<LatLng?> requestMyLocationLatLng() async {
    return _myLastLocation;
  }

  @override
  Future<LatLngBounds> getVisibleRegion() async {
    final bounds = _map.getBounds();
    return LatLngBounds(
      southwest: LatLng(
        bounds.getSouthWest().lat as double,
        bounds.getSouthWest().lng as double,
      ),
      northeast: LatLng(
        bounds.getNorthEast().lat as double,
        bounds.getNorthEast().lng as double,
      ),
    );
  }

  @override
  Future<void> addImage(
    String name,
    Uint8List bytes, [
    bool sdf = false,
    double pixelRatio = 1.0,
  ]) async {
    if (_map.hasImage(name)) return;

    // Use browser-native image decoding instead of the `image` package,
    // which reports incorrect dimensions when compiled to JavaScript.
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final img = html.ImageElement(src: url);
    await img.onLoad.first;
    final w = img.naturalWidth;
    final h = img.naturalHeight;
    html.Url.revokeObjectUrl(url);

    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    ctx.drawImage(img, 0, 0);
    final imageData = ctx.getImageData(0, 0, w, h);

    _map.addImage(
      name,
      {
        'width': w,
        'height': h,
        'data': imageData.data,
      },
      {
        'sdf': sdf,
        'pixelRatio': pixelRatio,
      },
    );
  }

  @override
  Future<void> removeSource(String sourceId) async {
    _map.removeSource(sourceId);
  }

  CameraPosition? _getCameraPosition() {
    if (_trackCameraPosition) {
      final center = _map.getCenter();
      return CameraPosition(
        bearing: _map.getBearing() as double,
        target: LatLng(center.lat as double, center.lng as double),
        tilt: _map.getPitch() as double,
        zoom: _map.getZoom() as double,
      );
    }
    return null;
  }

  void _onStyleLoaded(_) {
    final loaded = _map.isStyleLoaded();
    if (!loaded) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _onStyleLoaded(_);
      });
      return;
    }
    _onMapResize();
    if (_webMeasurementEnabled) {
      _ensureWebMeasurementLayers();
      _renderWebMeasurement();
    }
    if (_webEditableLines.values.any((line) => line.enabled)) {
      _ensureWebLineEditingLayers();
      _renderWebLineEditingHandles();
    }
    onMapStyleLoadedPlatform(null);
  }

  void _onMapResize() {
    Timer(Duration.zero, () {
      final container = _map.getContainer();
      final canvas = _map.getCanvas();
      final widthMismatch = canvas.clientWidth != container.clientWidth;
      final heightMismatch = canvas.clientHeight != container.clientHeight;
      if (widthMismatch || heightMismatch) {
        _map.resize();
      }
    });
  }

  void _onMapClick(Event e) {
    if (_suppressNextMapClick) {
      _suppressNextMapClick = false;
      return;
    }
    if (_webMeasurementEnabled) return;
    final features = _map.queryRenderedFeatures([e.point.x, e.point.y],
        {"layers": _interactiveFeatureLayerIds.toList()});
    final payload = {
      'point': Point<double>(e.point.x.toDouble(), e.point.y.toDouble()),
      'latLng': LatLng(e.lngLat.lat.toDouble(), e.lngLat.lng.toDouble()),
      if (features.isNotEmpty) "id": features.first.id ?? '',
      if (features.isNotEmpty) "layerId": features.first.source ?? '',
    };
    if (features.isNotEmpty) {
      onFeatureTappedPlatform(payload);
    } else {
      onMapClickPlatform(payload);
    }
  }

  void _onMapLongClick(e) {
    onMapLongClickPlatform({
      'point': Point<double>(e.point.x, e.point.y),
      'latLng': LatLng(e.lngLat.lat, e.lngLat.lng),
    });
  }

  void _onCameraMoveStarted(_) {
    onCameraMoveStartedPlatform(null);
  }

  void _onCameraMove(_) {
    final center = _map.getCenter();
    final camera = CameraPosition(
      bearing: _map.getBearing() as double,
      target: LatLng(center.lat as double, center.lng as double),
      tilt: _map.getPitch() as double,
      zoom: _map.getZoom() as double,
    );
    onCameraMovePlatform(camera);
  }

  void _onCameraIdle(_) {
    final center = _map.getCenter();
    final camera = CameraPosition(
      bearing: _map.getBearing() as double,
      target: LatLng(center.lat as double, center.lng as double),
      tilt: _map.getPitch() as double,
      zoom: _map.getZoom() as double,
    );
    onCameraIdlePlatform(camera);
  }

  void _onCameraTrackingChanged(bool isTracking) {
    if (isTracking) {
      onCameraTrackingChangedPlatform(MyLocationTrackingMode.tracking);
    } else {
      onCameraTrackingChangedPlatform(MyLocationTrackingMode.none);
    }
  }

  void _onCameraTrackingDismissed() {
    onCameraTrackingDismissedPlatform(null);
  }

  void _addGeolocateControl({bool trackUserLocation = false}) {
    _removeGeolocateControl();
    _geolocateControl = GeolocateControl(
      GeolocateControlOptions(
        positionOptions: PositionOptions(enableHighAccuracy: true),
        trackUserLocation: trackUserLocation,
        showAccuracyCircle: true,
        showUserLocation: true,
      ),
    );
    _geolocateControl!.on('geolocate', (e) {
      _myLastLocation = LatLng(e.coords.latitude, e.coords.longitude);
      onUserLocationUpdatedPlatform(UserLocation(
          position: LatLng(e.coords.latitude, e.coords.longitude),
          altitude: e.coords.altitude,
          bearing: e.coords.heading,
          speed: e.coords.speed,
          horizontalAccuracy: e.coords.accuracy,
          verticalAccuracy: e.coords.altitudeAccuracy,
          heading: null,
          timestamp: DateTime.fromMillisecondsSinceEpoch(e.timestamp)));
    });
    _geolocateControl!.on('trackuserlocationstart', (_) {
      _onCameraTrackingChanged(true);
    });
    _geolocateControl!.on('trackuserlocationend', (_) {
      _onCameraTrackingChanged(false);
      _onCameraTrackingDismissed();
    });
    _map.addControl(_geolocateControl, 'bottom-right');
  }

  void _removeGeolocateControl() {
    if (_geolocateControl != null) {
      _map.removeControl(_geolocateControl);
      _geolocateControl = null;
    }
  }

  void _updateNavigationControl({
    bool? compassEnabled,
    CompassViewPosition? position,
  }) {
    bool? prevShowCompass;
    if (_navigationControl != null) {
      prevShowCompass = _navigationControl!.options.showCompass;
    }
    final prevPosition = _navigationControlPosition;

    final positionString = switch (position) {
      CompassViewPosition.topRight => 'top-right',
      CompassViewPosition.topLeft => 'top-left',
      CompassViewPosition.bottomRight => 'bottom-right',
      CompassViewPosition.bottomLeft => 'bottom-left',
      _ => null,
    };

    final newShowCompass = compassEnabled ?? prevShowCompass ?? false;
    final newPosition = positionString ?? prevPosition;

    _removeNavigationControl();
    _navigationControl = NavigationControl(NavigationControlOptions(
      showCompass: newShowCompass,
      showZoom: false,
      visualizePitch: false,
    ));

    if (newPosition == null) {
      _map.addControl(_navigationControl);
    } else {
      _map.addControl(_navigationControl, newPosition);
      _navigationControlPosition = newPosition;
    }
  }

  void _removeNavigationControl() {
    if (_navigationControl != null) {
      _map.removeControl(_navigationControl);
      _navigationControl = null;
    }
  }

  void _updateAttributionButton(
    AttributionButtonPosition position,
  ) {
    String? positionString;
    switch (position) {
      case AttributionButtonPosition.topRight:
        positionString = 'top-right';
      case AttributionButtonPosition.topLeft:
        positionString = 'top-left';
      case AttributionButtonPosition.bottomRight:
        positionString = 'bottom-right';
      case AttributionButtonPosition.bottomLeft:
        positionString = 'bottom-left';
    }

    _removeAttributionButton();
    _attributionControl = AttributionControl(AttributionControlOptions());
    _map.addControl(_attributionControl, positionString);
  }

  void _removeAttributionButton() {
    if (_attributionControl != null) {
      _map.removeControl(_attributionControl);
      _attributionControl = null;
    }
  }

  /*
   *  MapLibreMapOptionsSink
   */
  @override
  void setAttributionButtonMargins(int x, int y) {
    print('setAttributionButtonMargins not available in web');
  }

  @override
  void setCameraTargetBounds(LatLngBounds? bounds) {
    if (bounds == null) {
      _map.setMaxBounds(null);
    } else {
      _map.setMaxBounds(
        LngLatBounds(
          LngLat(
            bounds.southwest.longitude,
            bounds.southwest.latitude,
          ),
          LngLat(
            bounds.northeast.longitude,
            bounds.northeast.latitude,
          ),
        ),
      );
    }
  }

  @override
  void setCompassEnabled(bool compassEnabled) {
    _updateNavigationControl(compassEnabled: compassEnabled);
  }

  @override
  void setCompassAlignment(CompassViewPosition position) {
    _updateNavigationControl(position: position);
  }

  @override
  void setAttributionButtonAlignment(AttributionButtonPosition position) {
    _updateAttributionButton(position);
  }

  @override
  void setCompassViewMargins(int x, int y) {
    print('setCompassViewMargins not available in web');
  }

  @override
  void setLogoViewMargins(int x, int y) {
    print('setLogoViewMargins not available in web');
  }

  @override
  void setLogoViewAlignment(LogoViewPosition position) {
    print('setLogoViewAlignment not available in web');
  }

  @override
  void setScaleControlEnabled(bool enabled) {
    print('setScaleControlEnabled not available in web');
  }

  @override
  void setScaleControlPosition(ScaleControlPosition position) {
    print('setScaleControlPosition not available in web');
  }

  @override
  void setScaleControlUnit(ScaleControlUnit unit) {
    print('setScaleControlUnit not available in web');
  }

  @override
  void setFeatureTapsTriggersMapClick(bool triggers) {
    print('setFeatureTapsTriggersMapClick not available in web');
  }

  @override
  void setLocationEngineProperties({
    required bool enableHighAccuracy,
    required int maximumAge,
    required int timeout,
  }) {
    print('setLocationEngineProperties not available in web');
  }

  @override
  void setMinMaxZoomPreference(num? min, num? max) {
    // FIX: why is called indefinitely? (map_ui page)
    _map.setMinZoom(min);
    _map.setMaxZoom(max);
  }

  @override
  void setMyLocationEnabled(bool myLocationEnabled) {
    if (myLocationEnabled) {
      _addGeolocateControl();
    } else {
      _removeGeolocateControl();
    }
  }

  @override
  void setMyLocationRenderMode(int myLocationRenderMode) {
    print('myLocationRenderMode not available in web');
  }

  @override
  void setMyLocationTrackingMode(int myLocationTrackingMode) {
    if (_geolocateControl == null) {
      //myLocationEnabled is false, ignore myLocationTrackingMode
      return;
    }
    if (myLocationTrackingMode == 0) {
      _addGeolocateControl();
    } else {
      print('Only one tracking mode available in web');
      _addGeolocateControl(trackUserLocation: true);
    }
  }

  @override
  void setStyle(dynamic styleObject) {
    _map.setStyle(styleObject, {'diff': false});
  }

  @override
  void setStyleString(String? styleString) {
    //remove old mouseenter callbacks to avoid multicalling
    for (final layerId in _interactiveFeatureLayerIds) {
      _map.off('mouseenter', layerId, _onMouseEnterFeature);
      _map.off('mousemouve', layerId, _onMouseEnterFeature);
      _map.off('mouseleave', layerId, _onMouseLeaveFeature);
      if (_dragEnabled) _map.off('mousedown', layerId, _onMouseDown);
    }
    _interactiveFeatureLayerIds.clear();

    _map.setStyle(styleString, {'diff': false});
  }

  @override
  void setTrackCameraPosition(bool trackCameraPosition) {
    _trackCameraPosition = trackCameraPosition;
  }

  @override
  Future<LatLng> toLatLng(Point<num> screenLocation) async {
    final lngLat =
        _map.unproject(geo_point.Point(screenLocation.x, screenLocation.y));
    return LatLng(lngLat.lat as double, lngLat.lng as double);
  }

  @override
  Future<Point> toScreenLocation(LatLng latLng) async {
    final screenPosition =
        _map.project(LngLat(latLng.longitude, latLng.latitude));
    final point = Point(screenPosition.x.round(), screenPosition.y.round());

    return point;
  }

  @override
  Future<List<Point<num>>> toScreenLocationBatch(
      Iterable<LatLng> latLngs) async {
    return latLngs.map((latLng) {
      final screenPosition =
          _map.project(LngLat(latLng.longitude, latLng.latitude));
      return Point(screenPosition.x.round(), screenPosition.y.round());
    }).toList(growable: false);
  }

  @override
  Future<double> getMetersPerPixelAtLatitude(double latitude) async {
    //https://wiki.openstreetmap.org/wiki/Zoom_levels
    const circumference = 40075017.686;
    final zoom = _map.getZoom();
    return circumference * cos(latitude * (pi / 180)) / pow(2, zoom + 9);
  }

  @override
  Future<void> removeLayer(String imageLayerId) async {
    _interactiveFeatureLayerIds.remove(imageLayerId);
    _map.removeLayer(imageLayerId);
  }

  @override
  Future<void> setFilter(String layerId, dynamic filter) async {
    _map.setFilter(layerId, filter);
  }

  @override
  Future<void> addGeoJsonSource(String sourceId, Map<String, dynamic> geojson,
      {String? promoteId}) async {
    final data = _makeFeatureCollection(geojson);
    _addedFeaturesByLayer[sourceId] = data;
    _map.addSource(sourceId, {
      "type": 'geojson',
      "data": geojson, // pass the raw string here to avoid errors
      if (promoteId != null) "promoteId": promoteId
    });
  }

  Feature _makeFeature(Map<String, dynamic> geojsonFeature) {
    return Feature(
        geometry: Geometry(
            type: geojsonFeature["geometry"]["type"],
            coordinates: geojsonFeature["geometry"]["coordinates"]),
        properties: geojsonFeature["properties"],
        id: geojsonFeature["properties"]?["id"] ?? geojsonFeature["id"]);
  }

  FeatureCollection _makeFeatureCollection(Map<String, dynamic> geojson) {
    return FeatureCollection(
        features: [for (final f in geojson["features"] ?? []) _makeFeature(f)]);
  }

  @override
  Future<void> setGeoJsonSource(
      String sourceId, Map<String, dynamic> geojson) async {
    final source = _map.getSource(sourceId) as GeoJsonSource;
    final data = _makeFeatureCollection(geojson);
    _addedFeaturesByLayer[sourceId] = data;
    source.setData(data);
  }

  @override
  Future setCameraBounds({
    required double west,
    required double north,
    required double south,
    required double east,
    required int padding,
  }) async {
    _map.fitBounds(LngLatBounds(LngLat(west, south), LngLat(east, north)),
        {'padding': padding});
  }

  @override
  Future<void> addFillExtrusionLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    return _addLayer(sourceId, layerId, properties, "fill-extrusion",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        filter: filter,
        enableInteraction: enableInteraction);
  }

  @override
  Future<void> addCircleLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    return _addLayer(sourceId, layerId, properties, "circle",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        filter: filter,
        enableInteraction: enableInteraction);
  }

  @override
  Future<void> addFillLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    return _addLayer(sourceId, layerId, properties, "fill",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        filter: filter,
        enableInteraction: enableInteraction);
  }

  @override
  Future<void> addLineLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    return _addLayer(sourceId, layerId, properties, "line",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        filter: filter,
        enableInteraction: enableInteraction);
  }

  @override
  Future<void> setLayerProperties(
      String layerId, Map<String, dynamic> properties) async {
    for (final entry in properties.entries) {
      // Very hacky: because we don't know if the property is a layout
      // or paint property, we try to set it as both.
      try {
        _map.setLayoutProperty(layerId, entry.key, entry.value);
      } catch (e) {
        print('Caught exception (usually safe to ignore): $e');
      }
      try {
        _map.setPaintProperty(layerId, entry.key, entry.value);
      } catch (e) {
        print('Caught exception (usually safe to ignore): $e');
      }
    }
  }

  @override
  Future<void> addSymbolLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    return _addLayer(sourceId, layerId, properties, "symbol",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        filter: filter,
        enableInteraction: enableInteraction);
  }

  @override
  Future<void> addHillshadeLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom}) async {
    return _addLayer(sourceId, layerId, properties, "hillshade",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false);
  }

  @override
  Future<void> addHeatmapLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom}) async {
    return _addLayer(sourceId, layerId, properties, "heatmap",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false);
  }

  @override
  Future<void> addRasterLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom}) async {
    await _addLayer(sourceId, layerId, properties, "raster",
        belowLayerId: belowLayerId,
        sourceLayer: sourceLayer,
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false);
  }

  Future<void> _addLayer(String sourceId, String layerId,
      Map<String, dynamic> properties, String layerType,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    if (_layerExists(layerId)) {
      if (enableInteraction) _registerInteractiveLayer(layerId, layerType);
      return;
    }
    final layout = Map.fromEntries(
        properties.entries.where((entry) => isLayoutProperty(entry.key)));
    final paint = Map.fromEntries(
        properties.entries.where((entry) => !isLayoutProperty(entry.key)));

    _map.addLayer({
      'id': layerId,
      'type': layerType,
      'source': sourceId,
      'layout': layout,
      'paint': paint,
      if (sourceLayer != null) 'source-layer': sourceLayer,
      if (minzoom != null) 'minzoom': minzoom,
      if (maxzoom != null) 'maxzoom': maxzoom,
      if (filter != null) 'filter': filter,
    }, belowLayerId);

    if (enableInteraction) {
      _registerInteractiveLayer(layerId, layerType, force: true);
    }
  }

  void _registerInteractiveLayer(
    String layerId,
    String layerType, {
    bool force = false,
  }) {
    if (!force && !_interactiveFeatureLayerIds.add(layerId)) return;
    _interactiveFeatureLayerIds.add(layerId);
    if (layerType == "fill") {
      _map.on('mousemove', layerId, _onMouseEnterFeature);
    } else {
      _map.on('mouseenter', layerId, _onMouseEnterFeature);
    }
    _map.on('mouseleave', layerId, _onMouseLeaveFeature);
    if (_dragEnabled) _map.on('mousedown', layerId, _onMouseDown);
  }

  void _onMouseEnterFeature(_) {
    if (_draggedFeatureId == null) {
      _map.getCanvas().style.cursor = 'pointer';
    }
  }

  void _onMouseLeaveFeature(_) {
    _map.getCanvas().style.cursor = '';
  }

  @override
  void setGestures(
      {required bool rotateGesturesEnabled,
      required bool scrollGesturesEnabled,
      required bool tiltGesturesEnabled,
      required bool zoomGesturesEnabled,
      required bool doubleClickZoomEnabled}) {
    if (rotateGesturesEnabled &&
        scrollGesturesEnabled &&
        tiltGesturesEnabled &&
        zoomGesturesEnabled) {
      _map.keyboard.enable();
    } else {
      _map.keyboard.disable();
    }

    if (scrollGesturesEnabled) {
      _map.dragPan.enable();
    } else {
      _map.dragPan.disable();
    }

    if (zoomGesturesEnabled) {
      _map.doubleClickZoom.enable();
      _map.boxZoom.enable();
      _map.scrollZoom.enable();
      _map.touchZoomRotate.enable();
    } else {
      _map.doubleClickZoom.disable();
      _map.boxZoom.disable();
      _map.scrollZoom.disable();
      _map.touchZoomRotate.disable();
    }

    if (doubleClickZoomEnabled) {
      _map.doubleClickZoom.enable();
    } else {
      _map.doubleClickZoom.disable();
    }

    if (rotateGesturesEnabled) {
      _map.touchZoomRotate.enableRotation();
    } else {
      _map.touchZoomRotate.disableRotation();
    }

    // dragRotate is shared by both gestures
    if (tiltGesturesEnabled && rotateGesturesEnabled) {
      _map.dragRotate.enable();
    } else {
      _map.dragRotate.disable();
    }
  }

  @override
  Future<void> addSource(String sourceId, SourceProperties properties) async {
    _map.addSource(sourceId, properties.toJson());
  }

  @override
  Future<void> addImageSource(
      String imageSourceId, Uint8List bytes, LatLngQuad coordinates) {
    // TODO: implement addImageSource
    throw UnimplementedError();
  }

  @override
  Future<void> updateImageSource(
      String imageSourceId, Uint8List? bytes, LatLngQuad? coordinates) {
    // TODO: implement updateImageSource
    throw UnimplementedError();
  }

  @override
  Future<void> addLayer(String imageLayerId, String imageSourceId,
      double? minzoom, double? maxzoom) {
    // TODO: implement addLayer
    throw UnimplementedError();
  }

  @override
  Future<void> addLayerBelow(String imageLayerId, String imageSourceId,
      String belowLayerId, double? minzoom, double? maxzoom) {
    // TODO: implement addLayerBelow
    throw UnimplementedError();
  }

  @override
  Future<void> updateContentInsets(EdgeInsets insets, bool animated) {
    // TODO: implement updateContentInsets
    throw UnimplementedError();
  }

  @override
  Future<void> setFeatureForGeoJsonSource(
      String sourceId, Map<String, dynamic> geojsonFeature) async {
    final source = _map.getSource(sourceId) as GeoJsonSource?;
    final data = _addedFeaturesByLayer[sourceId];

    if (source != null && data != null) {
      final feature = _makeFeature(geojsonFeature);
      final features = data.features.toList();
      final index = features.indexWhere((f) => f.id == feature.id);
      if (index >= 0) {
        features[index] = feature;
        final newData = FeatureCollection(features: features);
        _addedFeaturesByLayer[sourceId] = newData;

        source.setData(newData);
      }
    }
  }

  @override
  void resizeWebMap() {
    _onMapResize();
  }

  @override
  void forceResizeWebMap() {
    _map.resize();
  }

  @override
  Future<void> setLayerVisibility(String layerId, bool visible) async {
    _map.setLayoutProperty(layerId, 'visibility', visible ? 'visible' : 'none');
  }

  @override
  Future getFilter(String layerId) async {
    return _map.getFilter(layerId);
  }

  @override
  Future<List> getLayerIds() async {
    return _map.getLayers().map((e) => e.id).toList();
  }

  @override
  Future<List> getSourceIds() async {
    throw UnimplementedError();
  }

  // ?? Stub implementations for methods added to the platform interface ??

  @override
  Future<void> createPillLabel({
    required String name,
    required String text,
    String backgroundColor = '#0066FF',
    String textColor = '#FFFFFF',
    double textSize = 14.0,
    double paddingHorizontal = 12.0,
    double paddingVertical = 6.0,
    double cornerRadius = 8.0,
  }) async {
    // Not supported on web
  }

  @override
  Future<void> createCircleLabel({
    required String name,
    required String text,
    double radius = 40.0,
    String circleColor = '#0066FF',
    double circleStrokeWidth = 2.0,
    String textColor = '#FFFFFF',
    double textSize = 16.0,
    bool topArc = true,
    bool roundedEdges = true,
  }) async {
    // Not supported on web
  }

  @override
  Future<void> addTriangleLayer(
      String sourceId, String layerId, Map<String, dynamic> properties,
      {String? belowLayerId,
      String? sourceLayer,
      double? minzoom,
      double? maxzoom,
      dynamic filter,
      required bool enableInteraction}) async {
    // Not supported on web
  }

  @override
  Future<void> addRotatableSymbolLayers(
      String sourceId, String baseLayerId, Map<String, dynamic> properties,
      {String? belowLayerId, required bool enableInteraction}) async {
    // Not supported on web
  }

  @override
  Future<void> addRotatableSymbolPngLayers({
    required String sourceId,
    required String baseLayerId,
    String? belowLayerId,
    required String aircraftIconPath,
    required String arrowIconPath,
    required double aircraftIconSize,
    required double arrowIconSize,
    required bool enableInteraction,
    required Map<String, dynamic> config,
  }) async {
    // Not supported on web
  }

  @override
  Future<void> addImageOverlayControls(
      String overlayId, List<List<double>> coordinates, bool editMode) async {
    // Not supported on web
  }

  @override
  Future<void> updateImageOverlayControls(
      String overlayId, List<List<double>> coordinates, bool editMode) async {
    // Not supported on web
  }

  @override
  Future<void> removeImageOverlayControls(String overlayId) async {
    // Not supported on web
  }

  @override
  Future<void> handleImageOverlayGesture(String overlayId, String gestureType,
      double screenX, double screenY, double deltaX, double deltaY) async {
    // Not supported on web
  }

  @override
  Future<void> setImageOverlayControlsSensitivity(
      String overlayId, double sensitivity) async {
    // Not supported on web
  }

  @override
  Future<void> enableNativeMeasurement(bool enabled) async {
    _webMeasurementEnabled = enabled;
    _clearWebMeasurementPendingClick();
    if (enabled) {
      _ensureWebMeasurementLayers();
      _renderWebMeasurement();
    } else {
      _webMeasurementDragRole = null;
      _map.dragPan.enable();
      _map.getCanvas().style.cursor = '';
    }
  }

  @override
  Future<void> setNativeMeasurementStyle({
    required String lineColor,
    required double lineWidth,
    required double lineOpacity,
    required String endpointColor,
    required double endpointRadius,
  }) async {
    _webMeasurementLineColor = lineColor;
    _webMeasurementLineWidth = lineWidth;
    _webMeasurementLineOpacity = lineOpacity;
    _webMeasurementEndpointColor = endpointColor;
    _webMeasurementEndpointRadius = endpointRadius;
    _applyWebMeasurementLayerStyles();
    _renderWebMeasurement();
  }

  @override
  Future<void> clearNativeMeasurement() async {
    _webMeasurementDragRole = null;
    _clearWebMeasurementPendingClick();
    _webMeasurementStart = null;
    _webMeasurementEnd = null;
    _webMeasurementStartedAt = null;
    _renderWebMeasurement();
  }

  @override
  Future<void> ensureMeasurementLayersOnTop() async {
    _ensureWebMeasurementLayers();
    _ensureWebPluginOverlayLayerOrder();
  }

  @override
  Future<void> enableLineEditing(String lineId, bool enabled,
      [List<LatLng>? coordinates]) async {
    final existing = _webEditableLines[lineId];
    if (enabled) {
      final nextCoordinates = coordinates ?? existing?.coordinates;
      if (nextCoordinates == null || nextCoordinates.length < 2) {
        onPolylineEditingErrorPlatform({
          'lineId': lineId,
          'error': 'Polyline editing requires at least two coordinates.',
        });
        return;
      }
      _webEditableLines[lineId] = _WebEditableLine(
        lineId: lineId,
        enabled: true,
        coordinates: List<LatLng>.from(nextCoordinates),
      );
      _ensureWebLineEditingLayers();
    } else if (existing != null) {
      existing.enabled = false;
      if (_webLineEditDrag?.lineId == lineId) {
        _webLineEditDrag = null;
      }
    }
    _renderWebLineEditingHandles();
  }

  @override
  Future<void> setLineEditingStyle(Map<String, dynamic> style) async {
    _webLineEditingStyle = {
      ..._webLineEditingStyle,
      ...style,
    };
    _applyWebLineEditingLayerStyles();
    _renderWebLineEditingHandles();
  }

  @override
  Future<bool> isLineEditable(String lineId) async {
    return _webEditableLines[lineId]?.enabled ?? false;
  }

  bool _handleWebMeasurementCoordinate(LatLng coordinate) {
    if (!_webMeasurementEnabled) return false;
    if (_webMeasurementStart == null) {
      _webMeasurementStart = coordinate;
      _webMeasurementEnd = null;
      _webMeasurementStartedAt = DateTime.now();
      _renderWebMeasurement();
      return true;
    }

    if (_webMeasurementEnd == null) {
      _webMeasurementEnd = coordinate;
      _emitWebMeasurement(onNativeMeasurementStart);
      _renderWebMeasurement();
      _emitWebMeasurement(onNativeMeasurementEnd);
      return true;
    }

    clearNativeMeasurement();
    return true;
  }

  void _clearWebMeasurementPendingClick() {
    _webMeasurementPendingClickPoint = null;
    _webMeasurementPendingClickCoordinate = null;
    _webMeasurementPendingClickMoved = false;
  }

  bool _tryStartWebMeasurementDragAt(Point<double> point) {
    if (!_webMeasurementEnabled || _webMeasurementEnd == null) return false;
    final role = _webMeasurementHandleAt(point);
    if (role == null) return false;
    _clearWebMeasurementPendingClick();
    _webMeasurementDragRole = role;
    _suppressNextMapClick = true;
    _map.dragPan.disable();
    _map.getCanvas().style.cursor = 'grabbing';
    return true;
  }

  void _updateWebMeasurementDragAt(LatLng coordinate) {
    final role = _webMeasurementDragRole;
    if (role == null) return;
    if (role == 'start') {
      _webMeasurementStart = coordinate;
    } else {
      _webMeasurementEnd = coordinate;
    }
    _renderWebMeasurement();
    _emitWebMeasurement(onNativeMeasurementUpdate);
  }

  void _finishWebMeasurementDragAt(LatLng coordinate) {
    _updateWebMeasurementDragAt(coordinate);
    _webMeasurementDragRole = null;
    _map.dragPan.enable();
    _map.getCanvas().style.cursor = '';
    _emitWebMeasurement(onNativeMeasurementEnd);
  }

  String? _webMeasurementHandleAt(Point<double> point) {
    final start = _webMeasurementStart;
    final end = _webMeasurementEnd;
    if (start == null || end == null) return null;
    final radius = max(_webMeasurementEndpointRadius + 14.0, 24.0);
    final startDistance = _pointDistance(point, _projectLatLng(start));
    final endDistance = _pointDistance(point, _projectLatLng(end));
    if (startDistance <= radius && startDistance <= endDistance) {
      return 'start';
    }
    if (endDistance <= radius) return 'end';
    return null;
  }

  void _ensureWebMeasurementLayers() {
    if (!_map.isStyleLoaded()) return;
    _ensureGeoJsonSource(_webMeasurementSourceId);
    _ensureLayer(
      _webMeasurementLineCasingLayerId,
      _webMeasurementSourceId,
      'line',
      {
        'line-color': '#111827',
        'line-width': _webMeasurementLineWidth + 4,
        'line-opacity': 0.72,
        'line-cap': 'round',
        'line-join': 'round',
        'line-sort-key': 10,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'line'
      ],
    );
    _ensureLayer(
      _webMeasurementLineLayerId,
      _webMeasurementSourceId,
      'line',
      {
        'line-color': _webMeasurementLineColor,
        'line-width': _webMeasurementLineWidth,
        'line-opacity': _webMeasurementLineOpacity,
        'line-cap': 'round',
        'line-join': 'round',
        'line-sort-key': 11,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'line'
      ],
    );
    _ensureLayer(
      _webMeasurementEndpointLayerId,
      _webMeasurementSourceId,
      'circle',
      {
        'circle-radius': _webMeasurementEndpointRadius,
        'circle-color': _webMeasurementEndpointColor,
        'circle-stroke-color': _webMeasurementLineColor,
        'circle-stroke-width': 3.0,
        'circle-sort-key': 12,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'endpoint'
      ],
    );
    _ensureLayer(
      _webMeasurementDistanceLayerId,
      _webMeasurementSourceId,
      'symbol',
      {
        'text-field': ['get', 'label'],
        'text-size': 15.0,
        'text-font': ['Noto Sans Bold'],
        'text-color': '#FFFFFF',
        'text-halo-color': '#111827',
        'text-halo-width': 3.2,
        'text-halo-blur': 0.0,
        'text-anchor': 'center',
        'text-allow-overlap': true,
        'text-ignore-placement': true,
        'symbol-sort-key': 13,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'distance'
      ],
    );
    _ensureLayer(
      _webMeasurementBearingLayerId,
      _webMeasurementSourceId,
      'symbol',
      {
        'text-field': ['get', 'label'],
        'text-size': 16.0,
        'text-font': ['Noto Sans Bold'],
        'text-color': '#FFFFFF',
        'text-halo-color': '#111827',
        'text-halo-width': 3.2,
        'text-halo-blur': 0.0,
        'text-anchor': 'center',
        'text-rotation-alignment': 'viewport',
        'text-rotate': ['get', 'textAngle'],
        'text-allow-overlap': true,
        'text-ignore-placement': true,
        'symbol-sort-key': 14,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'bearing'
      ],
    );
    _ensureWebPluginOverlayLayerOrder();
  }

  void _applyWebMeasurementLayerStyles() {
    if (!_map.isStyleLoaded()) return;
    try {
      if (_layerExists(_webMeasurementLineCasingLayerId)) {
        _map.setPaintProperty(
          _webMeasurementLineCasingLayerId,
          'line-width',
          _webMeasurementLineWidth + 4,
        );
      }
      if (_layerExists(_webMeasurementLineLayerId)) {
        _map.setPaintProperty(
          _webMeasurementLineLayerId,
          'line-color',
          _webMeasurementLineColor,
        );
        _map.setPaintProperty(
          _webMeasurementLineLayerId,
          'line-width',
          _webMeasurementLineWidth,
        );
        _map.setPaintProperty(
          _webMeasurementLineLayerId,
          'line-opacity',
          _webMeasurementLineOpacity,
        );
      }
      if (_layerExists(_webMeasurementEndpointLayerId)) {
        _map.setPaintProperty(
          _webMeasurementEndpointLayerId,
          'circle-radius',
          _webMeasurementEndpointRadius,
        );
        _map.setPaintProperty(
          _webMeasurementEndpointLayerId,
          'circle-color',
          _webMeasurementEndpointColor,
        );
        _map.setPaintProperty(
          _webMeasurementEndpointLayerId,
          'circle-stroke-color',
          _webMeasurementLineColor,
        );
      }
    } catch (_) {}
  }

  void _renderWebMeasurement() {
    if (!_map.isStyleLoaded() || !_sourceExists(_webMeasurementSourceId)) {
      return;
    }
    final start = _webMeasurementStart;
    final end = _webMeasurementEnd;
    final features = <Map<String, dynamic>>[];
    if (start != null) {
      features.add(_pointFeature(
        id: 'measure-start',
        coordinate: start,
        properties: {
          'featureType': 'endpoint',
          'role': 'start',
          'sortKey': 12,
        },
      ));
    }
    if (start != null && end != null) {
      final distanceNm = _distanceNm(start, end);
      final bearing = _bearingDegrees(start, end);
      final reciprocal = _normalizeDegrees(bearing + 180);
      final labelAngle = _uprightScreenAngle(start, end);
      final midpoint = _screenOffsetCoordinate(start, end, 0.5, 0);
      final startBearingPoint = _screenOffsetCoordinate(start, end, 0.16, -28);
      final endBearingPoint = _screenOffsetCoordinate(start, end, 0.84, 28);
      features.add({
        'type': 'Feature',
        'id': 'measure-line',
        'properties': {
          'featureType': 'line',
          'sortKey': 10,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [start.longitude, start.latitude],
            [end.longitude, end.latitude],
          ],
        },
      });
      features.add(_pointFeature(
        id: 'measure-end',
        coordinate: end,
        properties: {
          'featureType': 'endpoint',
          'role': 'end',
          'sortKey': 12,
        },
      ));
      features.add(_pointFeature(
        id: 'measure-distance',
        coordinate: midpoint,
        properties: {
          'featureType': 'distance',
          'label': '${_formatDistanceNm(distanceNm)} NM',
          'sortKey': 13,
        },
      ));
      features.add(_pointFeature(
        id: 'measure-bearing-start',
        coordinate: startBearingPoint,
        properties: {
          'featureType': 'bearing',
          'label': '${bearing.round()}°',
          'textAngle': labelAngle,
          'sortKey': 14,
        },
      ));
      features.add(_pointFeature(
        id: 'measure-bearing-end',
        coordinate: endBearingPoint,
        properties: {
          'featureType': 'bearing',
          'label': '${reciprocal.round()}°',
          'textAngle': labelAngle,
          'sortKey': 14,
        },
      ));
    }
    _setGeoJsonSourceData(_webMeasurementSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
    _ensureWebPluginOverlayLayerOrder();
  }

  void _emitWebMeasurement(
    ArgumentCallbacks<Map<String, dynamic>> callbacks,
  ) {
    final start = _webMeasurementStart;
    final end = _webMeasurementEnd;
    if (start == null || end == null) return;
    final startPoint = _map.project(LngLat(start.longitude, start.latitude));
    final endPoint = _map.project(LngLat(end.longitude, end.latitude));
    final startedAt = _webMeasurementStartedAt ?? DateTime.now();
    callbacks({
      'x1': startPoint.x.toDouble(),
      'y1': startPoint.y.toDouble(),
      'x2': endPoint.x.toDouble(),
      'y2': endPoint.y.toDouble(),
      'lat1': start.latitude,
      'lng1': start.longitude,
      'lat2': end.latitude,
      'lng2': end.longitude,
      'distance': _distanceNm(start, end),
      'bearing': _bearingDegrees(start, end),
      'duration': DateTime.now().difference(startedAt).inMilliseconds,
    });
  }

  bool _tryStartWebLineEditDragAt(Point<double> point) {
    if (_webMeasurementEnabled || _webLineEditDrag != null) return false;
    if (!_webEditableLines.values.any((line) => line.enabled)) return false;

    final handle = _nearestWebLineHandle(point);
    if (handle != null) {
      _webLineEditDrag = handle;
      _suppressNextMapClick = true;
      _map.dragPan.disable();
      _map.getCanvas().style.cursor = 'grabbing';
      return true;
    }

    final segment = _nearestWebLineSegment(point);
    if (segment == null || segment.distance > 18.0) return false;

    final line = _webEditableLines[segment.lineId];
    if (line == null) return false;
    final coordinate = _unprojectPoint(segment.projectedPoint);
    line.coordinates.insert(segment.insertIndex, coordinate);
    _webLineEditDrag = _WebLineEditDrag(
      lineId: segment.lineId,
      pointIndex: segment.insertIndex,
      inserted: true,
    );
    _suppressNextMapClick = true;
    _map.dragPan.disable();
    _map.getCanvas().style.cursor = 'grabbing';
    _renderWebLineEditingHandles();
    _emitWebLineModified(line);
    return true;
  }

  void _updateWebLineEditDragAt(LatLng coordinate) {
    final drag = _webLineEditDrag;
    if (drag == null) return;
    final line = _webEditableLines[drag.lineId];
    if (line == null ||
        drag.pointIndex <= 0 ||
        drag.pointIndex >= line.coordinates.length - 1) {
      return;
    }
    line.coordinates[drag.pointIndex] = coordinate;
    _renderWebLineEditingHandles();
    _emitWebLineModified(line);
  }

  void _finishWebLineEditDragAt(LatLng coordinate) {
    _updateWebLineEditDragAt(coordinate);
    final drag = _webLineEditDrag;
    if (drag != null) {
      final line = _webEditableLines[drag.lineId];
      if (line != null) _emitWebLineModified(line);
    }
    _webLineEditDrag = null;
    _map.dragPan.enable();
    _map.getCanvas().style.cursor = '';
  }

  _WebLineEditDrag? _nearestWebLineHandle(Point<double> point) {
    final radius = _styleDouble('breakPointRadius', 12.0) + 10.0;
    _WebLineEditDrag? nearest;
    var nearestDistance = double.infinity;
    for (final line in _webEditableLines.values.where((line) => line.enabled)) {
      for (var i = 1; i < line.coordinates.length - 1; i++) {
        final projected = _projectLatLng(line.coordinates[i]);
        final distance = _pointDistance(point, projected);
        if (distance <= radius && distance < nearestDistance) {
          nearestDistance = distance;
          nearest = _WebLineEditDrag(lineId: line.lineId, pointIndex: i);
        }
      }
    }
    return nearest;
  }

  _WebLineSegmentHit? _nearestWebLineSegment(Point<double> point) {
    _WebLineSegmentHit? nearest;
    for (final line in _webEditableLines.values.where((line) => line.enabled)) {
      for (var i = 0; i < line.coordinates.length - 1; i++) {
        final a = _projectLatLng(line.coordinates[i]);
        final b = _projectLatLng(line.coordinates[i + 1]);
        final projected = _nearestPointOnSegment(point, a, b);
        final distance = _pointDistance(point, projected);
        if (nearest == null || distance < nearest.distance) {
          nearest = _WebLineSegmentHit(
            lineId: line.lineId,
            insertIndex: i + 1,
            projectedPoint: projected,
            distance: distance,
          );
        }
      }
    }
    return nearest;
  }

  void _ensureWebLineEditingLayers() {
    if (!_map.isStyleLoaded()) return;
    _ensureGeoJsonSource(_webLineEditingSourceId);
    _ensureLayer(
      _webLineEditingPreviewCasingLayerId,
      _webLineEditingSourceId,
      'line',
      {
        'line-color': '#111827',
        'line-width': _styleDouble('previewLineWidth', 4.0) + 4.0,
        'line-opacity': min(_styleDouble('previewLineOpacity', 0.82) + 0.12, 1),
        'line-cap': 'round',
        'line-join': 'round',
        'line-sort-key': 18,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'editable-line'
      ],
    );
    _ensureLayer(
      _webLineEditingPreviewLayerId,
      _webLineEditingSourceId,
      'line',
      {
        'line-color': _styleString('previewLineColor', '#FFC857'),
        'line-width': _styleDouble('previewLineWidth', 4.0),
        'line-opacity': _styleDouble('previewLineOpacity', 0.82),
        'line-cap': 'round',
        'line-join': 'round',
        'line-sort-key': 19,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'editable-line'
      ],
    );
    _ensureLayer(
      _webLineEditingCasingLayerId,
      _webLineEditingSourceId,
      'circle',
      {
        'circle-radius': _styleDouble('breakPointRadius', 12.0) +
            _styleDouble('breakPointBorderWidth', 2.0),
        'circle-color': _styleString('breakPointBorderColor', '#FFFFFF'),
        'circle-sort-key': 20,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'breakpoint'
      ],
    );
    _ensureLayer(
      _webLineEditingPointLayerId,
      _webLineEditingSourceId,
      'circle',
      {
        'circle-radius': _styleDouble('breakPointRadius', 12.0),
        'circle-color': _styleString('breakPointColor', '#FFC857'),
        'circle-sort-key': 21,
      },
      filter: const [
        '==',
        ['get', 'featureType'],
        'breakpoint'
      ],
    );
    _ensureWebPluginOverlayLayerOrder();
  }

  void _applyWebLineEditingLayerStyles() {
    if (!_map.isStyleLoaded()) return;
    try {
      if (_layerExists(_webLineEditingPreviewCasingLayerId)) {
        _map.setPaintProperty(
          _webLineEditingPreviewCasingLayerId,
          'line-width',
          _styleDouble('previewLineWidth', 4.0) + 4.0,
        );
        _map.setPaintProperty(
          _webLineEditingPreviewCasingLayerId,
          'line-opacity',
          min(_styleDouble('previewLineOpacity', 0.82) + 0.12, 1),
        );
      }
      if (_layerExists(_webLineEditingPreviewLayerId)) {
        _map.setPaintProperty(
          _webLineEditingPreviewLayerId,
          'line-color',
          _styleString('previewLineColor', '#FFC857'),
        );
        _map.setPaintProperty(
          _webLineEditingPreviewLayerId,
          'line-width',
          _styleDouble('previewLineWidth', 4.0),
        );
        _map.setPaintProperty(
          _webLineEditingPreviewLayerId,
          'line-opacity',
          _styleDouble('previewLineOpacity', 0.82),
        );
      }
      if (_layerExists(_webLineEditingCasingLayerId)) {
        _map.setPaintProperty(
          _webLineEditingCasingLayerId,
          'circle-radius',
          _styleDouble('breakPointRadius', 12.0) +
              _styleDouble('breakPointBorderWidth', 2.0),
        );
        _map.setPaintProperty(
          _webLineEditingCasingLayerId,
          'circle-color',
          _styleString('breakPointBorderColor', '#FFFFFF'),
        );
      }
      if (_layerExists(_webLineEditingPointLayerId)) {
        _map.setPaintProperty(
          _webLineEditingPointLayerId,
          'circle-radius',
          _styleDouble('breakPointRadius', 12.0),
        );
        _map.setPaintProperty(
          _webLineEditingPointLayerId,
          'circle-color',
          _styleString('breakPointColor', '#FFC857'),
        );
      }
    } catch (_) {}
    _ensureWebPluginOverlayLayerOrder();
  }

  void _renderWebLineEditingHandles() {
    if (!_map.isStyleLoaded() || !_sourceExists(_webLineEditingSourceId)) {
      return;
    }
    final features = <Map<String, dynamic>>[];
    for (final line in _webEditableLines.values.where((line) => line.enabled)) {
      if (line.coordinates.length >= 2) {
        features.add({
          'type': 'Feature',
          'id': '${line.lineId}-editable-line',
          'properties': {
            'featureType': 'editable-line',
            'lineId': line.lineId,
            'sortKey': 19,
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final coordinate in line.coordinates)
                [coordinate.longitude, coordinate.latitude],
            ],
          },
        });
      }
      for (var i = 1; i < line.coordinates.length - 1; i++) {
        features.add(_pointFeature(
          id: '${line.lineId}-$i',
          coordinate: line.coordinates[i],
          properties: {
            'featureType': 'breakpoint',
            'lineId': line.lineId,
            'pointIndex': i,
            'sortKey': 21,
          },
        ));
      }
    }
    _setGeoJsonSourceData(_webLineEditingSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
    _ensureWebPluginOverlayLayerOrder();
  }

  void _emitWebLineModified(_WebEditableLine line) {
    onPolylineModifiedPlatform({
      'lineId': line.lineId,
      'coordinates': [
        for (final coordinate in line.coordinates)
          [coordinate.latitude, coordinate.longitude],
      ],
    });
  }

  void _ensureGeoJsonSource(String sourceId) {
    if (_sourceExists(sourceId)) return;
    try {
      _map.addSource(sourceId, {
        'type': 'geojson',
        'data': _emptyFeatureCollection(),
      });
      _addedFeaturesByLayer[sourceId] =
          _makeFeatureCollection(_emptyFeatureCollection());
    } catch (_) {}
  }

  void _ensureLayer(
    String layerId,
    String sourceId,
    String layerType,
    Map<String, dynamic> properties, {
    dynamic filter,
  }) {
    if (_layerExists(layerId)) return;
    try {
      _addLayer(
        sourceId,
        layerId,
        properties,
        layerType,
        filter: filter,
        enableInteraction: false,
      );
    } catch (_) {}
  }

  void _ensureWebPluginOverlayLayerOrder() {
    _moveLayersToTop(_webLineEditingLayerIds);
    _moveLayersToTop(_webMeasurementLayerIds);
  }

  void _moveLayersToTop(List<String> layerIds) {
    for (final layerId in layerIds) {
      if (!_layerExists(layerId)) continue;
      try {
        _map.style.moveLayer(layerId);
      } catch (_) {}
    }
  }

  bool _layerExists(String layerId) {
    try {
      return _map.getLayer(layerId) != null;
    } catch (_) {
      return false;
    }
  }

  bool _sourceExists(String sourceId) {
    try {
      return _map.getSource(sourceId) != null;
    } catch (_) {
      return false;
    }
  }

  void _setGeoJsonSourceData(String sourceId, Map<String, dynamic> geojson) {
    try {
      final data = _makeFeatureCollection(geojson);
      _addedFeaturesByLayer[sourceId] = data;
      final source = _map.getSource(sourceId) as GeoJsonSource?;
      source?.setData(data);
    } catch (_) {}
  }

  Map<String, dynamic> _emptyFeatureCollection() => {
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[],
      };

  Map<String, dynamic> _pointFeature({
    required String id,
    required LatLng coordinate,
    required Map<String, dynamic> properties,
  }) {
    return {
      'type': 'Feature',
      'id': id,
      'properties': properties,
      'geometry': {
        'type': 'Point',
        'coordinates': [coordinate.longitude, coordinate.latitude],
      },
    };
  }

  Point<double> _projectLatLng(LatLng coordinate) {
    final point = _map.project(
      LngLat(coordinate.longitude, coordinate.latitude),
    );
    return Point<double>(point.x.toDouble(), point.y.toDouble());
  }

  Point<double>? _mapPointFromMouseEvent(html.MouseEvent event) {
    final canvas = _map.getCanvas();
    if (canvas is! html.Element) return null;
    final bounds = canvas.getBoundingClientRect();
    return Point<double>(
      event.client.x.toDouble() - bounds.left.toDouble(),
      event.client.y.toDouble() - bounds.top.toDouble(),
    );
  }

  LatLng _unprojectPoint(Point<double> point) {
    final lngLat = _map.unproject(geo_point.Point(point.x, point.y));
    return LatLng(lngLat.lat.toDouble(), lngLat.lng.toDouble());
  }

  LatLng _screenOffsetCoordinate(
    LatLng start,
    LatLng end,
    double t,
    double perpendicularPx,
  ) {
    final a = _projectLatLng(start);
    final b = _projectLatLng(end);
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = max(sqrt(dx * dx + dy * dy), 1.0);
    final nx = -dy / length;
    final ny = dx / length;
    final point = Point<double>(
      a.x + dx * t + nx * perpendicularPx,
      a.y + dy * t + ny * perpendicularPx,
    );
    return _unprojectPoint(point);
  }

  double _uprightScreenAngle(LatLng start, LatLng end) {
    final a = _projectLatLng(start);
    final b = _projectLatLng(end);
    var angle = atan2(b.y - a.y, b.x - a.x) * 180 / pi;
    if (angle > 90) angle -= 180;
    if (angle < -90) angle += 180;
    return angle;
  }

  Point<double> _nearestPointOnSegment(
    Point<double> p,
    Point<double> a,
    Point<double> b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return a;
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    return Point<double>(a.x + dx * t, a.y + dy * t);
  }

  double _pointDistance(Point<double> a, Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  double _distanceNm(LatLng start, LatLng end) {
    const earthRadiusMeters = 6371008.8;
    final lat1 = start.latitude * pi / 180;
    final lat2 = end.latitude * pi / 180;
    final dLat = (end.latitude - start.latitude) * pi / 180;
    final dLng = (end.longitude - start.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c / 1852.0;
  }

  double _bearingDegrees(LatLng start, LatLng end) {
    final lat1 = start.latitude * pi / 180;
    final lat2 = end.latitude * pi / 180;
    final dLng = (end.longitude - start.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return _normalizeDegrees(atan2(y, x) * 180 / pi);
  }

  double _normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  String _formatDistanceNm(double distanceNm) {
    if (distanceNm < 10) return distanceNm.toStringAsFixed(1);
    if (distanceNm < 100) return distanceNm.toStringAsFixed(0);
    return distanceNm.round().toString();
  }

  double _styleDouble(String key, double fallback) {
    final value = _webLineEditingStyle[key];
    if (value is num) return value.toDouble();
    return fallback;
  }

  String _styleString(String key, String fallback) {
    final value = _webLineEditingStyle[key];
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }
}

class _WebEditableLine {
  _WebEditableLine({
    required this.lineId,
    required this.enabled,
    required this.coordinates,
  });

  final String lineId;
  bool enabled;
  final List<LatLng> coordinates;
}

class _WebLineEditDrag {
  const _WebLineEditDrag({
    required this.lineId,
    required this.pointIndex,
    this.inserted = false,
  });

  final String lineId;
  final int pointIndex;
  final bool inserted;
}

class _WebLineSegmentHit {
  const _WebLineSegmentHit({
    required this.lineId,
    required this.insertIndex,
    required this.projectedPoint,
    required this.distance,
  });

  final String lineId;
  final int insertIndex;
  final Point<double> projectedPoint;
  final double distance;
}
