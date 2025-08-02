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
    private var editableLines: [String: PolylineEditingConfig] = [:]
    private var globalEditingStyle: [String: Any] = [:]
    
    /**
     * Configuration for an editable polyline.
     */
    struct PolylineEditingConfig {
        let lineId: String
        let enabled: Bool
        let coordinates: [CLLocationCoordinate2D]
        let style: [String: Any]
        
        init(lineId: String, enabled: Bool, coordinates: [CLLocationCoordinate2D] = [], style: [String: Any] = [:]) {
            self.lineId = lineId
            self.enabled = enabled
            self.coordinates = coordinates
            self.style = style
        }
    }
    
    init(mapView: MLNMapView) {
        self.mapView = mapView
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
    func enableLineEditing(lineId: String, enabled: Bool) {
        NSLog("\(PolylineEditingManager.TAG): enableLineEditing called for line \(lineId), enabled: \(enabled)")
        
        if enabled {
            // Get coordinates from the map if available
            let coordinates = getLineCoordinates(lineId: lineId)
            let config = PolylineEditingConfig(
                lineId: lineId,
                enabled: true,
                coordinates: coordinates,
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
            style: config.style
        )
        editableLines[lineId] = updatedConfig
        
        NSLog("\(PolylineEditingManager.TAG): Updated coordinates for line \(lineId) with \(coordinates.count) points")
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
     * Gets the coordinates for a line from the map view.
     * This is a placeholder implementation - in a real scenario, this would
     * query the map's style sources to get the actual line coordinates.
     *
     * @param lineId The ID of the line to get coordinates for
     * @return An array of coordinates for the line
     */
    private func getLineCoordinates(lineId: String) -> [CLLocationCoordinate2D] {
        // TODO: Implement actual coordinate retrieval from map sources
        // For now, return empty array as this would be populated when the line is registered
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