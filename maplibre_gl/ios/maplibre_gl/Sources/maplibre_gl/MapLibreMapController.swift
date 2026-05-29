import Flutter
import MapLibre

class MapLibreMapController: NSObject, FlutterPlatformView, MLNMapViewDelegate, MapLibreMapOptionsSink,
    UIGestureRecognizerDelegate
{
    // Feature flags for experimental features
    private static let enableExperimentalTriangleLayers = ProcessInfo.processInfo.environment["MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS"] == "true"
    
    private var registrar: FlutterPluginRegistrar
    private var channel: FlutterMethodChannel?

    private var mapView: MLNMapView
    private var isMapReady = false
    private var dragEnabled = true
    private var isFirstStyleLoad = true
    private var onStyleLoadedCalled = false
    private var mapReadyResult: FlutterResult?
    private var previousDragCoordinate: CLLocationCoordinate2D?
    private var originDragCoordinate: CLLocationCoordinate2D?
    private var dragFeature: MLNFeature?

    private var initialTilt: CGFloat?
    private var cameraTargetBounds: MLNCoordinateBounds?
    private var trackCameraPosition = false
    private var myLocationEnabled = false
    private var scrollingEnabled = true

    private var interactiveFeatureLayerIds = Set<String>()
    private var addedShapesByLayer = [String: MLNShape]()
    
    // Polyline editing components
    private var polylineEditingManager: PolylineEditingManager?
    private var polylineBreakPointSystem: PolylineBreakPointSystem?
    private var polylineRenderer: EditablePolylineRenderer?
    private var polylineGestureHandler: PolylineGestureHandler?

    func view() -> UIView {
        return mapView
    }

    init(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        registrar: FlutterPluginRegistrar
    ) {
        mapView = MLNMapView(frame: frame)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.logoView.isHidden = true
        self.registrar = registrar

        super.init()

        channel = FlutterMethodChannel(
            name: "plugins.flutter.io/maplibre_gl_\(viewId)",
            binaryMessenger: registrar.messenger()
        )
        channel!
            .setMethodCallHandler { [weak self] in self?.onMethodCall(methodCall: $0, result: $1) }

        mapView.delegate = self

        let singleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleMapTap(sender:))
        )
        for recognizer in mapView.gestureRecognizers! where recognizer is UITapGestureRecognizer {
            singleTap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(singleTap)

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleMapLongPress(sender:))
        )
        for recognizer in mapView.gestureRecognizers!
            where recognizer is UILongPressGestureRecognizer
        {
            longPress.require(toFail: recognizer)
        }
        var longPressRecognizerAdded = false

        if let args = args as? [String: Any] {

            Convert.interpretMapLibreMapOptions(options: args["options"], delegate: self)
            if let initialCameraPosition = args["initialCameraPosition"] as? [String: Any],
               let camera = MLNMapCamera.fromDict(initialCameraPosition, mapView: mapView),
               let zoom = initialCameraPosition["zoom"] as? Double
            {
                mapView.setCenter(
                    camera.centerCoordinate,
                    zoomLevel: zoom,
                    direction: camera.heading,
                    animated: false
                )
                initialTilt = camera.pitch
            }
            // if let onAttributionClickOverride = args["onAttributionClickOverride"] as? Bool {
            //     if onAttributionClickOverride {
            //         setupAttribution(mapView)
            //     }
            // }

            if let enabled = args["dragEnabled"] as? Bool {
                dragEnabled = enabled
            }

            if let iosLongClickDurationMilliseconds = args["iosLongClickDurationMilliseconds"] as? Int {
                longPress.minimumPressDuration = TimeInterval(iosLongClickDurationMilliseconds) / 1000
                mapView.addGestureRecognizer(longPress)
                longPressRecognizerAdded = true
            }
        }
        if dragEnabled {
            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleMapPan(sender:))
            )
            pan.delegate = self
            mapView.addGestureRecognizer(pan)
        }

        if(!longPressRecognizerAdded) {
            mapView.addGestureRecognizer(longPress)
            longPressRecognizerAdded = true
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    func onMethodCall(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        switch methodCall.method {
        case "map#waitForMap":
            if isMapReady {
                result(nil)
                // only call map#onStyleLoaded here if isMapReady has happend and isFirstStyleLoad is true
                if isFirstStyleLoad {
                    isFirstStyleLoad = false
                    if let channel = channel {
                        onStyleLoadedCalled = true
                        channel.invokeMethod("map#onStyleLoaded", arguments: nil)
                    }
                }
            } else {
                mapReadyResult = result
            }
        case "map#update":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            Convert.interpretMapLibreMapOptions(options: arguments["options"], delegate: self)
            if let camera = getCamera() {
                result(camera.toDict(mapView: mapView))
            } else {
                result(nil)
            }
        case "map#invalidateAmbientCache":
            MLNOfflineStorage.shared.invalidateAmbientCache {
                error in
                if let error = error {
                    result(error)
                } else {
                    result(nil)
                }
            }
        case "map#clearAmbientCache":
            MLNOfflineStorage.shared.clearAmbientCache {
                error in
                if let error = error {
                    result(error)
                } else {
                    result(nil)
                }
            }
        case "map#updateMyLocationTrackingMode":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            if let myLocationTrackingMode = arguments["mode"] as? UInt,
               let trackingMode = MLNUserTrackingMode(rawValue: myLocationTrackingMode)
            {
                setMyLocationTrackingMode(myLocationTrackingMode: trackingMode)
            }
            result(nil)
        case "map#matchMapLanguageWithDeviceDefault":
            if let langStr = Locale.current.languageCode {
                setMapLanguage(language: langStr)
            }

            result(nil)
        case "map#updateContentInsets":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }

            if let bounds = arguments["bounds"] as? [String: Any],
               let top = bounds["top"] as? CGFloat,
               let left = bounds["left"] as? CGFloat,
               let bottom = bounds["bottom"] as? CGFloat,
               let right = bounds["right"] as? CGFloat,
               let animated = arguments["animated"] as? Bool
            {
                mapView.setContentInset(
                    UIEdgeInsets(top: top, left: left, bottom: bottom, right: right),
                    animated: animated
                ) {
                    result(nil)
                }
            } else {
                result(nil)
            }
        case "locationComponent#getLastLocation":
            var reply = [String: NSObject]()
            if let loc = mapView.userLocation?.location?.coordinate {
                reply["latitude"] = loc.latitude as NSObject
                reply["longitude"] = loc.longitude as NSObject
                result(reply)
            } else {
                result(nil)
            }
        case "map#setMapLanguage":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            if let localIdentifier = arguments["language"] as? String {
                setMapLanguage(language: localIdentifier)
            }
            result(nil)
        case "map#queryRenderedFeatures":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            var styleLayerIdentifiers: Set<String>?
            if let layerIds = arguments["layerIds"] as? [String] {
                styleLayerIdentifiers = Set<String>(layerIds)
            }
            var filterExpression: NSPredicate?
            if let filter = arguments["filter"] as? [Any] {
                filterExpression = NSPredicate(mglJSONObject: filter)
            }
            var reply = [String: NSObject]()
            var features: [MLNFeature] = []
            if let x = arguments["x"] as? Double, let y = arguments["y"] as? Double {
                features = mapView.visibleFeatures(
                    at: CGPoint(x: x, y: y),
                    styleLayerIdentifiers: styleLayerIdentifiers,
                    predicate: filterExpression
                )
            }
            if let top = arguments["top"] as? Double,
               let bottom = arguments["bottom"] as? Double,
               let left = arguments["left"] as? Double,
               let right = arguments["right"] as? Double
            {
                var width = right - left
                var height = bottom - top
                features = mapView.visibleFeatures(in: CGRect(x: left, y: top, width: width, height: height), styleLayerIdentifiers: styleLayerIdentifiers, predicate: filterExpression)
            }
            var featuresJson = [String]()
            for feature in features {
                let dictionary = feature.geoJSONDictionary()
                if let theJSONData = try? JSONSerialization.data(
                    withJSONObject: dictionary,
                    options: []
                ),
                    let theJSONText = String(data: theJSONData, encoding: .utf8)
                {
                    featuresJson.append(theJSONText)
                }
            }
            reply["features"] = featuresJson as NSObject
            result(reply)
        case "map#setTelemetryEnabled":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            let telemetryEnabled = arguments["enabled"] as? Bool
            UserDefaults.standard.set(telemetryEnabled, forKey: "MLNMapboxMetricsEnabled")
            result(nil)
        case "map#getTelemetryEnabled":
            let telemetryEnabled = UserDefaults.standard.bool(forKey: "MLNMapboxMetricsEnabled")
            result(telemetryEnabled)
        case "map#getVisibleRegion":
            var reply = [String: NSObject]()
            let visibleRegion = mapView.visibleCoordinateBounds
            reply["sw"] = [visibleRegion.sw.latitude, visibleRegion.sw.longitude] as NSObject
            reply["ne"] = [visibleRegion.ne.latitude, visibleRegion.ne.longitude] as NSObject
            result(reply)
        case "map#toScreenLocation":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let latitude = arguments["latitude"] as? Double else { return }
            guard let longitude = arguments["longitude"] as? Double else { return }
            let latlng = CLLocationCoordinate2DMake(latitude, longitude)
            let returnVal = mapView.convert(latlng, toPointTo: mapView)
            var reply = [String: NSObject]()
            reply["x"] = returnVal.x as NSObject
            reply["y"] = returnVal.y as NSObject
            result(reply)
        case "map#toScreenLocationBatch":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let data = arguments["coordinates"] as? FlutterStandardTypedData else { return }
            let latLngs = data.data.withUnsafeBytes {
                Array(
                    UnsafeBufferPointer(
                        start: $0.baseAddress!.assumingMemoryBound(to: Double.self),
                        count: Int(data.elementCount)
                    )
                )
            }
            var reply: [Double] = Array(repeating: 0.0, count: latLngs.count)
            for i in stride(from: 0, to: latLngs.count, by: 2) {
                let coordinate = CLLocationCoordinate2DMake(latLngs[i], latLngs[i + 1])
                let returnVal = mapView.convert(coordinate, toPointTo: mapView)
                reply[i] = Double(returnVal.x)
                reply[i + 1] = Double(returnVal.y)
            }
            result(FlutterStandardTypedData(
                float64: Data(bytes: &reply, count: reply.count * 8)
            ))
        case "map#getMetersPerPixelAtLatitude":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            var reply = [String: NSObject]()
            guard let latitude = arguments["latitude"] as? Double else { return }
            let returnVal = mapView.metersPerPoint(atLatitude: latitude)
            reply["metersperpixel"] = returnVal as NSObject
            result(reply)
        case "map#toLatLng":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let x = arguments["x"] as? Double else { return }
            guard let y = arguments["y"] as? Double else { return }
            let screenPoint = CGPoint(x: x, y: y)
            let coordinates: CLLocationCoordinate2D = mapView.convert(
                screenPoint,
                toCoordinateFrom: mapView
            )
            var reply = [String: NSObject]()
            reply["latitude"] = coordinates.latitude as NSObject
            reply["longitude"] = coordinates.longitude as NSObject
            result(reply)
        case "camera#move":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let cameraUpdate = arguments["cameraUpdate"] as? [Any] else { return }

            if let camera = Convert.parseCameraUpdate(cameraUpdate: cameraUpdate, mapView: mapView) {
                mapView.setCamera(camera, animated: false)
            }
            result(nil)
        case "camera#animate":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let cameraUpdate = arguments["cameraUpdate"] as? [Any] else { return }
            guard let camera = Convert.parseCameraUpdate(cameraUpdate: cameraUpdate, mapView: mapView) else { return }


            let completion = {
                result(nil)
            }

            if let duration = arguments["duration"] as? TimeInterval {
                if let padding = Convert.parseLatLngBoundsPadding(cameraUpdate) {
                    mapView.fly(to: camera, edgePadding: padding, withDuration: duration / 1000, completionHandler: completion)
                } else {
                    mapView.fly(to: camera, withDuration: duration / 1000, completionHandler: completion)
                }
            } else {
                mapView.setCamera(camera, animated: true)
                completion()
            }
        case "symbolLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String

            let addResult = addSymbolLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "lineLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String

            let addResult = addLineLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "layer#setProperties":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }

            guard let layer = mapView.style?.layer(withIdentifier: layerId) else {
                result(FlutterError(
                    code: "LAYER_NOT_FOUND_ERROR",
                    message: "Layer " + layerId + "not found",
                    details: ""
                ))
                return
            }

            //switch depending on the runtime type of layer
            switch layer {
            case let lineLayer as MLNLineStyleLayer:
                LayerPropertyConverter.addLineProperties(lineLayer: lineLayer, properties: properties)
            case let fillLayer as MLNFillStyleLayer:
                LayerPropertyConverter.addFillProperties(fillLayer: fillLayer, properties: properties)
            case let circleLayer as MLNCircleStyleLayer:
                LayerPropertyConverter.addCircleProperties(circleLayer: circleLayer, properties: properties)
             case let symbolLayer as MLNSymbolStyleLayer:
                LayerPropertyConverter.addSymbolProperties(symbolLayer: symbolLayer, properties: properties)
            case let rasterLayer as MLNRasterStyleLayer:
                LayerPropertyConverter.addRasterProperties(rasterLayer: rasterLayer, properties: properties)
            case let hillshadeLayer as MLNHillshadeStyleLayer:
                LayerPropertyConverter.addHillshadeProperties(hillshadeLayer: hillshadeLayer, properties: properties)
            default:
                result(FlutterError(
                    code: "UNSUPPORTED_LAYER_TYPE",
                    message: "Layer type not supported",
                    details: ""
                ))
                return
            }

            result(nil)

        case "fillLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String

            let addResult = addFillLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "fillExtrusionLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String

            let addResult = addFillExtrusionLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "circleLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String

            let addResult = addCircleLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "triangleLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let sourceLayer = arguments["sourceLayer"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let filter = arguments["filter"] as? String
        
            let addResult = addTriangleLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                sourceLayerIdentifier: sourceLayer,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                filter: filter,
                enableInteraction: enableInteraction,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "rotatableSymbolLayers#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let baseLayerId = arguments["baseLayerId"] as? String else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            guard let properties = arguments["properties"] as? [String: Any] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            
            let addResult = addRotatableSymbolLayers(
                sourceId: sourceId,
                baseLayerId: baseLayerId,
                belowLayerId: belowLayerId,
                properties: properties,
                enableInteraction: enableInteraction
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "rotatableSymbolPngLayers#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let baseLayerId = arguments["baseLayerId"] as? String else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            guard let properties = arguments["properties"] as? [String: Any] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            
            let addResult = addRotatableSymbolPngLayers(
                sourceId: sourceId,
                baseLayerId: baseLayerId,
                belowLayerId: belowLayerId,
                properties: properties,
                enableInteraction: enableInteraction
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "map#addRotatableSymbolPngLayers":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let baseLayerId = arguments["baseLayerId"] as? String else { return }
            guard let aircraftIconPath = arguments["aircraftIconPath"] as? String else { return }
            guard let arrowIconPath = arguments["arrowIconPath"] as? String else { return }
            guard let aircraftIconSize = arguments["aircraftIconSize"] as? Double else { return }
            guard let arrowIconSize = arguments["arrowIconSize"] as? Double else { return }
            guard let enableInteraction = arguments["enableInteraction"] as? Bool else { return }
            guard let config = arguments["config"] as? [String: Any] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            
            // Build properties dictionary to match the existing implementation
            var properties: [String: Any] = [
                "config": [
                    "aircraftIconPath": aircraftIconPath,
                    "arrowIconPath": arrowIconPath,
                    "aircraftIconSize": aircraftIconSize,
                    "arrowIconSize": arrowIconSize,
                    "topLabelOffset": config["topLabelOffset"] ?? -2.5,
                    "bottomLabelOffset": config["bottomLabelOffset"] ?? 2.5,
                    "arrowOffsetX": config["arrowOffsetX"] ?? 20.0
                ]
            ]
            
            let addResult = addRotatableSymbolPngLayers(
                sourceId: sourceId,
                baseLayerId: baseLayerId,
                belowLayerId: belowLayerId,
                properties: properties,
                enableInteraction: enableInteraction
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "hillshadeLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double

            let addResult = addHillshadeLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                properties: properties
            )
          
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "heatmapLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let addResult = addHeatmapLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "rasterLayer#add":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: String] else { return }
            let belowLayerId = arguments["belowLayerId"] as? String
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double
            let addResult = addRasterLayer(
                sourceId: sourceId,
                layerId: layerId,
                belowLayerId: belowLayerId,
                minimumZoomLevel: minzoom,
                maximumZoomLevel: maxzoom,
                properties: properties
            )
            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "style#addImage":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let name = arguments["name"] as? String else { return }
            // guard let length = arguments["length"] as? NSNumber else { return }
            guard let bytes = arguments["bytes"] as? FlutterStandardTypedData else { return }
            guard let sdf = arguments["sdf"] as? Bool else { return }
            guard let data = bytes.data as? Data else { return }
            guard let image = UIImage(data: data, scale: UIScreen.main.scale) else { return }
            if sdf {
                mapView.style?.setImage(image.withRenderingMode(.alwaysTemplate), forName: name)
            } else {
                mapView.style?.setImage(image, forName: name)
            }
            result(nil)

        case "style#createPillLabel":
            guard let arguments = methodCall.arguments as? [String: Any] else { 
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return 
            }
            guard let name = arguments["name"] as? String else {
                result(FlutterError(code: "MISSING_NAME", message: "Name is required", details: nil))
                return
            }
            guard let text = arguments["text"] as? String else {
                result(FlutterError(code: "MISSING_TEXT", message: "Text is required", details: nil))
                return
            }
            guard let backgroundColorHex = arguments["backgroundColor"] as? String else {
                result(FlutterError(code: "MISSING_BG_COLOR", message: "Background color is required", details: nil))
                return
            }
            guard let textColorHex = arguments["textColor"] as? String else {
                result(FlutterError(code: "MISSING_TEXT_COLOR", message: "Text color is required", details: nil))
                return
            }
            let textSize = arguments["textSize"] as? Double ?? 24.0
            let padding = arguments["padding"] as? Double ?? 12.0
            let cornerRadius = arguments["cornerRadius"] as? Double ?? 15.0
            
            // Convert hex colors to UIColor
            let backgroundColor = hexToUIColor(hex: backgroundColorHex)
            let textColor = hexToUIColor(hex: textColorHex)
            
            // Create the pill label image
            guard let image = createPillLabelImage(
                text: text,
                textSize: CGFloat(textSize),
                textColor: textColor,
                backgroundColor: backgroundColor,
                padding: CGFloat(padding),
                cornerRadius: CGFloat(cornerRadius)
            ) else {
                result(FlutterError(code: "IMAGE_CREATION_FAILED", message: "Failed to create pill label image", details: nil))
                return
            }
            
            // Add to map style
            mapView.style?.setImage(image, forName: name)
            result(nil)

        case "style#createCircleLabel":
            guard let arguments = methodCall.arguments as? [String: Any] else { 
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return 
            }
            guard let name = arguments["name"] as? String else {
                result(FlutterError(code: "MISSING_NAME", message: "Name is required", details: nil))
                return
            }
            guard let text = arguments["text"] as? String else {
                result(FlutterError(code: "MISSING_TEXT", message: "Text is required", details: nil))
                return
            }
            guard let radius = arguments["radius"] as? Double else {
                result(FlutterError(code: "MISSING_RADIUS", message: "Radius is required", details: nil))
                return
            }
            guard let circleColorHex = arguments["circleColor"] as? String else {
                result(FlutterError(code: "MISSING_CIRCLE_COLOR", message: "Circle color is required", details: nil))
                return
            }
            guard let textColorHex = arguments["textColor"] as? String else {
                result(FlutterError(code: "MISSING_TEXT_COLOR", message: "Text color is required", details: nil))
                return
            }
            let strokeWidth = arguments["strokeWidth"] as? Double ?? 4.0
            let textSize = arguments["textSize"] as? Double ?? 24.0
            let topArc = arguments["topArc"] as? Bool ?? true
            let roundedEdges = arguments["roundedEdges"] as? Bool ?? true
            
            // Convert hex colors to UIColor
            let circleColor = hexToUIColor(hex: circleColorHex)
            let textColor = hexToUIColor(hex: textColorHex)
            
            // Create the circular label image
            guard let image = createCircleLabelImage(
                text: text,
                radius: CGFloat(radius),
                textSize: CGFloat(textSize),
                textColor: textColor,
                circleColor: circleColor,
                strokeWidth: CGFloat(strokeWidth),
                topArc: topArc,
                roundedEdges: roundedEdges
            ) else {
                result(FlutterError(code: "IMAGE_CREATION_FAILED", message: "Failed to create circle label image", details: nil))
                return
            }
            
            // Add to map style
            mapView.style?.setImage(image, forName: name)
            result(nil)

        case "style#addImageSource":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let imageSourceId = arguments["imageSourceId"] as? String else { return }
            guard let bytes = arguments["bytes"] as? FlutterStandardTypedData else { return }
            guard let data = bytes.data as? Data else { return }
            guard let image = UIImage(data: data) else { return }

            guard let coordinates = arguments["coordinates"] as? [[Double]] else { return }
            let quad = MLNCoordinateQuad(
                topLeft: CLLocationCoordinate2D(
                    latitude: coordinates[0][0],
                    longitude: coordinates[0][1]
                ),
                bottomLeft: CLLocationCoordinate2D(
                    latitude: coordinates[3][0],
                    longitude: coordinates[3][1]
                ),
                bottomRight: CLLocationCoordinate2D(
                    latitude: coordinates[2][0],
                    longitude: coordinates[2][1]
                ),
                topRight: CLLocationCoordinate2D(
                    latitude: coordinates[1][0],
                    longitude: coordinates[1][1]
                )
            )

            // Check for duplicateSource error
            if mapView.style?.source(withIdentifier: imageSourceId) != nil {
                result(FlutterError(
                    code: "duplicateSource",
                    message: "Source with imageSourceId \(imageSourceId) already exists",
                    details: "Can't add duplicate source with imageSourceId: \(imageSourceId)"
                ))
                return
            }

            let source = MLNImageSource(
                identifier: imageSourceId,
                coordinateQuad: quad,
                image: image
            )
            mapView.style?.addSource(source)

            result(nil)
        case "style#updateImageSource":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let imageSourceId = arguments["imageSourceId"] as? String else { return }
            guard let imageSource = mapView.style?
                .source(withIdentifier: imageSourceId) as? MLNImageSource else { return }
            let bytes = arguments["bytes"] as? FlutterStandardTypedData
            if bytes != nil {
                guard let data = bytes!.data as? Data else { return }
                guard let image = UIImage(data: data) else { return }
                imageSource.image = image
            }
            let coordinates = arguments["coordinates"] as? [[Double]]
            if coordinates != nil {
                let quad = MLNCoordinateQuad(
                    topLeft: CLLocationCoordinate2D(
                        latitude: coordinates![0][0],
                        longitude: coordinates![0][1]
                    ),
                    bottomLeft: CLLocationCoordinate2D(
                        latitude: coordinates![3][0],
                        longitude: coordinates![3][1]
                    ),
                    bottomRight: CLLocationCoordinate2D(
                        latitude: coordinates![2][0],
                        longitude: coordinates![2][1]
                    ),
                    topRight: CLLocationCoordinate2D(
                        latitude: coordinates![1][0],
                        longitude: coordinates![1][1]
                    )
                )
                imageSource.coordinates = quad
            }
            result(nil)
        case "style#removeSource":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let source = mapView.style?.source(withIdentifier: sourceId) else {
                result(nil)
                return
            }
            mapView.style?.removeSource(source)
            result(nil)
        case "style#addLayer":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let imageLayerId = arguments["imageLayerId"] as? String else { return }
            guard let imageSourceId = arguments["imageSourceId"] as? String else { return }
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double

            // Check for duplicateLayer error
            if (mapView.style?.layer(withIdentifier: imageLayerId)) != nil {
                result(FlutterError(
                    code: "duplicateLayer",
                    message: "Layer already exists",
                    details: "Can't add duplicate layer with imageLayerId: \(imageLayerId)"
                ))
                return
            }
            // Check for noSuchSource error
            guard let source = mapView.style?.source(withIdentifier: imageSourceId) else {
                result(FlutterError(
                    code: "noSuchSource",
                    message: "No source found with imageSourceId \(imageSourceId)",
                    details: "Can't add add layer for imageSourceId \(imageLayerId), as the source does not exist."
                ))
                return
            }

            let layer = MLNRasterStyleLayer(identifier: imageLayerId, source: source)

            if let minzoom = minzoom {
                layer.minimumZoomLevel = Float(minzoom)
            }

            if let maxzoom = maxzoom {
                layer.maximumZoomLevel = Float(maxzoom)
            }

            mapView.style?.addLayer(layer)
        case "style#addLayerBelow":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let imageLayerId = arguments["imageLayerId"] as? String else { return }
            guard let imageSourceId = arguments["imageSourceId"] as? String else { return }
            guard let belowLayerId = arguments["belowLayerId"] as? String else { return }
            let minzoom = arguments["minzoom"] as? Double
            let maxzoom = arguments["maxzoom"] as? Double

            // Check for duplicateLayer error
            if (mapView.style?.layer(withIdentifier: imageLayerId)) != nil {
                result(FlutterError(
                    code: "duplicateLayer",
                    message: "Layer already exists",
                    details: "Can't add duplicate layer with imageLayerId: \(imageLayerId)"
                ))
                return
            }
            // Check for noSuchSource error
            guard let source = mapView.style?.source(withIdentifier: imageSourceId) else {
                result(FlutterError(
                    code: "noSuchSource",
                    message: "No source found with imageSourceId \(imageSourceId)",
                    details: "Can't add add layer for imageSourceId \(imageLayerId), as the source does not exist."
                ))
                return
            }
            // Check for noSuchLayer error
            guard let belowLayer = mapView.style?.layer(withIdentifier: belowLayerId) else {
                result(FlutterError(
                    code: "noSuchLayer",
                    message: "No layer found with layerId \(belowLayerId)",
                    details: "Can't insert layer below layer with id \(belowLayerId), as no such layer exists."
                ))
                return
            }

            let layer = MLNRasterStyleLayer(identifier: imageLayerId, source: source)

            if let minzoom = minzoom {
                layer.minimumZoomLevel = Float(minzoom)
            }

            if let maxzoom = maxzoom {
                layer.maximumZoomLevel = Float(maxzoom)
            }
            mapView.style?.insertLayer(layer, below: belowLayer)
            result(nil)

        case "style#removeLayer":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let layer = mapView.style?.layer(withIdentifier: layerId) else {
                result(MethodCallError.layerNotFound(
                   layerId: layerId
                ).flutterError)
                return
            }
            interactiveFeatureLayerIds.remove(layerId)
            mapView.style?.removeLayer(layer)
            result(nil)

        case "map#setCameraBounds":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let west = arguments["west"] as? Double else { return }
            guard let north = arguments["north"] as? Double else { return }
            guard let south = arguments["south"] as? Double else { return }
            guard let east = arguments["east"] as? Double else { return }
            guard let padding = arguments["padding"] as? CGFloat else { return }

            let southwest = CLLocationCoordinate2D(latitude: south, longitude: west)
            let northeast = CLLocationCoordinate2D(latitude: north, longitude: east)
            let bounds = MLNCoordinateBounds(sw: southwest, ne: northeast)
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: padding,
                left: padding, bottom: padding, right: padding) , animated: true)
            result(nil)

        case "style#setFilter":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let filter = arguments["filter"] as? String else { return }
            guard let layer = mapView.style?.layer(withIdentifier: layerId) else {
                result(MethodCallError.layerNotFound(
                   layerId: layerId
                ).flutterError)
                return
            }
            switch setFilter(layer, filter) {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "source#addGeoJson":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let geojson = arguments["geojson"] as? String else { return }
            let addResult = addSourceGeojson(sourceId: sourceId, geojson: geojson)

            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "style#addSource":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let properties = arguments["properties"] as? [String: Any] else { return }
            let addResult = addSource(sourceId: sourceId, properties: properties)

            switch addResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "source#setGeoJson":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let geojson = arguments["geojson"] as? String else { return }
            let setResult = setSource(sourceId: sourceId, geojson: geojson)

            switch setResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "source#setFeature":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }
            guard let geojson = arguments["geojsonFeature"] as? String else { return }
            let setResult = setFeature(sourceId: sourceId, geojsonFeature: geojson)

            switch setResult {
            case .success: result(nil)
            case let .failure(error): result(error.flutterError)
            }

        case "layer#setVisibility":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let layerId = arguments["layerId"] as? String else { return }
            guard let visible = arguments["visible"] as? Bool else { return }
            guard let layer = mapView.style?.layer(withIdentifier: layerId) else {
                result(MethodCallError.layerNotFound(
                   layerId: layerId
                ).flutterError)
                return
            }
            layer.isVisible = visible
            result(nil)

        case "map#querySourceFeatures":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let sourceId = arguments["sourceId"] as? String else { return }

            var sourceLayerId = Set<String>()
            if let layerId = arguments["sourceLayerId"] as? String {
                sourceLayerId.insert(layerId)
            }
            var filterExpression: NSPredicate?
            if let filter = arguments["filter"] as? [Any] {
                filterExpression = NSPredicate(mglJSONObject: filter)
            }

            var reply = [String: NSObject]()
            var features: [MLNFeature] = []

            guard let style = mapView.style else { return }
            if let source = style.source(withIdentifier: sourceId) {
                if let vectorSource = source as? MLNVectorTileSource {
                    features = vectorSource.features(sourceLayerIdentifiers: sourceLayerId, predicate: filterExpression)
                } else if let shapeSource = source as? MLNShapeSource {
                    features = shapeSource.features(matching: filterExpression)
                }
            }

            var featuresJson = [String]()
            for feature in features {
                let dictionary = feature.geoJSONDictionary()
                if let theJSONData = try? JSONSerialization.data(
                    withJSONObject: dictionary,
                    options: []
                ),
                    let theJSONText = String(data: theJSONData, encoding: .utf8)
                {
                    featuresJson.append(theJSONText)
                }
            }
            reply["features"] = featuresJson as NSObject
            result(reply)

        case "style#getLayerIds":
            var layerIds = [String]()

            guard let style = mapView.style else { return }

            style.layers.forEach { layer in layerIds.append(layer.identifier) }

            var reply = [String: NSObject]()
            reply["layers"] = layerIds as NSObject
            result(reply)

        case "style#getSourceIds":
            var sourceIds = [String]()

            guard let style = mapView.style else { return }

            style.sources.forEach { source in sourceIds.append(source.identifier) }

            var reply = [String: NSObject]()
            reply["sources"] = sourceIds as NSObject
            result(reply)

        case "style#getFilter":
            guard let arguments = methodCall.arguments as? [String: Any] else { return }
            guard let layerId = arguments["layerId"] as? String else { return }

            guard let style = mapView.style else { return }
            guard let layer = style.layer(withIdentifier: layerId) else { return }

            var currentLayerFilter : String = ""
            if let vectorLayer = layer as? MLNVectorStyleLayer {
                if let layerFilter = vectorLayer.predicate {

                    let jsonExpression = layerFilter.mgl_jsonExpressionObject
                    if let data = try? JSONSerialization.data(withJSONObject: jsonExpression, options: []) {
                        currentLayerFilter = String(data: data, encoding: String.Encoding.utf8) ?? ""
                    }
                }
            } else {
                result(MethodCallError.invalidLayerType(
                    details: "Layer '\(layer.identifier)' does not support filtering."
                ).flutterError)
                return;
            }

            var reply = [String: NSObject]()
            reply["filter"] = currentLayerFilter as NSObject
            result(reply)
            
        case "map#enableNativeMeasurement",
             "map#setNativeMeasurementStyle",
             "map#clearNativeMeasurement",
             "map#ensureMeasurementLayersOnTop":
            result(nil)

        case "line#enableEditing", "line#setEditingStyle", "line#isEditable":
            handlePolylineEditingMethodCall(methodCall: methodCall, result: result)
            
        

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func loadIconImage(name: String) -> UIImage? {
        // Build up the full path of the asset.
        // First find the last '/' ans split the image name in the asset directory and the image file name.
        if let range = name.range(of: "/", options: [.backwards]) {
            let directory = String(name[..<range.lowerBound])
            let assetPath = registrar.lookupKey(forAsset: "\(directory)/")
            let fileName = String(name[range.upperBound...])
            // If we can load the image from file then add it to the map.
            return UIImage.loadFromFile(
                imagePath: assetPath,
                imageName: fileName
            )
        }
        return nil
    }

    private func addIconImageToMap(iconImageName: String) {
        // Check if the image has already been added to the map.
        if mapView.style?.image(forName: iconImageName) == nil {
            if let imageFromAsset = loadIconImage(name: iconImageName) {
                mapView.style?.setImage(imageFromAsset, forName: iconImageName)
            }
        }
    }

    private func updateMyLocationEnabled() {
        mapView.showsUserLocation = myLocationEnabled
    }

    private func getCamera() -> MLNMapCamera? {
        return trackCameraPosition ? mapView.camera : nil
    }

    private func setMapLanguage(language: String) {
        self.mapView.setMapLanguage(language)
    }

    /*
     *  Scan layers from top to bottom and return the first matching feature
     */
    private func firstFeatureOnLayers(at: CGPoint) -> (feature: MLNFeature?, layerId: String?) {
        guard let style = mapView.style else { return (nil, nil) }

        // get layers in order (interactiveFeatureLayerIds is unordered)
        let clickableLayers = style.layers.filter { layer in
            interactiveFeatureLayerIds.contains(layer.identifier)
        }

        for layer in clickableLayers.reversed() {
            let features = mapView.visibleFeatures(
                at: at,
                styleLayerIdentifiers: [layer.identifier]
            )
            if let feature = features.first {
                return (feature, layer.identifier)
            }
        }
        return (nil, nil)
    }

    /*
     *  UITapGestureRecognizer
     *  On tap invoke the map#onMapClick callback.
     */
    @IBAction func handleMapTap(sender: UITapGestureRecognizer) {
        // Get the CGPoint where the user tapped.
        let point = sender.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

        let result = firstFeatureOnLayers(at: point)
        if let feature = result.feature {
            channel?.invokeMethod("feature#onTap", arguments: [
                        "id": feature.identifier,
                        "x": point.x,
                        "y": point.y,
                        "lng": coordinate.longitude,
                        "lat": coordinate.latitude,
                        "layerId": result.layerId,
            ])
        } else {
            channel?.invokeMethod("map#onMapClick", arguments: [
                "x": point.x,
                "y": point.y,
                "lng": coordinate.longitude,
                "lat": coordinate.latitude,
            ])
        }
    }

    fileprivate func invokeFeatureDrag(
        _ point: CGPoint,
        _ coordinate: CLLocationCoordinate2D,
        _ eventType: String
    ) {
        if let feature = dragFeature,
           let id = feature.identifier,
           let previous = previousDragCoordinate,
           let origin = originDragCoordinate
        {
            channel?.invokeMethod("feature#onDrag", arguments: [
                "id": id,
                "x": point.x,
                "y": point.y,
                "originLng": origin.longitude,
                "originLat": origin.latitude,
                "currentLng": coordinate.longitude,
                "currentLat": coordinate.latitude,
                "eventType": eventType,
                "deltaLng": coordinate.longitude - previous.longitude,
                "deltaLat": coordinate.latitude - previous.latitude,
            ])
        }
    }

    @IBAction func handleMapPan(sender: UIPanGestureRecognizer) {
        let began = sender.state == UIGestureRecognizer.State.began
        let end = sender.state == UIGestureRecognizer.State.ended
        let point = sender.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

        if dragFeature == nil, began, sender.numberOfTouches == 1 {
            let result = firstFeatureOnLayers(at: point)
            if let feature = result.feature,
            let draggable = feature.attribute(forKey: "draggable") as? Bool,
            draggable {
                sender.state = UIGestureRecognizer.State.began
                dragFeature = feature
                originDragCoordinate = coordinate
                previousDragCoordinate = coordinate
                mapView.allowsScrolling = false
                let eventType = "start"
                invokeFeatureDrag(point, coordinate, eventType)
                for gestureRecognizer in mapView.gestureRecognizers! {
                    if let _ = gestureRecognizer as? UIPanGestureRecognizer {
                        gestureRecognizer.addTarget(self, action: #selector(handleMapPan))
                        break
                    }
                }
            }
        }
        if end, dragFeature != nil {
            mapView.allowsScrolling = true
            let eventType = "end"
            invokeFeatureDrag(point, coordinate, eventType)
            dragFeature = nil
            originDragCoordinate = nil
            previousDragCoordinate = nil
        }

        if !began, !end, dragFeature != nil {
            let eventType = "drag"
            invokeFeatureDrag(point, coordinate, eventType)
            previousDragCoordinate = coordinate
        }
    }

    /*
     *  UILongPressGestureRecognizer
     *  After a long press invoke the map#onMapLongClick callback.
     */
    @IBAction func handleMapLongPress(sender: UILongPressGestureRecognizer) {
        // Fire when the long press starts
        if sender.state == .began {
            // Get the CGPoint where the user tapped.
            let point = sender.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            channel?.invokeMethod("map#onMapLongClick", arguments: [
                "x": point.x,
                "y": point.y,
                "lng": coordinate.longitude,
                "lat": coordinate.latitude,
            ])
        }
    }

    /* /*
     * Override the attribution button's click target to handle the event locally.
     * Called if the application supplies an onAttributionClick handler.
     */
    func setupAttribution(_ mapView: MLNMapView) {
        mapView.attributionButton.removeTarget(
            mapView,
            action: #selector(mapView.showAttribution),
            for: .touchUpInside
        )
        mapView.attributionButton.addTarget(
            self,
            action: #selector(showAttribution),
            for: UIControl.Event.touchUpInside
        )
    }

    /*
     * Custom click handler for the attribution button. This callback is bound when
     * the application specifies an onAttributionClick handler.
     */
    @objc func showAttribution() {
        channel?.invokeMethod("map#onAttributionClick", arguments: [])
    } */

    /*
     *  MLNMapViewDelegate
     */
    func mapView(_ mapView: MLNMapView, didFinishLoading _: MLNStyle) {
        isMapReady = true
        updateMyLocationEnabled()

        if let initialTilt = initialTilt {
            let camera = mapView.camera
            camera.pitch = initialTilt
            mapView.setCamera(camera, animated: false)
        }

        addedShapesByLayer.removeAll()
        interactiveFeatureLayerIds.removeAll()
        
        // Initialize polyline editing components
        initializePolylineEditing()

        mapReadyResult?(nil)

        // On first launch we only call map#onStyleLoaded if map#waitForMap has already been called
        if !isFirstStyleLoad || mapReadyResult != nil {
            isFirstStyleLoad = false



            if let channel = channel {
                channel.invokeMethod("map#onStyleLoaded", arguments: nil)
            }
        }
    }

    // handle missing images
    func mapView(_: MLNMapView, didFailToLoadImage name: String) -> UIImage? {
        return loadIconImage(name: name)
    }

    func mapView(_: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        if let channel = channel, let userLocation = userLocation,
           let location = userLocation.location
        {
            channel.invokeMethod("map#onUserLocationUpdated", arguments: [
                "userLocation": location.toDict(),
                "heading": userLocation.heading?.toDict(),
            ])
        }
    }

    func mapView(_: MLNMapView, didChange mode: MLNUserTrackingMode, animated _: Bool) {
        if let channel = channel {
            channel.invokeMethod("map#onCameraTrackingChanged", arguments: ["mode": mode.rawValue])
            if mode == .none {
                channel.invokeMethod("map#onCameraTrackingDismissed", arguments: [])
            }
        }
    }
    
    private func validateBeforeLayerAdd(
        sourceId: String,
        layerId: String
    ) -> Result<(MLNStyle, MLNSource), MethodCallError> {
        guard let style = mapView.style else {
            return .failure(.styleNotFound)
        }
        guard let source = style.source(withIdentifier: sourceId) else {
            return .failure(.sourceNotFound(sourceId: sourceId))
        }
        guard style.layer(withIdentifier: layerId) == nil else {
            return .failure(.layerAlreadyExists(layerId: layerId))
        }
        return .success((style, source))
    }


    func addSymbolLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNSymbolStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addSymbolProperties(
                symbolLayer: layer,
                properties: properties
            )
            if let sourceLayerIdentifier = sourceLayerIdentifier {
                layer.sourceLayerIdentifier = sourceLayerIdentifier
            }
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let filter = filter {
                if case let .failure(error) = setFilter(layer, filter) {
                    return .failure(error)
                }
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            if enableInteraction {
                interactiveFeatureLayerIds.insert(layerId)
            }
            return .success(())
        }
    }

    func addLineLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNLineStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addLineProperties(lineLayer: layer, properties: properties)
            if let sourceLayerIdentifier = sourceLayerIdentifier {
                layer.sourceLayerIdentifier = sourceLayerIdentifier
            }
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let filter = filter {
                if case let .failure(error) = setFilter(layer, filter) {
                    return .failure(error)
                }
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            if enableInteraction {
                interactiveFeatureLayerIds.insert(layerId)
            }
            return .success(())
        }
    }

    func addFillLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNFillStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addFillProperties(fillLayer: layer, properties: properties)
            if let sourceLayerIdentifier = sourceLayerIdentifier {
                layer.sourceLayerIdentifier = sourceLayerIdentifier
            }
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let filter = filter {
                if case let .failure(error) = setFilter(layer, filter) {
                    return .failure(error)
                }
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            if enableInteraction {
                interactiveFeatureLayerIds.insert(layerId)
            }
            return .success(())
        }
    }

    func addFillExtrusionLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNFillExtrusionStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addFillExtrusionProperties(
                fillExtrusionLayer: layer,
                properties: properties
            )
            if let sourceLayerIdentifier = sourceLayerIdentifier {
                layer.sourceLayerIdentifier = sourceLayerIdentifier
            }
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let filter = filter {
                if case let .failure(error) = setFilter(layer, filter) {
                    return .failure(error)
                }
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            if enableInteraction {
                interactiveFeatureLayerIds.insert(layerId)
            }
            return .success(())
        }
    }



    func addCircleLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNCircleStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addCircleProperties(
                circleLayer: layer,
                properties: properties
            )
            if let sourceLayerIdentifier = sourceLayerIdentifier {
                layer.sourceLayerIdentifier = sourceLayerIdentifier
            }
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let filter = filter {
                if case let .failure(error) = setFilter(layer, filter) {
                    return .failure(error)
                }
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            if enableInteraction {
                interactiveFeatureLayerIds.insert(layerId)
            }
            return .success(())
        }
    }

    // Private custom implementation using MLNCustomStyleLayer to render triangles via Metal
    func addTriangleLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        NSLog("Adding triangle layer: \(layerId)")
        
        // Use native triangle layer implementation
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, _)):
            do {
                // Note: MLNCustomStyleLayer does not bind to a data source automatically.
                // This custom layer is private and will manage its own rendering.
                let customLayer = MLNTriangleCustomStyleLayer(identifier: layerId)
                
                if let minimumZoomLevel = minimumZoomLevel {
                    customLayer.minimumZoomLevel = Float(minimumZoomLevel)
                }
                if let maximumZoomLevel = maximumZoomLevel {
                    customLayer.maximumZoomLevel = Float(maximumZoomLevel)
                }
                
                // Filters are not directly supported on custom layers; ignore if provided
                _ = filter
                
                // Apply style properties to custom layer using the property converter
                LayerPropertyConverter.addTriangleProperties(
                    triangleLayer: customLayer,
                    properties: properties
                )
                
                if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                    style.insertLayer(customLayer, below: belowLayer)
                } else {
                    style.addLayer(customLayer)
                }
                if enableInteraction {
                    interactiveFeatureLayerIds.insert(layerId)
                }
                return .success(())
                
            } catch {
                let errorMessage = "Failed to create triangle layer '\(layerId)': \(error.localizedDescription)"
                NSLog(errorMessage)
                return .failure(.invalidArguments(errorMessage))
            }
        }
    }
    
    // Fallback implementation using circle layer for immediate functionality when triangle layers are disabled
    func addTriangleLayerFallback(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        sourceLayerIdentifier: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        filter: String?,
        enableInteraction: Bool,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        NSLog("Adding triangle layer fallback (circle): \(layerId)")
        
        // Convert triangle properties to circle properties
        var circleProperties: [String: String] = [:]
        
        // Set visible defaults for fallback
        circleProperties["circle-radius"] = "10"
        circleProperties["circle-color"] = "#FF6B35"  // Orange color for visibility
        circleProperties["circle-opacity"] = "0.8"
        circleProperties["circle-stroke-color"] = "#FFFFFF"  // White outline
        circleProperties["circle-stroke-width"] = "2"
        circleProperties["circle-stroke-opacity"] = "0.9"
        
        // Map triangle properties to circle properties
        for (key, value) in properties {
            switch key {
            case "triangle-size":
                circleProperties["circle-radius"] = value
            case "triangle-color":
                circleProperties["circle-color"] = value
            case "triangle-opacity":
                circleProperties["circle-opacity"] = value
            case "triangle-stroke-width":
                circleProperties["circle-stroke-width"] = value
            case "triangle-stroke-color":
                circleProperties["circle-stroke-color"] = value
            case "triangle-stroke-opacity":
                circleProperties["circle-stroke-opacity"] = value
            case "triangle-translate":
                circleProperties["circle-translate"] = value
            case "triangle-translate-anchor":
                circleProperties["circle-translate-anchor"] = value
            case "triangle-pitch-scale":
                circleProperties["circle-pitch-scale"] = value
            case "triangle-pitch-alignment":
                circleProperties["circle-pitch-alignment"] = value
            default:
                NSLog("Triangle property not mapped to circle: \(key)")
                break
            }
        }
        
        NSLog("Mapped triangle properties to circle properties: \(circleProperties)")
        
        // Use the existing addCircleLayer method with converted properties
        return addCircleLayer(
            sourceId: sourceId,
            layerId: layerId,
            belowLayerId: belowLayerId,
            sourceLayerIdentifier: sourceLayerIdentifier,
            minimumZoomLevel: minimumZoomLevel,
            maximumZoomLevel: maximumZoomLevel,
            filter: filter,
            enableInteraction: enableInteraction,
            properties: circleProperties
        )
    }

    func setFilter(_ layer: MLNStyleLayer, _ filter: String) -> Result<Void, MethodCallError> {
        do {
            let filter = try JSONSerialization.jsonObject(
                with: filter.data(using: .utf8)!,
                options: .fragmentsAllowed
            )
            if filter is NSNull {
                return .success(())
            }
            let predicate = NSPredicate(mglJSONObject: filter)
            if let layer = layer as? MLNVectorStyleLayer {
                layer.predicate = predicate
            } else {
                return .failure(MethodCallError.invalidLayerType(
                    details: "Layer '\(layer.identifier)' does not support filtering."
                ))
            }
            return .success(())
        } catch {
            return .failure(MethodCallError.invalidExpression)
        }
    }

    func addHillshadeLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNHillshadeStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addHillshadeProperties(
                hillshadeLayer: layer,
                properties: properties
            )
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            return .success(())
        }
    }

    func addHeatmapLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        properties: [String: String]
    ) -> Result<Void, MethodCallError> {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNHeatmapStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addHeatmapProperties(
                heatmapLayer: layer,
                properties: properties
            )
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            return .success(())
        }
    }

    func addRasterLayer(
        sourceId: String,
        layerId: String,
        belowLayerId: String?,
        minimumZoomLevel: Double?,
        maximumZoomLevel: Double?,
        properties: [String: String]
    )  -> Result<Void, MethodCallError>  {
        switch validateBeforeLayerAdd(sourceId: sourceId, layerId: layerId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (style, source)):
            let layer = MLNRasterStyleLayer(identifier: layerId, source: source)
            LayerPropertyConverter.addRasterProperties(
                rasterLayer: layer,
                properties: properties
            )
            if let minimumZoomLevel = minimumZoomLevel {
                layer.minimumZoomLevel = Float(minimumZoomLevel)
            }
            if let maximumZoomLevel = maximumZoomLevel {
                layer.maximumZoomLevel = Float(maximumZoomLevel)
            }
            if let id = belowLayerId, let belowLayer = style.layer(withIdentifier: id) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
            return .success(())
        }
    }

    func addSource(sourceId: String, properties: [String: Any]) -> Result<Void, MethodCallError> {
        guard let style = mapView.style else { 
            return .failure(.styleNotFound)
        }
        guard style.source(withIdentifier: sourceId) == nil else {
            return .failure(.sourceAlreadyExists(sourceId: sourceId))
        }
        guard let type = properties["type"] as? String else {
            return .failure(.invalidSourceType(
                details: "Source '\(sourceId)' does not have a type."
            ))
        }

        var source: MLNSource?
        switch type {
        case "vector":
            source = SourcePropertyConverter.buildVectorTileSource(
                identifier: sourceId,
                properties: properties
            )
        case "raster":
            source = SourcePropertyConverter.buildRasterTileSource(
                identifier: sourceId,
                properties: properties
            )
        case "raster-dem":
            source = SourcePropertyConverter.buildRasterDemSource(
                identifier: sourceId,
                properties: properties
            )
        case "image":
            source = SourcePropertyConverter.buildImageSource(
                identifier: sourceId,
                properties: properties
            )
        case "geojson":
            source = SourcePropertyConverter.buildShapeSource(
                identifier: sourceId,
                properties: properties
            )
        default:
            // unsupported source type
            source = nil
        }
        if let source = source {
            style.addSource(source)
            return .success(())
        }
        return .failure(.invalidSourceType(
            details: "Source '\(sourceId)' does not support type '\(type)'."
        ))
       
    }

    func mapViewDidBecomeIdle(_: MLNMapView) {
        if let channel = channel {
            channel.invokeMethod("map#onIdle", arguments: [])
        }
    }

    func mapView(_: MLNMapView, regionWillChangeAnimated _: Bool) {
        if let channel = channel {
            channel.invokeMethod("camera#onMoveStarted", arguments: [])
        }
    }

    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        if !trackCameraPosition { return }
        if let channel = channel {
            channel.invokeMethod("camera#onMove", arguments: [
                "position": getCamera()?.toDict(mapView: mapView),
            ])
        }
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated _: Bool) {
        let arguments = trackCameraPosition ? [
            "position": getCamera()?.toDict(mapView: mapView)
        ] : [:]
        if let channel = channel {
            channel.invokeMethod("camera#onIdle", arguments: arguments)
        }
    }

    func addSourceGeojson(sourceId: String, geojson: String) -> Result<Void, MethodCallError> {
        do{
            guard let style = mapView.style else { 
                return .failure(.styleNotFound)
            }
            guard style.source(withIdentifier: sourceId) == nil else {
                return .failure(.sourceAlreadyExists(sourceId: sourceId))
            }

            let parsed = try MLNShape(
                data: geojson.data(using: .utf8)!,
                encoding: String.Encoding.utf8.rawValue
            )
            let source = MLNShapeSource(identifier: sourceId, shape: parsed, options: [:])
            addedShapesByLayer[sourceId] = parsed
            style.addSource(source)
            return .success(())
        } catch {
            return .failure(.geojsonParseError(sourceId: sourceId))
        }
    }

    func setSource(sourceId: String, geojson: String) -> Result<Void, MethodCallError> {
        guard let style = mapView.style else { 
            return .failure(.styleNotFound)
        }

        do{
            let parsed = try MLNShape(
                data: geojson.data(using: .utf8)!,
                encoding: String.Encoding.utf8.rawValue
            )
            guard let source = style.source(withIdentifier: sourceId) as? MLNShapeSource else {
                return .failure(.sourceNotFound(sourceId: sourceId))
            }
            addedShapesByLayer[sourceId] = parsed
            source.shape = parsed
            return .success(())
        }catch{
            return .failure(.geojsonParseError(sourceId: sourceId))
        }

    }
    

    func setFeature(sourceId: String, geojsonFeature: String) -> Result<Void, MethodCallError> {
        guard let style = mapView.style else { 
            return .failure(.styleNotFound)
        }
        do {
            let newShape = try MLNShape(
                data: geojsonFeature.data(using: .utf8)!,
                encoding: String.Encoding.utf8.rawValue
            )
            guard let source = style.source(withIdentifier: sourceId) as? MLNShapeSource else {
                return .failure(.sourceNotFound(sourceId: sourceId))
            }
            if let shape = addedShapesByLayer[sourceId] as? MLNShapeCollectionFeature,
               let feature = newShape as? MLNShape & MLNFeature
            {
                if let index = shape.shapes
                    .firstIndex(where: {
                        if let id = $0.identifier as? String,
                           let featureId = feature.identifier as? String
                        { return id == featureId }

                        if let id = $0.identifier as? NSNumber,
                           let featureId = feature.identifier as? NSNumber
                        { return id == featureId }
                        return false
                    })
                {
                    var shapes = shape.shapes
                    shapes[index] = feature

                    source.shape = MLNShapeCollectionFeature(shapes: shapes)
                }

                addedShapesByLayer[sourceId] = source.shape
                return .success(())
            }
            return .failure(.genericError(details: "Failed to set feature for sourceId \(sourceId)"))

        } catch {
            return .failure(.geojsonParseError(sourceId: sourceId))
        }
    }

    /*
     *  MapLibreMapOptionsSink
     */
    func setCameraTargetBounds(bounds: MLNCoordinateBounds?) {
        cameraTargetBounds = bounds
    }

    func setCompassEnabled(compassEnabled: Bool) {
        mapView.compassView.isHidden = compassEnabled
        mapView.compassView.isHidden = !compassEnabled
    }

    func setMinMaxZoomPreference(min: Double, max: Double) {
        mapView.minimumZoomLevel = min
        mapView.maximumZoomLevel = max
    }

    func setStyleString(styleString: String) {
        // Check if json, url, absolute path or asset path:
        if styleString.isEmpty {
            NSLog("setStyleString - string empty")
        } else if styleString.hasPrefix("{") || styleString.hasPrefix("[") {
            // Currently the iOS MapLibre SDK does not have a builder for json.
            NSLog("setStyleString - JSON style currently not supported")
        } else if styleString.hasPrefix("/") {
            // Absolute path
            mapView.styleURL = URL(fileURLWithPath: styleString, isDirectory: false)
        } else if
            !styleString.hasPrefix("http://"),
            !styleString.hasPrefix("https://"),
            !styleString.hasPrefix("mapbox://")
        {
            // We are assuming that the style will be loaded from an asset here.
            let assetPath = registrar.lookupKey(forAsset: styleString)
            mapView.styleURL = URL(string: assetPath, relativeTo: Bundle.main.resourceURL)

        } else if (styleString.hasPrefix("file://")) {
            if let path = Bundle.main.path(forResource: styleString.deletingPrefix("file://"), ofType: "json") {
                let url = URL(fileURLWithPath: path)
                mapView.styleURL = url
            } else {
                NSLog("setStyleString - Path not found")
            }
        } else {
            mapView.styleURL = URL(string: styleString)
        }
    }

    func setRotateGesturesEnabled(rotateGesturesEnabled: Bool) {
        mapView.allowsRotating = rotateGesturesEnabled
    }

    func setScrollGesturesEnabled(scrollGesturesEnabled: Bool) {
        mapView.allowsScrolling = scrollGesturesEnabled
        scrollingEnabled = scrollGesturesEnabled
    }

    func setTiltGesturesEnabled(tiltGesturesEnabled: Bool) {
        mapView.allowsTilting = tiltGesturesEnabled
    }

    func setTrackCameraPosition(trackCameraPosition: Bool) {
        self.trackCameraPosition = trackCameraPosition
    }

    func setZoomGesturesEnabled(zoomGesturesEnabled: Bool) {
        mapView.allowsZooming = zoomGesturesEnabled
    }

    func setMyLocationEnabled(myLocationEnabled: Bool) {
        if self.myLocationEnabled == myLocationEnabled {
            return
        }
        self.myLocationEnabled = myLocationEnabled
        updateMyLocationEnabled()
    }

    func setMyLocationTrackingMode(myLocationTrackingMode: MLNUserTrackingMode) {
        mapView.userTrackingMode = myLocationTrackingMode
    }

    func setMyLocationRenderMode(myLocationRenderMode: MyLocationRenderMode) {
        switch myLocationRenderMode {
        case .Normal:
            mapView.showsUserHeadingIndicator = false
        case .Compass:
            mapView.showsUserHeadingIndicator = true
        case .Gps:
            NSLog("RenderMode.GPS currently not supported")
        }
    }

    func setLogoViewMargins(x: Double, y: Double) {
        mapView.logoViewMargins = CGPoint(x: x, y: y)
    }

    func setCompassViewPosition(position: MLNOrnamentPosition) {
        mapView.compassViewPosition = position
    }

    func setCompassViewMargins(x: Double, y: Double) {
        mapView.compassViewMargins = CGPoint(x: x, y: y)
    }

    func setAttributionButtonMargins(x: Double, y: Double) {
        mapView.attributionButtonMargins = CGPoint(x: x, y: y)
    }

    func setAttributionButtonPosition(position: MLNOrnamentPosition) {
        mapView.attributionButtonPosition = position
    }
    
    // MARK: - Rotatable Symbol PNG Layers Implementation
    
    /**
     * Adds a multi-layer rotatable symbol to the map using PNG assets.
     * Creates 4 synchronized layers: aircraft PNG, top label, bottom label, and side arrow PNG.
     * Similar to addRotatableSymbolLayers but uses PNG assets instead of programmatically created icons.
     */
    private func addRotatableSymbolPngLayers(
        sourceId: String,
        baseLayerId: String,
        belowLayerId: String?,
        properties: [String: Any],
        enableInteraction: Bool
    ) -> Result<Void, MethodCallError> {
        
        guard let style = mapView.style else {
            return .failure(.styleNotLoaded)
        }
        
        guard style.source(withIdentifier: sourceId) != nil else {
            return .failure(.sourceNotFound(sourceId: sourceId))
        }
        
        do {
            NSLog("Adding rotatable symbol PNG layers with base ID: \(baseLayerId)")
            
            // Extract PNG asset configuration from properties
            let config = properties["config"] as? [String: Any] ?? [:]
            
            // Extract PNG asset paths and sizes
            guard let aircraftIconPath = config["aircraftIconPath"] as? String,
                  !aircraftIconPath.isEmpty else {
                return .failure(.genericError(details: "aircraftIconPath is required in config for PNG layers"))
            }
            
            guard let arrowIconPath = config["arrowIconPath"] as? String,
                  !arrowIconPath.isEmpty else {
                return .failure(.genericError(details: "arrowIconPath is required in config for PNG layers"))
            }
            
            let aircraftIconSize = config["aircraftIconSize"] as? Double ?? 0.4
            let arrowIconSize = config["arrowIconSize"] as? Double ?? 0.3
            
            // Load and register PNG assets - Load colored traffic PNG assets (all colors) 
            try loadColoredTrafficPngAssets()
            
            // Load and register colored arrow PNG assets (all colors)
            try loadColoredArrowPngAssets()
            
            // Load primary aircraft icon as fallback (but don't fail if it doesn't exist)
            var fallbackAircraftIconId: String? = nil
            do {
                fallbackAircraftIconId = try ensurePngAssetExists(assetPath: aircraftIconPath, iconType: "aircraft-fallback")
                NSLog("Successfully loaded fallback aircraft icon: \(aircraftIconPath)")
            } catch {
                NSLog("Failed to load fallback aircraft icon: \(aircraftIconPath), will use colored rectangles")
            }
            
            // Extract configuration from properties
            let topLabelOffset = config["topLabelOffset"] as? Double ?? -2.5
            let bottomLabelOffset = config["bottomLabelOffset"] as? Double ?? 2.5
            let arrowOffsetX = config["arrowOffsetX"] as? Double ?? 20.0
            
            // 1. Add aircraft PNG layer (rotatable with map) with dynamic PNG swapping
            let aircraftLayerId = "\(baseLayerId)-aircraft"
            let aircraftLayer = MLNSymbolStyleLayer(identifier: aircraftLayerId, source: style.source(withIdentifier: sourceId)!)
            
            // Dynamic icon selection based on proximity distance (matching Android implementation)
            let iconImageExpression = NSExpression(
                format: "TERNARY(proximityDistance < 2.0, 'aircraft-red', TERNARY(proximityDistance < 5.0, 'aircraft-yellow', 'aircraft-green'))"
            )
            aircraftLayer.iconImageName = iconImageExpression
            aircraftLayer.iconScale = NSExpression(forConstantValue: aircraftIconSize)
            aircraftLayer.iconRotation = NSExpression(forKeyPath: "rotation")
            aircraftLayer.iconRotationAlignment = NSExpression(forConstantValue: "map") // Rotates with map
            aircraftLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            aircraftLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            
            NSLog("Aircraft layer configured with dynamic PNG swapping based on proximityDistance")
            
            // 2. Add top label layer (viewport aligned, stays horizontal)
            let topLabelLayerId = "\(baseLayerId)-top-label"
            let topLabelLayer = MLNSymbolStyleLayer(identifier: topLabelLayerId, source: style.source(withIdentifier: sourceId)!)
            
            topLabelLayer.text = NSExpression(forKeyPath: "topLabel")
            // Remove custom font specification - let MapLibre use default fonts
            topLabelLayer.textFontSize = NSExpression(forKeyPath: "labelSize")
            topLabelLayer.textColor = NSExpression(forKeyPath: "labelColor")
            topLabelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            topLabelLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
            topLabelLayer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: topLabelOffset))
            topLabelLayer.textRotationAlignment = NSExpression(forConstantValue: "viewport") // Always horizontal
            topLabelLayer.textAllowsOverlap = NSExpression(forConstantValue: true)
            topLabelLayer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            
            // 3. Add bottom label layer (viewport aligned, stays horizontal)
            let bottomLabelLayerId = "\(baseLayerId)-bottom-label"
            let bottomLabelLayer = MLNSymbolStyleLayer(identifier: bottomLabelLayerId, source: style.source(withIdentifier: sourceId)!)
            
            bottomLabelLayer.text = NSExpression(forKeyPath: "bottomLabel")
            bottomLabelLayer.textFontSize = NSExpression(forKeyPath: "labelSize")
            bottomLabelLayer.textColor = NSExpression(forKeyPath: "labelColor")
            bottomLabelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            bottomLabelLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
            bottomLabelLayer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: bottomLabelOffset))
            bottomLabelLayer.textRotationAlignment = NSExpression(forConstantValue: "viewport") // Always horizontal
            bottomLabelLayer.textAllowsOverlap = NSExpression(forConstantValue: true)
            bottomLabelLayer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            
            // 4. Add arrow PNG layer (viewport aligned, fixed to right side) with colored arrows
            let arrowLayerId = "\(baseLayerId)-arrow"
            let arrowLayer = MLNSymbolStyleLayer(identifier: arrowLayerId, source: style.source(withIdentifier: sourceId)!)
            
            // For now, use a static arrow icon (TODO: implement dynamic switching)
            // Dynamic arrow switching will be implemented using style updates in real-time  
            // Dynamic arrow selection based on proximity distance and climb state (matching Android implementation)
            // Red: Critical (<2nm), Yellow: Warning (2-5nm), Green: Safe (>=5nm)
            let arrowImageExpression = NSExpression(
                format: "TERNARY(proximityDistance < 2.0, TERNARY(isClimbing == YES, 'arrow-red-up', 'arrow-red-down'), TERNARY(proximityDistance < 5.0, TERNARY(isClimbing == YES, 'arrow-yellow-up', 'arrow-yellow-down'), TERNARY(isClimbing == YES, 'arrow-green-up', 'arrow-green-down')))"
            )
            arrowLayer.iconImageName = arrowImageExpression
            arrowLayer.iconScale = NSExpression(forConstantValue: arrowIconSize)
            arrowLayer.iconRotationAlignment = NSExpression(forConstantValue: "viewport") // Always upright
            arrowLayer.iconOffset = NSExpression(forConstantValue: CGVector(dx: arrowOffsetX, dy: 0.0)) // Fixed to right side
            arrowLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            arrowLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            arrowLayer.iconOpacity = NSExpression(forKeyPath: "arrowOpacity")
            
            // Add layers to style in proper order (aircraft first, then text on top, arrow last)
            if let belowLayerId = belowLayerId,
               let belowLayer = style.layer(withIdentifier: belowLayerId) {
                style.insertLayer(aircraftLayer, below: belowLayer)
                style.insertLayer(topLabelLayer, above: aircraftLayer)
                style.insertLayer(bottomLabelLayer, above: topLabelLayer)
                style.insertLayer(arrowLayer, above: bottomLabelLayer)
            } else {
                style.addLayer(aircraftLayer)
                style.addLayer(topLabelLayer)
                style.addLayer(bottomLabelLayer)
                style.addLayer(arrowLayer)
            }
            
            // Enable interaction if requested
            if enableInteraction {
                interactiveFeatureLayerIds.insert(aircraftLayerId)
                interactiveFeatureLayerIds.insert(topLabelLayerId)
                interactiveFeatureLayerIds.insert(bottomLabelLayerId)
                interactiveFeatureLayerIds.insert(arrowLayerId)
            }
            
            NSLog("Successfully added rotatable symbol PNG layers: \(aircraftLayerId), \(topLabelLayerId), \(bottomLabelLayerId), \(arrowLayerId)")
            NSLog("Aircraft icon size: \(aircraftIconSize), Arrow icon size: \(arrowIconSize)")
            NSLog("Arrow offset X: \(arrowOffsetX)")
            NSLog("Dynamic aircraft PNG swapping enabled with proximity-based color selection")
            NSLog("Dynamic arrow PNG swapping enabled based on proximityDistance and isClimbing")
            return .success(())
            
        } catch {
            let errorMessage = "Failed to add rotatable symbol PNG layers '\(baseLayerId)': \(error.localizedDescription)"
            NSLog(errorMessage)
            return .failure(.genericError(details: errorMessage))
        }
    }
    
    /**
     * Ensures a PNG asset exists in the map style.
     * Loads the PNG from assets and registers it with a unique name.
     */
    private func ensurePngAssetExists(assetPath: String, iconType: String) throws -> String {
        // Create unique icon ID based on asset path and type
        let iconId = "maplibre-png-\(iconType)-\(assetPath.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression))"
        
        // Check if icon already exists
        if let style = mapView.style, style.image(forName: iconId) != nil {
            NSLog("PNG icon already exists: \(iconId)")
            return iconId
        }
        
        // Load PNG from assets
        guard let image = loadImageFromAssets(assetPath: assetPath) else {
            throw NSError(domain: "MapLibrePNG", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to load PNG asset: \(assetPath)"])
        }
        
        var finalImage = image
        
        // For arrow icons, we might want to create rotated versions
        if iconType.hasPrefix("arrow") {
            if iconType == "arrow-up" {
                // Use image as-is for up arrow
            } else if iconType == "arrow-down" {
                // Rotate image 180 degrees for down arrow
                finalImage = rotateImage(image: image, angle: .pi) // 180 degrees in radians
            }
        }
        
        // Register the PNG icon
        guard let style = mapView.style else {
            throw NSError(domain: "MapLibrePNG", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Style not loaded"])
        }
        
        style.setImage(finalImage, forName: iconId)
        NSLog("Added PNG icon to style: \(iconId) from \(assetPath)")
        
        return iconId
    }
    
    /**
     * Loads all colored traffic PNG assets for proximity-based aircraft icons.
     * Loads red, yellow, and green aircraft variants matching Android implementation.
     */
    private func loadColoredTrafficPngAssets() throws {
        NSLog("Loading colored traffic PNG assets for proximity-based aircraft icons")
        
        // Define traffic color variants (matching Android)
        let trafficAssetPaths = [
            "traffic_red.png",
            "traffic_yellow.png", 
            "traffic_green.png"
        ]
        
        let trafficIconIds = [
            "aircraft-red",
            "aircraft-yellow", 
            "aircraft-green"
        ]
        
        guard let style = mapView.style else {
            throw NSError(domain: "MapLibrePNG", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Style not loaded"])
        }
        
        for (index, iconId) in trafficIconIds.enumerated() {
            let assetPath = trafficAssetPaths[index]
            
            // Check if icon already exists
            if style.image(forName: iconId) != nil {
                NSLog("Traffic PNG icon already exists: \(iconId)")
                continue
            }
            
            // Load the PNG asset
            guard let image = loadImageFromAssets(assetPath: assetPath) else {
                NSLog("Failed to load traffic asset: \(assetPath), using fallback for \(iconId)")
                // Create fallback colored rectangle if PNG fails to load
                let fallbackImage = createFallbackColoredIcon(for: iconId)
                style.setImage(fallbackImage, forName: iconId)
                continue
            }
            
            // Register with MapLibre style
            style.setImage(image, forName: iconId)
            NSLog("Successfully loaded traffic PNG icon: \(iconId) from \(assetPath) (\(image.size.width)x\(image.size.height))")
        }
        
        NSLog("Successfully loaded all colored traffic PNG assets")
    }
    
    /**
     * Loads all colored arrow PNG assets and creates rotated variants.
     * Creates both up and down arrow versions for all proximity colors (red, yellow, green).
     */
    private func loadColoredArrowPngAssets() throws {
        NSLog("Loading colored arrow PNG assets for all proximity colors")
        
        // Define all arrow color variants
        let arrowColors = ["red", "yellow", "green"]
        let arrowAssetPaths = [
            "arrow_red.png",
            "arrow_yellow.png", 
            "arrow_green.png"
        ]
        
        guard let style = mapView.style else {
            throw NSError(domain: "MapLibrePNG", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Style not loaded"])
        }
        
        for (index, color) in arrowColors.enumerated() {
            let assetPath = arrowAssetPaths[index]
            
            // Load the base arrow image for this color
            guard let baseImage = loadImageFromAssets(assetPath: assetPath) else {
                NSLog("Failed to load arrow asset: \(assetPath), skipping \(color) arrows")
                continue
            }
            
            // Create up arrow (use image as-is)
            let upArrowId = "arrow-\(color)-up"
            if style.image(forName: upArrowId) == nil {
                style.setImage(baseImage, forName: upArrowId)
                NSLog("Added \(color) up arrow icon: \(upArrowId)")
            }
            
            // Create down arrow (rotate 180 degrees)
            let downArrowId = "arrow-\(color)-down"
            if style.image(forName: downArrowId) == nil {
                let downImage = rotateImage(image: baseImage, angle: .pi) // 180 degrees
                style.setImage(downImage, forName: downArrowId)
                NSLog("Added \(color) down arrow icon: \(downArrowId)")
            }
        }
        
        NSLog("Successfully loaded all colored arrow PNG assets with rotation")
    }
    
    /**
     * Loads an image from Flutter assets.
     */
    private func loadImageFromAssets(assetPath: String) -> UIImage? {
        NSLog("🔍 loadImageFromAssets: Loading asset: \(assetPath)")
        
        // Strategy 1: Direct Flutter asset key resolution (proven method)
        let assetKey = registrar.lookupKey(forAsset: assetPath)
        NSLog("🔑 Flutter resolved key: \(assetKey)")
        
        // Method 1a: Try with NSDataAsset using the resolved key (framework bundle method)
        if let assetData = NSDataAsset(name: assetKey, bundle: Bundle.main) {
            if let image = UIImage(data: assetData.data) {
                NSLog("✅ Successfully loaded via NSDataAsset: \(assetKey)")
                return image
            }
        }
        
        // Method 1b: Try loading from App.framework bundle explicitly (where Flutter assets live)
        if let appFrameworkPath = Bundle.main.path(forResource: "App", ofType: "framework", inDirectory: "Frameworks"),
           let appBundle = Bundle(path: appFrameworkPath) {
            NSLog("🎯 Found App.framework bundle at: \(appFrameworkPath)")
            
            // Force load the bundle if not already loaded
            if !appBundle.isLoaded {
                NSLog("📦 Loading App.framework bundle...")
                if appBundle.load() {
                    NSLog("✅ App.framework loaded successfully")
                } else {
                    NSLog("❌ Failed to load App.framework")
                }
            }
            
            // Try loading the asset from App.framework
            if let assetData = NSDataAsset(name: assetKey, bundle: appBundle) {
                if let image = UIImage(data: assetData.data) {
                    NSLog("✅ Successfully loaded from App.framework: \(assetKey)")
                    return image
                }
            }
            
            if let image = UIImage(named: assetKey, in: appBundle, compatibleWith: nil) {
                NSLog("✅ Successfully loaded via UIImage(named:) from App.framework: \(assetKey)")
                return image
            }
        }
        
        // Method 1c: Try finding in all bundles that might contain Flutter assets
        let allBundles = [Bundle.main] + Bundle.allFrameworks + Bundle.allBundles
        for bundle in allBundles {
            if let assetData = NSDataAsset(name: assetKey, bundle: bundle) {
                if let image = UIImage(data: assetData.data) {
                    NSLog("✅ Successfully loaded from bundle \(bundle): \(assetKey)")
                    return image
                }
            }
            
            if let image = UIImage(named: assetKey, in: bundle, compatibleWith: nil) {
                NSLog("✅ Successfully loaded via UIImage(named:) from bundle \(bundle): \(assetKey)")
                return image
            }
        }
        
        // Method 1d: Try constructing path directly to asset within App.framework
        let assetRelativePath = "flutter_assets/assets/\(assetPath)"
        if let appFrameworkPath = Bundle.main.path(forResource: "App", ofType: "framework", inDirectory: "Frameworks") {
            let fullAssetPath = "\(appFrameworkPath)/\(assetRelativePath)"
            NSLog("🎯 Trying direct path to asset: \(fullAssetPath)")
            if let image = UIImage(contentsOfFile: fullAssetPath) {
                NSLog("✅ Successfully loaded via direct App.framework path: \(fullAssetPath)")
                return image
            }
        }
        
        // Method 1e: Try the traditional path method
        if let path = Bundle.main.path(forResource: assetKey, ofType: nil) {
            if let image = UIImage(contentsOfFile: path) {
                NSLog("✅ Successfully loaded via path: \(path)")
                return image
            }
        }
        
        // Strategy 2: Try using Flutter framework bundle
        if let flutterBundle = Bundle(identifier: "io.flutter.flutter.app") {
            NSLog("Found Flutter bundle: \(flutterBundle)")
            if let image = UIImage(named: assetKey, in: flutterBundle, compatibleWith: nil) {
                NSLog("Successfully loaded via Flutter bundle: \(assetKey)")
                return image
            }
        }
        
        // Strategy 3: Try explicit flutter_assets path (matching Android)
        let flutterAssetPath = "flutter_assets/\(assetPath)"
        if let bundlePath = Bundle.main.path(forResource: flutterAssetPath, ofType: nil) {
            if let image = UIImage(contentsOfFile: bundlePath) {
                NSLog("Successfully loaded via flutter_assets path: \(bundlePath)")
                return image
            }
        }
        
        // Strategy 4: Try direct asset path
        if let bundlePath = Bundle.main.path(forResource: assetPath, ofType: nil) {
            if let image = UIImage(contentsOfFile: bundlePath) {
                NSLog("Successfully loaded via direct path: \(bundlePath)")
                return image
            }
        }
        
        // Strategy 5: Try without extension (matching Android approach)
        let pathWithoutExt = (assetPath as NSString).deletingPathExtension
        let ext = (assetPath as NSString).pathExtension
        if !ext.isEmpty {
            if let bundlePath = Bundle.main.path(forResource: pathWithoutExt, ofType: ext) {
                if let image = UIImage(contentsOfFile: bundlePath) {
                    NSLog("Successfully loaded via split path: \(bundlePath)")
                    return image
                }
            }
        }
        
        // Strategy 6: Search all bundle paths for matching files
        NSLog("Searching all bundle paths for: \(assetPath)")
        let bundleResourcePaths = Bundle.main.paths(forResourcesOfType: (assetPath as NSString).pathExtension, inDirectory: nil)
        for resourcePath in bundleResourcePaths {
            let fileName = (resourcePath as NSString).lastPathComponent
            if fileName == assetPath {
                if let image = UIImage(contentsOfFile: resourcePath) {
                    NSLog("Successfully loaded via bundle search: \(resourcePath)")
                    return image
                }
            }
        }
        
        // Strategy 7: List all PNG files in bundle for debugging
        let allPngPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
        NSLog("All PNG files in bundle (\(allPngPaths.count) total):")
        for pngPath in allPngPaths {
            NSLog("  - \((pngPath as NSString).lastPathComponent) at \(pngPath)")
        }
        
        // Strategy 8: Test loading a known asset like sydney0.png
        NSLog("Testing known asset sydney0.png...")
        let testAssetKey = registrar.lookupKey(forAsset: "sydney0.png")
        NSLog("sydney0.png resolved to key: \(testAssetKey)")
        if let testPath = Bundle.main.path(forResource: testAssetKey, ofType: nil) {
            NSLog("Found sydney0.png at: \(testPath)")
        } else {
            NSLog("sydney0.png not found in bundle")
        }
        
        NSLog("Failed to load image from assets: \(assetPath) (key: \(assetKey))")
        return nil
    }
    
    /**
     * Rotates an image by the specified angle.
     */
    private func rotateImage(image: UIImage, angle: CGFloat) -> UIImage {
        let size = image.size
        
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return image // Return original if rotation fails
        }
        
        // Move to center, rotate, then move back
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: angle)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)
        
        // Draw the image
        image.draw(in: CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    /**
     * Creates a fallback colored icon for testing when PNG assets fail to load.
     * Matches the Android fallback implementation.
     */
    private func createFallbackColoredIcon(for iconId: String) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        
        // Determine color based on icon ID
        var color = UIColor.gray
        if iconId.contains("red") {
            color = UIColor.red
        } else if iconId.contains("yellow") {
            color = UIColor.yellow
        } else if iconId.contains("blue") {
            color = UIColor.blue
        } else if iconId.contains("green") {
            color = UIColor.green
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage() // Return empty image if context creation fails
        }
        
        // Fill with the appropriate color
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        // Add black border for better visibility
        UIColor.black.setStroke()
        context.setLineWidth(2.0)
        context.stroke(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        NSLog("Created fallback colored icon: \(iconId) with color: \(color)")
        return image
    }
    
    // MARK: - Rotatable Symbol Layers Implementation
    
    /**
     * Ensures that triangle and arrow icons exist in the map style.
     * Creates programmatic icon images if they don't exist.
     */
    private func ensureRotatableSymbolIconsExist() {
        guard let style = mapView.style else { return }
        
        let triangleIconId = "maplibre-triangle-icon"
        let upArrowIconId = "maplibre-arrow-up-icon"
        let downArrowIconId = "maplibre-arrow-down-icon"
        
        // Check if icons already exist
        if style.image(forName: triangleIconId) != nil &&
           style.image(forName: upArrowIconId) != nil &&
           style.image(forName: downArrowIconId) != nil {
            return
        }
        
        // Create triangle icon
        if style.image(forName: triangleIconId) == nil {
            if let triangleImage = createTriangleImage() {
                style.setImage(triangleImage, forName: triangleIconId)
                NSLog("Added triangle icon to style: \(triangleIconId)")
            }
        }
        
        // Create arrow icons
        if style.image(forName: upArrowIconId) == nil {
            if let upArrowImage = createArrowImage(pointingUp: true) {
                style.setImage(upArrowImage, forName: upArrowIconId)
                NSLog("Added up arrow icon to style: \(upArrowIconId)")
            }
        }
        
        if style.image(forName: downArrowIconId) == nil {
            if let downArrowImage = createArrowImage(pointingUp: false) {
                style.setImage(downArrowImage, forName: downArrowIconId)
                NSLog("Added down arrow icon to style: \(downArrowIconId)")
            }
        }
    }
    
    /**
     * Creates a triangle image programmatically using Core Graphics.
     */
    private func createTriangleImage() -> UIImage? {
        let size = CGSize(width: 64, height: 64)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Clear background
        context.clear(CGRect(origin: .zero, size: size))
        
        // Setup drawing properties
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate triangle points
        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius: CGFloat = size.width * 0.35
        
        // Equilateral triangle pointing up
        let topX = centerX
        let topY = centerY - radius
        let bottomLeftX = centerX - (radius * 0.866) // cos(30°)
        let bottomLeftY = centerY + (radius * 0.5)   // sin(30°)
        let bottomRightX = centerX + (radius * 0.866)
        let bottomRightY = centerY + (radius * 0.5)
        
        // Create triangle path
        context.beginPath()
        context.move(to: CGPoint(x: topX, y: topY))
        context.addLine(to: CGPoint(x: bottomLeftX, y: bottomLeftY))
        context.addLine(to: CGPoint(x: bottomRightX, y: bottomRightY))
        context.closePath()
        
        // Fill triangle with orange color
        context.setFillColor(UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0).cgColor) // #FF6B35
        context.fillPath()
        
        // Stroke triangle with white border
        context.beginPath()
        context.move(to: CGPoint(x: topX, y: topY))
        context.addLine(to: CGPoint(x: bottomLeftX, y: bottomLeftY))
        context.addLine(to: CGPoint(x: bottomRightX, y: bottomRightY))
        context.closePath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.strokePath()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    /**
     * Creates an arrow image programmatically using Core Graphics.
     * @param pointingUp: true for up arrow, false for down arrow
     */
    private func createArrowImage(pointingUp: Bool) -> UIImage? {
        let size = CGSize(width: 32, height: 32)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Clear background
        context.clear(CGRect(origin: .zero, size: size))
        
        // Setup drawing properties
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate arrow dimensions
        let centerX = size.width / 2
        let centerY = size.height / 2
        let arrowHeight = size.height * 0.6
        let arrowWidth = size.width * 0.4
        
        // Create arrow path
        context.beginPath()
        
        if pointingUp {
            // Up arrow: ▲
            let topX = centerX
            let topY = centerY - arrowHeight / 2
            let bottomLeftX = centerX - arrowWidth / 2
            let bottomLeftY = centerY + arrowHeight / 2
            let bottomRightX = centerX + arrowWidth / 2
            let bottomRightY = centerY + arrowHeight / 2
            
            context.move(to: CGPoint(x: topX, y: topY))
            context.addLine(to: CGPoint(x: bottomLeftX, y: bottomLeftY))
            context.addLine(to: CGPoint(x: bottomRightX, y: bottomRightY))
        } else {
            // Down arrow: ▼
            let topLeftX = centerX - arrowWidth / 2
            let topLeftY = centerY - arrowHeight / 2
            let topRightX = centerX + arrowWidth / 2
            let topRightY = centerY - arrowHeight / 2
            let bottomX = centerX
            let bottomY = centerY + arrowHeight / 2
            
            context.move(to: CGPoint(x: topLeftX, y: topLeftY))
            context.addLine(to: CGPoint(x: topRightX, y: topRightY))
            context.addLine(to: CGPoint(x: bottomX, y: bottomY))
        }
        
        context.closePath()
        
        // Fill arrow with black color
        context.setFillColor(UIColor.black.cgColor)
        context.fillPath()
        
        // Stroke arrow with white border
        context.beginPath()
        if pointingUp {
            let topX = centerX
            let topY = centerY - arrowHeight / 2
            let bottomLeftX = centerX - arrowWidth / 2
            let bottomLeftY = centerY + arrowHeight / 2
            let bottomRightX = centerX + arrowWidth / 2
            let bottomRightY = centerY + arrowHeight / 2
            
            context.move(to: CGPoint(x: topX, y: topY))
            context.addLine(to: CGPoint(x: bottomLeftX, y: bottomLeftY))
            context.addLine(to: CGPoint(x: bottomRightX, y: bottomRightY))
        } else {
            let topLeftX = centerX - arrowWidth / 2
            let topLeftY = centerY - arrowHeight / 2
            let topRightX = centerX + arrowWidth / 2
            let topRightY = centerY - arrowHeight / 2
            let bottomX = centerX
            let bottomY = centerY + arrowHeight / 2
            
            context.move(to: CGPoint(x: topLeftX, y: topLeftY))
            context.addLine(to: CGPoint(x: topRightX, y: topRightY))
            context.addLine(to: CGPoint(x: bottomX, y: bottomY))
        }
        context.closePath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.strokePath()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    /**
     * Adds a multi-layer rotatable symbol to the map.
     * Creates 4 synchronized layers: triangle, top label, bottom label, and side arrow.
     */
    private func addRotatableSymbolLayers(
        sourceId: String,
        baseLayerId: String,
        belowLayerId: String?,
        properties: [String: Any],
        enableInteraction: Bool
    ) -> Result<Void, MethodCallError> {
        
        guard let style = mapView.style else {
            return .failure(.styleNotLoaded)
        }
        
        guard style.source(withIdentifier: sourceId) != nil else {
            return .failure(.sourceNotFound(sourceId: sourceId))
        }
        
        do {
            NSLog("Adding rotatable symbol layers with base ID: \(baseLayerId)")
            
            // Ensure required icons exist
            ensureRotatableSymbolIconsExist()
            
            // Extract configuration from properties
            let config = properties["config"] as? [String: Any] ?? [:]
            let topLabelOffset = config["topLabelOffset"] as? Double ?? -2.5
            let bottomLabelOffset = config["bottomLabelOffset"] as? Double ?? 2.5
            let arrowOffsetX = config["arrowOffsetX"] as? Double ?? 20.0
            
            // 1. Add triangle layer (rotatable with map)
            let triangleLayerId = "\(baseLayerId)-triangle"
            let triangleLayer = MLNSymbolStyleLayer(identifier: triangleLayerId, source: style.source(withIdentifier: sourceId)!)
            
            triangleLayer.iconImageName = NSExpression(forConstantValue: "maplibre-triangle-icon")
            triangleLayer.iconScale = NSExpression(forKeyPath: "triangleSize")
            triangleLayer.iconRotation = NSExpression(forKeyPath: "rotation")
            triangleLayer.iconRotationAlignment = NSExpression(forConstantValue: "map") // Rotates with map
            triangleLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            triangleLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            triangleLayer.iconOpacity = NSExpression(forKeyPath: "triangleOpacity")
            
            // 2. Add top label layer (viewport aligned, stays horizontal)
            let topLabelLayerId = "\(baseLayerId)-top-label"
            let topLabelLayer = MLNSymbolStyleLayer(identifier: topLabelLayerId, source: style.source(withIdentifier: sourceId)!)
            
            topLabelLayer.text = NSExpression(forKeyPath: "topLabel")
            // Remove custom font specification - let MapLibre use default fonts
            topLabelLayer.textFontSize = NSExpression(forKeyPath: "labelSize")
            topLabelLayer.textColor = NSExpression(forKeyPath: "labelColor")
            topLabelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            topLabelLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
            topLabelLayer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: topLabelOffset))
            topLabelLayer.textRotationAlignment = NSExpression(forConstantValue: "viewport") // Always horizontal
            topLabelLayer.textAllowsOverlap = NSExpression(forConstantValue: true)
            topLabelLayer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            
            // 3. Add bottom label layer (viewport aligned, stays horizontal)
            let bottomLabelLayerId = "\(baseLayerId)-bottom-label"
            let bottomLabelLayer = MLNSymbolStyleLayer(identifier: bottomLabelLayerId, source: style.source(withIdentifier: sourceId)!)
            
            bottomLabelLayer.text = NSExpression(forKeyPath: "bottomLabel")
            bottomLabelLayer.textFontSize = NSExpression(forKeyPath: "labelSize")
            bottomLabelLayer.textColor = NSExpression(forKeyPath: "labelColor")
            bottomLabelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            bottomLabelLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
            bottomLabelLayer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: bottomLabelOffset))
            bottomLabelLayer.textRotationAlignment = NSExpression(forConstantValue: "viewport") // Always horizontal
            bottomLabelLayer.textAllowsOverlap = NSExpression(forConstantValue: true)
            bottomLabelLayer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            
            // 4. Add arrow layer (viewport aligned, fixed to right side)
            let arrowLayerId = "\(baseLayerId)-arrow"
            let arrowLayer = MLNSymbolStyleLayer(identifier: arrowLayerId, source: style.source(withIdentifier: sourceId)!)
            
            // Use static arrow for now (conditional expressions are complex in iOS MapLibre)
            arrowLayer.iconImageName = NSExpression(forConstantValue: "maplibre-arrow-up-icon")
            arrowLayer.iconScale = NSExpression(forKeyPath: "arrowSize")
            arrowLayer.iconRotationAlignment = NSExpression(forConstantValue: "viewport") // Always upright
            arrowLayer.iconOffset = NSExpression(forConstantValue: CGVector(dx: arrowOffsetX, dy: 0.0)) // Fixed to right side
            arrowLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            arrowLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            arrowLayer.iconOpacity = NSExpression(forKeyPath: "arrowOpacity")
            
            // Add layers to style in proper order
            if let belowLayerId = belowLayerId {
                style.insertLayer(triangleLayer, below: style.layer(withIdentifier: belowLayerId)!)
                style.insertLayer(topLabelLayer, above: triangleLayer)
                style.insertLayer(bottomLabelLayer, above: topLabelLayer)
                style.insertLayer(arrowLayer, above: bottomLabelLayer)
            } else {
                style.addLayer(triangleLayer)
                style.addLayer(topLabelLayer)
                style.addLayer(bottomLabelLayer)
                style.addLayer(arrowLayer)
            }
            
            // Enable interaction if requested
            if enableInteraction {
                interactiveFeatureLayerIds.insert(triangleLayerId)
                interactiveFeatureLayerIds.insert(topLabelLayerId)
                interactiveFeatureLayerIds.insert(bottomLabelLayerId)
                interactiveFeatureLayerIds.insert(arrowLayerId)
            }
            
            NSLog("Successfully added rotatable symbol layers: \(triangleLayerId), \(topLabelLayerId), \(bottomLabelLayerId), \(arrowLayerId)")
            return .success(())
            
        } catch {
            NSLog("Failed to add rotatable symbol layers '\(baseLayerId)': \(error.localizedDescription)")
            return .failure(.genericError(details: error.localizedDescription))
        }
    }
    // MARK: - Polyline Editing
    
    /**
     * Provides access to the stored shapes for polyline editing.
     */
    func getStoredShape(for sourceId: String) -> MLNShape? {
        return addedShapesByLayer[sourceId]
    }
    
    /**
     * Gets all stored shapes.
     */
    func getAllStoredShapes() -> [String: MLNShape] {
        return addedShapesByLayer
    }
    
    /**
     * Initializes the polyline editing components.
     */
    private func initializePolylineEditing() {
        // Initialize polyline editing manager
        polylineEditingManager = PolylineEditingManager(mapView: mapView, controller: self)
        
        // Initialize polyline break point system
        polylineBreakPointSystem = PolylineBreakPointSystem(mapView: mapView)
        
        // Initialize polyline renderer
        polylineRenderer = EditablePolylineRenderer(mapView: mapView)
        polylineRenderer?.initialize()
        
        // Initialize polyline gesture handler
        if let editingManager = polylineEditingManager,
           let breakPointSystem = polylineBreakPointSystem,
           let renderer = polylineRenderer {
            polylineGestureHandler = PolylineGestureHandler(
                mapView: mapView,
                editingManager: editingManager,
                breakPointSystem: breakPointSystem,
                renderer: renderer
            )
            polylineGestureHandler?.delegate = self
        }
        
        NSLog("MapLibreMapController: Polyline editing components initialized")
    }
    
    /**
     * Handles polyline editing method calls.
     */
    private func handlePolylineEditingMethodCall(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        switch methodCall.method {
        case "line#enableEditing":
            handleEnableLineEditing(methodCall: methodCall, result: result)
        case "line#setEditingStyle":
            handleSetLineEditingStyle(methodCall: methodCall, result: result)
        case "line#isEditable":
            handleIsLineEditable(methodCall: methodCall, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /**
     * Handles the line#enableEditing method call.
     */
    private func handleEnableLineEditing(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = methodCall.arguments as? [String: Any],
              let lineId = arguments["lineId"] as? String,
              let enabled = arguments["enabled"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "lineId and enabled are required", details: nil))
            return
        }
        
        guard let editingManager = polylineEditingManager else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Polyline editing manager not initialized", details: nil))
            return
        }
        
        do {
            editingManager.enableLineEditing(lineId: lineId, enabled: enabled)
            result(nil)
        } catch {
            result(FlutterError(code: "NATIVE_ERROR", message: "Failed to enable/disable line editing: \(error.localizedDescription)", details: nil))
        }
    }
    
    /**
     * Handles the line#setEditingStyle method call.
     */
    private func handleSetLineEditingStyle(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let style = methodCall.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "style is required", details: nil))
            return
        }
        
        guard let editingManager = polylineEditingManager,
              let renderer = polylineRenderer else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Polyline editing components not initialized", details: nil))
            return
        }
        
        do {
            editingManager.setEditingStyle(style: style)
            renderer.updateStyle(style)
            result(nil)
        } catch {
            result(FlutterError(code: "NATIVE_ERROR", message: "Failed to set editing style: \(error.localizedDescription)", details: nil))
        }
    }
    
    /**
     * Handles the line#isEditable method call.
     */
    private func handleIsLineEditable(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = methodCall.arguments as? [String: Any],
              let lineId = arguments["lineId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "lineId is required", details: nil))
            return
        }
        
        guard let editingManager = polylineEditingManager else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Polyline editing manager not initialized", details: nil))
            return
        }
        
        do {
            let isEditable = editingManager.isLineEditable(lineId: lineId)
            result(isEditable)
        } catch {
            result(FlutterError(code: "NATIVE_ERROR", message: "Failed to check if line is editable: \(error.localizedDescription)", details: nil))
        }
    }
}

// MARK: - PolylineGestureHandlerDelegate

extension MapLibreMapController: PolylineGestureHandlerDelegate {
    func onPolylineBroken(lineId: String, breakPoint: CLLocationCoordinate2D, segment1: [CLLocationCoordinate2D], segment2: [CLLocationCoordinate2D]) {
        NSLog("MapLibreMapController: Polyline broken: \(lineId) at \(breakPoint.latitude), \(breakPoint.longitude)")
        
        // Convert coordinates to Flutter format
        let segment1Coords = segment1.map { [$0.latitude, $0.longitude] }
        let segment2Coords = segment2.map { [$0.latitude, $0.longitude] }
        
        let arguments: [String: Any] = [
            "lineId": lineId,
            "segment1": segment1Coords,
            "segment2": segment2Coords
        ]
        
        channel?.invokeMethod("polylineEditing#onBroken", arguments: arguments)
    }
    
    func onPolylineModified(lineId: String, newCoordinates: [CLLocationCoordinate2D]) {
        NSLog("MapLibreMapController: Polyline modified: \(lineId)")
        
        // Convert coordinates to Flutter format
        let coordinates = newCoordinates.map { [$0.latitude, $0.longitude] }
        
        let arguments: [String: Any] = [
            "lineId": lineId,
            "coordinates": coordinates
        ]
        
        channel?.invokeMethod("polylineEditing#onModified", arguments: arguments)
    }
    
    func onPolylineEditingError(lineId: String, error: String) {
        NSLog("MapLibreMapController: Polyline editing error for \(lineId): \(error)")
        
        let arguments: [String: Any] = [
            "lineId": lineId,
            "error": error
        ]
        
        channel?.invokeMethod("polylineEditing#onError", arguments: arguments)
    }
}

// MARK: - Label Image Creation Helpers
extension MapLibreMapController {
    
    /// Convert hex color string to UIColor
    private func hexToUIColor(hex: String) -> UIColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    /// Create a pill-shaped label image
    private func createPillLabelImage(
        text: String,
        textSize: CGFloat,
        textColor: UIColor,
        backgroundColor: UIColor,
        padding: CGFloat,
        cornerRadius: CGFloat
    ) -> UIImage? {
        // Set up text attributes
        let font = UIFont.boldSystemFont(ofSize: textSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Calculate text size
        let textString = text as NSString
        let textRect = textString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )
        
        // Calculate image dimensions with padding
        let imageWidth = textRect.width + (padding * 2)
        let imageHeight = textRect.height + (padding * 2)
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        
        // Use screen scale for retina displays
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Draw rounded rectangle background
        let backgroundRect = CGRect(origin: .zero, size: imageSize)
        let backgroundPath = UIBezierPath(roundedRect: backgroundRect, cornerRadius: cornerRadius)
        context.setFillColor(backgroundColor.cgColor)
        backgroundPath.fill()
        
        // Draw text centered
        let textX = padding
        let textY = padding
        textString.draw(at: CGPoint(x: textX, y: textY), withAttributes: attributes)
        
        // Get the image
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    /// Create a circular label image with text following the contour
    private func createCircleLabelImage(
        text: String,
        radius: CGFloat,
        textSize: CGFloat,
        textColor: UIColor,
        circleColor: UIColor,
        strokeWidth: CGFloat,
        topArc: Bool,
        roundedEdges: Bool
    ) -> UIImage? {
        // Set up text attributes for measurement
        let font = UIFont.boldSystemFont(ofSize: textSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Measure text height for pill background sizing
        let textString = text as NSString
        let textRect = textString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )
        let textHeight = textRect.height
        
        // Calculate pill background stroke width (text height + padding)
        let pillPadding: CGFloat = 8.0
        let pillStrokeWidth = textHeight + (pillPadding * 2)
        
        // Calculate image size with padding for pill background
        let imageSize = (radius * 2) + (pillStrokeWidth * 2) + 40
        let size = CGSize(width: imageSize, height: imageSize)
        let center = CGPoint(x: imageSize / 2, y: imageSize / 2)
        
        // Use screen scale for retina displays
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Draw circle outline
        let circlePath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: CGFloat.pi * 2,
            clockwise: true
        )
        context.setStrokeColor(circleColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.addPath(circlePath.cgPath)
        context.strokePath()
        
        // Calculate text radius (offset from circle for pill background)
        let textRadius = radius + strokeWidth + pillStrokeWidth / 2 + 5
        
        // Measure text width to calculate arc sweep angle
        let textWidth = textRect.width
        let arcLength = textWidth * 1.1 // 10% extra for spacing
        let sweepAngle = arcLength / textRadius // In radians
        let sweepAngleLimited = min(sweepAngle, CGFloat.pi * 0.89) // Limit to 160°
        
        // Calculate start angle to center the arc
        let startAngle: CGFloat
        if topArc {
            // Center on top (270° = 3π/2 = top of circle)
            startAngle = (3 * CGFloat.pi / 2) - (sweepAngleLimited / 2)
        } else {
            // Center on bottom (90° = π/2 = bottom of circle)
            startAngle = (CGFloat.pi / 2) - (sweepAngleLimited / 2)
        }
        
        // Create path for the pill background arc
        let pillPath = UIBezierPath(
            arcCenter: center,
            radius: textRadius,
            startAngle: startAngle,
            endAngle: startAngle + sweepAngleLimited,
            clockwise: true
        )
        
        // CRITICAL: Configure context BEFORE adding path
        context.setStrokeColor(circleColor.cgColor)
        context.setLineWidth(pillStrokeWidth)
        context.setLineCap(roundedEdges ? .round : .butt)
        context.setLineJoin(.round)
        
        // Add path to context and stroke it
        context.addPath(pillPath.cgPath)
        context.strokePath()
        
        // Draw border/outline for pill (for better definition)
        context.setStrokeColor(circleColor.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(roundedEdges ? .round : .butt)
        context.addPath(pillPath.cgPath)
        context.strokePath()
        
        
        // Draw text along the pill path (character by character)
        let totalArcLength = sweepAngleLimited * textRadius
        if totalArcLength > 0 && text.count > 0 {
            let scaledTextWidth = max(textRect.width, 0.001)
            let spacingScale = totalArcLength / scaledTextWidth
            var accumulatedLength: CGFloat = 0

            for char in text {
                let charString = String(char) as NSString
                let charSize = charString.size(withAttributes: attributes)
                let scaledCharWidth = max(charSize.width, 0.001) * spacingScale
                let charCenterLength = accumulatedLength + (scaledCharWidth / 2)
                let charAngle = startAngle + (charCenterLength / textRadius)

                let position = CGPoint(
                    x: center.x + cos(charAngle) * textRadius,
                    y: center.y + sin(charAngle) * textRadius
                )
                let rotationAngle: CGFloat = topArc
                    ? charAngle + (CGFloat.pi / 2)
                    : charAngle - (CGFloat.pi / 2)

                context.saveGState()
                context.translateBy(x: position.x, y: position.y)
                context.rotate(by: rotationAngle)

                charString.draw(
                    at: CGPoint(x: -charSize.width / 2, y: -charSize.height / 2),
                    withAttributes: attributes
                )

                context.restoreGState()
                accumulatedLength += scaledCharWidth
            }
        }
        
        // Get the image
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
}

extension String {
    func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}
