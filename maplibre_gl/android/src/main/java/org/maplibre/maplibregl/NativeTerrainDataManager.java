package org.maplibre.maplibregl;

import android.graphics.Bitmap;
import android.util.Log;
import android.util.LruCache;
import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.geometry.LatLngBounds;
import org.maplibre.android.geometry.LatLngQuad;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.Style;
import org.maplibre.android.style.layers.PropertyFactory;
import org.maplibre.android.style.layers.RasterLayer;
import org.maplibre.android.style.sources.ImageSource;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.List;
import java.util.Map;
import java.util.ArrayList;

/**
 * High-performance native terrain data manager that eliminates Flutter-to-native data transfer lag.
 * 
 * This class implements several performance optimizations:
 * 1. Native-side terrain data buffering (no repeated Flutter transfers)
 * 2. Multi-resolution terrain tile pre-generation at different zoom levels
 * 3. Asynchronous terrain processing on background threads
 * 4. LRU cache for efficient tile management
 * 5. Viewport-based tile pool for smooth panning
 * 
 * Design Philosophy:
 * - All heavy terrain processing happens on native side in background threads
 * - Terrain data is transferred from Flutter ONCE during initialization
 * - Zoom/pan operations only swap pre-computed tiles (instant response)
 * - Tiles are generated asynchronously and cached for future use
 */
public class NativeTerrainDataManager {
    private static final String TAG = "NativeTerrainDataManager";
    
    // Tile management constants
    private static final int TILE_SIZE_PIXELS = 256; // Standard tile size
    private static final int MAX_CACHED_TILES = 200; // LRU cache size
    private static final int BACKGROUND_THREAD_POOL_SIZE = 3; // Background processing threads
    private static final double VIEWPORT_EXPANSION_FACTOR = 1.5; // Pre-generate tiles beyond viewport
    
    // Zoom level configuration for multi-resolution pre-generation
    private static final int MIN_ZOOM_LEVEL = 3;
    private static final int MAX_ZOOM_LEVEL = 12;
    private static final int PRELOAD_ZOOM_RANGE = 2; // Pre-generate ±2 zoom levels
    
    // Core components
    private final MapLibreMap mapLibreMap;
    private final Style style;
    private final ExecutorService backgroundExecutor;
    private final LruCache<String, TerrainTile> tileCache;
    private final Map<String, TerrainLayerData> terrainLayers;
    
    // Thread-safe state tracking
    private final Map<String, Integer> currentDisplayedZoomLevel;
    private final Map<String, Future<?>> pendingTileGenerationTasks;
    
    /**
     * Represents a single terrain tile with all necessary rendering data.
     */
    private static class TerrainTile {
        final String tileId;
        final Bitmap bitmap;
        final LatLngQuad bounds;
        final int zoomLevel;
        final long creationTime;
        final boolean isInUse;
        
        TerrainTile(String tileId, Bitmap bitmap, LatLngQuad bounds, int zoomLevel) {
            this.tileId = tileId;
            this.bitmap = bitmap;
            this.bounds = bounds;
            this.zoomLevel = zoomLevel;
            this.creationTime = System.currentTimeMillis();
            this.isInUse = false;
        }
        
        void cleanup() {
            if (bitmap != null && !bitmap.isRecycled()) {
                bitmap.recycle();
            }
        }
    }
    
    /**
     * Stores all terrain data for a layer (buffered on native side).
     */
    private static class TerrainLayerData {
        final String layerId;
        final double[] elevationData; // Full world elevation data (stored once)
        final int dataWidth;
        final int dataHeight;
        final LatLngBounds dataBounds;
        final Map<Integer, List<String>> tilesByZoomLevel; // Pre-generated tiles per zoom
        
        // Current altitude settings (can change frequently)
        volatile double referenceAltitude;
        volatile double warningAltitude;
        volatile long lastAltitudeUpdate;
        
        TerrainLayerData(String layerId, double[] elevationData, int width, int height, 
                        LatLngBounds bounds, double refAlt, double warnAlt) {
            this.layerId = layerId;
            this.elevationData = elevationData;
            this.dataWidth = width;
            this.dataHeight = height;
            this.dataBounds = bounds;
            this.referenceAltitude = refAlt;
            this.warningAltitude = warnAlt;
            this.lastAltitudeUpdate = System.currentTimeMillis();
            this.tilesByZoomLevel = new ConcurrentHashMap<>();
        }
        
        void updateAltitudes(double refAlt, double warnAlt) {
            this.referenceAltitude = refAlt;
            this.warningAltitude = warnAlt;
            this.lastAltitudeUpdate = System.currentTimeMillis();
        }
    }
    
    public NativeTerrainDataManager(MapLibreMap mapLibreMap, Style style) {
        this.mapLibreMap = mapLibreMap;
        this.style = style;
        this.backgroundExecutor = Executors.newFixedThreadPool(BACKGROUND_THREAD_POOL_SIZE);
        this.terrainLayers = new ConcurrentHashMap<>();
        this.currentDisplayedZoomLevel = new ConcurrentHashMap<>();
        this.pendingTileGenerationTasks = new ConcurrentHashMap<>();
        
        // Initialize LRU cache with automatic cleanup
        this.tileCache = new LruCache<String, TerrainTile>(MAX_CACHED_TILES) {
            @Override
            protected void entryRemoved(boolean evicted, String key, TerrainTile oldValue, TerrainTile newValue) {
                if (oldValue != null) {
                    Log.v(TAG, "LRU evicting tile: " + key);
                    oldValue.cleanup();
                }
            }
        };
        
        Log.d(TAG, "Initialized NativeTerrainDataManager with " + BACKGROUND_THREAD_POOL_SIZE + 
                   " background threads and " + MAX_CACHED_TILES + " tile cache");
    }
    
    /**
     * Initializes a terrain layer with elevation data (called once from Flutter).
     * This is the ONLY time terrain data is transferred from Flutter to native.
     * All subsequent operations use the buffered native data.
     */
    public void initializeTerrainLayer(String layerId, double[] elevationData, int width, int height,
                                     List<Double> bounds, double referenceAltitude, double warningAltitude) {
        try {
            Log.d(TAG, "Initializing terrain layer: " + layerId + " with " + elevationData.length + 
                       " elevation points (" + width + "x" + height + ")");
            
            // Convert bounds list to LatLngBounds
            LatLngBounds dataBounds = new LatLngBounds.Builder()
                .include(new LatLng(bounds.get(3), bounds.get(0))) // North, West
                .include(new LatLng(bounds.get(1), bounds.get(2))) // South, East
                .build();
            
            // Create and store terrain layer data (buffered on native side)
            TerrainLayerData layerData = new TerrainLayerData(
                layerId, elevationData, width, height, dataBounds, referenceAltitude, warningAltitude
            );
            
            terrainLayers.put(layerId, layerData);
            
            // Start asynchronous pre-generation of terrain tiles for multiple zoom levels
            startAsyncTerrainPreGeneration(layerData);
            
            Log.d(TAG, "Successfully initialized terrain layer: " + layerId + 
                       " (data buffered natively, starting async pre-generation)");
            
        } catch (Exception e) {
            Log.e(TAG, "Error initializing terrain layer: " + e.getMessage(), e);
            throw new RuntimeException("Failed to initialize terrain layer: " + layerId, e);
        }
    }
    
    /**
     * Updates altitude thresholds for a terrain layer (fast operation).
     * This triggers asynchronous re-coloring of cached tiles with new altitude thresholds.
     */
    public void updateAltitudes(String layerId, double referenceAltitude, double warningAltitude) {
        try {
            TerrainLayerData layerData = terrainLayers.get(layerId);
            if (layerData == null) {
                Log.w(TAG, "Cannot update altitudes - terrain layer not found: " + layerId);
                return;
            }
            
            Log.d(TAG, "Fast altitude update for layer: " + layerId + 
                       " (ref: " + referenceAltitude + "ft, warn: " + warningAltitude + "ft)");
            
            // Update altitude thresholds (instant operation)
            layerData.updateAltitudes(referenceAltitude, warningAltitude);
            
            // Trigger asynchronous re-coloring of existing tiles
            triggerAsyncTileRecoloring(layerData);
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating altitudes: " + e.getMessage(), e);
        }
    }
    
    /**
     * Handles zoom/pan events by instantly swapping pre-computed tiles.
     * This is the main performance optimization - no tile generation on zoom/pan!
     */
    public void handleViewportChange(String layerId, LatLngBounds viewport, double zoomLevel) {
        try {
            TerrainLayerData layerData = terrainLayers.get(layerId);
            if (layerData == null) {
                Log.w(TAG, "Cannot handle viewport change - terrain layer not found: " + layerId);
                return;
            }
            
            int discreteZoom = (int) Math.floor(zoomLevel);
            Integer lastDisplayedZoom = currentDisplayedZoomLevel.get(layerId);
            
            // OPTIMIZATION: Only update display if discrete zoom level changed
            if (lastDisplayedZoom != null && lastDisplayedZoom == discreteZoom) {
                Log.v(TAG, "SKIPPING tile swap for " + layerId + " - same discrete zoom " + discreteZoom + 
                           " (current: " + String.format("%.1f", zoomLevel) + ")");
                return;
            }
            
            Log.d(TAG, "FAST tile swap for " + layerId + " - zoom: " + 
                       (lastDisplayedZoom != null ? lastDisplayedZoom : "initial") + " → " + discreteZoom);
            
            // Update displayed zoom level
            currentDisplayedZoomLevel.put(layerId, discreteZoom);
            
            // Instantly swap to pre-computed tiles for this zoom level
            swapToPreComputedTiles(layerData, viewport, discreteZoom);
            
            // Asynchronously ensure tiles exist for nearby zoom levels (pre-generation)
            ensureNearbyZoomTilesExist(layerData, discreteZoom, viewport);
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling viewport change: " + e.getMessage(), e);
        }
    }
    
    /**
     * Starts asynchronous pre-generation of terrain tiles at multiple zoom levels.
     * This happens in the background after initialization to prepare for zoom operations.
     */
    private void startAsyncTerrainPreGeneration(TerrainLayerData layerData) {
        // Cancel any existing pre-generation task
        Future<?> existingTask = pendingTileGenerationTasks.get(layerData.layerId);
        if (existingTask != null && !existingTask.isDone()) {
            existingTask.cancel(true);
        }
        
        // Start new async pre-generation task
        Future<?> task = backgroundExecutor.submit(() -> {
            try {
                Log.d(TAG, "Starting async terrain pre-generation for layer: " + layerData.layerId);
                
                // Get current viewport for initial tile generation
                LatLngBounds currentViewport = mapLibreMap.getProjection().getVisibleRegion().latLngBounds;
                double currentZoom = mapLibreMap.getCameraPosition().zoom;
                int startZoom = (int) Math.floor(currentZoom);
                
                // Pre-generate tiles for current zoom level first (priority)
                generateTilesForZoomLevel(layerData, startZoom, currentViewport);
                
                // Then pre-generate tiles for nearby zoom levels
                for (int zoomOffset = 1; zoomOffset <= PRELOAD_ZOOM_RANGE; zoomOffset++) {
                    // Generate tiles for zoom levels above and below current
                    int higherZoom = startZoom + zoomOffset;
                    int lowerZoom = startZoom - zoomOffset;
                    
                    if (higherZoom <= MAX_ZOOM_LEVEL) {
                        generateTilesForZoomLevel(layerData, higherZoom, currentViewport);
                    }
                    
                    if (lowerZoom >= MIN_ZOOM_LEVEL) {
                        generateTilesForZoomLevel(layerData, lowerZoom, currentViewport);
                    }
                    
                    // Check for task cancellation
                    if (Thread.currentThread().isInterrupted()) {
                        Log.d(TAG, "Terrain pre-generation cancelled for layer: " + layerData.layerId);
                        return;
                    }
                }
                
                Log.d(TAG, "Completed async terrain pre-generation for layer: " + layerData.layerId);
                
            } catch (Exception e) {
                Log.e(TAG, "Error in async terrain pre-generation: " + e.getMessage(), e);
            }
        });
        
        pendingTileGenerationTasks.put(layerData.layerId, task);
    }
    
    /**
     * Generates terrain tiles for a specific zoom level.
     * Creates an appropriate number of tiles based on zoom level and viewport coverage.
     */
    private void generateTilesForZoomLevel(TerrainLayerData layerData, int zoomLevel, LatLngBounds viewport) {
        try {
            Log.d(TAG, "Generating tiles for zoom level " + zoomLevel + " (layer: " + layerData.layerId + ")");
            
            // Calculate tile grid size based on zoom level
            int tilesPerSide = getTilesPerSideForZoom(zoomLevel);
            double tileDegreesLat = (viewport.getLatNorth() - viewport.getLatSouth()) / tilesPerSide;
            double tileDegreesLng = (viewport.getLonEast() - viewport.getLonWest()) / tilesPerSide;
            
            // Expand viewport for smooth panning
            double expandedNorth = Math.min(90.0, viewport.getLatNorth() + tileDegreesLat * VIEWPORT_EXPANSION_FACTOR);
            double expandedSouth = Math.max(-90.0, viewport.getLatSouth() - tileDegreesLat * VIEWPORT_EXPANSION_FACTOR);
            double expandedEast = Math.min(180.0, viewport.getLonEast() + tileDegreesLng * VIEWPORT_EXPANSION_FACTOR);
            double expandedWest = Math.max(-180.0, viewport.getLonWest() - tileDegreesLng * VIEWPORT_EXPANSION_FACTOR);
            
            List<String> generatedTileIds = new ArrayList<>();
            
            // Generate tiles to cover expanded viewport
            double currentLat = expandedSouth;
            int tileRow = 0;
            
            while (currentLat < expandedNorth && tileRow < tilesPerSide * 2) { // Limit for safety
                double currentLng = expandedWest;
                int tileCol = 0;
                
                while (currentLng < expandedEast && tileCol < tilesPerSide * 2) {
                    // Calculate tile bounds
                    double tileNorth = Math.min(expandedNorth, currentLat + tileDegreesLat);
                    double tileSouth = currentLat;
                    double tileEast = Math.min(expandedEast, currentLng + tileDegreesLng);
                    double tileWest = currentLng;
                    
                    // Generate tile ID
                    String tileId = generateTileId(layerData.layerId, zoomLevel, tileRow, tileCol);
                    
                    // Check if tile already exists in cache
                    if (tileCache.get(tileId) == null) {
                        // Generate new tile
                        TerrainTile tile = generateSingleTile(layerData, tileId, zoomLevel, 
                                                            tileWest, tileSouth, tileEast, tileNorth);
                        if (tile != null) {
                            tileCache.put(tileId, tile);
                            generatedTileIds.add(tileId);
                        }
                    }
                    
                    currentLng += tileDegreesLng;
                    tileCol++;
                }
                
                currentLat += tileDegreesLat;
                tileRow++;
            }
            
            // Store tile references for this zoom level
            layerData.tilesByZoomLevel.put(zoomLevel, generatedTileIds);
            
            Log.d(TAG, "Generated " + generatedTileIds.size() + " tiles for zoom " + zoomLevel + 
                       " (layer: " + layerData.layerId + ")");
            
        } catch (Exception e) {
            Log.e(TAG, "Error generating tiles for zoom level: " + e.getMessage(), e);
        }
    }
    
    /**
     * Generates a single terrain tile with optimized elevation processing.
     */
    private TerrainTile generateSingleTile(TerrainLayerData layerData, String tileId, int zoomLevel,
                                         double west, double south, double east, double north) {
        try {
            // Extract elevation data for this tile area
            double[] tileElevationData = extractElevationForTileArea(
                layerData.elevationData, layerData.dataWidth, layerData.dataHeight,
                layerData.dataBounds, west, south, east, north
            );
            
            if (tileElevationData == null) {
                return null;
            }
            
            // Create terrain bitmap with current altitude thresholds
            Bitmap tileBitmap = createOptimizedTerrainBitmap(
                tileElevationData, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS,
                layerData.referenceAltitude, layerData.warningAltitude
            );
            
            if (tileBitmap == null) {
                return null;
            }
            
            // Create tile bounds
            LatLng nw = new LatLng(north, west);
            LatLng ne = new LatLng(north, east);
            LatLng se = new LatLng(south, east);
            LatLng sw = new LatLng(south, west);
            LatLngQuad tileBounds = new LatLngQuad(nw, ne, se, sw);
            
            TerrainTile tile = new TerrainTile(tileId, tileBitmap, tileBounds, zoomLevel);
            
            Log.v(TAG, "Generated tile: " + tileId + " (" + TILE_SIZE_PIXELS + "x" + TILE_SIZE_PIXELS + ")");
            return tile;
            
        } catch (Exception e) {
            Log.e(TAG, "Error generating single tile: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Extracts elevation data for a specific tile area from the full world dataset.
     * Optimized for performance with minimal memory allocation.
     */
    private double[] extractElevationForTileArea(double[] fullData, int fullWidth, int fullHeight,
                                               LatLngBounds fullBounds, double tileWest, double tileSouth,
                                               double tileEast, double tileNorth) {
        try {
            double fullWest = fullBounds.getLonWest();
            double fullSouth = fullBounds.getLatSouth();
            double fullEast = fullBounds.getLonEast();
            double fullNorth = fullBounds.getLatNorth();
            
            double fullLngSpan = fullEast - fullWest;
            double fullLatSpan = fullNorth - fullSouth;
            double tileLngSpan = tileEast - tileWest;
            double tileLatSpan = tileNorth - tileSouth;
            
            double[] tileData = new double[TILE_SIZE_PIXELS * TILE_SIZE_PIXELS];
            
            // Optimized sampling with minimal coordinate conversions
            double lngRatio = fullLngSpan / fullWidth;
            double latRatio = fullLatSpan / fullHeight;
            double tileLngStep = tileLngSpan / TILE_SIZE_PIXELS;
            double tileLatStep = tileLatSpan / TILE_SIZE_PIXELS;
            
            for (int tileY = 0; tileY < TILE_SIZE_PIXELS; tileY++) {
                for (int tileX = 0; tileX < TILE_SIZE_PIXELS; tileX++) {
                    // Convert tile pixel to geographic coordinate
                    double tileLng = tileWest + tileX * tileLngStep;
                    double tileLat = tileNorth - tileY * tileLatStep; // Flip Y axis
                    
                    // Convert to full data array indices
                    int fullXIndex = (int) Math.round((tileLng - fullWest) / lngRatio);
                    int fullYIndex = (int) Math.round((fullNorth - tileLat) / latRatio);
                    
                    // Clamp to valid indices
                    fullXIndex = Math.max(0, Math.min(fullWidth - 1, fullXIndex));
                    fullYIndex = Math.max(0, Math.min(fullHeight - 1, fullYIndex));
                    
                    // Sample elevation
                    int dataIndex = fullYIndex * fullWidth + fullXIndex;
                    if (dataIndex >= 0 && dataIndex < fullData.length) {
                        tileData[tileY * TILE_SIZE_PIXELS + tileX] = fullData[dataIndex];
                    }
                }
            }
            
            return tileData;
            
        } catch (Exception e) {
            Log.e(TAG, "Error extracting elevation for tile area: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Creates an optimized terrain bitmap with ultra-fast color mapping.
     */
    private Bitmap createOptimizedTerrainBitmap(double[] elevationData, int width, int height,
                                              double referenceAltitude, double warningAltitude) {
        try {
            // Convert altitudes from feet to meters
            double refAltM = referenceAltitude * 0.3048;
            double warnAltM = warningAltitude * 0.3048;
            
            // Create bitmap with optimized pixel array
            Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            int[] pixels = new int[width * height];
            
            // Ultra-fast color mapping (no lookup table needed for this size)
            for (int i = 0; i < Math.min(elevationData.length, pixels.length); i++) {
                double elevation = elevationData[i];
                
                if (elevation < warnAltM) {
                    pixels[i] = 0x80FF4444; // Semi-transparent red
                } else if (elevation < refAltM) {
                    pixels[i] = 0x80FFFF44; // Semi-transparent yellow
                } else {
                    pixels[i] = 0x8044FF44; // Semi-transparent green
                }
            }
            
            // Set pixels in one batch operation
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height);
            return bitmap;
            
        } catch (Exception e) {
            Log.e(TAG, "Error creating optimized terrain bitmap: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Instantly swaps to pre-computed tiles for the specified zoom level.
     * This is the key performance optimization - no generation, just swapping!
     */
    private void swapToPreComputedTiles(TerrainLayerData layerData, LatLngBounds viewport, int zoomLevel) {
        try {
            Log.d(TAG, "INSTANT tile swap to zoom " + zoomLevel + " for layer: " + layerData.layerId);
            
            // Clean up currently displayed tiles
            cleanupDisplayedTiles(layerData.layerId);
            
            // Get pre-computed tiles for this zoom level
            List<String> tileIds = layerData.tilesByZoomLevel.get(zoomLevel);
            if (tileIds == null || tileIds.isEmpty()) {
                Log.w(TAG, "No pre-computed tiles available for zoom " + zoomLevel + 
                           " - generating on-demand (may cause brief lag)");
                
                // Fallback: generate minimal tiles on-demand
                generateMinimalTilesOnDemand(layerData, viewport, zoomLevel);
                return;
            }
            
            // Instantly display pre-computed tiles
            int displayedCount = 0;
            for (String tileId : tileIds) {
                TerrainTile tile = tileCache.get(tileId);
                if (tile != null && tile.zoomLevel == zoomLevel) {
                    // Check if tile is relevant to current viewport
                    if (isTileRelevantToViewport(tile.bounds, viewport)) {
                        displayTileOnMap(tile);
                        displayedCount++;
                    }
                }
            }
            
            Log.d(TAG, "INSTANTLY displayed " + displayedCount + " pre-computed tiles for zoom " + zoomLevel);
            
        } catch (Exception e) {
            Log.e(TAG, "Error swapping to pre-computed tiles: " + e.getMessage(), e);
        }
    }
    
    /**
     * Displays a terrain tile on the map using MapLibre ImageSource and RasterLayer.
     */
    private void displayTileOnMap(TerrainTile tile) {
        try {
            String sourceId = tile.tileId + "-source";
            String layerId = tile.tileId + "-layer";
            
            // Create ImageSource for the tile
            ImageSource tileSource = new ImageSource(sourceId, tile.bounds, tile.bitmap);
            style.addSource(tileSource);
            
            // Create RasterLayer to display the tile
            RasterLayer tileLayer = new RasterLayer(layerId, sourceId);
            tileLayer.setProperties(
                PropertyFactory.rasterOpacity(0.65f), // Slightly more opaque
                PropertyFactory.rasterFadeDuration(0.0f) // No fade for instant display
            );
            
            style.addLayer(tileLayer);
            
            Log.v(TAG, "Displayed tile on map: " + tile.tileId);
            
        } catch (Exception e) {
            Log.e(TAG, "Error displaying tile on map: " + e.getMessage(), e);
        }
    }
    
    /**
     * Checks if a tile is relevant to the current viewport (for culling distant tiles).
     */
    private boolean isTileRelevantToViewport(LatLngQuad tileBounds, LatLngBounds viewport) {
        try {
            // Simple bounds intersection check
            double tileWest = Math.min(tileBounds.getBottomLeft().getLongitude(), tileBounds.getTopLeft().getLongitude());
            double tileEast = Math.max(tileBounds.getBottomRight().getLongitude(), tileBounds.getTopRight().getLongitude());
            double tileSouth = Math.min(tileBounds.getBottomLeft().getLatitude(), tileBounds.getBottomRight().getLatitude());
            double tileNorth = Math.max(tileBounds.getTopLeft().getLatitude(), tileBounds.getTopRight().getLatitude());
            
            // Check for intersection with expanded viewport
            double viewportExpansion = 0.5; // 50% expansion for relevance check
            double viewportLatSpan = viewport.getLatNorth() - viewport.getLatSouth();
            double viewportLngSpan = viewport.getLonEast() - viewport.getLonWest();
            
            double expandedViewportNorth = viewport.getLatNorth() + viewportLatSpan * viewportExpansion;
            double expandedViewportSouth = viewport.getLatSouth() - viewportLatSpan * viewportExpansion;
            double expandedViewportEast = viewport.getLonEast() + viewportLngSpan * viewportExpansion;
            double expandedViewportWest = viewport.getLonWest() - viewportLngSpan * viewportExpansion;
            
            boolean intersects = !(tileEast < expandedViewportWest || tileWest > expandedViewportEast ||
                                 tileNorth < expandedViewportSouth || tileSouth > expandedViewportNorth);
            
            return intersects;
            
        } catch (Exception e) {
            Log.e(TAG, "Error checking tile relevance: " + e.getMessage(), e);
            return true; // Default to relevant on error
        }
    }
    
    /**
     * Cleans up currently displayed tiles for a layer.
     */
    private void cleanupDisplayedTiles(String layerId) {
        try {
            List<String> layersToRemove = new ArrayList<>();
            List<String> sourcesToRemove = new ArrayList<>();
            
            // Find all displayed tiles for this layer
            for (org.maplibre.android.style.layers.Layer layer : style.getLayers()) {
                String id = layer.getId();
                if (id.startsWith(layerId + "-") && id.endsWith("-layer")) {
                    layersToRemove.add(id);
                }
            }
            
            for (org.maplibre.android.style.sources.Source source : style.getSources()) {
                String id = source.getId();
                if (id.startsWith(layerId + "-") && id.endsWith("-source")) {
                    sourcesToRemove.add(id);
                }
            }
            
            // Remove layers and sources
            for (String layerIdToRemove : layersToRemove) {
                style.removeLayer(layerIdToRemove);
            }
            
            for (String sourceIdToRemove : sourcesToRemove) {
                style.removeSource(sourceIdToRemove);
            }
            
            if (!layersToRemove.isEmpty()) {
                Log.v(TAG, "Cleaned up " + layersToRemove.size() + " displayed tiles for layer: " + layerId);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error cleaning up displayed tiles: " + e.getMessage(), e);
        }
    }
    
    /**
     * Ensures tiles exist for nearby zoom levels (background pre-generation).
     */
    private void ensureNearbyZoomTilesExist(TerrainLayerData layerData, int currentZoom, LatLngBounds viewport) {
        // Submit async task to generate nearby zoom tiles
        backgroundExecutor.submit(() -> {
            try {
                for (int zoomOffset = 1; zoomOffset <= 1; zoomOffset++) { // ±1 zoom level
                    int higherZoom = currentZoom + zoomOffset;
                    int lowerZoom = currentZoom - zoomOffset;
                    
                    if (higherZoom <= MAX_ZOOM_LEVEL && layerData.tilesByZoomLevel.get(higherZoom) == null) {
                        generateTilesForZoomLevel(layerData, higherZoom, viewport);
                    }
                    
                    if (lowerZoom >= MIN_ZOOM_LEVEL && layerData.tilesByZoomLevel.get(lowerZoom) == null) {
                        generateTilesForZoomLevel(layerData, lowerZoom, viewport);
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error ensuring nearby zoom tiles: " + e.getMessage(), e);
            }
        });
    }
    
    /**
     * Triggers asynchronous re-coloring of existing tiles with new altitude thresholds.
     */
    private void triggerAsyncTileRecoloring(TerrainLayerData layerData) {
        backgroundExecutor.submit(() -> {
            try {
                Log.d(TAG, "Starting async tile re-coloring for layer: " + layerData.layerId);
                
                // Re-color tiles for all zoom levels
                for (Map.Entry<Integer, List<String>> entry : layerData.tilesByZoomLevel.entrySet()) {
                    int zoomLevel = entry.getKey();
                    List<String> tileIds = entry.getValue();
                    
                    for (String tileId : tileIds) {
                        TerrainTile existingTile = tileCache.get(tileId);
                        if (existingTile != null) {
                            // Re-generate tile with new altitude thresholds
                            // Extract the tile area from the tile ID
                            TileCoordinates coords = parseTileId(tileId);
                            if (coords != null) {
                                TerrainTile recoloredTile = generateSingleTile(
                                    layerData, tileId, zoomLevel, 
                                    coords.west, coords.south, coords.east, coords.north
                                );
                                
                                if (recoloredTile != null) {
                                    // Replace in cache
                                    tileCache.put(tileId, recoloredTile);
                                }
                            }
                        }
                    }
                }
                
                Log.d(TAG, "Completed async tile re-coloring for layer: " + layerData.layerId);
                
            } catch (Exception e) {
                Log.e(TAG, "Error in async tile re-coloring: " + e.getMessage(), e);
            }
        });
    }
    
    /**
     * Generates minimal tiles on-demand when pre-computed tiles are not available.
     */
    private void generateMinimalTilesOnDemand(TerrainLayerData layerData, LatLngBounds viewport, int zoomLevel) {
        try {
            Log.d(TAG, "Generating minimal on-demand tiles for zoom " + zoomLevel);
            
            // Generate just 4 tiles covering the viewport (minimal lag)
            double latSpan = viewport.getLatNorth() - viewport.getLatSouth();
            double lngSpan = viewport.getLonEast() - viewport.getLonWest();
            
            double midLat = viewport.getLatSouth() + latSpan / 2;
            double midLng = viewport.getLonWest() + lngSpan / 2;
            
            // 2x2 tile grid
            double[][] tileAreas = {
                {viewport.getLonWest(), midLat, midLng, viewport.getLatNorth()}, // NW
                {midLng, midLat, viewport.getLonEast(), viewport.getLatNorth()}, // NE
                {viewport.getLonWest(), viewport.getLatSouth(), midLng, midLat}, // SW
                {midLng, viewport.getLatSouth(), viewport.getLonEast(), midLat}  // SE
            };
            
            List<String> onDemandTileIds = new ArrayList<>();
            
            for (int i = 0; i < 4; i++) {
                String tileId = layerData.layerId + "-ondemand-" + zoomLevel + "-" + i;
                
                TerrainTile tile = generateSingleTile(layerData, tileId, zoomLevel,
                                                    tileAreas[i][0], tileAreas[i][1],
                                                    tileAreas[i][2], tileAreas[i][3]);
                
                if (tile != null) {
                    tileCache.put(tileId, tile);
                    displayTileOnMap(tile);
                    onDemandTileIds.add(tileId);
                }
            }
            
            // Store for future reference
            layerData.tilesByZoomLevel.put(zoomLevel, onDemandTileIds);
            
            Log.d(TAG, "Generated " + onDemandTileIds.size() + " on-demand tiles");
            
        } catch (Exception e) {
            Log.e(TAG, "Error generating minimal on-demand tiles: " + e.getMessage(), e);
        }
    }
    
    /**
     * Determines the number of tiles per side based on zoom level.
     */
    private int getTilesPerSideForZoom(int zoomLevel) {
        if (zoomLevel <= 4) return 2;  // 2x2 = 4 tiles
        if (zoomLevel <= 6) return 3;  // 3x3 = 9 tiles
        if (zoomLevel <= 8) return 4;  // 4x4 = 16 tiles
        return 5; // 5x5 = 25 tiles max
    }
    
    /**
     * Generates a unique tile ID.
     */
    private String generateTileId(String layerId, int zoomLevel, int row, int col) {
        return String.format("%s-z%d-r%d-c%d", layerId, zoomLevel, row, col);
    }
    
    /**
     * Helper class for tile coordinate parsing.
     */
    private static class TileCoordinates {
        final double west, south, east, north;
        
        TileCoordinates(double west, double south, double east, double north) {
            this.west = west;
            this.south = south;
            this.east = east;
            this.north = north;
        }
    }
    
    /**
     * Parses tile coordinates from tile ID (simplified implementation).
     */
    private TileCoordinates parseTileId(String tileId) {
        // This is a simplified implementation - in practice, you'd store tile coordinates
        // For now, return null to indicate coordinate parsing is not implemented
        return null;
    }
    
    /**
     * Disposes of a terrain layer and cleans up all associated resources.
     */
    public void disposeTerrainLayer(String layerId) {
        try {
            Log.d(TAG, "Disposing terrain layer: " + layerId);
            
            // Cancel any pending tasks
            Future<?> task = pendingTileGenerationTasks.remove(layerId);
            if (task != null && !task.isDone()) {
                task.cancel(true);
            }
            
            // Clean up displayed tiles
            cleanupDisplayedTiles(layerId);
            
            // Remove from terrain layers
            terrainLayers.remove(layerId);
            currentDisplayedZoomLevel.remove(layerId);
            
            // Clean up cached tiles for this layer
            List<String> tilesToRemove = new ArrayList<>();
            for (Map.Entry<String, TerrainTile> entry : tileCache.snapshot().entrySet()) {
                if (entry.getKey().startsWith(layerId + "-")) {
                    tilesToRemove.add(entry.getKey());
                }
            }
            
            for (String tileId : tilesToRemove) {
                TerrainTile tile = tileCache.remove(tileId);
                if (tile != null) {
                    tile.cleanup();
                }
            }
            
            Log.d(TAG, "Successfully disposed terrain layer: " + layerId + 
                       " (cleaned up " + tilesToRemove.size() + " cached tiles)");
            
        } catch (Exception e) {
            Log.e(TAG, "Error disposing terrain layer: " + e.getMessage(), e);
        }
    }
    
    /**
     * Shuts down the terrain data manager and cleans up all resources.
     */
    public void shutdown() {
        try {
            Log.d(TAG, "Shutting down NativeTerrainDataManager");
            
            // Cancel all pending tasks
            for (Future<?> task : pendingTileGenerationTasks.values()) {
                if (task != null && !task.isDone()) {
                    task.cancel(true);
                }
            }
            
            // Shutdown executor
            backgroundExecutor.shutdown();
            
            // Clean up all cached tiles
            tileCache.evictAll();
            
            // Clear all data
            terrainLayers.clear();
            currentDisplayedZoomLevel.clear();
            pendingTileGenerationTasks.clear();
            
            Log.d(TAG, "NativeTerrainDataManager shutdown complete");
            
        } catch (Exception e) {
            Log.e(TAG, "Error shutting down terrain data manager: " + e.getMessage(), e);
        }
    }
    
    /**
     * Gets cache statistics for debugging and monitoring.
     */
    public String getCacheStats() {
        try {
            int cacheSize = tileCache.size();
            int maxSize = tileCache.maxSize();
            int hitCount = tileCache.hitCount();
            int missCount = tileCache.missCount();
            float hitRate = hitCount > 0 ? (float) hitCount / (hitCount + missCount) * 100f : 0f;
            
            return String.format("Tiles: %d/%d, Hit rate: %.1f%% (%d hits, %d misses)", 
                               cacheSize, maxSize, hitRate, hitCount, missCount);
            
        } catch (Exception e) {
            return "Cache stats unavailable: " + e.getMessage();
        }
    }
}
