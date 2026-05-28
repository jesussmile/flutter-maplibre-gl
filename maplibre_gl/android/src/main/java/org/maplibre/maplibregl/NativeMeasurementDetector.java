package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.util.Log;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.style.layers.Layer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.layers.CircleLayer;
import org.maplibre.android.style.layers.SymbolLayer;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;
import org.maplibre.geojson.FeatureCollection;

import static org.maplibre.android.style.expressions.Expression.*;
import static org.maplibre.android.style.layers.PropertyFactory.*;

/**
 * Native two-finger measurement detector that extends TwoFingerHoldGestureDetector
 * to provide measurement functionality with gesture detection, calculation, and rendering.
 */
public class NativeMeasurementDetector {
    private static final String TAG = "NativeMeasurementDetector";
    private static final long HOLD_DURATION_MS = 500; // 500ms hold duration
    private static final float MOVEMENT_THRESHOLD = 50f; // pixels
    
    // MapLibre style constants for measurement rendering
    private static final String MEASUREMENT_SOURCE_ID = "measurement-source";
    private static final String MEASUREMENT_LINE_LAYER_ID = "measurement-line-layer";
    private static final String MEASUREMENT_POINTS_LAYER_ID = "measurement-points-layer";
    private static final String MEASUREMENT_DISTANCE_LAYER_ID = "measurement-distance-layer";
    private static final String MEASUREMENT_BEARING_LAYER_ID = "measurement-bearing-layer";
    private static final String MEASUREMENT_ARROWS_LAYER_ID = "measurement-arrows-layer";
    private static final String[] MEASUREMENT_COMPAT_SOURCE_IDS = new String[] {
            "measurement-line-source",
            "measurement-points-source",
            "measurement-distance-source",
            "measurement-bearing-source",
            "measurement-arrows-source"
    };
    
    private final MapLibreMap mapLibreMap;
    private final OnNativeMeasurementListener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    
    // Gesture state
    private boolean isTwoFingerDown = false;
    private PointF initialPoint1;
    private PointF initialPoint2;
    private PointF currentPoint1;
    private PointF currentPoint2;
    private long gestureStartTime;
    private Runnable holdRunnable;
    
    // Measurement state
    private boolean isMeasuring = false;
    private boolean hasPersistentMeasurement = false;
    private LatLng startLatLng;
    private LatLng endLatLng;
    
    // Dragging state for persistent measurement
    private boolean isDraggingStart = false;
    private boolean isDraggingEnd = false;
    private static final float MARKER_TOUCH_RADIUS = 56f; // pixels
    
    // Track if we just finished creating a measurement to prevent immediate cleanup
    private boolean justFinishedMeasurement = false;
    private long measurementEndTime = 0;
    private static final long CLEANUP_GRACE_PERIOD_MS = 500; // 500ms grace period
    
    // Track when user is performing a tap-to-clear gesture
    private boolean pendingClearGesture = false;
    private PointF initialTouchPoint;
    private static final float TAP_MOVEMENT_THRESHOLD = 20f; // pixels - max movement for tap vs pan
    
    // Measurement style configuration - Aviation-friendly colors
    private String lineColor = "#00BFFF";        // Deep sky blue - highly visible on most map backgrounds
    private double lineWidth = 4.0;              // Slightly thicker for better visibility
    private double lineOpacity = 0.9;            // Higher opacity for better contrast
    private String endpointColor = "#FF4500";    // Orange red - aviation standard for important markers
    private double endpointRadius = 14.0;        // Larger for better touch targeting and visibility
    
    public interface OnNativeMeasurementListener {
        void onMeasurementStart(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2, 
                               double distance, double bearing, long duration);
        void onMeasurementUpdate(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2, 
                                double distance, double bearing, long duration);
        void onMeasurementEnd(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2, 
                             double distance, double bearing, long duration);
    }
    
    public NativeMeasurementDetector(MapLibreMap mapLibreMap, OnNativeMeasurementListener listener) {
        this.mapLibreMap = mapLibreMap;
        this.listener = listener;
        
        // Initialize measurement style layers
        initializeMeasurementLayers();
    }
    
    public boolean onTouchEvent(MotionEvent event) {
        // If we have a persistent measurement and not currently creating a new one, 
        // check for marker dragging but only for single-finger gestures
        if (hasPersistentMeasurement && !isMeasuring && event.getPointerCount() == 1) {
            if (handlePersistentMeasurementTouch(event)) {
                return true; // Consumed the event - prevents map interaction
            }
        }
        
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                // First finger down
                if (event.getPointerCount() == 1) {
                    initialPoint1 = new PointF(event.getX(), event.getY());
                    currentPoint1 = new PointF(event.getX(), event.getY());
                }
                break;
                
            case MotionEvent.ACTION_POINTER_DOWN:
                // Second finger down
                if (event.getPointerCount() == 2) {
                    initialPoint2 = new PointF(event.getX(1), event.getY(1));
                    currentPoint2 = new PointF(event.getX(1), event.getY(1));
                    
                    isTwoFingerDown = true;
                    gestureStartTime = System.currentTimeMillis();
                    
                    // Schedule the hold detection for measurement start. Do not
                    // consume this pointer event yet; a moving two-finger
                    // gesture should stay available to MapLibre for pinch zoom.
                    holdRunnable = new Runnable() {
                        @Override
                        public void run() {
                            if (isTwoFingerDown && !isMeasuring && listener != null) {
                                startMeasurement();
                            }
                        }
                    };
                    handler.postDelayed(holdRunnable, HOLD_DURATION_MS);
                    return false;
                }
                break;
                
            case MotionEvent.ACTION_MOVE:
                if (isTwoFingerDown && event.getPointerCount() == 2) {
                    float currentX1 = event.getX(0);
                    float currentY1 = event.getY(0);
                    float currentX2 = event.getX(1);
                    float currentY2 = event.getY(1);
                    
                    // Update current positions
                    currentPoint1.set(currentX1, currentY1);
                    currentPoint2.set(currentX2, currentY2);
                    
                    if (isMeasuring) {
                        // Update measurement during active measurement
                        updateMeasurement();
                        return true; // Consume the event to prevent map interaction during measurement
                    } else {
                        // Check if fingers moved too much during initial hold
                        float distance1 = calculateDistance(currentX1, currentY1, initialPoint1.x, initialPoint1.y);
                        float distance2 = calculateDistance(currentX2, currentY2, initialPoint2.x, initialPoint2.y);
                        
                        if (distance1 > MOVEMENT_THRESHOLD || distance2 > MOVEMENT_THRESHOLD) {
                            cancelGesture();
                        }
                        return false; // Allow pinch/pan until the hold becomes a measurement.
                    }
                }
                break;
                
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (isMeasuring) {
                    endMeasurement();
                    return true; // Consume the event when ending measurement
                } else {
                    cancelGesture();
                    return false;
                }
        }
        
        // Return true if we're actively measuring or dragging to consume touch events
        return isMeasuring || isDraggingStart || isDraggingEnd;
    }
    
    private void startMeasurement() {
        if (currentPoint1 == null || currentPoint2 == null) return;
        
        try {
            startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
            endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
            
            isMeasuring = true;
            long duration = System.currentTimeMillis() - gestureStartTime;
            
            // Calculate distance and bearing
            double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
            double bearing = calculateBearing(startLatLng, endLatLng);
            
            Log.d(TAG, String.format("Measurement started: distance=%.2f nm, bearing=%.1f°", distance, bearing));
            
            // Render measurement line on map
            renderMeasurementLine(startLatLng, endLatLng);
            
            if (listener != null) {
                listener.onMeasurementStart(currentPoint1, currentPoint2, startLatLng, endLatLng, 
                                          distance, bearing, duration);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error starting measurement", e);
            cancelGesture();
        }
    }
    
    private void updateMeasurement() {
        if (!isMeasuring || currentPoint1 == null || currentPoint2 == null) return;
        
        try {
            startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
            endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
            
            long duration = System.currentTimeMillis() - gestureStartTime;
            
            // Calculate distance and bearing
            double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
            double bearing = calculateBearing(startLatLng, endLatLng);
            
            // Update measurement line rendering
            renderMeasurementLine(startLatLng, endLatLng);
            
            if (listener != null) {
                listener.onMeasurementUpdate(currentPoint1, currentPoint2, startLatLng, endLatLng, 
                                           distance, bearing, duration);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error updating measurement", e);
        }
    }
    
    private void endMeasurement() {
        if (!isMeasuring || currentPoint1 == null || currentPoint2 == null) return;
        
        try {
            startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
            endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
            
            long duration = System.currentTimeMillis() - gestureStartTime;
            
            // Calculate final distance and bearing
            double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
            double bearing = calculateBearing(startLatLng, endLatLng);
            
            Log.d(TAG, String.format("Measurement ended: distance=%.2f nm, bearing=%.1f°", distance, bearing));
            
            // Make measurement persistent
            hasPersistentMeasurement = true;
            justFinishedMeasurement = true;
            measurementEndTime = System.currentTimeMillis();
            
            // Automatically reset grace period after timeout
            handler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    justFinishedMeasurement = false;
                    Log.d(TAG, "Grace period expired - tap-to-clear now enabled");
                }
            }, CLEANUP_GRACE_PERIOD_MS);
            
            renderMeasurementLine(startLatLng, endLatLng);
            
            if (listener != null) {
                listener.onMeasurementEnd(currentPoint1, currentPoint2, startLatLng, endLatLng, 
                                        distance, bearing, duration);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error ending measurement", e);
        } finally {
            // Reset gesture state but keep measurement persistent
            isMeasuring = false;
            isTwoFingerDown = false;
            initialPoint1 = null;
            initialPoint2 = null;
            currentPoint1 = null;
            currentPoint2 = null;
        }
    }
    
    private void cancelGesture() {
        isTwoFingerDown = false;
        isMeasuring = false;
        if (holdRunnable != null) {
            handler.removeCallbacks(holdRunnable);
            holdRunnable = null;
        }
        
        // Don't clear persistent measurement, only clear if we were in the middle of creating one
        if (!hasPersistentMeasurement) {
            clearMeasurementRendering();
        }
        
        // Reset gesture state
        initialPoint1 = null;
        initialPoint2 = null;
        currentPoint1 = null;
        currentPoint2 = null;
        
        // Reset dragging state
        isDraggingStart = false;
        isDraggingEnd = false;
    }
    
    /**
     * Calculate distance between two points in pixels
     */
    private float calculateDistance(float x1, float y1, float x2, float y2) {
        return (float) Math.sqrt(Math.pow(x2 - x1, 2) + Math.pow(y2 - y1, 2));
    }
    
    /**
     * Calculate distance between two geographic points in nautical miles
     */
    private double calculateDistanceNauticalMiles(LatLng from, LatLng to) {
        // Use the more accurate calculation method directly
        return calculateDistanceSimple(from, to);
    }
    
    /**
     * Simple distance calculation fallback (less accurate)
     */
    private double calculateDistanceSimple(LatLng from, LatLng to) {
        double earthRadius = 3440.065; // Earth radius in nautical miles
        double dLat = Math.toRadians(to.getLatitude() - from.getLatitude());
        double dLon = Math.toRadians(to.getLongitude() - from.getLongitude());
        
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(from.getLatitude())) * Math.cos(Math.toRadians(to.getLatitude())) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        return earthRadius * c;
    }
    
    /**
     * Calculate bearing between two geographic points in degrees
     */
    private double calculateBearing(LatLng from, LatLng to) {
        // Use the simple calculation method directly
        return calculateBearingSimple(from, to);
    }
    
    /**
     * Simple bearing calculation fallback
     */
    private double calculateBearingSimple(LatLng from, LatLng to) {
        double dLon = Math.toRadians(to.getLongitude() - from.getLongitude());
        double fromLatRad = Math.toRadians(from.getLatitude());
        double toLatRad = Math.toRadians(to.getLatitude());
        
        double y = Math.sin(dLon) * Math.cos(toLatRad);
        double x = Math.cos(fromLatRad) * Math.sin(toLatRad) - 
                  Math.sin(fromLatRad) * Math.cos(toLatRad) * Math.cos(dLon);
        
        double bearing = Math.atan2(y, x);
        return (Math.toDegrees(bearing) + 360) % 360;
    }
    
    /**
     * Handle touch events for persistent measurement markers
     */
    private boolean handlePersistentMeasurementTouch(MotionEvent event) {
        if (startLatLng == null || endLatLng == null) return false;
        
        PointF touchPoint = new PointF(event.getX(), event.getY());
        PointF startScreenPoint = mapLibreMap.getProjection().toScreenLocation(startLatLng);
        PointF endScreenPoint = mapLibreMap.getProjection().toScreenLocation(endLatLng);
        
        // Check if we're in the grace period after just finishing a measurement
        long currentTime = System.currentTimeMillis();
        boolean inGracePeriod = justFinishedMeasurement && 
                               (currentTime - measurementEndTime) < CLEANUP_GRACE_PERIOD_MS;
        
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                // Reset pending clear gesture flag and store initial touch point
                pendingClearGesture = false;
                initialTouchPoint = new PointF(touchPoint.x, touchPoint.y);
                
                // Reset grace period flag only on a clear new gesture (single finger down)
                // Don't reset during multi-finger scenarios
                if (event.getPointerCount() == 1 && !inGracePeriod) {
                    justFinishedMeasurement = false;
                }
                
                float distanceToStart = calculateDistance(touchPoint.x, touchPoint.y, startScreenPoint.x, startScreenPoint.y);
                float distanceToEnd = calculateDistance(touchPoint.x, touchPoint.y, endScreenPoint.x, endScreenPoint.y);
                
                if (distanceToStart <= MARKER_TOUCH_RADIUS) {
                    isDraggingStart = true;
                    Log.d(TAG, "Started dragging start marker - disabling map interaction");
                    return true; // Consume event to prevent map interaction
                } else if (distanceToEnd <= MARKER_TOUCH_RADIUS) {
                    isDraggingEnd = true;
                    Log.d(TAG, "Started dragging end marker - disabling map interaction");
                    return true; // Consume event to prevent map interaction
                } else if (inGracePeriod) {
                    // We're in grace period - don't clear measurement yet, but allow map interaction
                    Log.d(TAG, "Touch during grace period - allowing map interaction");
                    return false; // Don't consume - allow map interaction
                } else {
                    // Touch is not on any marker and not in grace period - this could be a tap or pan
                    // Set flag to track potential tap-to-clear, but don't consume yet
                    pendingClearGesture = true;
                    Log.d(TAG, "Touch detected outside markers - monitoring for tap vs pan");
                    return false; // Don't consume initially - allow map interaction to start
                }
                
            case MotionEvent.ACTION_MOVE:
                if (isDraggingStart || isDraggingEnd) {
                    LatLng newPosition = mapLibreMap.getProjection().fromScreenLocation(touchPoint);
                    
                    if (isDraggingStart) {
                        startLatLng = newPosition;
                    } else if (isDraggingEnd) {
                        endLatLng = newPosition;
                    }
                    
                    // Update measurement rendering
                    renderMeasurementLine(startLatLng, endLatLng);
                    
                    // Notify listener of update
                    if (listener != null) {
                        double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
                        double bearing = calculateBearing(startLatLng, endLatLng);
                        listener.onMeasurementUpdate(startScreenPoint, endScreenPoint, startLatLng, endLatLng, 
                                                   distance, bearing, 0);
                    }
                    return true; // Consume event to prevent map interaction
                } else if (pendingClearGesture && initialTouchPoint != null && !inGracePeriod) {
                    // Check if user has moved beyond tap threshold - if so, it's a pan gesture
                    float moveDistance = calculateDistance(touchPoint.x, touchPoint.y, initialTouchPoint.x, initialTouchPoint.y);
                    if (moveDistance > TAP_MOVEMENT_THRESHOLD) {
                        // User is panning - cancel the potential clear gesture and allow map interaction
                        Log.d(TAG, "Movement detected beyond tap threshold - canceling clear gesture");
                        pendingClearGesture = false;
                        initialTouchPoint = null; 
                        return false; // Don't consume - allow map interaction
                    }
                    // Still within tap threshold, keep tracking but don't consume yet
                    return false; // Don't consume - allow map interaction to continue
                }
                // Not dragging and no pending clear gesture - allow normal map interaction
                return false;
                
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (isDraggingStart || isDraggingEnd) {
                    Log.d(TAG, "Finished dragging marker - re-enabling map interaction");
                    
                    // Notify listener of final position
                    if (listener != null) {
                        double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
                        double bearing = calculateBearing(startLatLng, endLatLng);
                        listener.onMeasurementEnd(startScreenPoint, endScreenPoint, startLatLng, endLatLng, 
                                                distance, bearing, 0);
                    }
                    
                    // Reset dragging state
                    isDraggingStart = false;
                    isDraggingEnd = false;
                    return true; // Consume event to prevent map interaction
                } else if (pendingClearGesture && initialTouchPoint != null && !inGracePeriod) {
                    // Check if this was a tap (minimal movement) vs a pan (lots of movement)
                    float moveDistance = calculateDistance(touchPoint.x, touchPoint.y, initialTouchPoint.x, initialTouchPoint.y);
                    if (moveDistance <= TAP_MOVEMENT_THRESHOLD) {
                        // This was a tap - clear the measurement
                        Log.d(TAG, "Tap detected - clearing measurement");
                        clearMeasurement();
                        pendingClearGesture = false;
                        initialTouchPoint = null;
                        return true; // Consume event to prevent map interaction
                    } else {
                        // This was a pan - don't clear measurement, allow map interaction
                        Log.d(TAG, "Pan detected - not clearing measurement, allowing map interaction");
                        pendingClearGesture = false;
                        initialTouchPoint = null;
                        return false; // Don't consume - allow map interaction
                    }
                } else if (inGracePeriod) {
                    // In grace period - don't clear measurement, allow map interaction
                    Log.d(TAG, "ACTION_UP during grace period - allowing map interaction");
                    return false; // Don't consume - allow map interaction
                } else {
                    // No pending clear gesture and not dragging - allow normal map interaction
                    Log.d(TAG, "ACTION_UP with no measurement interaction - allowing map interaction");
                    pendingClearGesture = false;
                    initialTouchPoint = null;
                    return false; // Don't consume - allow map interaction
                }
        }
        
        // Only consume events if we're actively handling measurement interactions
        // Allow map interactions for touches that don't involve measurement markers
        return false; // Don't consume - allow map interaction for other touches
    }
    
    /**
     * Ensure all measurement layers are positioned on top of other map layers
     * This method should be called when other layers are added to maintain proper layer ordering
     * OPTIMIZATION: Now called conditionally to prevent excessive repositioning
     */
    public void ensureMeasurementLayersOnTop() {
        try {
            if (mapLibreMap.getStyle() == null || !mapLibreMap.getStyle().isFullyLoaded()) {
                Log.w(TAG, "Map style not ready for layer repositioning");
                return;
            }
            
            // Get the topmost non-measurement layer ID to position measurement layers above it
            String topLayerId = getTopNonMeasurementLayerId();
            
            if (topLayerId != null) {
                // Check if layers actually need repositioning to avoid unnecessary operations
                boolean actuallyRepositioned = false;
                
                // Reposition measurement layers in correct order (bottom to top)
                actuallyRepositioned |= repositionLayerIfExists(MEASUREMENT_LINE_LAYER_ID, topLayerId);
                actuallyRepositioned |= repositionLayerIfExists(MEASUREMENT_POINTS_LAYER_ID, MEASUREMENT_LINE_LAYER_ID);
                actuallyRepositioned |= repositionLayerIfExists(MEASUREMENT_DISTANCE_LAYER_ID, MEASUREMENT_POINTS_LAYER_ID);
                actuallyRepositioned |= repositionLayerIfExists(MEASUREMENT_BEARING_LAYER_ID, MEASUREMENT_DISTANCE_LAYER_ID);
                actuallyRepositioned |= repositionLayerIfExists(MEASUREMENT_ARROWS_LAYER_ID, MEASUREMENT_BEARING_LAYER_ID);
                
                if (actuallyRepositioned) {
                    Log.d(TAG, "Repositioned measurement layers on top");
                } else {
                    Log.v(TAG, "Measurement layers already positioned correctly");
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error ensuring measurement layers on top", e);
        }
    }
    
    /**
     * Get the ID of the topmost non-measurement layer
     */
    private String getTopNonMeasurementLayerId() {
        try {
            java.util.List<Layer> layers = mapLibreMap.getStyle().getLayers();
            for (int i = layers.size() - 1; i >= 0; i--) {
                String layerId = layers.get(i).getId();
                if (!layerId.startsWith("measurement-")) {
                    return layerId;
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error getting top non-measurement layer", e);
        }
        return null;
    }
    
    /**
     * Reposition a layer above another layer if it exists and needs repositioning
     * @return true if layer was actually repositioned, false if not needed or failed
     */
    private boolean repositionLayerIfExists(String layerId, String aboveLayerId) {
        try {
            Layer layer = mapLibreMap.getStyle().getLayer(layerId);
            if (layer != null) {
                // Check if layer is already in correct position to avoid unnecessary operations
                java.util.List<Layer> layers = mapLibreMap.getStyle().getLayers();
                Layer aboveLayer = mapLibreMap.getStyle().getLayer(aboveLayerId);
                
                if (aboveLayer != null) {
                    int currentLayerIndex = -1;
                    int aboveLayerIndex = -1;
                    
                    for (int i = 0; i < layers.size(); i++) {
                        Layer l = layers.get(i);
                        if (l.getId().equals(layerId)) {
                            currentLayerIndex = i;
                        }
                        if (l.getId().equals(aboveLayerId)) {
                            aboveLayerIndex = i;
                        }
                    }
                    
                    // Only reposition if layer is not already above the target layer
                    if (currentLayerIndex <= aboveLayerIndex) {
                        mapLibreMap.getStyle().removeLayer(layer);
                        mapLibreMap.getStyle().addLayerAbove(layer, aboveLayerId);
                        Log.v(TAG, "Repositioned layer " + layerId + " above " + aboveLayerId);
                        return true;
                    } else {
                        Log.v(TAG, "Layer " + layerId + " already positioned correctly above " + aboveLayerId);
                        return false;
                    }
                }
            }
            return false;
        } catch (Exception e) {
            Log.w(TAG, "Could not reposition layer " + layerId + ": " + e.getMessage());
            return false;
        }
    }

    /**
     * Initialize measurement layers on the map style
     */
    private void initializeMeasurementLayers() {
        try {
            if (mapLibreMap.getStyle() != null && mapLibreMap.getStyle().isFullyLoaded()) {
                setupMeasurementLayers();
            } else {
                // Wait for style to load
                mapLibreMap.getStyle(style -> {
                    if (style != null) {
                        setupMeasurementLayers();
                    }
                });
            }
        } catch (Exception e) {
            Log.e(TAG, "Error initializing measurement layers", e);
        }
    }
    
    /**
     * Setup measurement layers on the map style
     */
    private void setupMeasurementLayers() {
        try {
            ensureGeoJsonSource(MEASUREMENT_SOURCE_ID);
            
            // Add measurement line layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_LINE_LAYER_ID) == null) {
                LineLayer lineLayer = new LineLayer(MEASUREMENT_LINE_LAYER_ID, MEASUREMENT_SOURCE_ID);
                lineLayer.setProperties(
                    lineColor(lineColor),
                    lineWidth((float) lineWidth),
                    lineOpacity((float) lineOpacity),
                    lineCap("round"),           // Rounded line caps for better appearance
                    lineJoin("round")          // Rounded line joins, solid line
                );
                // Add above user marker layers to ensure measurement appears on top
                try {
                    mapLibreMap.getStyle().addLayerAbove(lineLayer, "user-marker-layer");
                    Log.d(TAG, "Added measurement line layer above user marker");
                } catch (Exception e) {
                    // Fallback: add normally if user marker layer doesn't exist yet
                    mapLibreMap.getStyle().addLayer(lineLayer);
                    Log.d(TAG, "Added measurement line layer (user marker not found, will be repositioned later)");
                }
            }
            
            // Add measurement points layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_POINTS_LAYER_ID) == null) {
                CircleLayer circleLayer = new CircleLayer(MEASUREMENT_POINTS_LAYER_ID, MEASUREMENT_SOURCE_ID);
                circleLayer.setProperties(
                    circleColor(endpointColor),
                    circleRadius((float) endpointRadius),
                    circleOpacity((float) lineOpacity),
                    circleStrokeColor("#FFFFFF"),      // White border for better contrast
                    circleStrokeWidth(2f),             // Border width
                    circleStrokeOpacity(0.9f)          // Border opacity
                );
                // Filter to only show circles for endpoint features
                circleLayer.setFilter(eq(get("type"), literal("endpoint")));
                // Add above user marker layers to ensure measurement appears on top
                try {
                    mapLibreMap.getStyle().addLayerAbove(circleLayer, "user-marker-layer");
                    Log.d(TAG, "Added measurement points layer above user marker");
                } catch (Exception e) {
                    // Fallback: add normally if user marker layer doesn't exist yet
                    mapLibreMap.getStyle().addLayer(circleLayer);
                    Log.d(TAG, "Added measurement points layer (user marker not found, will be repositioned later)");
                }
            }
            
            // Add distance label layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_DISTANCE_LAYER_ID) == null) {
                SymbolLayer distanceLayer = new SymbolLayer(MEASUREMENT_DISTANCE_LAYER_ID, MEASUREMENT_SOURCE_ID);
                distanceLayer.setProperties(
                    textField(get("distance-text")),
                    textSize(16f),                     // Larger text for better readability
                    textColor("#FFFFFF"),
                    textHaloColor("#000000"),
                    textHaloWidth(2f),
                    textAnchor("center"),
                    textOffset(new Float[]{0f, -2f}),  // Offset text above the line
                    textFont(new String[]{"Noto Sans Bold"}),
                    textRotationAlignment("map"),       // Rotate with map
                    textPitchAlignment("map"),          // Align with map pitch
                    textAllowOverlap(true),            // Allow overlap for better visibility
                    textIgnorePlacement(true)          // Ignore placement conflicts
                );
                distanceLayer.setFilter(eq(get("type"), literal("distance")));
                // Add above user marker layers to ensure measurement appears on top
                try {
                    mapLibreMap.getStyle().addLayerAbove(distanceLayer, "user-marker-layer");
                    Log.d(TAG, "Added measurement distance layer above user marker");
                } catch (Exception e) {
                    // Fallback: add normally if user marker layer doesn't exist yet
                    mapLibreMap.getStyle().addLayer(distanceLayer);
                    Log.d(TAG, "Added measurement distance layer (user marker not found, will be repositioned later)");
                }
            }
            
            // Add bearing label layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_BEARING_LAYER_ID) == null) {
                SymbolLayer bearingLayer = new SymbolLayer(MEASUREMENT_BEARING_LAYER_ID, MEASUREMENT_SOURCE_ID);
                bearingLayer.setProperties(
                    textField(get("bearing-text")),
                    textSize(14f),                     // Slightly larger for better readability
                    textColor("#00FF00"),              // Bright green for bearing (aviation standard)
                    textHaloColor("#000000"),
                    textHaloWidth(2f),
                    textAnchor("center"),
                    textOffset(new Float[]{0f, 2f}),   // Position below the endpoints
                    textFont(new String[]{"Noto Sans Regular"}),
                    textRotate(get("text-rotation")),  // Dynamic rotation based on line bearing
                    textRotationAlignment("map"),       // Rotate with map
                    textPitchAlignment("map"),          // Align with map pitch
                    textAllowOverlap(true),            // Allow overlap for better visibility
                    textIgnorePlacement(true),         // Ignore placement conflicts
                    textKeepUpright(true)              // Keep text readable (flip if upside down)
                );
                bearingLayer.setFilter(eq(get("type"), literal("bearing")));
                // Add above user marker layers to ensure measurement appears on top
                try {
                    mapLibreMap.getStyle().addLayerAbove(bearingLayer, "user-marker-layer");
                    Log.d(TAG, "Added measurement bearing layer above user marker");
                } catch (Exception e) {
                    // Fallback: add normally if user marker layer doesn't exist yet
                    mapLibreMap.getStyle().addLayer(bearingLayer);
                    Log.d(TAG, "Added measurement bearing layer (user marker not found, will be repositioned later)");
                }
            }
            
            // Add directional arrows layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_ARROWS_LAYER_ID) == null) {
                SymbolLayer arrowLayer = new SymbolLayer(MEASUREMENT_ARROWS_LAYER_ID, MEASUREMENT_SOURCE_ID);
                arrowLayer.setProperties(
                    textField("➤"),                    // Arrow symbol (Unicode)
                    textSize(20f),                     // Large arrow for visibility
                    textColor("#FF6600"),              // Orange color for direction indicators
                    textHaloColor("#000000"),
                    textHaloWidth(1.5f),
                    textAnchor("center"),
                    textRotate(get("arrow-rotation")), // Dynamic rotation for arrow direction
                    textRotationAlignment("map"),       // Rotate with map
                    textPitchAlignment("map"),          // Align with map pitch
                    textAllowOverlap(true),            // Allow overlap for better visibility
                    textIgnorePlacement(true)          // Ignore placement conflicts
                );
                arrowLayer.setFilter(eq(get("type"), literal("arrow")));
                // Add above user marker layers to ensure measurement appears on top
                try {
                    mapLibreMap.getStyle().addLayerAbove(arrowLayer, "user-marker-layer");
                    Log.d(TAG, "Added measurement arrows layer above user marker");
                } catch (Exception e) {
                    // Fallback: add normally if user marker layer doesn't exist yet
                    mapLibreMap.getStyle().addLayer(arrowLayer);
                    Log.d(TAG, "Added measurement arrows layer (user marker not found, will be repositioned later)");
                }
            }
            
            // Ensure all layers are properly positioned after setup
            // This is the ONLY place layer repositioning should happen in normal operation
            ensureMeasurementLayersOnTop();
            Log.d(TAG, "Measurement layers setup complete with proper positioning");
        } catch (Exception e) {
            Log.e(TAG, "Error setting up measurement layers", e);
        }
    }

    private void ensureGeoJsonSource(String sourceId) {
        if (mapLibreMap.getStyle().getSource(sourceId) == null) {
            mapLibreMap.getStyle().addSource(new GeoJsonSource(sourceId));
            Log.d(TAG, "Added measurement source: " + sourceId);
        }
    }
    
    /**
     * Render measurement line and endpoints on the map
     */
    private void renderMeasurementLine(LatLng start, LatLng end) {
        try {
            if (mapLibreMap.getStyle() == null || !mapLibreMap.getStyle().isFullyLoaded()) {
                Log.w(TAG, "Map style not ready for rendering");
                return;
            }
            
            // OPTIMIZATION: Layer repositioning removed from render loop
            // Layers are positioned once during initialization and remain stable
            // unless the map style changes (handled by Flutter-side event system)
            
            // Calculate distance and bearing for labels
            double distance = calculateDistanceNauticalMiles(start, end);
            double forwardBearing = calculateBearing(start, end);
            double reverseBearing = (forwardBearing + 180) % 360;
            
            // Calculate text rotation angles (align text with line direction)
            // For MapLibre, rotation is in degrees clockwise from north
            double textRotation = forwardBearing - 90; // Adjust for text orientation
            double reverseTextRotation = reverseBearing - 90;
            
            // Ensure text is readable (not upside down)
            if (textRotation > 90 && textRotation < 270) {
                textRotation += 180;
            }
            if (reverseTextRotation > 90 && reverseTextRotation < 270) {
                reverseTextRotation += 180;
            }
            
            // Create line geometry
            Point startPoint = Point.fromLngLat(start.getLongitude(), start.getLatitude());
            Point endPoint = Point.fromLngLat(end.getLongitude(), end.getLatitude());
            
            // Calculate midpoint for distance label
            double midLat = (start.getLatitude() + end.getLatitude()) / 2;
            double midLng = (start.getLongitude() + end.getLongitude()) / 2;
            Point midPoint = Point.fromLngLat(midLng, midLat);
            
            java.util.List<Point> points = new java.util.ArrayList<>();
            points.add(startPoint);
            points.add(endPoint);
            
            LineString lineString = LineString.fromLngLats(points);
            
            // Create features for line and points
            Feature lineFeature = Feature.fromGeometry(lineString);
            lineFeature.addStringProperty("type", "line");
            Feature startPointFeature = Feature.fromGeometry(startPoint);
            startPointFeature.addStringProperty("type", "endpoint");  // Mark as endpoint for circle filter
            Feature endPointFeature = Feature.fromGeometry(endPoint);
            endPointFeature.addStringProperty("type", "endpoint");    // Mark as endpoint for circle filter
            
            // Create distance label feature at midpoint
            Feature distanceFeature = Feature.fromGeometry(midPoint);
            distanceFeature.addStringProperty("type", "distance");
            distanceFeature.addStringProperty("distance-text", String.format("%.1f nm", distance));
            
            // Create bearing label features at endpoints with rotation
            Feature startBearingFeature = Feature.fromGeometry(startPoint);
            startBearingFeature.addStringProperty("type", "bearing");
            startBearingFeature.addStringProperty("bearing-text", String.format("%.0f°", forwardBearing));
            startBearingFeature.addNumberProperty("text-rotation", textRotation);
            
            Feature endBearingFeature = Feature.fromGeometry(endPoint);
            endBearingFeature.addStringProperty("type", "bearing");
            endBearingFeature.addStringProperty("bearing-text", String.format("%.0f°", reverseBearing));
            endBearingFeature.addNumberProperty("text-rotation", reverseTextRotation);
            
            // Create directional arrow features at line endpoints
            // Calculate positions along the line for arrow placement (slightly inside the endpoints)
            double arrowOffset = 0.15; // 15% from each endpoint
            double startArrowLat = start.getLatitude() + arrowOffset * (end.getLatitude() - start.getLatitude());
            double startArrowLng = start.getLongitude() + arrowOffset * (end.getLongitude() - start.getLongitude());
            double endArrowLat = end.getLatitude() - arrowOffset * (end.getLatitude() - start.getLatitude());
            double endArrowLng = end.getLongitude() - arrowOffset * (end.getLongitude() - start.getLongitude());
            
            Point startArrowPoint = Point.fromLngLat(startArrowLng, startArrowLat);
            Point endArrowPoint = Point.fromLngLat(endArrowLng, endArrowLat);
            
            Feature startArrowFeature = Feature.fromGeometry(startArrowPoint);
            startArrowFeature.addStringProperty("type", "arrow");
            startArrowFeature.addNumberProperty("arrow-rotation", forwardBearing);
            
            Feature endArrowFeature = Feature.fromGeometry(endArrowPoint);
            endArrowFeature.addStringProperty("type", "arrow");
            endArrowFeature.addNumberProperty("arrow-rotation", reverseBearing);
            
            java.util.List<Feature> features = new java.util.ArrayList<>();
            features.add(lineFeature);
            features.add(startPointFeature);
            features.add(endPointFeature);
            features.add(distanceFeature);
            features.add(startBearingFeature);
            features.add(endBearingFeature);
            features.add(startArrowFeature);
            features.add(endArrowFeature);

            FeatureCollection featureCollection = FeatureCollection.fromFeatures(features);

            GeoJsonSource source = mapLibreMap.getStyle().getSourceAs(MEASUREMENT_SOURCE_ID);
            if (source == null) {
                setupMeasurementLayers();
                source = mapLibreMap.getStyle().getSourceAs(MEASUREMENT_SOURCE_ID);
            }

            if (source != null) {
                source.setGeoJson(featureCollection);
                Log.d(TAG, "Updated measurement rendering with labels");
            } else {
                Log.w(TAG, "Measurement source not found");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error rendering measurement line", e);
        }
    }
    
    /**
     * Clear measurement rendering from the map
     */
    private void clearMeasurementRendering() {
        try {
            if (mapLibreMap.getStyle() != null && mapLibreMap.getStyle().isFullyLoaded()) {
                FeatureCollection emptyCollection =
                        FeatureCollection.fromFeatures(new java.util.ArrayList<>());
                GeoJsonSource source = mapLibreMap.getStyle().getSourceAs(MEASUREMENT_SOURCE_ID);
                if (source != null) {
                    source.setGeoJson(emptyCollection);
                }
                for (String sourceId : MEASUREMENT_COMPAT_SOURCE_IDS) {
                    GeoJsonSource compatSource = mapLibreMap.getStyle().getSourceAs(sourceId);
                    if (compatSource != null) {
                        compatSource.setGeoJson(emptyCollection);
                    }
                }
                Log.d(TAG, "Cleared measurement rendering");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error clearing measurement rendering", e);
        }
    }
    
    /**
     * Update measurement style and refresh layers
     */
    private void updateMeasurementLayers() {
        try {
            if (mapLibreMap.getStyle() != null && mapLibreMap.getStyle().isFullyLoaded()) {
                // Update line layer properties
                LineLayer lineLayer = mapLibreMap.getStyle().getLayerAs(MEASUREMENT_LINE_LAYER_ID);
                if (lineLayer != null) {
                    lineLayer.setProperties(
                        lineColor(lineColor),
                        lineWidth((float) lineWidth),
                        lineOpacity((float) lineOpacity),
                        lineCap("round"),
                        lineJoin("round")
                    );
                }
                
                // Update points layer properties
                CircleLayer circleLayer = mapLibreMap.getStyle().getLayerAs(MEASUREMENT_POINTS_LAYER_ID);
                if (circleLayer != null) {
                    circleLayer.setProperties(
                        circleColor(endpointColor),
                        circleRadius((float) endpointRadius),
                        circleOpacity((float) lineOpacity),
                        circleStrokeColor("#FFFFFF"),
                        circleStrokeWidth(2f),
                        circleStrokeOpacity(0.9f)
                    );
                    // Ensure filter is applied to only show endpoint circles
                    circleLayer.setFilter(eq(get("type"), literal("endpoint")));
                }
                
                Log.d(TAG, "Updated measurement layer styles");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error updating measurement layers", e);
        }
    }

    /**
     * Update measurement style configuration
     */
    public void setMeasurementStyle(String lineColor, double lineWidth, double lineOpacity,
                                   String endpointColor, double endpointRadius) {
        this.lineColor = lineColor;
        this.lineWidth = lineWidth;
        this.lineOpacity = lineOpacity;
        this.endpointColor = endpointColor;
        this.endpointRadius = endpointRadius;
        
        // Update the visual style on existing layers
        updateMeasurementLayers();
    }
    
    /**
     * Get current measurement style configuration
     */
    public MeasurementStyle getMeasurementStyle() {
        return new MeasurementStyle(lineColor, lineWidth, lineOpacity, endpointColor, endpointRadius);
    }
    
    /**
     * Check if currently measuring
     */
    public boolean isMeasuring() {
        return isMeasuring;
    }
    
    /**
     * Check if there's a persistent measurement on the map
     */
    public boolean hasPersistentMeasurement() {
        return hasPersistentMeasurement;
    }
    
    /**
     * Check if map interactions should be disabled (measurement in progress or dragging)
     */
    public boolean isBlockingMapInteraction() {
        return isMeasuring || isDraggingStart || isDraggingEnd;
    }
    
    /**
     * Disable the measurement detector
     */
    public void disable() {
        cancelGesture();
    }
    
    /**
     * Clear any active measurement
     */
    public void clearMeasurement() {
        if (isMeasuring) {
            endMeasurement();
        } else {
            cancelGesture();
        }
        
        // Clear persistent measurement
        hasPersistentMeasurement = false;
        startLatLng = null;
        endLatLng = null;
        isDraggingStart = false;
        isDraggingEnd = false;
        
        // Reset grace period flags
        justFinishedMeasurement = false;
        measurementEndTime = 0;
        
        // Reset pending clear gesture flag
        pendingClearGesture = false;
        
        // Clear rendering
        clearMeasurementRendering();
    }

    /**
     * Clean up resources
     */
    public void cleanup() {
        cancelGesture();
    }
    
    /**
     * Helper class to hold measurement style configuration
     */
    public static class MeasurementStyle {
        public final String lineColor;
        public final double lineWidth;
        public final double lineOpacity;
        public final String endpointColor;
        public final double endpointRadius;
        
        public MeasurementStyle(String lineColor, double lineWidth, double lineOpacity,
                               String endpointColor, double endpointRadius) {
            this.lineColor = lineColor;
            this.lineWidth = lineWidth;
            this.lineOpacity = lineOpacity;
            this.endpointColor = endpointColor;
            this.endpointRadius = endpointRadius;
        }
    }
}
