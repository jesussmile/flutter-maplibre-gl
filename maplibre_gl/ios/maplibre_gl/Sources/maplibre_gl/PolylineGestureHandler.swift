import Foundation
import MapLibre
import UIKit

/**
 * Protocol for handling polyline gesture events.
 */
protocol PolylineGestureHandlerDelegate: AnyObject {
    func onPolylineBroken(lineId: String, breakPoint: CLLocationCoordinate2D, segment1: [CLLocationCoordinate2D], segment2: [CLLocationCoordinate2D])
    func onPolylineModified(lineId: String, newCoordinates: [CLLocationCoordinate2D])
    func onPolylineEditCompleted(lineId: String, newCoordinates: [CLLocationCoordinate2D], pointIndex: Int, inserted: Bool)
    func onPolylinePointDeleted(lineId: String, newCoordinates: [CLLocationCoordinate2D], pointIndex: Int, deletedCoordinate: CLLocationCoordinate2D)
    func onPolylineEditingError(lineId: String, error: String)
}

/**
 * Handles gesture recognition for polyline editing using UILongPressGestureRecognizer and UIPanGestureRecognizer.
 * 
 * This class integrates with MLNMapView to detect polyline touches and provides
 * coordinate calculations using CoreLocation for geometric operations.
 */
class PolylineGestureHandler: NSObject {
    private static let TAG = "PolylineGestureHandler"
    
    private let mapView: MLNMapView
    private let editingManager: PolylineEditingManager
    private let breakPointSystem: PolylineBreakPointSystem
    private let renderer: EditablePolylineRenderer
    private let errorHandler: PolylineEditingErrorHandler
    
    weak var delegate: PolylineGestureHandlerDelegate?
    
    // Gesture recognizers
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var panRecognizer: UIPanGestureRecognizer?
    
    // Current editing state
    private var currentEditingLineId: String?
    private var currentBreakPoint: PolylineBreakPoint?
    private var isDragging = false
    private var originalCoordinates: [CLLocationCoordinate2D] = []
    private var deleteZoneView: UIView?
    private var deleteZoneLabel: UILabel?
    private var deleteZoneArmed = false
    private let deleteZoneHeight: CGFloat = 104
    
    // Store original coordinates for each line when break point is created
    private var originalLineCoordinates: [String: [CLLocationCoordinate2D]] = [:]
    
    // Gesture configuration
    private let longPressMinimumDuration: TimeInterval = 0.5
    private var hitTestTolerance: CGFloat = 20.0
    
    init(mapView: MLNMapView, editingManager: PolylineEditingManager, breakPointSystem: PolylineBreakPointSystem, renderer: EditablePolylineRenderer) {
        self.mapView = mapView
        self.editingManager = editingManager
        self.breakPointSystem = breakPointSystem
        self.renderer = renderer
        self.errorHandler = PolylineEditingErrorHandler()
        
        super.init()
        
        setupGestureRecognizers()
    }

    func setHitTestTolerance(_ tolerance: CGFloat) {
        hitTestTolerance = max(1, tolerance)
    }
    
    /**
     * Sets up the gesture recognizers for polyline editing.
     */
    private func setupGestureRecognizers() {
        // Long press gesture for creating break points
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressRecognizer?.minimumPressDuration = longPressMinimumDuration
        longPressRecognizer?.delegate = self
        
        if let longPress = longPressRecognizer {
            mapView.addGestureRecognizer(longPress)
        }
        
        // Pan gesture for dragging break points
        panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panRecognizer?.delegate = self
        
        if let pan = panRecognizer {
            mapView.addGestureRecognizer(pan)
        }
        
        NSLog("\(PolylineGestureHandler.TAG): Gesture recognizers set up")
    }
    
    /**
     * Handles long press gestures to create break points on polylines.
     */
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        
        // Validate touch location
        let touchValidation = errorHandler.validateTouchLocation(point: point, mapBounds: mapView.bounds)
        if !touchValidation.isValid {
            NSLog("\(PolylineGestureHandler.TAG): Invalid touch location: \(touchValidation.errorMessage ?? "Unknown error")")
            return
        }
        
        // Validate coordinates
        let coordValidation = errorHandler.validateCoordinates(coordinate: coordinate)
        if !coordValidation.isValid {
            NSLog("\(PolylineGestureHandler.TAG): Invalid coordinates: \(coordValidation.errorMessage ?? "Unknown error")")
            delegate?.onPolylineEditingError(lineId: "unknown", error: coordValidation.errorMessage ?? "Invalid coordinates")
            return
        }
        
        NSLog("\(PolylineGestureHandler.TAG): Long press detected at \(coordinate.latitude), \(coordinate.longitude)")
        
        do {
            // Find the nearest editable polyline
            if let (lineId, segmentIndex, distanceAlongSegment) = findNearestEditablePolyline(at: point) {
                NSLog("\(PolylineGestureHandler.TAG): Found editable polyline \(lineId) at segment \(segmentIndex)")
                
                // Validate that the line still exists and has valid coordinates
                guard let config = editingManager.getLineConfig(lineId: lineId),
                      config.coordinates.count >= 2 else {
                    NSLog("\(PolylineGestureHandler.TAG): Line \(lineId) is invalid or has insufficient coordinates")
                    delegate?.onPolylineEditingError(lineId: lineId, error: "Invalid polyline coordinates")
                    return
                }
                
                // Create break point
                createBreakPoint(lineId: lineId, coordinate: coordinate, segmentIndex: segmentIndex, distanceAlongSegment: distanceAlongSegment)
                
                // Provide haptic feedback
                if shouldProvideHapticFeedback() {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }
            } else {
                NSLog("\(PolylineGestureHandler.TAG): No editable polyline found at touch location")
            }
        } catch {
            let result = errorHandler.handleError(
                errorType: .geometricCalculationFailure,
                error: error,
                context: "Long press gesture handling",
                retryCallback: nil
            )
            
            if !result.canContinue {
                delegate?.onPolylineEditingError(lineId: "unknown", error: result.message)
            }
        }
    }
    
    /**
     * Handles pan gestures for dragging break points.
     */
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        
        switch recognizer.state {
        case .began:
            startDragging(at: point, coordinate: coordinate)
        case .changed:
            updateDragging(to: coordinate, at: point)
        case .ended, .cancelled:
            endDragging(at: coordinate, screenPoint: point)
        default:
            break
        }
    }
    
    /**
     * Starts a dragging operation.
     */
    private func startDragging(at point: CGPoint, coordinate: CLLocationCoordinate2D) {
        // Check if we're starting to drag a break point
        if let breakPoint = findBreakPointAt(point: point) {
            currentBreakPoint = breakPoint
            currentEditingLineId = breakPoint.parentLineId
            isDragging = true
            
            // Store original coordinates - use the stored original line
            if let config = editingManager.getLineConfig(lineId: breakPoint.parentLineId) {
                originalCoordinates = config.coordinates
                NSLog("\(PolylineGestureHandler.TAG): Using current coordinates: \(originalCoordinates.count) points")
            }
            
            // Update break point state
            let updatedBreakPoint = PolylineBreakPoint(
                id: breakPoint.id,
                parentLineId: breakPoint.parentLineId,
                coordinate: coordinate,
                segmentIndex: breakPoint.segmentIndex,
                distanceAlongSegment: breakPoint.distanceAlongSegment,
                isDragging: true
            )
            currentBreakPoint = updatedBreakPoint
            breakPointSystem.updateBreakPoint(updatedBreakPoint)
            setDeleteZoneVisible(true, armed: false)
            
            NSLog("\(PolylineGestureHandler.TAG): Started dragging break point \(breakPoint.id), original coordinates: \(originalCoordinates.count)")
        }
    }
    
    /**
     * Updates the dragging operation.
     */
    private func updateDragging(to coordinate: CLLocationCoordinate2D, at point: CGPoint) {
        guard isDragging, let breakPoint = currentBreakPoint else { return }
        
        // Update break point coordinate
        let updatedBreakPoint = PolylineBreakPoint(
            id: breakPoint.id,
            parentLineId: breakPoint.parentLineId,
            coordinate: coordinate,
            segmentIndex: breakPoint.segmentIndex,
            distanceAlongSegment: breakPoint.distanceAlongSegment,
            isDragging: true
        )
        currentBreakPoint = updatedBreakPoint
        breakPointSystem.updateBreakPoint(updatedBreakPoint)
        
        // Update break point visual position
        renderer.showBreakPoint(lineId: breakPoint.parentLineId, coordinate: coordinate)
        
        // Calculate new coordinates with the updated break point
        let newCoordinates = calculateNewCoordinates(breakPoint: updatedBreakPoint, originalCoordinates: originalCoordinates)
        
        // Send real-time updates to Flutter during dragging
        // Note: We don't show preview line here since the actual polyline is updated in real-time
        delegate?.onPolylineModified(lineId: breakPoint.parentLineId, newCoordinates: newCoordinates)
        updateDeleteZone(for: point)
        
        NSLog("\(PolylineGestureHandler.TAG): Sent real-time update for line \(breakPoint.parentLineId) with \(newCoordinates.count) coordinates")
    }
    
    /**
     * Ends the dragging operation.
     */
    private func endDragging(at coordinate: CLLocationCoordinate2D, screenPoint: CGPoint) {
        guard isDragging, let breakPoint = currentBreakPoint, let lineId = currentEditingLineId else { return }

        updateDeleteZone(for: screenPoint)
        if deleteZoneArmed {
            let pointIndex = max(1, min(originalCoordinates.count - 2, breakPoint.segmentIndex + 1))
            let inserted = !breakPoint.id.hasPrefix("\(breakPoint.parentLineId):")
            if inserted {
                breakPointSystem.removeBreakPoint(breakPointId: breakPoint.id)
                renderer.hidePreviewLine(lineId: lineId)
                if let config = editingManager.getLineConfig(lineId: lineId) {
                    renderer.syncBreakPoints(
                        lineId: lineId,
                        coordinates: originalCoordinates,
                        lockedPointIndices: config.lockedPointIndices
                    )
                } else {
                    renderer.hideBreakPoint(lineId: lineId)
                }
                delegate?.onPolylineModified(lineId: lineId, newCoordinates: originalCoordinates)
                delegate?.onPolylinePointDeleted(
                    lineId: lineId,
                    newCoordinates: originalCoordinates,
                    pointIndex: pointIndex,
                    deletedCoordinate: breakPoint.coordinate
                )
                if shouldProvideHapticFeedback() {
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.success)
                }
                resetDragState()
                NSLog("\(PolylineGestureHandler.TAG): Cancelled inserted point \(pointIndex) on line \(lineId)")
                return
            }
            if let deleteResult = editingManager.deleteLineCoordinate(
                lineId: lineId,
                pointIndex: pointIndex
            ) {
                breakPointSystem.removeBreakPoint(breakPointId: breakPoint.id)
                renderer.hidePreviewLine(lineId: lineId)
                if let config = editingManager.getLineConfig(lineId: lineId) {
                    renderer.syncBreakPoints(
                        lineId: lineId,
                        coordinates: deleteResult.coordinates,
                        lockedPointIndices: config.lockedPointIndices
                    )
                } else {
                    renderer.hideBreakPoint(lineId: lineId)
                }
                delegate?.onPolylineModified(lineId: lineId, newCoordinates: deleteResult.coordinates)
                delegate?.onPolylinePointDeleted(
                    lineId: lineId,
                    newCoordinates: deleteResult.coordinates,
                    pointIndex: pointIndex,
                    deletedCoordinate: deleteResult.deletedCoordinate
                )
                if shouldProvideHapticFeedback() {
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.success)
                }
                resetDragState()
                NSLog("\(PolylineGestureHandler.TAG): Deleted point \(pointIndex) from line \(lineId)")
                return
            }
        }
        
        // Calculate final coordinates
        let finalCoordinates = calculateNewCoordinates(breakPoint: breakPoint, originalCoordinates: originalCoordinates)
        
        // Update the line coordinates
        editingManager.updateLineCoordinates(lineId: lineId, coordinates: finalCoordinates)
        
        // Hide visual elements
        renderer.hideBreakPoint(lineId: lineId)
        renderer.hidePreviewLine(lineId: lineId)
        
        // Notify delegate
        delegate?.onPolylineModified(lineId: lineId, newCoordinates: finalCoordinates)
        let pointIndex = max(1, min(finalCoordinates.count - 2, breakPoint.segmentIndex + 1))
        let inserted = !breakPoint.id.hasPrefix("\(breakPoint.parentLineId):")
        delegate?.onPolylineEditCompleted(
            lineId: lineId,
            newCoordinates: finalCoordinates,
            pointIndex: pointIndex,
            inserted: inserted
        )
        
        // Clean up state
        resetDragState()
        
        NSLog("\(PolylineGestureHandler.TAG): Finished dragging, updated line \(lineId) with \(finalCoordinates.count) coordinates")
    }

    private func resetDragState() {
        isDragging = false
        currentBreakPoint = nil
        currentEditingLineId = nil
        originalCoordinates = []
        setDeleteZoneVisible(false, armed: false)
    }

    private func updateDeleteZone(for point: CGPoint) {
        let armed = point.y <= deleteZoneHeight
        if armed != deleteZoneArmed && armed && shouldProvideHapticFeedback() {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        setDeleteZoneVisible(true, armed: armed)
    }

    private func setDeleteZoneVisible(_ visible: Bool, armed: Bool) {
        deleteZoneArmed = visible && armed
        if !visible {
            deleteZoneView?.isHidden = true
            return
        }

        if deleteZoneView == nil {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.layer.cornerRadius = 16
            view.layer.masksToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel(frame: .zero)
            label.text = "Release to delete waypoint"
            label.textColor = .white
            label.font = UIFont.boldSystemFont(ofSize: 15)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)

            mapView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 16),
                view.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 16),
                view.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -16),
                view.heightAnchor.constraint(equalToConstant: 72),
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])

            deleteZoneView = view
            deleteZoneLabel = label
        }

        deleteZoneLabel?.text = "Release to delete waypoint"
        if deleteZoneArmed {
            deleteZoneView?.backgroundColor = UIColor(
                red: 0.83,
                green: 0.18,
                blue: 0.18,
                alpha: 0.91
            )
        } else {
            deleteZoneView?.backgroundColor = UIColor(
                red: 0.06,
                green: 0.09,
                blue: 0.16,
                alpha: 0.82
            )
        }
        deleteZoneView?.isHidden = false
        if let deleteZoneView = deleteZoneView {
            mapView.bringSubviewToFront(deleteZoneView)
        }
    }
    
    /**
     * Creates a break point on a polyline.
     */
    private func createBreakPoint(lineId: String, coordinate: CLLocationCoordinate2D, segmentIndex: Int, distanceAlongSegment: Double) {
        guard let config = editingManager.getLineConfig(lineId: lineId) else {
            delegate?.onPolylineEditingError(lineId: lineId, error: "Line configuration not found")
            return
        }
        
        originalLineCoordinates[lineId] = config.coordinates
        
        // Create break point
        let breakPoint = PolylineBreakPoint(
            id: UUID().uuidString,
            parentLineId: lineId,
            coordinate: coordinate,
            segmentIndex: segmentIndex,
            distanceAlongSegment: distanceAlongSegment,
            isDragging: false
        )
        
        // Add to break point system
        breakPointSystem.addBreakPoint(breakPoint)
        
        // Show break point visually
        renderer.showBreakPoint(lineId: lineId, coordinate: coordinate)
        
        // Split the polyline into segments
        let (segment1, segment2) = splitPolylineAtBreakPoint(coordinates: config.coordinates, breakPoint: breakPoint)
        
        // Notify delegate
        delegate?.onPolylineBroken(lineId: lineId, breakPoint: coordinate, segment1: segment1, segment2: segment2)
        
        NSLog("\(PolylineGestureHandler.TAG): Created break point for line \(lineId), split into segments of \(segment1.count) and \(segment2.count) points")
    }
    
    /**
     * Finds the nearest editable polyline to a touch point.
     */
    private func findNearestEditablePolyline(at point: CGPoint) -> (lineId: String, segmentIndex: Int, distanceAlongSegment: Double)? {
        let editableLineIds = editingManager.getEditableLineIds()
        var nearestResult: (lineId: String, segmentIndex: Int, distanceAlongSegment: Double, distance: Double)?
        
        for lineId in editableLineIds {
            guard let config = editingManager.getLineConfig(lineId: lineId) else { continue }
            
            // Check if coordinates are valid for creating segments
            guard config.coordinates.count >= 2 else {
                NSLog("\(PolylineGestureHandler.TAG): Line \(lineId) has insufficient coordinates (\(config.coordinates.count)). Skipping.")
                continue
            }
            
            // Check each segment of the polyline
            for i in 0..<(config.coordinates.count - 1) {
                let start = config.coordinates[i]
                let end = config.coordinates[i + 1]
                
                let startPoint = mapView.convert(start, toPointTo: mapView)
                let endPoint = mapView.convert(end, toPointTo: mapView)
                
                let (closestPoint, distanceAlongSegment) = closestPointOnLineSegment(
                    point: point,
                    lineStart: startPoint,
                    lineEnd: endPoint
                )
                
                let distance = Double(sqrt(pow(point.x - closestPoint.x, 2) + pow(point.y - closestPoint.y, 2)))
                
                if distance <= Double(hitTestTolerance) {
                    if nearestResult == nil || distance < nearestResult!.distance {
                        nearestResult = (lineId: lineId, segmentIndex: i, distanceAlongSegment: distanceAlongSegment, distance: distance)
                    }
                }
            }
        }
        
        if let result = nearestResult {
            return (result.lineId, result.segmentIndex, result.distanceAlongSegment)
        }
        
        return nil
    }
    
    /**
     * Finds a break point at the given screen point.
     */
    private func findBreakPointAt(point: CGPoint) -> PolylineBreakPoint? {
        let breakPoints = breakPointSystem.getAllBreakPoints()
        
        for breakPoint in breakPoints {
            let breakPointScreenPoint = mapView.convert(breakPoint.coordinate, toPointTo: mapView)
            let distance = sqrt(pow(point.x - breakPointScreenPoint.x, 2) + pow(point.y - breakPointScreenPoint.y, 2))
            
            if distance <= hitTestTolerance {
                return breakPoint
            }
        }
        
        return nil
    }
    
    /**
     * Calculates new coordinates after moving a break point.
     */
    private func calculateNewCoordinates(breakPoint: PolylineBreakPoint, originalCoordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard breakPoint.segmentIndex < originalCoordinates.count - 1 else {
            return originalCoordinates
        }
        
        guard originalCoordinates.count >= 2 else {
            return originalCoordinates
        }

        var newCoordinates = originalCoordinates
        let insertIndex = breakPoint.segmentIndex + 1

        let existingHandlePrefix = "\(breakPoint.parentLineId):"
        if breakPoint.id.hasPrefix(existingHandlePrefix),
           insertIndex > 0,
           insertIndex < newCoordinates.count - 1 {
            newCoordinates[insertIndex] = breakPoint.coordinate
        } else if insertIndex > 0 && insertIndex < newCoordinates.count {
            newCoordinates.insert(breakPoint.coordinate, at: insertIndex)
        }

        return newCoordinates
    }
    
    /**
     * Splits a polyline at a break point into two segments.
     */
    private func splitPolylineAtBreakPoint(coordinates: [CLLocationCoordinate2D], breakPoint: PolylineBreakPoint) -> ([CLLocationCoordinate2D], [CLLocationCoordinate2D]) {
        let splitIndex = breakPoint.segmentIndex + 1
        
        var segment1 = Array(coordinates[0..<splitIndex])
        segment1.append(breakPoint.coordinate)
        
        var segment2 = [breakPoint.coordinate]
        segment2.append(contentsOf: coordinates[splitIndex...])
        
        return (segment1, segment2)
    }
    
    /**
     * Calculates the closest point on a line segment to a given point.
     */
    private func closestPointOnLineSegment(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> (closestPoint: CGPoint, distanceAlongSegment: Double) {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        
        if dx == 0 && dy == 0 {
            return (lineStart, 0.0)
        }
        
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx * dx + dy * dy)))
        
        let closestPoint = CGPoint(
            x: lineStart.x + t * dx,
            y: lineStart.y + t * dy
        )
        
        return (closestPoint, Double(t))
    }
    
    /**
     * Checks if haptic feedback should be provided based on the editing style.
     */
    private func shouldProvideHapticFeedback() -> Bool {
        let style = editingManager.getEditingStyle()
        return style["enableHapticFeedback"] as? Bool ?? true
    }
    
    /**
     * Cleans up gesture recognizers.
     */
    func cleanup() {
        if let longPress = longPressRecognizer {
            mapView.removeGestureRecognizer(longPress)
        }
        if let pan = panRecognizer {
            mapView.removeGestureRecognizer(pan)
        }
        
        longPressRecognizer = nil
        panRecognizer = nil
        deleteZoneView?.removeFromSuperview()
        deleteZoneView = nil
        deleteZoneLabel = nil
        
        NSLog("\(PolylineGestureHandler.TAG): Cleaned up gesture recognizers")
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PolylineGestureHandler: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let point = gestureRecognizer.location(in: mapView)
        if gestureRecognizer === longPressRecognizer {
            return findNearestEditablePolyline(at: point) != nil
        }
        if gestureRecognizer === panRecognizer {
            return findBreakPointAt(point: point) != nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition with map gestures
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle touches if we have editable lines
        return !editingManager.getEditableLineIds().isEmpty
    }
}
