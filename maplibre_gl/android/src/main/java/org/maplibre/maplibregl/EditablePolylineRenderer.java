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
import org.maplibre.android.style.layers.PropertyFactory;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.FeatureCollection;
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
 * - Visual state management for active editing sessions
 */
public class EditablePolylineRenderer {
    private static final String TAG = "EditablePolylineRenderer";
    
    // Layer and source IDs
    private static final String BREAK_POINT_SOURCE_ID = "polyline-editing-break-points";
    private static final String BREAK_POINT_LAYER_ID = "polyline-editing-break-points-layer";
    
    // Default styling
    private static final String DEFAULT_BREAK_POINT_COLOR = "#FF0000";
    private static final float DEFAULT_BREAK_POINT_RADIUS = 8.0f;
    private static final String DEFAULT_BREAK_POINT_BORDER_COLOR = "#FFFFFF";
    private static final float DEFAULT_BREAK_POINT_BORDER_WIDTH = 2.0f;
    
    private final MapLibreMap mapLibreMap;
    private final Map<String, BreakPointVisualState> activeBreakPoints;
    
    // Current styling configuration
    private String breakPointColor = DEFAULT_BREAK_POINT_COLOR;
    private float breakPointRadius = DEFAULT_BREAK_POINT_RADIUS;
    private String breakPointBorderColor = DEFAULT_BREAK_POINT_BORDER_COLOR;
    private float breakPointBorderWidth = DEFAULT_BREAK_POINT_BORDER_WIDTH;
    
    private boolean isInitialized = false;
    
    /**
     * Represents the visual state of a break point.
     */
    public static class BreakPointVisualState {
        public final String lineId;
        public final int pointIndex;
        public final LatLng location;
        public final boolean isVisible;
        public final boolean isDragging;
        public final long createdTime;
        
        public BreakPointVisualState(@NonNull String lineId, @NonNull LatLng location, 
                                   boolean isVisible, boolean isDragging) {
            this(lineId, -1, location, isVisible, isDragging);
        }

        public BreakPointVisualState(@NonNull String lineId, int pointIndex,
                                   @NonNull LatLng location,
                                   boolean isVisible, boolean isDragging) {
            this.lineId = lineId;
            this.pointIndex = pointIndex;
            this.location = location;
            this.isVisible = isVisible;
            this.isDragging = isDragging;
            this.createdTime = System.currentTimeMillis();
        }
        
        public BreakPointVisualState withLocation(@NonNull LatLng newLocation) {
            return new BreakPointVisualState(
                lineId, pointIndex, newLocation, isVisible, isDragging);
        }
        
        public BreakPointVisualState withDragging(boolean dragging) {
            return new BreakPointVisualState(
                lineId, pointIndex, location, isVisible, dragging);
        }
        
        public BreakPointVisualState withVisibility(boolean visible) {
            return new BreakPointVisualState(
                lineId, pointIndex, location, visible, isDragging);
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
        
        // Update break point layer styling
        if (isInitialized) {
            updateBreakPointLayerStyling();
        }
    }
    
    /**
     * Shows a break point marker at the specified location.
     * 
     * @param lineId The ID of the polyline
     * @param location The location of the break point
     */
    public void showBreakPoint(@NonNull String lineId, @NonNull LatLng location) {
        showBreakPoint(lineId, -1, location);
    }

    public void showBreakPoint(
            @NonNull String lineId, int pointIndex, @NonNull LatLng location) {
        if (!isInitialized) {
            Log.w(TAG, "Renderer not initialized, cannot show break point");
            return;
        }
        
        Log.d(TAG, "Showing break point for line " + lineId + " at " + location);
        
        try {
            BreakPointVisualState state = new BreakPointVisualState(
                lineId, pointIndex, location, true, false);
            activeBreakPoints.put(breakPointKey(lineId, pointIndex), state);
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
        updateBreakPoint(lineId, -1, newLocation);
    }

    public void updateBreakPoint(
            @NonNull String lineId, int pointIndex, @NonNull LatLng newLocation) {
        if (!isInitialized) {
            Log.w(TAG, "Renderer not initialized, cannot update break point");
            return;
        }
        
        BreakPointVisualState currentState =
            activeBreakPoints.get(breakPointKey(lineId, pointIndex));
        if (currentState == null) {
            Log.w(TAG, "No active break point found for line " + lineId);
            return;
        }
        
        try {
            BreakPointVisualState updatedState = currentState.withLocation(newLocation);
            activeBreakPoints.put(breakPointKey(lineId, pointIndex), updatedState);
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
        setBreakPointDragging(lineId, -1, isDragging);
    }

    public void setBreakPointDragging(
            @NonNull String lineId, int pointIndex, boolean isDragging) {
        if (!isInitialized) {
            return;
        }
        
        BreakPointVisualState currentState =
            activeBreakPoints.get(breakPointKey(lineId, pointIndex));
        if (currentState == null) {
            return;
        }
        
        try {
            BreakPointVisualState updatedState = currentState.withDragging(isDragging);
            activeBreakPoints.put(breakPointKey(lineId, pointIndex), updatedState);
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
            activeBreakPoints.entrySet().removeIf(
                entry -> entry.getValue().lineId.equals(lineId));
            updateBreakPointSource();
            
            Log.d(TAG, "Hidden break point for line " + lineId);
            
        } catch (Exception e) {
            Log.e(TAG, "Error hiding break point: " + e.getMessage(), e);
        }
    }

    public void syncBreakPoints(
            @NonNull String lineId,
            @NonNull List<LatLng> coordinates,
            @NonNull java.util.Set<Integer> lockedIndices) {
        if (!isInitialized) return;
        activeBreakPoints.entrySet().removeIf(
            entry -> entry.getValue().lineId.equals(lineId));
        for (int index = 1; index < coordinates.size() - 1; index++) {
            if (lockedIndices.contains(index)) continue;
            BreakPointVisualState state = new BreakPointVisualState(
                lineId, index, coordinates.get(index), true, false);
            activeBreakPoints.put(breakPointKey(lineId, index), state);
        }
        updateBreakPointSource();
    }

    private String breakPointKey(@NonNull String lineId, int pointIndex) {
        return lineId + ":" + pointIndex;
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
            
            activeBreakPoints.clear();
            updateBreakPointSource();
            
            Log.d(TAG, "Cleared " + breakPointCount + " break points");
            
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
     * Updates the styling of break point layer.
     */
    private void updateBreakPointLayerStyling() {
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
            
            Log.d(TAG, "Updated break point layer styling");
            
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
                    feature.addNumberProperty("pointIndex", state.pointIndex);
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
     * Logs the current state of the renderer for debugging.
     */
    public void logState() {
        Log.d(TAG, "EditablePolylineRenderer state:");
        Log.d(TAG, "  Initialized: " + isInitialized);
        Log.d(TAG, "  Active break points: " + activeBreakPoints.size());
        
        for (Map.Entry<String, BreakPointVisualState> entry : activeBreakPoints.entrySet()) {
            BreakPointVisualState state = entry.getValue();
            Log.d(TAG, "    Break point " + entry.getKey() + ": visible=" + state.isVisible + 
                      ", dragging=" + state.isDragging + ", location=" + state.location);
        }
    }
}
