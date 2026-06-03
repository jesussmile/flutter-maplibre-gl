import Foundation
import MapLibre
import UIKit

struct NativeMeasurementEvent {
    let point1: CGPoint
    let point2: CGPoint
    let coordinate1: CLLocationCoordinate2D
    let coordinate2: CLLocationCoordinate2D
    let distance: Double
    let bearing: Double
    let duration: Int
}

protocol NativeMeasurementDetectorDelegate: AnyObject {
    func nativeMeasurementDetector(_ detector: NativeMeasurementDetector, didStart event: NativeMeasurementEvent)
    func nativeMeasurementDetector(_ detector: NativeMeasurementDetector, didUpdate event: NativeMeasurementEvent)
    func nativeMeasurementDetector(_ detector: NativeMeasurementDetector, didEnd event: NativeMeasurementEvent)
}

class NativeMeasurementDetector: NSObject, UIGestureRecognizerDelegate {
    private static let holdDuration: TimeInterval = 0.5
    private static let movementThreshold: CGFloat = 50.0
    private static let cleanupGracePeriod: TimeInterval = 0.5
    private static let markerTouchRadius: CGFloat = 36.0
    private static let renderMovementThreshold: CGFloat = 1.5

    private static let sourceId = "measurement-source"
    private static let lineLayerId = "measurement-line-layer"
    private static let endpointLayerId = "measurement-endpoint-layer"
    private static let distanceLayerId = "measurement-distance-layer"
    private static let startBearingLayerId = "measurement-start-bearing-layer"
    private static let endBearingLayerId = "measurement-end-bearing-layer"

    private weak var mapView: MLNMapView?
    weak var delegate: NativeMeasurementDetectorDelegate?

    private var twoFingerLongPressRecognizer: UILongPressGestureRecognizer?
    private var endpointPanRecognizer: UIPanGestureRecognizer?

    private var isMeasuring = false
    private var hasPersistentMeasurement = false
    private var justFinishedMeasurement = false
    private var draggingEndpoint: DraggingEndpoint?
    private var gestureStartDate: Date?
    private var measurementEndDate: Date?
    private var currentPoint1: CGPoint?
    private var currentPoint2: CGPoint?
    private var startCoordinate: CLLocationCoordinate2D?
    private var endCoordinate: CLLocationCoordinate2D?
    private var lastRenderedStartPoint: CGPoint?
    private var lastRenderedEndPoint: CGPoint?
    private var suspendedGestures: SuspendedGestures?

    private var lineColor = "#E8604C"
    private var lineWidth = 4.0
    private var lineOpacity = 0.9
    private var endpointColor = "#FFFFFF"
    private var endpointRadius = 9.0

    private enum DraggingEndpoint {
        case start
        case end
    }

    private struct SuspendedGestures {
        let scrolling: Bool
        let zooming: Bool
        let rotating: Bool
        let tilting: Bool
    }

    init(mapView: MLNMapView, delegate: NativeMeasurementDetectorDelegate?) {
        self.mapView = mapView
        self.delegate = delegate

        super.init()

        setupGestureRecognizers(on: mapView)
        initializeMeasurementLayers()
    }

    func setMeasurementStyle(
        lineColor: String,
        lineWidth: Double,
        lineOpacity: Double,
        endpointColor: String,
        endpointRadius: Double
    ) {
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.lineOpacity = lineOpacity
        self.endpointColor = endpointColor
        self.endpointRadius = endpointRadius
        updateMeasurementLayerStyle()
    }

    func clearMeasurement() {
        isMeasuring = false
        hasPersistentMeasurement = false
        justFinishedMeasurement = false
        draggingEndpoint = nil
        currentPoint1 = nil
        currentPoint2 = nil
        startCoordinate = nil
        endCoordinate = nil
        resumeMapGestures()
        clearMeasurementRendering()
    }

    func disable() {
        clearMeasurement()

        guard let mapView = mapView else { return }
        if let recognizer = twoFingerLongPressRecognizer {
            mapView.removeGestureRecognizer(recognizer)
        }
        if let recognizer = endpointPanRecognizer {
            mapView.removeGestureRecognizer(recognizer)
        }
        twoFingerLongPressRecognizer = nil
        endpointPanRecognizer = nil
    }

    func ensureMeasurementLayersOnTop() {
        setupMeasurementLayers()

        guard let style = mapView?.style else { return }
        guard let topLayer = topNonMeasurementLayer(in: style) else { return }

        repositionLayer(Self.lineLayerId, above: topLayer.identifier, in: style)
        repositionLayer(Self.endpointLayerId, above: Self.lineLayerId, in: style)
        repositionLayer(Self.distanceLayerId, above: Self.endpointLayerId, in: style)
        repositionLayer(Self.startBearingLayerId, above: Self.distanceLayerId, in: style)
        repositionLayer(Self.endBearingLayerId, above: Self.startBearingLayerId, in: style)

        if hasPersistentMeasurement,
           let startCoordinate = startCoordinate,
           let endCoordinate = endCoordinate {
            _ = renderMeasurement(start: startCoordinate, end: endCoordinate, force: true)
        }
    }

    func handleMapTap(at point: CGPoint) -> Bool {
        guard hasPersistentMeasurement,
              !isMeasuring,
              !isInCleanupGracePeriod(),
              endpoint(at: point) == nil else {
            return false
        }

        clearMeasurement()
        return true
    }

    private func setupGestureRecognizers(on mapView: MLNMapView) {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTwoFingerLongPress(_:)))
        longPress.numberOfTouchesRequired = 2
        longPress.minimumPressDuration = Self.holdDuration
        longPress.allowableMovement = Self.movementThreshold
        longPress.delegate = self
        mapView.addGestureRecognizer(longPress)
        twoFingerLongPressRecognizer = longPress

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEndpointPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        mapView.addGestureRecognizer(pan)
        endpointPanRecognizer = pan
    }

    @objc private func handleTwoFingerLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let mapView = mapView else { return }

        switch recognizer.state {
        case .began:
            guard recognizer.numberOfTouches >= 2 else { return }
            currentPoint1 = recognizer.location(ofTouch: 0, in: mapView)
            currentPoint2 = recognizer.location(ofTouch: 1, in: mapView)
            gestureStartDate = Date()
            startMeasurement()
        case .changed:
            guard isMeasuring, recognizer.numberOfTouches >= 2 else { return }
            currentPoint1 = recognizer.location(ofTouch: 0, in: mapView)
            currentPoint2 = recognizer.location(ofTouch: 1, in: mapView)
            updateMeasurement()
        case .ended:
            if isMeasuring {
                endMeasurement()
            }
        case .cancelled, .failed:
            if isMeasuring {
                endMeasurement()
            } else {
                clearTransientGestureState()
            }
        default:
            break
        }
    }

    @objc private func handleEndpointPan(_ recognizer: UIPanGestureRecognizer) {
        guard let mapView = mapView else { return }

        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

        switch recognizer.state {
        case .began:
            guard let endpoint = endpoint(at: point) else { return }
            draggingEndpoint = endpoint
            suspendMapGestures()
        case .changed:
            guard let draggingEndpoint = draggingEndpoint else { return }
            if draggingEndpoint == .start {
                startCoordinate = coordinate
            } else {
                endCoordinate = coordinate
            }
            guard let startCoordinate = startCoordinate,
                  let endCoordinate = endCoordinate else { return }
            _ = renderMeasurement(start: startCoordinate, end: endCoordinate)
            sendPersistentUpdate()
        case .ended, .cancelled, .failed:
            if draggingEndpoint != nil {
                sendPersistentEnd()
            }
            draggingEndpoint = nil
            resumeMapGestures()
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === endpointPanRecognizer {
            guard hasPersistentMeasurement,
                  !isMeasuring,
                  let mapView = mapView else {
                return false
            }
            let point = gestureRecognizer.location(in: mapView)
            return endpoint(at: point) != nil
        }

        return true
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    private func startMeasurement() {
        guard let mapView = mapView,
              let point1 = currentPoint1,
              let point2 = currentPoint2 else {
            return
        }

        ensureMeasurementLayersOnTop()
        suspendMapGestures()

        let coordinate1 = mapView.convert(point1, toCoordinateFrom: mapView)
        let coordinate2 = mapView.convert(point2, toCoordinateFrom: mapView)
        startCoordinate = coordinate1
        endCoordinate = coordinate2
        isMeasuring = true
        hasPersistentMeasurement = false

        _ = renderMeasurement(start: coordinate1, end: coordinate2, force: true)

        if let event = measurementEvent(point1: point1, point2: point2, duration: currentDurationMilliseconds()) {
            delegate?.nativeMeasurementDetector(self, didStart: event)
        }
    }

    private func updateMeasurement() {
        guard let mapView = mapView,
              let point1 = currentPoint1,
              let point2 = currentPoint2 else {
            return
        }

        let coordinate1 = mapView.convert(point1, toCoordinateFrom: mapView)
        let coordinate2 = mapView.convert(point2, toCoordinateFrom: mapView)
        startCoordinate = coordinate1
        endCoordinate = coordinate2

        guard renderMeasurement(start: coordinate1, end: coordinate2) else { return }

        if let event = measurementEvent(point1: point1, point2: point2, duration: currentDurationMilliseconds()) {
            delegate?.nativeMeasurementDetector(self, didUpdate: event)
        }
    }

    private func endMeasurement() {
        guard let point1 = currentPoint1,
              let point2 = currentPoint2,
              let startCoordinate = startCoordinate,
              let endCoordinate = endCoordinate else {
            clearTransientGestureState()
            resumeMapGestures()
            return
        }

        hasPersistentMeasurement = true
        justFinishedMeasurement = true
        measurementEndDate = Date()
        _ = renderMeasurement(start: startCoordinate, end: endCoordinate, force: true)

        if let event = measurementEvent(point1: point1, point2: point2, duration: currentDurationMilliseconds()) {
            delegate?.nativeMeasurementDetector(self, didEnd: event)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cleanupGracePeriod) { [weak self] in
            self?.justFinishedMeasurement = false
        }

        clearTransientGestureState()
        resumeMapGestures()
    }

    private func sendPersistentUpdate() {
        guard let mapView = mapView,
              let startCoordinate = startCoordinate,
              let endCoordinate = endCoordinate else {
            return
        }

        let point1 = mapView.convert(startCoordinate, toPointTo: mapView)
        let point2 = mapView.convert(endCoordinate, toPointTo: mapView)
        if let event = measurementEvent(point1: point1, point2: point2, duration: 0) {
            delegate?.nativeMeasurementDetector(self, didUpdate: event)
        }
    }

    private func sendPersistentEnd() {
        guard let mapView = mapView,
              let startCoordinate = startCoordinate,
              let endCoordinate = endCoordinate else {
            return
        }

        let point1 = mapView.convert(startCoordinate, toPointTo: mapView)
        let point2 = mapView.convert(endCoordinate, toPointTo: mapView)
        if let event = measurementEvent(point1: point1, point2: point2, duration: 0) {
            delegate?.nativeMeasurementDetector(self, didEnd: event)
        }
    }

    private func measurementEvent(point1: CGPoint, point2: CGPoint, duration: Int) -> NativeMeasurementEvent? {
        guard let startCoordinate = startCoordinate,
              let endCoordinate = endCoordinate else {
            return nil
        }

        return NativeMeasurementEvent(
            point1: point1,
            point2: point2,
            coordinate1: startCoordinate,
            coordinate2: endCoordinate,
            distance: calculateDistanceNauticalMiles(from: startCoordinate, to: endCoordinate),
            bearing: calculateBearing(from: startCoordinate, to: endCoordinate),
            duration: duration
        )
    }

    private func currentDurationMilliseconds() -> Int {
        guard let gestureStartDate = gestureStartDate else { return 0 }
        return max(0, Int(Date().timeIntervalSince(gestureStartDate) * 1000))
    }

    private func clearTransientGestureState() {
        isMeasuring = false
        currentPoint1 = nil
        currentPoint2 = nil
        gestureStartDate = nil
    }

    private func isInCleanupGracePeriod() -> Bool {
        guard justFinishedMeasurement,
              let measurementEndDate = measurementEndDate else {
            return false
        }
        return Date().timeIntervalSince(measurementEndDate) < Self.cleanupGracePeriod
    }

    private func suspendMapGestures() {
        guard suspendedGestures == nil,
              let mapView = mapView else {
            return
        }

        suspendedGestures = SuspendedGestures(
            scrolling: mapView.allowsScrolling,
            zooming: mapView.allowsZooming,
            rotating: mapView.allowsRotating,
            tilting: mapView.allowsTilting
        )
        mapView.allowsScrolling = false
        mapView.allowsZooming = false
        mapView.allowsRotating = false
        mapView.allowsTilting = false
    }

    private func resumeMapGestures() {
        guard let suspendedGestures = suspendedGestures,
              let mapView = mapView else {
            return
        }

        mapView.allowsScrolling = suspendedGestures.scrolling
        mapView.allowsZooming = suspendedGestures.zooming
        mapView.allowsRotating = suspendedGestures.rotating
        mapView.allowsTilting = suspendedGestures.tilting
        self.suspendedGestures = nil
    }

    private func endpoint(at point: CGPoint) -> DraggingEndpoint? {
        guard let mapView = mapView,
              let startCoordinate = startCoordinate,
              let endCoordinate = endCoordinate else {
            return nil
        }

        let startPoint = mapView.convert(startCoordinate, toPointTo: mapView)
        let endPoint = mapView.convert(endCoordinate, toPointTo: mapView)
        if distanceBetween(point, startPoint) <= Self.markerTouchRadius {
            return .start
        }
        if distanceBetween(point, endPoint) <= Self.markerTouchRadius {
            return .end
        }
        return nil
    }

    private func initializeMeasurementLayers() {
        setupMeasurementLayers()
    }

    private func setupMeasurementLayers() {
        guard let style = mapView?.style else { return }

        if style.source(withIdentifier: Self.sourceId) == nil {
            style.addSource(MLNShapeSource(identifier: Self.sourceId, shape: nil, options: nil))
        }

        guard let source = style.source(withIdentifier: Self.sourceId) else { return }

        if style.layer(withIdentifier: Self.lineLayerId) == nil {
            let layer = MLNLineStyleLayer(identifier: Self.lineLayerId, source: source)
            applyLineStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "line")

            if let topLayer = topNonMeasurementLayer(in: style) {
                style.insertLayer(layer, above: topLayer)
            } else {
                style.addLayer(layer)
            }
        }

        if style.layer(withIdentifier: Self.endpointLayerId) == nil {
            let layer = MLNCircleStyleLayer(identifier: Self.endpointLayerId, source: source)
            applyEndpointStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "endpoint")
            insertLayer(layer, aboveLayerId: Self.lineLayerId, in: style)
        }

        if style.layer(withIdentifier: Self.distanceLayerId) == nil {
            let layer = MLNSymbolStyleLayer(identifier: Self.distanceLayerId, source: source)
            applyDistanceLabelStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "distance")
            insertLayer(layer, aboveLayerId: Self.endpointLayerId, in: style)
        }

        if style.layer(withIdentifier: Self.startBearingLayerId) == nil {
            let layer = MLNSymbolStyleLayer(identifier: Self.startBearingLayerId, source: source)
            applyBearingLabelStyle(to: layer, offsetY: -1.05)
            layer.predicate = NSPredicate(format: "type == %@", "start-bearing")
            insertLayer(layer, aboveLayerId: Self.distanceLayerId, in: style)
        }

        if style.layer(withIdentifier: Self.endBearingLayerId) == nil {
            let layer = MLNSymbolStyleLayer(identifier: Self.endBearingLayerId, source: source)
            applyBearingLabelStyle(to: layer, offsetY: 1.05)
            layer.predicate = NSPredicate(format: "type == %@", "end-bearing")
            insertLayer(layer, aboveLayerId: Self.startBearingLayerId, in: style)
        }
    }

    private func insertLayer(_ layer: MLNStyleLayer, aboveLayerId: String, in style: MLNStyle) {
        if let aboveLayer = style.layer(withIdentifier: aboveLayerId) {
            style.insertLayer(layer, above: aboveLayer)
        } else {
            style.addLayer(layer)
        }
    }

    private func renderMeasurement(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        force: Bool = false
    ) -> Bool {
        setupMeasurementLayers()

        guard let mapView = mapView,
              let style = mapView.style,
              let source = style.source(withIdentifier: Self.sourceId) as? MLNShapeSource else {
            return false
        }

        let startPoint = mapView.convert(start, toPointTo: mapView)
        let endPoint = mapView.convert(end, toPointTo: mapView)
        if !force && !shouldRender(startPoint: startPoint, endPoint: endPoint) {
            return false
        }

        var lineCoordinates = [start, end]
        let lineFeature = MLNPolylineFeature(coordinates: &lineCoordinates, count: UInt(lineCoordinates.count))
        lineFeature.attributes = ["type": "line"]

        let startFeature = pointFeature(coordinate: start, attributes: ["type": "endpoint"])
        let endFeature = pointFeature(coordinate: end, attributes: ["type": "endpoint"])

        let distance = calculateDistanceNauticalMiles(from: start, to: end)
        let bearing = calculateBearing(from: start, to: end)
        let reciprocalBearing = fmod(bearing + 180.0, 360.0)
        let labelRotation = calculateLineTextRotation(bearing)

        let distanceFeature = pointFeature(
            coordinate: interpolateCoordinate(start: start, end: end, fraction: 0.5),
            attributes: [
                "type": "distance",
                "labelText": String(format: "%.1f NM", distance)
            ]
        )
        let startBearingFeature = pointFeature(
            coordinate: interpolateCoordinate(start: start, end: end, fraction: 0.12),
            attributes: [
                "type": "start-bearing",
                "labelText": String(format: "%03.0f°", bearing),
                "labelRotation": labelRotation
            ]
        )
        let endBearingFeature = pointFeature(
            coordinate: interpolateCoordinate(start: start, end: end, fraction: 0.88),
            attributes: [
                "type": "end-bearing",
                "labelText": String(format: "%03.0f°", reciprocalBearing),
                "labelRotation": labelRotation
            ]
        )

        source.shape = MLNShapeCollectionFeature(shapes: [
            lineFeature,
            startFeature,
            endFeature,
            distanceFeature,
            startBearingFeature,
            endBearingFeature
        ])
        lastRenderedStartPoint = startPoint
        lastRenderedEndPoint = endPoint
        return true
    }

    private func shouldRender(startPoint: CGPoint, endPoint: CGPoint) -> Bool {
        guard let lastRenderedStartPoint = lastRenderedStartPoint,
              let lastRenderedEndPoint = lastRenderedEndPoint else {
            return true
        }
        return distanceBetween(lastRenderedStartPoint, startPoint) >= Self.renderMovementThreshold
            || distanceBetween(lastRenderedEndPoint, endPoint) >= Self.renderMovementThreshold
    }

    private func clearMeasurementRendering() {
        guard let style = mapView?.style,
              let source = style.source(withIdentifier: Self.sourceId) as? MLNShapeSource else {
            return
        }
        source.shape = nil
        lastRenderedStartPoint = nil
        lastRenderedEndPoint = nil
    }

    private func updateMeasurementLayerStyle() {
        guard let style = mapView?.style else { return }

        if let layer = style.layer(withIdentifier: Self.lineLayerId) as? MLNLineStyleLayer {
            applyLineStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "line")
        }
        if let layer = style.layer(withIdentifier: Self.endpointLayerId) as? MLNCircleStyleLayer {
            applyEndpointStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "endpoint")
        }
        if let layer = style.layer(withIdentifier: Self.distanceLayerId) as? MLNSymbolStyleLayer {
            applyDistanceLabelStyle(to: layer)
            layer.predicate = NSPredicate(format: "type == %@", "distance")
        }
        if let layer = style.layer(withIdentifier: Self.startBearingLayerId) as? MLNSymbolStyleLayer {
            applyBearingLabelStyle(to: layer, offsetY: -1.05)
            layer.predicate = NSPredicate(format: "type == %@", "start-bearing")
        }
        if let layer = style.layer(withIdentifier: Self.endBearingLayerId) as? MLNSymbolStyleLayer {
            applyBearingLabelStyle(to: layer, offsetY: 1.05)
            layer.predicate = NSPredicate(format: "type == %@", "end-bearing")
        }
    }

    private func applyLineStyle(to layer: MLNLineStyleLayer) {
        layer.lineColor = NSExpression(forConstantValue: parseColor(lineColor))
        layer.lineWidth = NSExpression(forConstantValue: lineWidth)
        layer.lineOpacity = NSExpression(forConstantValue: lineOpacity)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
    }

    private func applyEndpointStyle(to layer: MLNCircleStyleLayer) {
        layer.circleColor = NSExpression(forConstantValue: parseColor(endpointColor))
        layer.circleRadius = NSExpression(forConstantValue: endpointRadius)
        layer.circleOpacity = NSExpression(forConstantValue: 1.0)
        layer.circleStrokeColor = NSExpression(forConstantValue: parseColor(lineColor))
        layer.circleStrokeWidth = NSExpression(forConstantValue: 3.0)
        layer.circleStrokeOpacity = NSExpression(forConstantValue: 1.0)
    }

    private func applyDistanceLabelStyle(to layer: MLNSymbolStyleLayer) {
        layer.text = NSExpression(forKeyPath: "labelText")
        layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
        layer.textFontSize = NSExpression(forConstantValue: 15.0)
        layer.textColor = NSExpression(forConstantValue: UIColor.white)
        layer.textHaloColor = NSExpression(forConstantValue: parseColor("#07111F"))
        layer.textHaloWidth = NSExpression(forConstantValue: 2.2)
        layer.textAnchor = NSExpression(forConstantValue: "center")
        layer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: -1.5))
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
    }

    private func applyBearingLabelStyle(to layer: MLNSymbolStyleLayer, offsetY: CGFloat) {
        layer.text = NSExpression(forKeyPath: "labelText")
        layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
        layer.textFontSize = NSExpression(forConstantValue: 15.0)
        layer.textColor = NSExpression(forConstantValue: UIColor.white)
        layer.textHaloColor = NSExpression(forConstantValue: parseColor("#07111F"))
        layer.textHaloWidth = NSExpression(forConstantValue: 2.0)
        layer.textAnchor = NSExpression(forConstantValue: "center")
        layer.textOffset = NSExpression(forConstantValue: CGVector(dx: 0.0, dy: offsetY))
        layer.textRotation = NSExpression(forKeyPath: "labelRotation")
        layer.textRotationAlignment = NSExpression(forConstantValue: "map")
        layer.textPitchAlignment = NSExpression(forConstantValue: "map")
        layer.keepsTextUpright = NSExpression(forConstantValue: true)
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
    }

    private func pointFeature(coordinate: CLLocationCoordinate2D, attributes: [String: Any]) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = coordinate
        feature.attributes = attributes
        return feature
    }

    private func topNonMeasurementLayer(in style: MLNStyle) -> MLNStyleLayer? {
        return style.layers.reversed().first { layer in
            !layer.identifier.hasPrefix("measurement-")
        }
    }

    private func repositionLayer(_ layerId: String, above aboveLayerId: String, in style: MLNStyle) {
        guard layerId != aboveLayerId,
              let layer = style.layer(withIdentifier: layerId),
              style.layer(withIdentifier: aboveLayerId) != nil else {
            return
        }

        style.removeLayer(layer)
        if let aboveLayer = style.layer(withIdentifier: aboveLayerId) {
            style.insertLayer(layer, above: aboveLayer)
        } else {
            style.addLayer(layer)
        }
    }

    private func parseColor(_ colorString: String) -> UIColor {
        var colorString = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        if colorString.hasPrefix("#") {
            colorString.removeFirst()
        }

        guard colorString.count == 6 else {
            return UIColor.red
        }

        var rgbValue: UInt64 = 0
        Scanner(string: colorString).scanHexInt64(&rgbValue)

        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }

    private func calculateDistanceNauticalMiles(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let earthRadiusNm = 3440.065
        let dLat = degreesToRadians(to.latitude - from.latitude)
        let dLon = degreesToRadians(to.longitude - from.longitude)
        let fromLat = degreesToRadians(from.latitude)
        let toLat = degreesToRadians(to.latitude)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(fromLat) * cos(toLat) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusNm * c
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLon = degreesToRadians(to.longitude - from.longitude)
        let fromLat = degreesToRadians(from.latitude)
        let toLat = degreesToRadians(to.latitude)

        let y = sin(dLon) * cos(toLat)
        let x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(dLon)
        return fmod(radiansToDegrees(atan2(y, x)) + 360.0, 360.0)
    }

    private func calculateLineTextRotation(_ bearing: Double) -> Double {
        var rotation = fmod(bearing - 90.0, 360.0)
        if rotation < 0.0 {
            rotation += 360.0
        }
        if rotation > 90.0 && rotation < 270.0 {
            rotation = fmod(rotation + 180.0, 360.0)
        }
        return rotation
    }

    private func interpolateCoordinate(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        var longitudeDelta = end.longitude - start.longitude
        if longitudeDelta > 180.0 {
            longitudeDelta -= 360.0
        } else if longitudeDelta < -180.0 {
            longitudeDelta += 360.0
        }

        let latitude = start.latitude + ((end.latitude - start.latitude) * fraction)
        var longitude = start.longitude + (longitudeDelta * fraction)
        if longitude > 180.0 {
            longitude -= 360.0
        } else if longitude < -180.0 {
            longitude += 360.0
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func distanceBetween(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt((dx * dx) + (dy * dy))
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        return degrees * .pi / 180.0
    }

    private func radiansToDegrees(_ radians: Double) -> Double {
        return radians * 180.0 / .pi
    }
}
