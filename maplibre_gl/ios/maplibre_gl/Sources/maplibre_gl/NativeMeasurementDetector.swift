import Foundation
import MapLibre
import UIKit

/**
 * iOS native two-finger measurement detector that provides measurement functionality
 * with gesture detection, calculation, and rendering equivalent to Android implementation.
 */
@objc class NativeMeasurementDetector: NSObject {
    private static let TAG = "NativeMeasurementDetector"
    private static let HOLD_DURATION: TimeInterval = 0.5 // 500ms hold duration
    private static let MOVEMENT_THRESHOLD: CGFloat = 50.0 // pixels
    
    // MapLibre style constants for measurement rendering
    private static let MEASUREMENT_SOURCE_ID = "measurement-source"
    private static let MEASUREMENT_LINE_LAYER_ID = "measurement-line-layer"
    private static let MEASUREMENT_POINTS_LAYER_ID = "measurement-points-layer"
    private static let MEASUREMENT_DISTANCE_LAYER_ID = "measurement-distance-layer"
    private static let MEASUREMENT_BEARING_LAYER_ID = "measurement-bearing-layer"
    private static let MEASUREMENT_ARROWS_LAYER_ID = "measurement-arrows-layer"
    
    private let mapView: MLNMapView
    private weak var listener: NativeMeasurementListener?
    
    // Gesture state
    private var isTwoFingerDown = false
    private var initialPoint1: CGPoint = .zero
    private var initialPoint2: CGPoint = .zero
    private var currentPoint1: CGPoint = .zero
    private var currentPoint2: CGPoint = .zero
    private var gestureStartTime: TimeInterval = 0
    private var holdTimer: Timer?
    
    // Measurement state
    private var isMeasuring = false
    private var hasPersistentMeasurement = false
    private var startLatLng: CLLocationCoordinate2D = CLLocationCoordinate2D()
    private var endLatLng: CLLocationCoordinate2D = CLLocationCoordinate2D()
    
    // Dragging state for persistent measurement
    private var isDraggingStart = false
    private var isDraggingEnd = false
    private static let MARKER_TOUCH_RADIUS: CGFloat = 30.0 // pixels
    
    // Track if we just finished creating a measurement to prevent immediate cleanup
    private var justFinishedMeasurement = false
    private var measurementEndTime: TimeInterval = 0
    private static let CLEANUP_GRACE_PERIOD: TimeInterval = 0.5 // 500ms grace period
    
    // Track when user is performing a tap-to-clear gesture
    private var pendingClearGesture = false
    private var initialTouchPoint: CGPoint = .zero
    private static let TAP_MOVEMENT_THRESHOLD: CGFloat = 20.0 // pixels - max movement for tap vs pan
    
    // Measurement style configuration - Aviation-friendly colors
    private var lineColor = "#00BFFF"        // Deep sky blue - highly visible on most map backgrounds
    private var lineWidth = 4.0              // Slightly thicker for better visibility
    private var lineOpacity = 0.9            // Higher opacity for better contrast
    private var endpointColor = "#FF4500"    // Orange red - aviation standard for important markers
    private var endpointRadius = 14.0        // Larger for better touch targeting and visibility
    
    // Gesture recognizers
    private var twoFingerLongPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    
    init(mapView: MLNMapView, listener: NativeMeasurementListener?) {
        self.mapView = mapView
        self.listener = listener
        super.init()
        
        // Initialize measurement style layers
        initializeMeasurementLayers()
        setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        // Two-finger long press for starting measurement
        twoFingerLongPressGestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleTwoFingerLongPress(_:))
        )
        twoFingerLongPressGestureRecognizer?.numberOfTouchesRequired = 2
        twoFingerLongPressGestureRecognizer?.minimumPressDuration = NativeMeasurementDetector.HOLD_DURATION
        twoFingerLongPressGestureRecognizer?.delegate = self
        
        // Pan gesture for updating measurement during creation and dragging markers
        panGestureRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePanGesture(_:))
        )
        panGestureRecognizer?.delegate = self
        panGestureRecognizer?.maximumNumberOfTouches = 1 // Only single finger for dragging markers
        
        // Tap gesture for clearing measurement
        tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTapGesture(_:))
        )
        tapGestureRecognizer?.delegate = self
        tapGestureRecognizer?.numberOfTouchesRequired = 1
        
        if let twoFingerLongPress = twoFingerLongPressGestureRecognizer {
            mapView.addGestureRecognizer(twoFingerLongPress)
        }
        if let panGesture = panGestureRecognizer {
            mapView.addGestureRecognizer(panGesture)
        }
        if let tapGesture = tapGestureRecognizer {
            mapView.addGestureRecognizer(tapGesture)
        }
        
        // Configure gesture priority - measurement gestures should have higher priority
        setupGesturePriorities()
    }
    
    private func setupGesturePriorities() {
        // Get the map's existing gesture recognizers
        for existingGesture in mapView.gestureRecognizers ?? [] {
            // Our pan gesture should have priority over map pan gestures ONLY when actively measuring
            // This is now handled dynamically in the gesture delegate methods
            // We don't set permanent failure requirements here to avoid blocking map gestures
            
            // Our tap gesture should have priority over map tap gestures ONLY when measurement is visible
            // This is also handled dynamically in the gesture delegate methods
        }
    }
    
    @objc private func handleTwoFingerLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            if gesture.numberOfTouches >= 2 {
                let point1 = gesture.location(ofTouch: 0, in: mapView)
                let point2 = gesture.location(ofTouch: 1, in: mapView)
                startMeasurement(point1: point1, point2: point2)
            }
        case .changed:
            if isMeasuring && gesture.numberOfTouches >= 2 {
                let point1 = gesture.location(ofTouch: 0, in: mapView)
                let point2 = gesture.location(ofTouch: 1, in: mapView)
                updateMeasurement(point1: point1, point2: point2)
            }
        case .ended, .cancelled:
            if isMeasuring {
                endMeasurement()
            }
        default:
            break
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard hasPersistentMeasurement else { return }
        
        let location = gesture.location(in: mapView)
        
        switch gesture.state {
        case .began:
            // Check if touch is near a measurement marker
            let startPoint = mapView.convert(startLatLng, toPointTo: mapView)
            let endPoint = mapView.convert(endLatLng, toPointTo: mapView)
            
            let distanceToStart = distance(from: location, to: startPoint)
            let distanceToEnd = distance(from: location, to: endPoint)
            
            if distanceToStart <= NativeMeasurementDetector.MARKER_TOUCH_RADIUS {
                isDraggingStart = true
            } else if distanceToEnd <= NativeMeasurementDetector.MARKER_TOUCH_RADIUS {
                isDraggingEnd = true
            }
            
        case .changed:
            if isDraggingStart {
                startLatLng = mapView.convert(location, toCoordinateFrom: mapView)
                renderMeasurementLine()
                fireMeasurementUpdate()
            } else if isDraggingEnd {
                endLatLng = mapView.convert(location, toCoordinateFrom: mapView)
                renderMeasurementLine()
                fireMeasurementUpdate()
            }
            
        case .ended, .cancelled:
            isDraggingStart = false
            isDraggingEnd = false
            
        default:
            break
        }
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        if hasPersistentMeasurement {
            clearMeasurement()
        }
    }
    
    private func startMeasurement(point1: CGPoint, point2: CGPoint) {
        print("\(NativeMeasurementDetector.TAG): Starting measurement")
        
        isMeasuring = true
        gestureStartTime = Date().timeIntervalSince1970
        
        currentPoint1 = point1
        currentPoint2 = point2
        
        // Convert screen points to coordinates
        startLatLng = mapView.convert(point1, toCoordinateFrom: mapView)
        endLatLng = mapView.convert(point2, toCoordinateFrom: mapView)
        
        renderMeasurementLine()
        fireMeasurementStart()
    }
    
    private func updateMeasurement(point1: CGPoint, point2: CGPoint) {
        currentPoint1 = point1
        currentPoint2 = point2
        
        // Convert screen points to coordinates
        startLatLng = mapView.convert(point1, toCoordinateFrom: mapView)
        endLatLng = mapView.convert(point2, toCoordinateFrom: mapView)
        
        renderMeasurementLine()
        fireMeasurementUpdate()
    }
    
    private func endMeasurement() {
        print("\(NativeMeasurementDetector.TAG): Ending measurement")
        
        isMeasuring = false
        hasPersistentMeasurement = true
        justFinishedMeasurement = true
        measurementEndTime = Date().timeIntervalSince1970
        
        fireMeasurementEnd()
        
        // Clear the "just finished" flag after grace period
        DispatchQueue.main.asyncAfter(deadline: .now() + NativeMeasurementDetector.CLEANUP_GRACE_PERIOD) {
            self.justFinishedMeasurement = false
        }
    }
    
    private func clearMeasurement() {
        print("\(NativeMeasurementDetector.TAG): Clearing measurement")
        
        isMeasuring = false
        hasPersistentMeasurement = false
        isDraggingStart = false
        isDraggingEnd = false
        
        // Remove measurement layers
        removeMeasurementLayers()
    }
    
    // MARK: - Public Interface
    
    func enable() {
        enableMeasurement(true)
    }
    
    func disable() {
        enableMeasurement(false)
    }
    
    func clear() {
        clearMeasurement()
    }
    
    func updateLineColor(_ color: String) {
        lineColor = color
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func updateLineWidth(_ width: Float) {
        lineWidth = Double(width)
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func updatePointColor(_ color: String) {
        endpointColor = color
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func updatePointRadius(_ radius: Float) {
        endpointRadius = Double(radius)
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func updateLabelColor(_ color: String) {
        // Label color can be updated here if needed
        // For now, labels use predefined colors (white/yellow)
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func updateLabelSize(_ size: Float) {
        // Label size can be updated here if needed
        // For now, labels use predefined sizes
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    // MARK: - Measurement Calculations
    
    private func calculateDistance() -> Double {
        return distanceInNauticalMiles(from: startLatLng, to: endLatLng)
    }
    
    private func calculateBearing() -> Double {
        return bearing(from: startLatLng, to: endLatLng)
    }
    
    private func distanceInNauticalMiles(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let distanceMeters = startLocation.distance(from: endLocation)
        return distanceMeters * 0.000539957 // Convert meters to nautical miles
    }
    
    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let lon2 = end.longitude * .pi / 180.0
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        var bearing = atan2(y, x) * 180.0 / .pi
        bearing = fmod(bearing + 360.0, 360.0)
        
        return bearing
    }
    
    // MARK: - Utility Functions
    
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Event Firing
    
    private func fireMeasurementStart() {
        let distance = calculateDistance()
        let bearing = calculateBearing()
        let duration = Int64((Date().timeIntervalSince1970 - gestureStartTime) * 1000)
        
        listener?.onMeasurementStart(
            point1: currentPoint1,
            point2: currentPoint2,
            latLng1: startLatLng,
            latLng2: endLatLng,
            distance: distance,
            bearing: bearing,
            duration: duration
        )
    }
    
    private func fireMeasurementUpdate() {
        let distance = calculateDistance()
        let bearing = calculateBearing()
        let duration = Int64((Date().timeIntervalSince1970 - gestureStartTime) * 1000)
        
        listener?.onMeasurementUpdate(
            point1: currentPoint1,
            point2: currentPoint2,
            latLng1: startLatLng,
            latLng2: endLatLng,
            distance: distance,
            bearing: bearing,
            duration: duration
        )
    }
    
    private func fireMeasurementEnd() {
        let distance = calculateDistance()
        let bearing = calculateBearing()
        let duration = Int64((Date().timeIntervalSince1970 - gestureStartTime) * 1000)
        
        listener?.onMeasurementEnd(
            point1: currentPoint1,
            point2: currentPoint2,
            latLng1: startLatLng,
            latLng2: endLatLng,
            distance: distance,
            bearing: bearing,
            duration: duration
        )
    }
    
    // MARK: - Layer Management
    
    private func initializeMeasurementLayers() {
        // Layers will be created when first measurement is made
        print("\(NativeMeasurementDetector.TAG): Measurement layers initialized")
    }
    
    private func renderMeasurementLine() {
        guard let style = mapView.style else { return }
        
        // Create GeoJSON for the measurement line
        let lineCoordinates = [
            CLLocationCoordinate2D(latitude: startLatLng.latitude, longitude: startLatLng.longitude),
            CLLocationCoordinate2D(latitude: endLatLng.latitude, longitude: endLatLng.longitude)
        ]
        
        // Remove existing layers and source
        removeMeasurementLayers()
        
        // Create line source
        let lineSource = MLNShapeSource(
            identifier: NativeMeasurementDetector.MEASUREMENT_SOURCE_ID,
            shape: MLNPolyline(coordinates: lineCoordinates, count: UInt(lineCoordinates.count)),
            options: nil
        )
        style.addSource(lineSource)
        
        // Create line layer
        let lineLayer = MLNLineStyleLayer(
            identifier: NativeMeasurementDetector.MEASUREMENT_LINE_LAYER_ID,
            source: lineSource
        )
        lineLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: lineColor))
        lineLayer.lineWidth = NSExpression(forConstantValue: lineWidth)
        lineLayer.lineOpacity = NSExpression(forConstantValue: lineOpacity)
        
        style.addLayer(lineLayer)
        
        // Create points for start and end markers
        let startPoint = MLNPointFeature()
        startPoint.coordinate = startLatLng
        let endPoint = MLNPointFeature()
        endPoint.coordinate = endLatLng
        
        let pointsSource = MLNShapeSource(
            identifier: NativeMeasurementDetector.MEASUREMENT_POINTS_LAYER_ID + "-source",
            features: [startPoint, endPoint],
            options: nil
        )
        style.addSource(pointsSource)
        
        let pointsLayer = MLNCircleStyleLayer(
            identifier: NativeMeasurementDetector.MEASUREMENT_POINTS_LAYER_ID,
            source: pointsSource
        )
        pointsLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: endpointColor))
        pointsLayer.circleRadius = NSExpression(forConstantValue: endpointRadius)
        
        style.addLayer(pointsLayer)
        
        // Add distance and bearing labels
        addMeasurementLabels()
    }
    
    private func addMeasurementLabels() {
        guard let style = mapView.style else { return }
        
        let distance = calculateDistance()
        let bearing = calculateBearing()
        let reverseBearing = fmod(bearing + 180.0, 360.0)
        
        // Create midpoint for distance label
        let midLat = (startLatLng.latitude + endLatLng.latitude) / 2.0
        let midLon = (startLatLng.longitude + endLatLng.longitude) / 2.0
        let midPoint = MLNPointFeature()
        midPoint.coordinate = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
        midPoint.attributes = ["text": String(format: "%.2f nm", distance)]
        
        // Create bearing labels at endpoints
        let startBearingPoint = MLNPointFeature()
        startBearingPoint.coordinate = startLatLng
        startBearingPoint.attributes = ["text": String(format: "%.0f°", bearing)]
        
        let endBearingPoint = MLNPointFeature()
        endBearingPoint.coordinate = endLatLng
        endBearingPoint.attributes = ["text": String(format: "%.0f°", reverseBearing)]
        
        // Distance label source and layer
        let distanceSource = MLNShapeSource(
            identifier: NativeMeasurementDetector.MEASUREMENT_DISTANCE_LAYER_ID + "-source",
            features: [midPoint],
            options: nil
        )
        style.addSource(distanceSource)
        
        let distanceLayer = MLNSymbolStyleLayer(
            identifier: NativeMeasurementDetector.MEASUREMENT_DISTANCE_LAYER_ID,
            source: distanceSource
        )
        distanceLayer.text = NSExpression(forKeyPath: "text")
        distanceLayer.textColor = NSExpression(forConstantValue: UIColor.white)
        distanceLayer.textHaloColor = NSExpression(forConstantValue: UIColor.black)
        distanceLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
        distanceLayer.textFontSize = NSExpression(forConstantValue: 14.0)
        
        style.addLayer(distanceLayer)
        
        // Bearing labels source and layer
        let bearingSource = MLNShapeSource(
            identifier: NativeMeasurementDetector.MEASUREMENT_BEARING_LAYER_ID + "-source",
            features: [startBearingPoint, endBearingPoint],
            options: nil
        )
        style.addSource(bearingSource)
        
        let bearingLayer = MLNSymbolStyleLayer(
            identifier: NativeMeasurementDetector.MEASUREMENT_BEARING_LAYER_ID,
            source: bearingSource
        )
        bearingLayer.text = NSExpression(forKeyPath: "text")
        bearingLayer.textColor = NSExpression(forConstantValue: UIColor.yellow)
        bearingLayer.textHaloColor = NSExpression(forConstantValue: UIColor.black)
        bearingLayer.textHaloWidth = NSExpression(forConstantValue: 2.0)
        bearingLayer.textFontSize = NSExpression(forConstantValue: 12.0)
        
        style.addLayer(bearingLayer)
    }
    
    private func removeMeasurementLayers() {
        guard let style = mapView.style else { return }
        
        let layerIds = [
            NativeMeasurementDetector.MEASUREMENT_LINE_LAYER_ID,
            NativeMeasurementDetector.MEASUREMENT_POINTS_LAYER_ID,
            NativeMeasurementDetector.MEASUREMENT_DISTANCE_LAYER_ID,
            NativeMeasurementDetector.MEASUREMENT_BEARING_LAYER_ID
        ]
        
        let sourceIds = [
            NativeMeasurementDetector.MEASUREMENT_SOURCE_ID,
            NativeMeasurementDetector.MEASUREMENT_POINTS_LAYER_ID + "-source",
            NativeMeasurementDetector.MEASUREMENT_DISTANCE_LAYER_ID + "-source",
            NativeMeasurementDetector.MEASUREMENT_BEARING_LAYER_ID + "-source"
        ]
        
        for layerId in layerIds {
            if let layer = style.layer(withIdentifier: layerId) {
                style.removeLayer(layer)
            }
        }
        
        for sourceId in sourceIds {
            if let source = style.source(withIdentifier: sourceId) {
                style.removeSource(source)
            }
        }
    }
    
    // MARK: - Style Configuration
    
    func setMeasurementStyle(
        lineColor: String?,
        lineWidth: Double?,
        lineOpacity: Double?,
        endpointColor: String?,
        endpointRadius: Double?
    ) {
        if let lineColor = lineColor {
            self.lineColor = lineColor
        }
        if let lineWidth = lineWidth {
            self.lineWidth = lineWidth
        }
        if let lineOpacity = lineOpacity {
            self.lineOpacity = lineOpacity
        }
        if let endpointColor = endpointColor {
            self.endpointColor = endpointColor
        }
        if let endpointRadius = endpointRadius {
            self.endpointRadius = endpointRadius
        }
        
        // Re-render if measurement is active
        if hasPersistentMeasurement || isMeasuring {
            renderMeasurementLine()
        }
    }
    
    func enableMeasurement(_ enabled: Bool) {
        if !enabled {
            clearMeasurement()
        }
        
        // Enable/disable gesture recognizers
        twoFingerLongPressGestureRecognizer?.isEnabled = enabled
        panGestureRecognizer?.isEnabled = enabled
        tapGestureRecognizer?.isEnabled = enabled
    }
    
    func cleanup() {
        clearMeasurement()
        
        // Remove gesture recognizers
        if let twoFingerLongPress = twoFingerLongPressGestureRecognizer {
            mapView.removeGestureRecognizer(twoFingerLongPress)
        }
        if let panGesture = panGestureRecognizer {
            mapView.removeGestureRecognizer(panGesture)
        }
        if let tapGesture = tapGestureRecognizer {
            mapView.removeGestureRecognizer(tapGesture)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension NativeMeasurementDetector: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // During measurement creation, only allow our two-finger gesture
        if isMeasuring && gestureRecognizer == twoFingerLongPressGestureRecognizer {
            return false // Block all other gestures during measurement creation
        }
        
        // When dragging measurement markers, block all map gestures
        if (isDraggingStart || isDraggingEnd) && gestureRecognizer == panGestureRecognizer {
            return false // Block map gestures while dragging markers
        }
        
        // For other measurement interactions, check if touch is near measurement elements
        if hasPersistentMeasurement && (gestureRecognizer == panGestureRecognizer || gestureRecognizer == tapGestureRecognizer) {
            let location = gestureRecognizer.location(in: mapView)
            if isTouchNearMeasurementElements(location) {
                return false // Block map gestures when touching measurement elements
            }
        }
        
        return true // Allow simultaneous recognition for other cases
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: mapView)
        
        // Two-finger gesture should only work when no persistent measurement exists
        if gestureRecognizer == twoFingerLongPressGestureRecognizer {
            return !hasPersistentMeasurement
        }
        
        // Pan gesture should prioritize measurement interactions only when measurement exists
        if gestureRecognizer == panGestureRecognizer {
            // If no measurement exists, don't interfere with map gestures
            guard hasPersistentMeasurement else { return false }
            return isTouchNearMeasurementElements(location)
        }
        
        // Tap gesture should work for clearing measurement only when measurement exists
        if gestureRecognizer == tapGestureRecognizer {
            return hasPersistentMeasurement
        }
        
        return true
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: mapView)
        
        // Pan gesture should only begin if near measurement elements when measurement exists
        if gestureRecognizer == panGestureRecognizer {
            // If no measurement exists, don't allow our pan gesture to begin
            guard hasPersistentMeasurement else { return false }
            return isTouchNearMeasurementElements(location)
        }
        
        // Tap gesture should only begin when measurement exists
        if gestureRecognizer == tapGestureRecognizer {
            return hasPersistentMeasurement
        }
        
        return true
    }
    
    private func isTouchNearMeasurementElements(_ location: CGPoint) -> Bool {
        guard hasPersistentMeasurement else { return false }
        
        let startPoint = mapView.convert(startLatLng, toPointTo: mapView)
        let endPoint = mapView.convert(endLatLng, toPointTo: mapView)
        
        let distanceToStart = distance(from: location, to: startPoint)
        let distanceToEnd = distance(from: location, to: endPoint)
        
        // Check if touch is near either endpoint
        if distanceToStart <= NativeMeasurementDetector.MARKER_TOUCH_RADIUS || 
           distanceToEnd <= NativeMeasurementDetector.MARKER_TOUCH_RADIUS {
            return true
        }
        
        // Check if touch is near the measurement line
        return isPointNearLine(location, startPoint: startPoint, endPoint: endPoint, threshold: 20.0)
    }
    
    private func isPointNearLine(_ point: CGPoint, startPoint: CGPoint, endPoint: CGPoint, threshold: CGFloat) -> Bool {
        let A = point.x - startPoint.x
        let B = point.y - startPoint.y
        let C = endPoint.x - startPoint.x
        let D = endPoint.y - startPoint.y
        
        let dot = A * C + B * D
        let lenSq = C * C + D * D
        
        guard lenSq != 0 else { return false }
        
        let param = dot / lenSq
        
        let closestPoint: CGPoint
        if param < 0 {
            closestPoint = startPoint
        } else if param > 1 {
            closestPoint = endPoint
        } else {
            closestPoint = CGPoint(
                x: startPoint.x + param * C,
                y: startPoint.y + param * D
            )
        }
        
        let distance = sqrt(pow(point.x - closestPoint.x, 2) + pow(point.y - closestPoint.y, 2))
        return distance <= threshold
    }
}

// MARK: - NativeMeasurementListener Protocol

@objc protocol NativeMeasurementListener: AnyObject {
    func onMeasurementStart(
        point1: CGPoint,
        point2: CGPoint,
        latLng1: CLLocationCoordinate2D,
        latLng2: CLLocationCoordinate2D,
        distance: Double,
        bearing: Double,
        duration: Int64
    )
    
    func onMeasurementUpdate(
        point1: CGPoint,
        point2: CGPoint,
        latLng1: CLLocationCoordinate2D,
        latLng2: CLLocationCoordinate2D,
        distance: Double,
        bearing: Double,
        duration: Int64
    )
    
    func onMeasurementEnd(
        point1: CGPoint,
        point2: CGPoint,
        latLng1: CLLocationCoordinate2D,
        latLng2: CLLocationCoordinate2D,
        distance: Double,
        bearing: Double,
        duration: Int64
    )
}

// MARK: - UIColor Extension for Hex Colors

extension UIColor {
    convenience init?(hex: String) {
        let r, g, b, a: CGFloat
        
        var hexColor = hex
        if hexColor.hasPrefix("#") {
            hexColor.removeFirst()
        }
        
        if hexColor.count == 6 {
            hexColor += "FF" // Add alpha if not provided
        }
        
        guard hexColor.count == 8 else {
            return nil
        }
        
        let scanner = Scanner(string: hexColor)
        var hexNumber: UInt64 = 0
        
        guard scanner.scanHexInt64(&hexNumber) else {
            return nil
        }
        
        r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
        g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
        b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
        a = CGFloat(hexNumber & 0x000000ff) / 255
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
