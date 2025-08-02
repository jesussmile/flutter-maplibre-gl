// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.maplibre.android.maps.MapLibreMap;

/**
 * Manages polyline editing state and configuration for all polylines on the map.
 * 
 * This class tracks which polylines are editable, stores their editing configuration,
 * and provides methods to enable/disable editing for specific polylines.
 */
public class PolylineEditingManager {
    private static final String TAG = "PolylineEditingManager";
    
    private final MapLibreMap mapLibreMap;
    private final Map<String, PolylineEditingConfig> editablePolylines;
    private final Map<String, Object> globalEditingStyle;
    
    /**
     * Configuration for an editable polyline.
     */
    public static class PolylineEditingConfig {
        public final String lineId;
        public final boolean enabled;
        public final Map<String, Object> style;
        
        public PolylineEditingConfig(@NonNull String lineId, boolean enabled, @Nullable Map<String, Object> style) {
            this.lineId = lineId;
            this.enabled = enabled;
            this.style = style != null ? new HashMap<>(style) : new HashMap<>();
        }
        
        public PolylineEditingConfig withEnabled(boolean enabled) {
            return new PolylineEditingConfig(this.lineId, enabled, this.style);
        }
        
        public PolylineEditingConfig withStyle(@NonNull Map<String, Object> style) {
            return new PolylineEditingConfig(this.lineId, this.enabled, style);
        }
    }
    
    /**
     * Creates a new PolylineEditingManager.
     * 
     * @param mapLibreMap The MapLibre map instance
     */
    public PolylineEditingManager(@NonNull MapLibreMap mapLibreMap) {
        this.mapLibreMap = mapLibreMap;
        this.editablePolylines = new ConcurrentHashMap<>();
        this.globalEditingStyle = new HashMap<>();
        
        // Set default editing style
        setDefaultEditingStyle();
        
        Log.d(TAG, "PolylineEditingManager initialized");
    }
    
    /**
     * Enables or disables editing for a specific polyline.
     * 
     * @param lineId The ID of the polyline
     * @param enabled Whether editing should be enabled
     */
    public void enableLineEditing(@NonNull String lineId, boolean enabled) {
        Log.d(TAG, "Setting editing enabled=" + enabled + " for line: " + lineId);
        
        PolylineEditingConfig existingConfig = editablePolylines.get(lineId);
        PolylineEditingConfig newConfig;
        
        if (existingConfig != null) {
            newConfig = existingConfig.withEnabled(enabled);
        } else {
            newConfig = new PolylineEditingConfig(lineId, enabled, globalEditingStyle);
        }
        
        if (enabled) {
            editablePolylines.put(lineId, newConfig);
            Log.d(TAG, "Enabled editing for polyline: " + lineId);
        } else {
            editablePolylines.remove(lineId);
            Log.d(TAG, "Disabled editing for polyline: " + lineId);
        }
    }
    
    /**
     * Sets the global editing style that will be applied to all editable polylines.
     * 
     * @param style Map containing style properties
     */
    public void setEditingStyle(@NonNull Map<String, Object> style) {
        Log.d(TAG, "Setting global editing style: " + style);
        
        globalEditingStyle.clear();
        globalEditingStyle.putAll(style);
        
        // Update existing polyline configurations with new style
        for (Map.Entry<String, PolylineEditingConfig> entry : editablePolylines.entrySet()) {
            String lineId = entry.getKey();
            PolylineEditingConfig oldConfig = entry.getValue();
            PolylineEditingConfig newConfig = oldConfig.withStyle(globalEditingStyle);
            editablePolylines.put(lineId, newConfig);
        }
        
        Log.d(TAG, "Updated editing style for " + editablePolylines.size() + " polylines");
    }
    
    /**
     * Checks if a polyline is currently editable.
     * 
     * @param lineId The ID of the polyline
     * @return true if the polyline is editable, false otherwise
     */
    public boolean isLineEditable(@NonNull String lineId) {
        PolylineEditingConfig config = editablePolylines.get(lineId);
        boolean editable = config != null && config.enabled;
        Log.d(TAG, "Line " + lineId + " is editable: " + editable);
        return editable;
    }
    
    /**
     * Gets the editing configuration for a specific polyline.
     * 
     * @param lineId The ID of the polyline
     * @return The editing configuration, or null if not editable
     */
    @Nullable
    public PolylineEditingConfig getEditingConfig(@NonNull String lineId) {
        return editablePolylines.get(lineId);
    }
    
    /**
     * Gets all currently editable polylines.
     * 
     * @return Map of line IDs to their editing configurations
     */
    @NonNull
    public Map<String, PolylineEditingConfig> getEditablePolylines() {
        return new HashMap<>(editablePolylines);
    }
    
    /**
     * Gets the current global editing style.
     * 
     * @return Map containing the current editing style properties
     */
    @NonNull
    public Map<String, Object> getGlobalEditingStyle() {
        return new HashMap<>(globalEditingStyle);
    }
    
    /**
     * Removes a polyline from editing management.
     * This should be called when a polyline is removed from the map.
     * 
     * @param lineId The ID of the polyline to remove
     */
    public void removePolyline(@NonNull String lineId) {
        PolylineEditingConfig removed = editablePolylines.remove(lineId);
        if (removed != null) {
            Log.d(TAG, "Removed polyline from editing management: " + lineId);
        }
    }
    
    /**
     * Clears all polyline editing configurations.
     * This should be called when the map is cleared or reset.
     */
    public void clear() {
        int count = editablePolylines.size();
        editablePolylines.clear();
        Log.d(TAG, "Cleared " + count + " polyline editing configurations");
    }
    
    /**
     * Sets the default editing style with sensible defaults.
     */
    private void setDefaultEditingStyle() {
        globalEditingStyle.put("breakPointColor", "#FF0000");
        globalEditingStyle.put("breakPointRadius", 8.0);
        globalEditingStyle.put("breakPointBorderColor", "#FFFFFF");
        globalEditingStyle.put("breakPointBorderWidth", 2.0);
        globalEditingStyle.put("previewLineColor", "#00FF00");
        globalEditingStyle.put("previewLineOpacity", 0.7);
        globalEditingStyle.put("previewLineWidth", 3.0);
        globalEditingStyle.put("enableHapticFeedback", true);
        
        Log.d(TAG, "Set default editing style");
    }
    
    /**
     * Gets the number of currently editable polylines.
     * 
     * @return The count of editable polylines
     */
    public int getEditablePolylineCount() {
        return editablePolylines.size();
    }
    
    /**
     * Logs the current state of the editing manager for debugging.
     */
    public void logState() {
        Log.d(TAG, "PolylineEditingManager state:");
        Log.d(TAG, "  Editable polylines: " + editablePolylines.size());
        Log.d(TAG, "  Global style properties: " + globalEditingStyle.size());
        
        for (Map.Entry<String, PolylineEditingConfig> entry : editablePolylines.entrySet()) {
            PolylineEditingConfig config = entry.getValue();
            Log.d(TAG, "    " + entry.getKey() + ": enabled=" + config.enabled + 
                      ", style properties=" + config.style.size());
        }
    }
}