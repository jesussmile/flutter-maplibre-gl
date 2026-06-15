import Foundation
import MapLibre

/**
 * Manages polyline editing state and configuration for all polylines on the map.
 * 
 * This class tracks which polylines are editable, stores their editing configuration,
 * and provides methods to enable/disable editing for specific polylines.
 */
class PolylineEditingManager {
    private static let TAG = "PolylineEditingManager"
    
    private let mapView: MLNMapView
    private weak var controller: MapLibreMapController?
    private var editableLines: [String: PolylineEditingConfig] = [:]
    private var globalEditingStyle: [String: Any] = [:]
    
    /**
     * Configuration for an editable polyline.
     */
    struct PolylineEditingConfig {
        let lineId: String
        let enabled: Bool
        let coordinates: [CLLocationCoordinate2D]
        let lockedPointIndices: Set<Int>
        let style: [String: Any]
        
        init(lineId: String, enabled: Bool, coordinates: [CLLocationCoordinate2D] = [], lockedPointIndices: Set<Int> = [], style: [String: Any] = [:]) {
            self.lineId = lineId
            self.enabled = enabled
            self.coordinates = coordinates
            self.lockedPointIndices = lockedPointIndices
            self.style = style
        }
    }
    
    init(mapView: MLNMapView, controller: MapLibreMapController) {
        self.mapView = mapView
        self.controller = controller
        setupDefaultStyle()
    }
    
    /**
     * Sets up default editing style configuration.
     */
    private func setupDefaultStyle() {
        globalEditingStyle = [
            "breakPointColor": "#FF0000",
            "breakPointRadius": 8.0,
            "breakPointBorderColor": "#FFFFFF",
            "breakPointBorderWidth": 2.0,
            "previewLineColor": "#00FF00",
            "previewLineOpacity": 0.7,
            "previewLineWidth": 3.0,
            "enableHapticFeedback": true
        ]
    }
    
    /**
     * Enables or disables editing for a specific polyline.
     *
     * @param lineId The ID of the polyline to enable/disable editing for
     * @param enabled Whether to enable or disable editing
     */
    func enableLineEditing(
        lineId: String,
        enabled: Bool,
        coordinates suppliedCoordinates: [CLLocationCoordinate2D] = [],
        lockedPointIndices: Set<Int> = []
    ) {
        NSLog("\(PolylineEditingManager.TAG): enableLineEditing called for line \(lineId), enabled: \(enabled)")
        
        if enabled {
            // Get coordinates from the map if available
            let coordinates = suppliedCoordinates.isEmpty
                ? getLineCoordinates(lineId: lineId)
                : suppliedCoordinates
            let config = PolylineEditingConfig(
                lineId: lineId,
                enabled: true,
                coordinates: coordinates,
                lockedPointIndices: lockedPointIndices,
                style: globalEditingStyle
            )
            editableLines[lineId] = config
            NSLog("\(PolylineEditingManager.TAG): Enabled editing for line \(lineId) with \(coordinates.count) coordinates")
        } else {
            editableLines.removeValue(forKey: lineId)
            NSLog("\(PolylineEditingManager.TAG): Disabled editing for line \(lineId)")
        }
    }
    
    /**
     * Checks if a polyline is currently editable.
     *
     * @param lineId The ID of the polyline to check
     * @return true if the polyline is editable, false otherwise
     */
    func isLineEditable(lineId: String) -> Bool {
        return editableLines[lineId]?.enabled ?? false
    }
    
    /**
     * Sets the global editing style configuration.
     *
     * @param style A dictionary containing style properties
     */
    func setEditingStyle(style: [String: Any]) {
        NSLog("\(PolylineEditingManager.TAG): setEditingStyle called with \(style.count) properties")
        
        // Merge with existing style
        for (key, value) in style {
            globalEditingStyle[key] = value
        }
        
        // Update all existing editable lines with new style
        for (lineId, config) in editableLines {
            let updatedConfig = PolylineEditingConfig(
                lineId: config.lineId,
                enabled: config.enabled,
                coordinates: config.coordinates,
                lockedPointIndices: config.lockedPointIndices,
                style: globalEditingStyle
            )
            editableLines[lineId] = updatedConfig
        }
        
        NSLog("\(PolylineEditingManager.TAG): Updated editing style for \(editableLines.count) editable lines")
    }
    
    /**
     * Gets the current editing style configuration.
     *
     * @return A dictionary containing the current style properties
     */
    func getEditingStyle() -> [String: Any] {
        return globalEditingStyle
    }
    
    /**
     * Gets all currently editable line IDs.
     *
     * @return A set of line IDs that are currently editable
     */
    func getEditableLineIds() -> Set<String> {
        return Set(editableLines.keys)
    }
    
    /**
     * Gets the configuration for a specific editable line.
     *
     * @param lineId The ID of the line to get configuration for
     * @return The configuration for the line, or nil if not editable
     */
    func getLineConfig(lineId: String) -> PolylineEditingConfig? {
        return editableLines[lineId]
    }
    
    /**
     * Updates the coordinates for an editable line.
     *
     * @param lineId The ID of the line to update
     * @param coordinates The new coordinates for the line
     */
    func updateLineCoordinates(lineId: String, coordinates: [CLLocationCoordinate2D]) {
        guard var config = editableLines[lineId] else {
            NSLog("\(PolylineEditingManager.TAG): Cannot update coordinates for non-editable line \(lineId)")
            return
        }
        
        let updatedConfig = PolylineEditingConfig(
            lineId: config.lineId,
            enabled: config.enabled,
            coordinates: coordinates,
            lockedPointIndices: config.lockedPointIndices,
            style: config.style
        )
        editableLines[lineId] = updatedConfig
        
        NSLog("\(PolylineEditingManager.TAG): Updated coordinates for line \(lineId) with \(coordinates.count) points")
    }

    func deleteLineCoordinate(
        lineId: String,
        pointIndex: Int
    ) -> (coordinates: [CLLocationCoordinate2D], deletedCoordinate: CLLocationCoordinate2D)? {
        guard let config = editableLines[lineId] else {
            NSLog("\(PolylineEditingManager.TAG): Cannot delete coordinate for non-editable line \(lineId)")
            return nil
        }
        guard pointIndex > 0,
              pointIndex < config.coordinates.count - 1,
              !config.lockedPointIndices.contains(pointIndex) else {
            NSLog("\(PolylineEditingManager.TAG): Refusing to delete locked or endpoint point \(pointIndex) for line \(lineId)")
            return nil
        }

        var coordinates = config.coordinates
        let deletedCoordinate = coordinates.remove(at: pointIndex)
        let shiftedLockedIndices = Set(
            config.lockedPointIndices.compactMap { lockedIndex -> Int? in
                if lockedIndex == pointIndex { return nil }
                return lockedIndex > pointIndex ? lockedIndex - 1 : lockedIndex
            }
        )
        editableLines[lineId] = PolylineEditingConfig(
            lineId: config.lineId,
            enabled: config.enabled,
            coordinates: coordinates,
            lockedPointIndices: shiftedLockedIndices,
            style: config.style
        )

        NSLog("\(PolylineEditingManager.TAG): Deleted point \(pointIndex) for line \(lineId); now \(coordinates.count) points")
        return (coordinates, deletedCoordinate)
    }
    
    /**
     * Removes all editing configurations and disables editing for all lines.
     */
    func clearAllEditableLines() {
        let count = editableLines.count
        editableLines.removeAll()
        NSLog("\(PolylineEditingManager.TAG): Cleared \(count) editable lines")
    }
    
    /**
     * Gets the coordinates for a line from the map view by searching through all shape sources.
     *
     * @param lineId The ID of the line to get coordinates for
     * @return An array of coordinates for the line
     */
    private func getLineCoordinates(lineId: String) -> [CLLocationCoordinate2D] {
        guard let style = mapView.style else {
            NSLog("\(PolylineEditingManager.TAG): Map style not available")
            return []
        }
        
        // Strategy 1: Search through stored shapes in the controller (most reliable)
        if let controller = controller {
            let storedShapes = controller.getAllStoredShapes()
            for (sourceId, shape) in storedShapes {
                // Try exact match first
                let coordinates = extractCoordinatesFromShape(shape: shape, targetLineId: lineId)
                if !coordinates.isEmpty {
                    NSLog("\(PolylineEditingManager.TAG): Found coordinates for line \(lineId): \(coordinates.count) points from stored shapes in source \(sourceId)")
                    return coordinates
                }
                
                // If no exact match, try sourceId-based matching (lineId might match sourceId)
                if sourceId == lineId {
                    let coordinates = extractCoordinatesFromAnyShape(shape: shape)
                    if !coordinates.isEmpty {
                        NSLog("\(PolylineEditingManager.TAG): Found coordinates for line \(lineId) by matching sourceId: \(coordinates.count) points")
                        return coordinates
                    }
                }
            }
        }
        
        // Strategy 2: Search through all shape sources
        for source in style.sources {
            if let shapeSource = source as? MLNShapeSource,
               let shape = shapeSource.shape {
                
                // Try exact match first
                let coordinates = extractCoordinatesFromShape(shape: shape, targetLineId: lineId)
                if !coordinates.isEmpty {
                    NSLog("\(PolylineEditingManager.TAG): Found coordinates for line \(lineId): \(coordinates.count) points from shape source")
                    return coordinates
                }
                
                // If no exact match and source identifier matches lineId, extract any polyline coordinates
                if source.identifier == lineId {
                    let coordinates = extractCoordinatesFromAnyShape(shape: shape)
                    if !coordinates.isEmpty {
                        NSLog("\(PolylineEditingManager.TAG): Found coordinates for line \(lineId) by matching source identifier: \(coordinates.count) points")
                        return coordinates
                    }
                }
            }
        }
        
        NSLog("\(PolylineEditingManager.TAG): No coordinates found for line \(lineId)")
        return []
    }
    
    /**
     * Extracts coordinates from an MLNShape, searching for a specific line ID.
     *
     * @param shape The MLNShape to search through
     * @param targetLineId The line ID to search for
     * @return An array of coordinates if found, empty array otherwise
     */
    private func extractCoordinatesFromShape(shape: MLNShape, targetLineId: String) -> [CLLocationCoordinate2D] {
        // Handle different types of MLNShape
        switch shape {
        case let polylineFeature as MLNPolylineFeature:
            // Polyline feature - check if it matches our target ID
            if let identifier = polylineFeature.identifier as? String, identifier == targetLineId {
                return Array(UnsafeBufferPointer(start: polylineFeature.coordinates, count: Int(polylineFeature.pointCount)))
            }
            
        case let shapeCollection as MLNShapeCollectionFeature:
            // Collection of shapes - search through all shapes
            for subShape in shapeCollection.shapes {
                let coordinates = extractCoordinatesFromShape(shape: subShape, targetLineId: targetLineId)
                if !coordinates.isEmpty {
                    return coordinates
                }
            }
            
        case let multiPolylineFeature as MLNMultiPolylineFeature:
            // Multiple polyline features - check the feature itself for ID match
            // Note: MLNMultiPolylineFeature.polylines contains MLNPolyline objects (not MLNPolylineFeature)
            // which don't have identifiers, so we check the parent feature instead
            if let identifier = multiPolylineFeature.identifier as? String, identifier == targetLineId {
                // Return coordinates from the first polyline in the multi-polyline
                if multiPolylineFeature.polylines.count > 0 {
                    let firstPolyline = multiPolylineFeature.polylines[0]
                    return Array(UnsafeBufferPointer(start: firstPolyline.coordinates, count: Int(firstPolyline.pointCount)))
                }
            }
            
        default:
            // For other shape types (including MLNPolyline, MLNMultiPolyline), 
            // check if the shape itself is an MLNFeature with the matching ID
            if let feature = shape as? MLNFeature,
               let identifier = feature.identifier as? String,
               identifier == targetLineId {
                
                // Try to extract coordinates based on the actual shape type
                if let polyline = feature as? MLNPolylineFeature {
                    return Array(UnsafeBufferPointer(start: polyline.coordinates, count: Int(polyline.pointCount)))
                } else {
                    NSLog("\(PolylineEditingManager.TAG): Found matching feature \(targetLineId) but unable to extract coordinates from type: \(type(of: shape))")
                }
            }
            
            // Special handling for MLNPolyline (which doesn't implement MLNFeature)
            if let polyline = shape as? MLNPolyline {
                // MLNPolyline doesn't have identifier property, so we need to check if this is
                // the only polyline in the source and assume it matches the target ID
                // This is a limitation of MapLibre's MLNPolyline class
                NSLog("\(PolylineEditingManager.TAG): Found MLNPolyline but cannot verify ID (no identifier property)")
                // We could return coordinates here as a fallback, but it's risky without ID verification
                // return Array(UnsafeBufferPointer(start: polyline.coordinates, count: Int(polyline.pointCount)))
            }
        }
        
        return []
    }
    
    /**
     * Extracts coordinates from any MLNShape without ID verification.
     * This is used as a fallback when we match by sourceId instead of feature ID.
     *
     * @param shape The MLNShape to extract coordinates from
     * @return An array of coordinates if found, empty array otherwise
     */
    private func extractCoordinatesFromAnyShape(shape: MLNShape) -> [CLLocationCoordinate2D] {
        switch shape {
        case let polyline as MLNPolyline:
            return Array(UnsafeBufferPointer(start: polyline.coordinates, count: Int(polyline.pointCount)))
            
        case let polylineFeature as MLNPolylineFeature:
            return Array(UnsafeBufferPointer(start: polylineFeature.coordinates, count: Int(polylineFeature.pointCount)))
            
        case let shapeCollection as MLNShapeCollectionFeature:
            // Return coordinates from the first polyline in the collection
            for subShape in shapeCollection.shapes {
                let coordinates = extractCoordinatesFromAnyShape(shape: subShape)
                if !coordinates.isEmpty {
                    return coordinates
                }
            }
            
        case let multiPolyline as MLNMultiPolyline:
            // Return coordinates from the first polyline
            if multiPolyline.polylines.count > 0 {
                let firstPolyline = multiPolyline.polylines[0]
                return Array(UnsafeBufferPointer(start: firstPolyline.coordinates, count: Int(firstPolyline.pointCount)))
            }
            
        case let multiPolylineFeature as MLNMultiPolylineFeature:
            // Return coordinates from the first polyline feature
            if multiPolylineFeature.polylines.count > 0 {
                let firstPolylineFeature = multiPolylineFeature.polylines[0]
                return Array(UnsafeBufferPointer(start: firstPolylineFeature.coordinates, count: Int(firstPolylineFeature.pointCount)))
            }
            
        default:
            NSLog("\(PolylineEditingManager.TAG): Cannot extract coordinates from unsupported shape type: \(type(of: shape))")
        }
        
        return []
    }
    
    /**
     * Validates that a line ID is valid and exists on the map.
     *
     * @param lineId The line ID to validate
     * @return true if the line ID is valid, false otherwise
     */
    private func isValidLineId(lineId: String) -> Bool {
        // Basic validation - check if the ID is not empty
        return !lineId.isEmpty
    }
}
