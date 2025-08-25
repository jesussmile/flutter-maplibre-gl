package org.maplibre.maplibregl;

import android.util.Log;
import org.maplibre.android.geometry.LatLngBounds;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Integrates the high-performance NativeTerrainDataManager with the MapLibreMapController.
 * 
 * This class bridges the gap between the Flutter plugin interface and the native
 * terrain data manager, ensuring smooth transition to the new architecture.
 */
public class NativeTerrainManagerIntegration {
    private static final String TAG = "TerrainManagerIntegration";
    
    private final MapLibreMapController mapController;
    private NativeTerrainDataManager terrainManager;
    private final Map<String, Object> pendingInitializations = new ConcurrentHashMap<>();
    
    public NativeTerrainManagerIntegration(MapLibreMapController controller) {
        this.mapController = controller;
    }
    
    /**
     * Initialize the terrain manager when the map style is loaded.
     * This method should be called after map style is fully loaded.
     */
    public void initializeWithMap(org.maplibre.android.maps.MapLibreMap mapLibreMap) {
        try {
            if (mapLibreMap != null && mapController.getStyle() != null) {
                Log.d(TAG, "Initializing NativeTerrainDataManager with loaded map");
                terrainManager = new NativeTerrainDataManager(
                    mapLibreMap, 
                    mapController.getStyle()
                );
                
                // Process any pending initializations that came in before the map was ready
                processPendingInitializations();
            } else {
                Log.w(TAG, "Map or style not ready for terrain manager initialization");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error initializing terrain manager: " + e.getMessage(), e);
        }
    }
    
    /**
     * Handles terrain layer initialization from Flutter.
     */
    public void handleTerrainInitialize(MethodCall call, MethodChannel.Result result) {
        try {
            Log.d(TAG, "handleTerrainInitialize called");
            
            String layerId = call.argument("layerId");
            if (layerId == null || layerId.isEmpty()) {
                result.error("INVALID_ARGUMENTS", "layerId is required", null);
                return;
            }
            
            // Extract initialization parameters
            Object boundsObj = call.argument("bounds");
            List<Double> bounds = null;
            if (boundsObj instanceof double[]) {
                double[] boundsArray = (double[]) boundsObj;
                bounds = new java.util.ArrayList<>();
                for (double d : boundsArray) {
                    bounds.add(d);
                }
            } else if (boundsObj instanceof List) {
                bounds = (List<Double>) boundsObj;
            }
            
            Integer width = call.argument("width");
            Integer height = call.argument("height");
            Double referenceAltitude = call.argument("referenceAltitude");
            Double warningAltitude = call.argument("warningAltitude");
            
            // Get elevation data
            Object elevationDataObj = call.argument("elevationData");
            double[] elevationArray = null;
            
            if (elevationDataObj instanceof double[]) {
                elevationArray = (double[]) elevationDataObj;
            } else if (elevationDataObj instanceof List) {
                List<?> list = (List<?>) elevationDataObj;
                elevationArray = new double[list.size()];
                for (int i = 0; i < list.size(); i++) {
                    Object item = list.get(i);
                    if (item instanceof Number) {
                        elevationArray[i] = ((Number) item).doubleValue();
                    }
                }
            }
            
            // Validate required parameters
            if (bounds == null || width == null || height == null || 
                referenceAltitude == null || warningAltitude == null || elevationArray == null) {
                result.error("INVALID_ARGUMENTS", "Missing required terrain parameters", null);
                return;
            }
            
            Log.d(TAG, "Initializing terrain layer: " + layerId);
            Log.d(TAG, "  Bounds: " + bounds);
            Log.d(TAG, "  Dimensions: " + width + "x" + height);
            Log.d(TAG, "  Reference altitude: " + referenceAltitude + "ft, Warning altitude: " + warningAltitude + "ft");
            Log.d(TAG, "  Elevation data size: " + (elevationArray != null ? elevationArray.length : "null"));
            
            // Check if terrain manager is initialized
            if (terrainManager == null) {
                Log.d(TAG, "Terrain manager not yet initialized, queueing initialization for later");
                
                // Store initialization parameters for later
                Map<String, Object> pendingInit = new HashMap<>();
                pendingInit.put("layerId", layerId);
                pendingInit.put("bounds", bounds);
                pendingInit.put("width", width);
                pendingInit.put("height", height);
                pendingInit.put("referenceAltitude", referenceAltitude);
                pendingInit.put("warningAltitude", warningAltitude);
                pendingInit.put("elevationData", elevationArray);
                
                pendingInitializations.put(layerId, pendingInit);
                result.success(null);
                return;
            }
            
            // Initialize terrain layer
            terrainManager.initializeTerrainLayer(
                layerId, 
                elevationArray, 
                width, 
                height, 
                bounds, 
                referenceAltitude, 
                warningAltitude
            );
            
            result.success(null);
            
        } catch (Exception e) {
            Log.e(TAG, "Error initializing terrain layer: " + e.getMessage(), e);
            result.error("TERRAIN_MANAGER_ERROR", "Failed to initialize terrain layer: " + e.getMessage(), null);
        }
    }
    
    /**
     * Handles altitude updates for terrain layers.
     */
    public void handleTerrainUpdateAltitudes(MethodCall call, MethodChannel.Result result) {
        try {
            String layerId = call.argument("layerId");
            if (layerId == null || layerId.isEmpty()) {
                result.error("INVALID_ARGUMENTS", "layerId is required", null);
                return;
            }
            
            Double referenceAltitude = call.argument("referenceAltitude");
            Double warningAltitude = call.argument("warningAltitude");
            
            if (referenceAltitude == null || warningAltitude == null) {
                result.error("INVALID_ARGUMENTS", "Reference and warning altitudes are required", null);
                return;
            }
            
            Log.d(TAG, "Updating altitudes for layer: " + layerId + 
                      " (ref: " + referenceAltitude + "ft, warn: " + warningAltitude + "ft)");
            
            // Check if terrain manager is initialized
            if (terrainManager == null) {
                Log.w(TAG, "Terrain manager not yet initialized, cannot update altitudes");
                result.error("NOT_INITIALIZED", "Terrain manager not initialized", null);
                return;
            }
            
            // Update altitudes
            terrainManager.updateAltitudes(layerId, referenceAltitude, warningAltitude);
            
            result.success(null);
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating terrain altitudes: " + e.getMessage(), e);
            result.error("TERRAIN_MANAGER_ERROR", "Failed to update terrain altitudes: " + e.getMessage(), null);
        }
    }
    
    /**
     * Handles viewport changes to update terrain tiles.
     * This should be called when the camera changes.
     */
    public void updateViewport(org.maplibre.android.camera.CameraPosition cameraPosition) {
        try {
            if (terrainManager == null || mapController.getMapLibreMap() == null) {
                return;
            }
            
            // Get current camera position and visible region
            double currentZoom = cameraPosition.zoom;
            LatLngBounds viewport = mapController.getMapLibreMap().getProjection().getVisibleRegion().latLngBounds;
            
            // Update terrain for all layers - for now, just log since we don't have active layers tracking
            Log.d(TAG, "Updating terrain viewport for zoom: " + String.format("%.2f", currentZoom));
            
            // TODO: Implement terrain manager viewport update when NativeTerrainDataManager is ready
            // terrainManager.handleViewportChange(layerId, viewport, currentZoom);
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling viewport change: " + e.getMessage(), e);
        }
    }
    
    /**
     * Handles terrain layer disposal.
     */
    public void handleTerrainDispose(MethodCall call, MethodChannel.Result result) {
        try {
            String layerId = call.argument("layerId");
            if (layerId == null || layerId.isEmpty()) {
                result.error("INVALID_ARGUMENTS", "layerId is required", null);
                return;
            }
            
            Log.d(TAG, "Disposing terrain layer: " + layerId);
            
            // Remove from pending initializations if present
            pendingInitializations.remove(layerId);
            
            // Check if terrain manager is initialized
            if (terrainManager == null) {
                Log.w(TAG, "Terrain manager not yet initialized, nothing to dispose");
                result.success(null);
                return;
            }
            
            // Dispose terrain layer
            terrainManager.disposeTerrainLayer(layerId);
            
            result.success(null);
            
        } catch (Exception e) {
            Log.e(TAG, "Error disposing terrain layer: " + e.getMessage(), e);
            result.error("TERRAIN_MANAGER_ERROR", "Failed to dispose terrain layer: " + e.getMessage(), null);
        }
    }
    
    /**
     * Processes any pending initializations that were received before the map was ready.
     */
    private void processPendingInitializations() {
        try {
            if (terrainManager == null || pendingInitializations.isEmpty()) {
                return;
            }
            
            Log.d(TAG, "Processing " + pendingInitializations.size() + " pending terrain layer initializations");
            
            for (Map.Entry<String, Object> entry : pendingInitializations.entrySet()) {
                try {
                    String layerId = entry.getKey();
                    @SuppressWarnings("unchecked")
                    Map<String, Object> initParams = (Map<String, Object>) entry.getValue();
                    
                    Log.d(TAG, "Initializing pending terrain layer: " + layerId);
                    
                    terrainManager.initializeTerrainLayer(
                        layerId,
                        (double[]) initParams.get("elevationData"),
                        (Integer) initParams.get("width"),
                        (Integer) initParams.get("height"),
                        (List<Double>) initParams.get("bounds"),
                        (Double) initParams.get("referenceAltitude"),
                        (Double) initParams.get("warningAltitude")
                    );
                    
                } catch (Exception e) {
                    Log.e(TAG, "Error processing pending initialization: " + e.getMessage(), e);
                }
            }
            
            // Clear processed initializations
            pendingInitializations.clear();
            
        } catch (Exception e) {
            Log.e(TAG, "Error processing pending initializations: " + e.getMessage(), e);
        }
    }
    
    /**
     * Returns debug statistics about the terrain manager's caching.
     */
    public String getDebugStats() {
        if (terrainManager == null) {
            return "Terrain manager not initialized";
        }
        return terrainManager.getCacheStats();
    }
    
    /**
     * Cleans up all resources used by the terrain manager.
     */
    public void shutdown() {
        try {
            if (terrainManager != null) {
                Log.d(TAG, "Shutting down terrain manager");
                terrainManager.shutdown();
                terrainManager = null;
            }
            
            pendingInitializations.clear();
            
        } catch (Exception e) {
            Log.e(TAG, "Error shutting down terrain manager: " + e.getMessage(), e);
        }
    }
}
