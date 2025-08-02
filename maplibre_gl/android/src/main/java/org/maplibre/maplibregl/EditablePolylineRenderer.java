// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.graphics.Color;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.style.layers.CircleLayer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.layers.PropertyFactory;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.FeatureCollection;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Renders visual feedback elements for polyline editing operations.
 * 
 * This class manages the visual representation of:
 * - Break point markers during editing
 * - Preview lines during drag operations
 * - Visual state management for active editing sessions
 * - Smooth animation transitions for editing operations
 */
public class EditablePolylineRenderer {
    private static final String TAG = "EditablePolylineRenderer";
    
    // Layer and source IDs
    private static final String BREAK_POINT_SOURCE_ID = "polyline-editing-break-points";
    private static final String BREAK_POINT_LAYER_ID = "polyline-editing-break-points-layer";
    private static final String PREVIEW_LINE_SOURCE_ID = "polyline-editing-preview-lines";
    private static final String PREVIEW_LINE_LAYER_ID = "polyline-editing-preview-lines-layer";
    
    // Default styling
    private static final String DEFAULT_BREAK_POINT_COLOR = "#FF0000";
    private static final float DEFAULT_BREAK_POINT_RADIUS = 8.0f;
    private static final String DEFAULT_BREAK_POINT_BORDER_COLOR = "#FFFFFF";
    private static final float DEFAULT_BREAK_POINT_BORDER_WIDTH = 2.0f;
    private static final String DEFAULT_PREVIEW_LINE_COLOR = "#00FF00";
    private static final float DEFAULT_PREVIEW_LINE_OPACITY = 0.7f;
    private static final float DEFAULT_PREVIEW_LINE_WIDTH = 3.0f;
    
    private final MapLibreMap mapLibreMap;
    private final Map<String, BreakPointVisualState> activeBreakPoints;
    private final Map<String, PreviewLineVisualState> activePreviewLines;
    
    // Current styling configuration
    private String breakPointColor = DEFAULT_BREAK_POINT_COLOR;
    private float breakPointRadius = DEFAULT_BREAK_POINT_RADIUS;
    private String breakPointBorderColor = DEFAULT_BREAK_POINT_BORDER_COLOR;
    private float breakPointBorderWidth = DEFAULT_BREAK_POINT_BORDER_WIDTH;
    private String previewLineColor = DEFAULT_PREVIEW_LINE_COLOR;
    private float previewLineOpacity = DEFAULT_PREVIEW_LINE_OPACITY;
    private float previewLineWidth = DEFAULT_PREVIEW_LINE_WIDTH;
    
    private boolean isInitialized = false;
    
    /**
     * Represents the visual state of a break point.
     */
    public static class BreakPointVisualState {
        public final String lineId;
        public final LatLng location;
        public final boolean isVisible;
        public final boolean isDragging;
        public final long createdTime;
        
        public BreakPointVisualState(@NonNull String lineId, @NonNull LatLng location, 
                                   boolean isVisible, boolean isDragging) {
            this.lineId = lineId;
            this.location = location;
            this.isVisible = isVisible;
            this.isDragging = isDragging;
            this.createdTime = System.currentTimeMillis();
        }
        
        public BreakPointVisualState withLocation(@NonNull LatLng newLocation) {
            return new BreakPointVisualState(lineId, newLocation, isVisible, isDragging);
        }
        
        public BreakPointVisualState withDragging(boolean dragging) {
            return new BreakPointVisualState(lineId, location, isVisible, dragging);
        }
        
        public BreakPointVisualState withVisibility(boolean visible) {
            return new BreakPointVisualState(lineId, location, visible, isDragging);
        }
    }
    
    /**
     * Represents the visual state of a preview line.
     */
    public static class PreviewLineVisualState {
        public final String lineId;
        public final List<LatLng> coordinates;
        public final boolean isVisible;
        public final long createdTime;
        
        public PreviewLineVisualState(@NonNull String lineId, @NonNull List<LatLng> coordinates, 
                                    boolean isVisible) {
            this.lineId = lineId;
            this.coordinates = new ArrayList<>(coordinates);
            this.isVisible = isVisible;
            this.createdTime = System.currentTimeMillis();
        }
        
        public PreviewLineVisualState withCoordinates(@NonNull List<LatLng> newCoordinates) {
            return new PreviewLineVisualState(lineId, newCoordinates, isVisible);
        }
        
        public PreviewLineVisualState withVisibility(boolean visible) {
            return new PreviewLineVisualState(lineId, coordinates, visible);
        }
    }
    
    /**
     * Creates a new EditablePolylineRenderer.
     * 
     * @param mapLibreMap The MapLibre map instance
     */
    public EditablePolylineRenderer(@NonNull MapLibreMap mapLibreMap) {
        this.mapLibreMap = mapLibreMap;
        this.activeBreakPoints = new HashMap<>();
        this.activePreviewLines = new HashMap<>();
        
        Log.d(TAG, "EditablePolylineRenderer created");
    }
    
    /**
     * Initializes the renderer by adding necessary sources and layers to the map.
     * This should be called after the map style is loaded.
     * 
     * @return true if initialization was successful, false otherwise
     */
    public boolean initialize() {
        if (isInitialized) {
            Log.d(TAG, "Renderer already initialized");
            return true;
        }
        
        try {
            // Add break point source and layer
            if (!addBreakPointLayer()) {
                Log.e(TAG, "Failed to add break point layer");
                return false;
            }
            
            // Add preview line source and layer
            if (!addPreviewLineLayer()) {
                Log.e(TAG, "Failed to add preview line layer");
                return false;
            }
            
            isInitialized = true;
            Log.d(TAG, "Renderer initialized successfully");
            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "Error initializing renderer: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * Updates the visual styling configuration.
     * 
     * @param style Map containing style properties
     */
    public void updateStyle(@NonNull Map<String, Object> style) {
        Log.d(TAG, "Updating visual style: " + style);
        
        // Update break point styling
        if (style.containsKey("breakPointColor")) {
            breakPointColor = (String) style.get("breakPointColor");
        }
        if (style.containsKey("breakPointRadius")) {
            Object radius = style.get("breakPointRadius");
            if (radius instanceof Number) {
                breakPointRadius = ((Number) radius).floatValue();
            }
        }
        if (style.containsKey("breakPointBorderColor")) {
            breakPointBorderColor = (String) style.get("breakPointBorderColor");
        }
        if (style.containsKey("breakPointBorderWidth")) {
            Object width = style.get("breakPointBorderWidth");
            if (width instanceof Number) {
                breakPointBorderWidth = ((Number) width).floatValue();
            }
        }
        
        // Update preview line styling
        if (style.containsKey("previewLineColor")) {
            previewLineColor = (String) style.get("previewLineColor");
        }
        if (style.containsKey("previewLineOpacity")) {
            Object opacity = style.get("previewLineOpacity");
            if (opacity instanceof Number) {
                previewLineOpacity = ((Number) opacity).floatValue();
            }
        }
        if (style.containsKey("previewLineWidth")) {
            Object width = style.get("previewLineWidth");
            if (width instanceof Number) {
                previewLineWidth = ((Number) width).floatValue();
            }
        }
        
        // Apply updated styling to existing layers
        if (isInitialized) {
            updateLayerStyling();
        }
    }
    
    /**
     * Shows a break point marker at the specified location.
     * 
     * @param lineId The ID of the polyline
     * @param location The location of the break point
     */
    public void showBreakPoint(@NonNull String lineId, @NonNull LatLng location) {
        if (!isInitialized) {
            Log.w(TAG, "Renderer not initialized, cannot show break point");
            return;
        }
        
        Log.d(TAG, "Showing break point for line " + lineId + " at " + location);
        
        try {
            BreakPointVisualState state = new BreakPointVisualState(lineId, location, true, false);
            activeBreakPoints.put(lineId, state);
            updateBreakPointSource();
            
        } catch (Exception e) {
            Log.e(TAG, "Error showing break point: " + e.getMessage(), e);
        }
    }
    
    /**
     * Updates the location of an existing break point marker.
     * 
     * @param lineId The ID of the polyline
     * @param newLocation The new location of the break point
     */
    public void updateBreakPoint(@NonNull String lineId, @NonNull LatLng newLocation) {
        if (!isInitialized) {
            Log.w(TAG, "Renderer not initialized, cannot update break point");
            return;
        }
        
        BreakPointVisualState currentState = activeBreakPoints.get(lineId);
        if (currentState == null) {
            Log.w(TAG, "No active break point found for line " + lineId);
            return;
        }
        
        try {
            BreakPointVisualState updatedState = currentState.withLocation(newLocation);
            activeBreakPoints.put(lineId, updatedState);
            updateBreakPointSource();
            
            Log.d(TAG, "Updated break point for line " + lineId + " to " + newLocation);
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating break point: " + e.getMessage(), e);
        }
    }
    
    /**
     * Sets the dragging state of a break point marker.
     * 
     * @param lineId The ID of the polyline
     * @param isDragging Whether the break point is being dragged
     */
    public void setBreakPointDragging(@NonNull String lineId, boolean isDragging) {
        if (!isInitialized) {
            return;
        }
        
        BreakPointVisualState currentState = activeBreakPoints.get(lineId);
        if (currentState == null) {
            return;
        }
        
        try {
            BreakPointVisualState updatedState = currentState.withDragging(isDragging);
            activeBreakPoints.put(lineId, updatedState);
            updateBreakPointSource();
            
        } catch (Exception e) {
            Log.e(TAG, "Error setting break point dragging state: " + e.getMessage(), e);
        }
    }
    
    /**
     * Hides the break point marker for the specified polyline.
     * 
     * @param lineId The ID of the polyline
     */
    public void hideBreakPoint(@NonNull String lineId) {
        if (!isInitialized) {
            return;
        }
        
        try {
            activeBreakPoints.remove(lineId);
            updateBreakPointSource();
            
            Log.d(TAG, "Hidden break point for line " + lineId);
            
        } catch (Exception e) {
            Log.e(TAG, "Error hiding break point: " + e.getMessage(), e);
        }
    }
    
    /**
     * Shows a preview line with the specified coordinates.
     * 
     * @param lineId The ID of the polyline
     * @param coordinates The coordinates of the preview line
     */
    public void showPreviewLine(@NonNull String lineId, @NonNull List<LatLng> coordinates) {
        if (!isInitialized) {
            Log.w(TAG, "Renderer not initialized, cannot show preview line");
            return;
        }
        
        if (coordinates.size() < 2) {
            Log.w(TAG, "Preview line requires at least 2 coordinates");
            return;
        }
        
        Log.d(TAG, "Showing preview line for line " + lineId + " with " + coordinates.size() + " points");
        
        try {
            PreviewLineVisualState state = new PreviewLineVisualState(lineId, coordinates, true);
            activePreviewLines.put(lineId, state);
            updatePreviewLineSource();
            
        } catch (Exception e) {
            Log.e(TAG, "Error showing preview line: " + e.getMessage(), e);
        }
    }
    
    /**
     * Updates the coordinates of an existing preview line.
     * 
     * @param lineId The ID of the polyline
     * @param newCoordinates The new coordinates of the preview line
     */
    public void updatePreviewLine(@NonNull String lineId, @NonNull List<LatLng> newCoordinates) {
        if (!isInitialized) {
            return;
        }
        
        PreviewLineVisualState currentState = activePreviewLines.get(lineId);
        if (currentState == null) {
            Log.w(TAG, "No active preview line found for line " + lineId);
            return;
        }
        
        if (newCoordinates.size() < 2) {
            Log.w(TAG, "Preview line requires at least 2 coordinates");
            return;
        }
        
        try {
            PreviewLineVisualState updatedState = currentState.withCoordinates(newCoordinates);
            activePreviewLines.put(lineId, updatedState);
            updatePreviewLineSource();
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating preview line: " + e.getMessage(), e);
        }
    }
    
    /**
     * Hides the preview line for the specified polyline.
     * 
     * @param lineId The ID of the polyline
     */
    public void hidePreviewLine(@NonNull String lineId) {
        if (!isInitialized) {
            return;
        }
        
        try {
            activePreviewLines.remove(lineId);
            updatePreviewLineSource();
            
            Log.d(TAG, "Hidden preview line for line " + lineId);
            
        } catch (Exception e) {
            Log.e(TAG, "Error hiding preview line: " + e.getMessage(), e);
        }
    }
    
    /**
     * Clears all visual feedback elements.
     */
    public void clearAll() {
        if (!isInitialized) {
            return;
        }
        
        try {
            int breakPointCount = activeBreakPoints.size();
            int previewLineCount = activePreviewLines.size();
            
            activeBreakPoints.clear();
            activePreviewLines.clear();
            
            updateBreakPointSource();
            updatePreviewLineSource();
            
            Log.d(TAG, "Cleared " + breakPointCount + " break points and " + previewLineCount + " preview lines");
            
        } catch (Exception e) {
            Log.e(TAG, "Error clearing visual feedback: " + e.getMessage(), e);
        }
    }
    
    /**
     * Gets the number of active break points.
     * 
     * @return The number of active break points
     */
    public int getActiveBreakPointCount() {
        return activeBreakPoints.size();
    }
    
    /**
     * Gets the number of active preview lines.
     * 
     * @return The number of active preview lines
     */
    public int getActivePreviewLineCount() {
        return activePreviewLines.size();
    }
    
    /**
     * Checks if the renderer is initialized.
     * 
     * @return true if initialized, false otherwise
     */
    public boolean isInitialized() {
        return isInitialized;
    }
    
    /**
     * Adds the break point source and layer to the map.
     */
    private boolean addBreakPointLayer() {
        try {
            // Add empty source
            GeoJsonSource breakPointSource = new GeoJsonSource(BREAK_POINT_SOURCE_ID, 
                FeatureCollection.fromFeatures(new ArrayList<>()));
            mapLibreMap.getStyle().addSource(breakPointSource);
            
            // Add circle layer for break points
            CircleLayer breakPointLayer = new CircleLayer(BREAK_POINT_LAYER_ID, BREAK_POINT_SOURCE_ID);
            breakPointLayer.setProperties(
                PropertyFactory.circleRadius(breakPointRadius),
                PropertyFactory.circleColor(Color.parseColor(breakPointColor)),
                PropertyFactory.circleStrokeColor(Color.parseColor(breakPointBorderColor)),
                PropertyFactory.circleStrokeWidth(breakPointBorderWidth)
            );
            
            mapLibreMap.getStyle().addLayer(breakPointLayer);
            
            Log.d(TAG, "Added break point layer");
            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "Error adding break point layer: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * Adds the preview line source and layer to the map.
     */
    private boolean addPreviewLineLayer() {
        try {
            // Add empty source
            GeoJsonSource previewLineSource = new GeoJsonSource(PREVIEW_LINE_SOURCE_ID, 
                FeatureCollection.fromFeatures(new ArrayList<>()));
            mapLibreMap.getStyle().addSource(previewLineSource);
            
            // Add line layer for preview lines
            LineLayer previewLineLayer = new LineLayer(PREVIEW_LINE_LAYER_ID, PREVIEW_LINE_SOURCE_ID);
            previewLineLayer.setProperties(
                PropertyFactory.lineColor(Color.parseColor(previewLineColor)),
                PropertyFactory.lineWidth(previewLineWidth),
                PropertyFactory.lineOpacity(previewLineOpacity)
            );
            
            mapLibreMap.getStyle().addLayer(previewLineLayer);
            
            Log.d(TAG, "Added preview line layer");
            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "Error adding preview line layer: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * Updates the styling of existing layers.
     */
    private void updateLayerStyling() {
        try {
            // Update break point layer styling
            CircleLayer breakPointLayer = (CircleLayer) mapLibreMap.getStyle().getLayer(BREAK_POINT_LAYER_ID);
            if (breakPointLayer != null) {
                breakPointLayer.setProperties(
                    PropertyFactory.circleRadius(breakPointRadius),
                    PropertyFactory.circleColor(Color.parseColor(breakPointColor)),
                    PropertyFactory.circleStrokeColor(Color.parseColor(breakPointBorderColor)),
                    PropertyFactory.circleStrokeWidth(breakPointBorderWidth)
                );
            }
            
            // Update preview line layer styling
            LineLayer previewLineLayer = (LineLayer) mapLibreMap.getStyle().getLayer(PREVIEW_LINE_LAYER_ID);
            if (previewLineLayer != null) {
                previewLineLayer.setProperties(
                    PropertyFactory.lineColor(Color.parseColor(previewLineColor)),
                    PropertyFactory.lineWidth(previewLineWidth),
                    PropertyFactory.lineOpacity(previewLineOpacity)
                );
            }
            
            Log.d(TAG, "Updated layer styling");
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating layer styling: " + e.getMessage(), e);
        }
    }
    
    /**
     * Updates the break point source with current break point data.
     */
    private void updateBreakPointSource() {
        try {
            List<Feature> features = new ArrayList<>();
            
            for (BreakPointVisualState state : activeBreakPoints.values()) {
                if (state.isVisible) {
                    Point point = Point.fromLngLat(state.location.getLongitude(), state.location.getLatitude());
                    Feature feature = Feature.fromGeometry(point);
                    feature.addStringProperty("lineId", state.lineId);
                    feature.addBooleanProperty("isDragging", state.isDragging);
                    features.add(feature);
                }
            }
            
            GeoJsonSource source = (GeoJsonSource) mapLibreMap.getStyle().getSource(BREAK_POINT_SOURCE_ID);
            if (source != null) {
                source.setGeoJson(FeatureCollection.fromFeatures(features));
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating break point source: " + e.getMessage(), e);
        }
    }
    
    /**
     * Updates the preview line source with current preview line data.
     */
    private void updatePreviewLineSource() {
        try {
            List<Feature> features = new ArrayList<>();
            
            for (PreviewLineVisualState state : activePreviewLines.values()) {
                if (state.isVisible && state.coordinates.size() >= 2) {
                    List<Point> points = new ArrayList<>();
                    for (LatLng coord : state.coordinates) {
                        points.add(Point.fromLngLat(coord.getLongitude(), coord.getLatitude()));
                    }
                    
                    LineString lineString = LineString.fromLngLats(points);
                    Feature feature = Feature.fromGeometry(lineString);
                    feature.addStringProperty("lineId", state.lineId);
                    features.add(feature);
                }
            }
            
            GeoJsonSource source = (GeoJsonSource) mapLibreMap.getStyle().getSource(PREVIEW_LINE_SOURCE_ID);
            if (source != null) {
                source.setGeoJson(FeatureCollection.fromFeatures(features));
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating preview line source: " + e.getMessage(), e);
        }
    }
    
    /**
     * Logs the current state of the renderer for debugging.
     */
    public void logState() {
        Log.d(TAG, "EditablePolylineRenderer state:");
        Log.d(TAG, "  Initialized: " + isInitialized);
        Log.d(TAG, "  Active break points: " + activeBreakPoints.size());
        Log.d(TAG, "  Active preview lines: " + activePreviewLines.size());
        
        for (Map.Entry<String, BreakPointVisualState> entry : activeBreakPoints.entrySet()) {
            BreakPointVisualState state = entry.getValue();
            Log.d(TAG, "    Break point " + entry.getKey() + ": visible=" + state.isVisible + 
                      ", dragging=" + state.isDragging + ", location=" + state.location);
        }
        
        for (Map.Entry<String, PreviewLineVisualState> entry : activePreviewLines.entrySet()) {
            PreviewLineVisualState state = entry.getValue();
            Log.d(TAG, "    Preview line " + entry.getKey() + ": visible=" + state.isVisible + 
                      ", points=" + state.coordinates.size());
        }
    }
}