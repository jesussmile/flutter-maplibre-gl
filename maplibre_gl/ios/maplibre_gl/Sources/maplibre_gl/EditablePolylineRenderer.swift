import Foundation
import MapLibre
import UIKit

/**
 * Manages visual feedback for polyline editing operations using MLNAnnotationView customization.
 * 
 * This class handles:
 * - Break point marker styling and rendering
 * - Preview line rendering during drag operations with MLNPolyline styling
 * - Visual state management for active editing sessions
 * - Smooth Core Animation transitions for editing operations
 */
class EditablePolylineRenderer {
    private static let TAG = "EditablePolylineRenderer"
    
    private let mapView: MLNMapView
    private var breakPointAnnotations: [String: MLNPointAnnotation] = [:]
    private var previewLines: [String: MLNPolyline] = [:]
    private var editingStyle: [String: Any] = [:]
    
    // Source and layer IDs for rendering
    private let breakPointSourceId = "polyline-editing-breakpoints"
    private let previewLineSourceId = "polyline-editing-preview"
    private let breakPointLayerId = "polyline-editing-breakpoint-layer"
    private let previewLineLayerId = "polyline-editing-preview-layer"
    
    init(mapView: MLNMapView) {
        self.mapView = mapView
        setupDefaultStyle()
        NSLog("\(EditablePolylineRenderer.TAG): Initialized editable polyline renderer")
    }
    
    /**
     * Sets up default visual styling for editing elements.
     */
    private func setupDefaultStyle() {
        editingStyle = [
            "breakPointColor": "#FF0000",
            "breakPointRadius": 8.0,
            "breakPointBorderColor": "#FFFFFF",
            "breakPointBorderWidth": 2.0,
            "previewLineColor": "#00FF00",
            "previewLineOpacity": 0.7,
            "previewLineWidth": 3.0
        ]
    }
    
    /**
     * Initializes the renderer after the map style is loaded.
     * This should be called when the map style is ready.
     */
    func initialize() {
        setupBreakPointLayer()
        setupPreviewLineLayer()
        NSLog("\(EditablePolylineRenderer.TAG): Renderer initialized with map style")
    }
    
    /**
     * Sets up the layer for rendering break point markers.
     */
    private func setupBreakPointLayer() {
        guard let style = mapView.style else {
            NSLog("\(EditablePolylineRenderer.TAG): Cannot setup break point layer - map style not available")
            return
        }
        
        // Create source for break points
        let breakPointSource = MLNShapeSource(identifier: breakPointSourceId, shape: nil, options: nil)
        style.addSource(breakPointSource)
        
        // Create layer for break points
        let breakPointLayer = MLNCircleStyleLayer(identifier: breakPointLayerId, source: breakPointSource)
        
        // Apply styling
        let radius = editingStyle["breakPointRadius"] as? Double ?? 8.0
        let color = parseColor(editingStyle["breakPointColor"] as? String ?? "#FF0000")
        let borderColor = parseColor(editingStyle["breakPointBorderColor"] as? String ?? "#FFFFFF")
        let borderWidth = editingStyle["breakPointBorderWidth"] as? Double ?? 2.0
        
        breakPointLayer.circleRadius = NSExpression(forConstantValue: radius)
        breakPointLayer.circleColor = NSExpression(forConstantValue: color)
        breakPointLayer.circleStrokeColor = NSExpression(forConstantValue: borderColor)
        breakPointLayer.circleStrokeWidth = NSExpression(forConstantValue: borderWidth)
        
        style.addLayer(breakPointLayer)
        NSLog("\(EditablePolylineRenderer.TAG): Break point layer setup complete")
    }
    
    /**
     * Sets up the layer for rendering preview lines.
     */
    private func setupPreviewLineLayer() {
        guard let style = mapView.style else {
            NSLog("\(EditablePolylineRenderer.TAG): Cannot setup preview line layer - map style not available")
            return
        }
        
        // Create source for preview lines
        let previewLineSource = MLNShapeSource(identifier: previewLineSourceId, shape: nil, options: nil)
        style.addSource(previewLineSource)
        
        // Create layer for preview lines
        let previewLineLayer = MLNLineStyleLayer(identifier: previewLineLayerId, source: previewLineSource)
        
        // Apply styling
        let color = parseColor(editingStyle["previewLineColor"] as? String ?? "#00FF00")
        let opacity = editingStyle["previewLineOpacity"] as? Double ?? 0.7
        let width = editingStyle["previewLineWidth"] as? Double ?? 3.0
        
        previewLineLayer.lineColor = NSExpression(forConstantValue: color)
        previewLineLayer.lineOpacity = NSExpression(forConstantValue: opacity)
        previewLineLayer.lineWidth = NSExpression(forConstantValue: width)
        previewLineLayer.lineCap = NSExpression(forConstantValue: "round")
        previewLineLayer.lineJoin = NSExpression(forConstantValue: "round")
        
        style.addLayer(previewLineLayer)
        NSLog("\(EditablePolylineRenderer.TAG): Preview line layer setup complete")
    }
    
    /**
     * Shows a break point marker at the specified coordinate.
     *
     * @param lineId The ID of the line the break point belongs to
     * @param coordinate The coordinate where the break point should be displayed
     */
    func showBreakPoint(lineId: String, coordinate: CLLocationCoordinate2D) {
        // Create point annotation for the break point
        let annotation = MLNPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Break Point"
        
        // Store the annotation
        breakPointAnnotations[lineId] = annotation
        
        // Update the break point source
        updateBreakPointSource()
        
        NSLog("\(EditablePolylineRenderer.TAG): Showing break point for line \(lineId) at \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    /**
     * Hides the break point marker for the specified line.
     *
     * @param lineId The ID of the line to hide the break point for
     */
    func hideBreakPoint(lineId: String) {
        breakPointAnnotations.removeValue(forKey: lineId)
        updateBreakPointSource()
        NSLog("\(EditablePolylineRenderer.TAG): Hidden break point for line \(lineId)")
    }
    
    /**
     * Shows a preview line during drag operations.
     *
     * @param lineId The ID of the line being edited
     * @param coordinates The coordinates of the preview line
     */
    func showPreviewLine(lineId: String, coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2 else {
            NSLog("\(EditablePolylineRenderer.TAG): Cannot show preview line with less than 2 coordinates")
            return
        }
        
        // Create polyline for preview
        let polyline = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
        previewLines[lineId] = polyline
        
        // Update the preview line source
        updatePreviewLineSource()
        
        NSLog("\(EditablePolylineRenderer.TAG): Showing preview line for line \(lineId) with \(coordinates.count) coordinates")
    }
    
    /**
     * Hides the preview line for the specified line.
     *
     * @param lineId The ID of the line to hide the preview line for
     */
    func hidePreviewLine(lineId: String) {
        previewLines.removeValue(forKey: lineId)
        updatePreviewLineSource()
        NSLog("\(EditablePolylineRenderer.TAG): Hidden preview line for line \(lineId)")
    }
    
    /**
     * Updates the visual styling for editing elements.
     *
     * @param style A dictionary containing the new style properties
     */
    func updateStyle(_ style: [String: Any]) {
        NSLog("\(EditablePolylineRenderer.TAG): Updating style with \(style.count) properties")
        
        // Merge with existing style
        for (key, value) in style {
            editingStyle[key] = value
        }
        
        // Update layer styles
        updateBreakPointLayerStyle()
        updatePreviewLineLayerStyle()
        
        NSLog("\(EditablePolylineRenderer.TAG): Style update complete")
    }
    
    /**
     * Updates the break point layer styling.
     */
    private func updateBreakPointLayerStyle() {
        guard let style = mapView.style,
              let layer = style.layer(withIdentifier: breakPointLayerId) as? MLNCircleStyleLayer else {
            return
        }
        
        let radius = editingStyle["breakPointRadius"] as? Double ?? 8.0
        let color = parseColor(editingStyle["breakPointColor"] as? String ?? "#FF0000")
        let borderColor = parseColor(editingStyle["breakPointBorderColor"] as? String ?? "#FFFFFF")
        let borderWidth = editingStyle["breakPointBorderWidth"] as? Double ?? 2.0
        
        layer.circleRadius = NSExpression(forConstantValue: radius)
        layer.circleColor = NSExpression(forConstantValue: color)
        layer.circleStrokeColor = NSExpression(forConstantValue: borderColor)
        layer.circleStrokeWidth = NSExpression(forConstantValue: borderWidth)
    }
    
    /**
     * Updates the preview line layer styling.
     */
    private func updatePreviewLineLayerStyle() {
        guard let style = mapView.style,
              let layer = style.layer(withIdentifier: previewLineLayerId) as? MLNLineStyleLayer else {
            return
        }
        
        let color = parseColor(editingStyle["previewLineColor"] as? String ?? "#00FF00")
        let opacity = editingStyle["previewLineOpacity"] as? Double ?? 0.7
        let width = editingStyle["previewLineWidth"] as? Double ?? 3.0
        
        layer.lineColor = NSExpression(forConstantValue: color)
        layer.lineOpacity = NSExpression(forConstantValue: opacity)
        layer.lineWidth = NSExpression(forConstantValue: width)
    }
    
    /**
     * Updates the break point source with current annotations.
     */
    private func updateBreakPointSource() {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: breakPointSourceId) as? MLNShapeSource else {
            return
        }
        
        if breakPointAnnotations.isEmpty {
            source.shape = nil
        } else {
            let annotations = Array(breakPointAnnotations.values)
            let shapeCollection = MLNShapeCollection(shapes: annotations)
            source.shape = shapeCollection
        }
    }
    
    /**
     * Updates the preview line source with current polylines.
     */
    private func updatePreviewLineSource() {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: previewLineSourceId) as? MLNShapeSource else {
            return
        }
        
        if previewLines.isEmpty {
            source.shape = nil
        } else {
            let polylines = Array(previewLines.values)
            let shapeCollection = MLNShapeCollection(shapes: polylines)
            source.shape = shapeCollection
        }
    }
    
    /**
     * Animates the appearance of a break point with a smooth transition.
     *
     * @param lineId The ID of the line the break point belongs to
     * @param coordinate The coordinate where the break point should appear
     */
    func animateBreakPointAppearance(lineId: String, coordinate: CLLocationCoordinate2D) {
        showBreakPoint(lineId: lineId, coordinate: coordinate)
        
        // Add a subtle animation by temporarily scaling the break point
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateBreakPointScale(lineId: lineId, scale: 1.2)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.animateBreakPointScale(lineId: lineId, scale: 1.0)
            }
        }
    }
    
    /**
     * Animates the scale of a break point.
     *
     * @param lineId The ID of the line the break point belongs to
     * @param scale The scale factor to animate to
     */
    private func animateBreakPointScale(lineId: String, scale: Double) {
        guard let style = mapView.style,
              let layer = style.layer(withIdentifier: breakPointLayerId) as? MLNCircleStyleLayer else {
            return
        }
        
        let baseRadius = editingStyle["breakPointRadius"] as? Double ?? 8.0
        let animatedRadius = baseRadius * scale
        
        layer.circleRadius = NSExpression(forConstantValue: animatedRadius)
    }
    
    /**
     * Clears all visual editing elements from the map.
     */
    func clearAllVisualElements() {
        breakPointAnnotations.removeAll()
        previewLines.removeAll()
        updateBreakPointSource()
        updatePreviewLineSource()
        NSLog("\(EditablePolylineRenderer.TAG): Cleared all visual editing elements")
    }
    
    /**
     * Clears visual elements for a specific line.
     *
     * @param lineId The ID of the line to clear visual elements for
     */
    func clearVisualElementsForLine(lineId: String) {
        hideBreakPoint(lineId: lineId)
        hidePreviewLine(lineId: lineId)
        NSLog("\(EditablePolylineRenderer.TAG): Cleared visual elements for line \(lineId)")
    }
    
    /**
     * Parses a color string into a UIColor.
     *
     * @param colorString The color string to parse (e.g., "#FF0000")
     * @return The parsed UIColor, or red as default
     */
    private func parseColor(_ colorString: String) -> UIColor {
        var colorString = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if colorString.hasPrefix("#") {
            colorString.removeFirst()
        }
        
        guard colorString.count == 6 else {
            NSLog("\(EditablePolylineRenderer.TAG): Invalid color string: \(colorString), using default red")
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
    
    /**
     * Gets statistics about the current visual state.
     *
     * @return A dictionary containing visual state statistics
     */
    func getVisualStatistics() -> [String: Any] {
        return [
            "activeBreakPoints": breakPointAnnotations.count,
            "activePreviewLines": previewLines.count,
            "currentStyle": editingStyle
        ]
    }
    
    /**
     * Cleans up resources when the renderer is no longer needed.
     */
    func cleanup() {
        clearAllVisualElements()
        
        // Remove layers and sources
        if let style = mapView.style {
            if style.layer(withIdentifier: breakPointLayerId) != nil {
                style.removeLayer(withIdentifier: breakPointLayerId)
            }
            if style.layer(withIdentifier: previewLineLayerId) != nil {
                style.removeLayer(withIdentifier: previewLineLayerId)
            }
            if style.source(withIdentifier: breakPointSourceId) != nil {
                style.removeSource(withIdentifier: breakPointSourceId)
            }
            if style.source(withIdentifier: previewLineSourceId) != nil {
                style.removeSource(withIdentifier: previewLineSourceId)
            }
        }
        
        NSLog("\(EditablePolylineRenderer.TAG): Cleanup complete")
    }
}