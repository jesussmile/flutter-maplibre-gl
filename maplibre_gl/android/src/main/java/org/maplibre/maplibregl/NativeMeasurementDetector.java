package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.util.Log;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
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
    private static final float MARKER_TOUCH_RADIUS = 30f; // pixels
    
    // Track if we just finished creating a measurement to prevent immediate cleanup
    private boolean justFinishedMeasurement = false;
    private long measurementEndTime = 0;
    private static final long CLEANUP_GRACE_PERIOD_MS = 500; // 500ms grace period
    
    // Track when user is performing a tap-to-clear gesture
    private boolean pendingClearGesture = false;
    private PointF initialTouchPoint;
    private static final float TAP_MOVEMENT_THRESHOLD = 20f; // pixels - max movement for tap vs pan
    
    // Measurement style configuration
    private String lineColor = "#FF0000";
    private double lineWidth = 3.0;
    private double lineOpacity = 0.8;
    private String endpointColor = "#FF0000";
    private double endpointRadius = 12.0; // Increased for better touch targeting
    
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
                    
                    // Schedule the hold detection for measurement start
                    holdRunnable = new Runnable() {
                        @Override
                        public void run() {
                            if (isTwoFingerDown && !isMeasuring && listener != null) {
                                startMeasurement();
                            }
                        }
                    };
                    handler.postDelayed(holdRunnable, HOLD_DURATION_MS);
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
                }
                break;
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
            // Add measurement source if it doesn't exist
            if (mapLibreMap.getStyle().getSource(MEASUREMENT_SOURCE_ID) == null) {
                mapLibreMap.getStyle().addSource(new GeoJsonSource(MEASUREMENT_SOURCE_ID));
                Log.d(TAG, "Added measurement source");
            }
            
            // Add measurement line layer if it doesn't exist
            if (mapLibreMap.getStyle().getLayer(MEASUREMENT_LINE_LAYER_ID) == null) {
                LineLayer lineLayer = new LineLayer(MEASUREMENT_LINE_LAYER_ID, MEASUREMENT_SOURCE_ID);
                lineLayer.setProperties(
                    lineColor(lineColor),
                    lineWidth((float) lineWidth),
                    lineOpacity((float) lineOpacity)
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
                    circleOpacity((float) lineOpacity)
                );
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
                    textSize(14f),
                    textColor("#FFFFFF"),
                    textHaloColor("#000000"),
                    textHaloWidth(2f),
                    textAnchor("center"),
                    textOffset(new Float[]{0f, -1f})
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
                    textSize(12f),
                    textColor("#FFFF00"),
                    textHaloColor("#000000"),
                    textHaloWidth(1.5f),
                    textAnchor("center"),
                    textOffset(new Float[]{0f, 1f})
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
        } catch (Exception e) {
            Log.e(TAG, "Error setting up measurement layers", e);
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
            
            // Ensure measurement layers are positioned correctly before rendering
            ensureMeasurementLayersOnTop();
            
            // Calculate distance and bearing for labels
            double distance = calculateDistanceNauticalMiles(start, end);
            double forwardBearing = calculateBearing(start, end);
            double reverseBearing = (forwardBearing + 180) % 360;
            
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
            Feature startPointFeature = Feature.fromGeometry(startPoint);
            Feature endPointFeature = Feature.fromGeometry(endPoint);
            
            // Create distance label feature at midpoint
            Feature distanceFeature = Feature.fromGeometry(midPoint);
            distanceFeature.addStringProperty("type", "distance");
            distanceFeature.addStringProperty("distance-text", String.format("%.1f nm", distance));
            
            // Create bearing label features at endpoints
            Feature startBearingFeature = Feature.fromGeometry(startPoint);
            startBearingFeature.addStringProperty("type", "bearing");
            startBearingFeature.addStringProperty("bearing-text", String.format("%.0f°", forwardBearing));
            
            Feature endBearingFeature = Feature.fromGeometry(endPoint);
            endBearingFeature.addStringProperty("type", "bearing");
            endBearingFeature.addStringProperty("bearing-text", String.format("%.0f°", reverseBearing));
            
            // Create feature collection
            java.util.List<Feature> features = new java.util.ArrayList<>();
            features.add(lineFeature);
            features.add(startPointFeature);
            features.add(endPointFeature);
            features.add(distanceFeature);
            features.add(startBearingFeature);
            features.add(endBearingFeature);
            
            FeatureCollection featureCollection = FeatureCollection.fromFeatures(features);
            
            // Update source with new features
            GeoJsonSource source = mapLibreMap.getStyle().getSourceAs(MEASUREMENT_SOURCE_ID);
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
                GeoJsonSource source = mapLibreMap.getStyle().getSourceAs(MEASUREMENT_SOURCE_ID);
                if (source != null) {
                    source.setGeoJson(FeatureCollection.fromFeatures(new java.util.ArrayList<>()));
                    Log.d(TAG, "Cleared measurement rendering");
                }
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
                        lineOpacity((float) lineOpacity)
                    );
                }
                
                // Update points layer properties
                CircleLayer circleLayer = mapLibreMap.getStyle().getLayerAs(MEASUREMENT_POINTS_LAYER_ID);
                if (circleLayer != null) {
                    circleLayer.setProperties(
                        circleColor(endpointColor),
                        circleRadius((float) endpointRadius),
                        circleOpacity((float) lineOpacity)
                    );
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
     * Ensure measurement layers are positioned above user marker layers
     * Call this after user marker layers have been created
     */
    public void ensureMeasurementLayersOnTop() {
        try {
            if (mapLibreMap.getStyle() == null || !mapLibreMap.getStyle().isFullyLoaded()) {
                Log.w(TAG, "Map style not ready for layer repositioning");
                return;
            }
            
            // Check if user marker layer exists
            if (mapLibreMap.getStyle().getLayer("user-marker-layer") == null) {
                Log.d(TAG, "User marker layer not found, cannot reposition measurement layers");
                return;
            }
            
            // Debug: Log current layer stack
            Log.d(TAG, "🔍 Repositioning measurement layers above user marker");
            Log.d(TAG, "🔍 User marker layer exists: " + (mapLibreMap.getStyle().getLayer("user-marker-layer") != null));
            Log.d(TAG, "🔍 Measurement line layer exists: " + (mapLibreMap.getStyle().getLayer(MEASUREMENT_LINE_LAYER_ID) != null));
            
            // Remove and re-add measurement layers above user marker layer
            String[] layerIds = {
                MEASUREMENT_LINE_LAYER_ID,
                MEASUREMENT_POINTS_LAYER_ID, 
                MEASUREMENT_DISTANCE_LAYER_ID,
                MEASUREMENT_BEARING_LAYER_ID
            };
            
            for (String layerId : layerIds) {
                if (mapLibreMap.getStyle().getLayer(layerId) != null) {
                    try {
                        // Remove layer temporarily
                        mapLibreMap.getStyle().removeLayer(layerId);
                        
                        // Re-add above user marker layer
                        if (layerId.equals(MEASUREMENT_LINE_LAYER_ID)) {
                            LineLayer lineLayer = new LineLayer(MEASUREMENT_LINE_LAYER_ID, MEASUREMENT_SOURCE_ID);
                            lineLayer.setProperties(
                                lineColor(lineColor),
                                lineWidth((float) lineWidth),
                                lineOpacity((float) lineOpacity)
                            );
                            mapLibreMap.getStyle().addLayerAbove(lineLayer, "user-marker-layer");
                        } else if (layerId.equals(MEASUREMENT_POINTS_LAYER_ID)) {
                            CircleLayer circleLayer = new CircleLayer(MEASUREMENT_POINTS_LAYER_ID, MEASUREMENT_SOURCE_ID);
                            circleLayer.setProperties(
                                circleColor(endpointColor),
                                circleRadius((float) endpointRadius),
                                circleOpacity((float) lineOpacity)
                            );
                            mapLibreMap.getStyle().addLayerAbove(circleLayer, "user-marker-layer");
                        } else if (layerId.equals(MEASUREMENT_DISTANCE_LAYER_ID)) {
                            SymbolLayer distanceLayer = new SymbolLayer(MEASUREMENT_DISTANCE_LAYER_ID, MEASUREMENT_SOURCE_ID);
                            distanceLayer.setProperties(
                                textField(get("distance-text")),
                                textSize(14f),
                                textColor("#FFFFFF"),
                                textHaloColor("#000000"),
                                textHaloWidth(2f),
                                textAnchor("center"),
                                textOffset(new Float[]{0f, -1f})
                            );
                            distanceLayer.setFilter(eq(get("type"), literal("distance")));
                            mapLibreMap.getStyle().addLayerAbove(distanceLayer, "user-marker-layer");
                        } else if (layerId.equals(MEASUREMENT_BEARING_LAYER_ID)) {
                            SymbolLayer bearingLayer = new SymbolLayer(MEASUREMENT_BEARING_LAYER_ID, MEASUREMENT_SOURCE_ID);
                            bearingLayer.setProperties(
                                textField(get("bearing-text")),
                                textSize(12f),
                                textColor("#FFFF00"),
                                textHaloColor("#000000"),
                                textHaloWidth(1.5f),
                                textAnchor("center"),
                                textOffset(new Float[]{0f, 1f})
                            );
                            bearingLayer.setFilter(eq(get("type"), literal("bearing")));
                            mapLibreMap.getStyle().addLayerAbove(bearingLayer, "user-marker-layer");
                        }
                        
                        Log.d(TAG, "Repositioned " + layerId + " above user marker layer");
                    } catch (Exception e) {
                        Log.w(TAG, "Failed to reposition layer " + layerId + ": " + e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error ensuring measurement layers on top", e);
        }
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
