import Foundation
import MapLibre
import UIKit

/**
 * Protocol for handling polyline gesture events.
 */
protocol PolylineGestureHandlerDelegate: AnyObject {
    func onPolylineBroken(lineId: String, breakPoint: CLLocationCoordinate2D, segment1: [CLLocationCoordinate2D], segment2: [CLLocationCoordinate2D])
    func onPolylineModified(lineId: String, newCoordinates: [CLLocationCoordinate2D])
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
    
    // Gesture configuration
    private let longPressMinimumDuration: TimeInterval = 0.5
    private let hitTestTolerance: CGFloat = 20.0
    
    init(mapView: MLNMapView, editingManager: PolylineEditingManager, breakPointSystem: PolylineBreakPointSystem, renderer: EditablePolylineRenderer) {
        self.mapView = mapView
        self.editingManager = editingManager
        self.breakPointSystem = breakPointSystem
        self.renderer = renderer
        self.errorHandler = PolylineEditingErrorHandler()
        
        super.init()
        
        setupGestureRecognizers()
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
            updateDragging(to: coordinate)
        case .ended, .cancelled:
            endDragging(at: coordinate)
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
            
            // Store original coordinates
            if let config = editingManager.getLineConfig(lineId: breakPoint.parentLineId) {
                originalCoordinates = config.coordinates
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
            
            NSLog("\(PolylineGestureHandler.TAG): Started dragging break point \(breakPoint.id)")
        }
    }
    
    /**
     * Updates the dragging operation.
     */
    private func updateDragging(to coordinate: CLLocationCoordinate2D) {
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
        
        // Update preview line
        let newCoordinates = calculateNewCoordinates(breakPoint: updatedBreakPoint, originalCoordinates: originalCoordinates)
        renderer.showPreviewLine(lineId: breakPoint.parentLineId, coordinates: newCoordinates)
    }
    
    /**
     * Ends the dragging operation.
     */
    private func endDragging(at coordinate: CLLocationCoordinate2D) {
        guard isDragging, let breakPoint = currentBreakPoint, let lineId = currentEditingLineId else { return }
        
        // Calculate final coordinates
        let finalCoordinates = calculateNewCoordinates(breakPoint: breakPoint, originalCoordinates: originalCoordinates)
        
        // Update the line coordinates
        editingManager.updateLineCoordinates(lineId: lineId, coordinates: finalCoordinates)
        
        // Hide visual elements
        renderer.hideBreakPoint(lineId: lineId)
        renderer.hidePreviewLine(lineId: lineId)
        
        // Notify delegate
        delegate?.onPolylineModified(lineId: lineId, newCoordinates: finalCoordinates)
        
        // Clean up state
        isDragging = false
        currentBreakPoint = nil
        currentEditingLineId = nil
        originalCoordinates = []
        
        NSLog("\(PolylineGestureHandler.TAG): Finished dragging, updated line \(lineId) with \(finalCoordinates.count) coordinates")
    }
    
    /**
     * Creates a break point on a polyline.
     */
    private func createBreakPoint(lineId: String, coordinate: CLLocationCoordinate2D, segmentIndex: Int, distanceAlongSegment: Double) {
        guard let config = editingManager.getLineConfig(lineId: lineId) else {
            delegate?.onPolylineEditingError(lineId: lineId, error: "Line configuration not found")
            return
        }
        
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
                
                let distance = sqrt(pow(point.x - closestPoint.x, 2) + pow(point.y - closestPoint.y, 2))
                
                if distance <= hitTestTolerance {
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
        
        var newCoordinates = originalCoordinates
        
        // Insert the break point coordinate at the appropriate position
        let insertIndex = breakPoint.segmentIndex + 1
        if insertIndex <= newCoordinates.count {
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
        
        NSLog("\(PolylineGestureHandler.TAG): Cleaned up gesture recognizers")
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PolylineGestureHandler: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition with map gestures
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle touches if we have editable lines
        return !editingManager.getEditableLineIds().isEmpty
    }
}