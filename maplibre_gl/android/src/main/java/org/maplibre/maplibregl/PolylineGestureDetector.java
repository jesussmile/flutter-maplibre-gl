// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.MotionEvent;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import java.util.List;

/**
 * Detects long press and drag gestures on polylines for interactive editing.
 * 
 * This class handles the gesture recognition for polyline editing, including:
 * - Long press detection on polylines to create break points
 * - Drag gesture handling for moving break points
 * - Coordinate calculations for finding nearest points on polylines
 */
public class PolylineGestureDetector {
    private static final String TAG = "PolylineGestureDetector";
    
    // Gesture thresholds
    private static final long LONG_PRESS_DURATION_MS = 500; // 500ms for long press
    private static final float MOVEMENT_THRESHOLD_PX = 20f; // 20px movement threshold
    private static final float HIT_TEST_RADIUS_PX = 30f; // 30px radius for hit testing
    
    private final MapLibreMap mapLibreMap;
    private final PolylineEditingManager polylineEditingManager;
    private final PolylineBreakPointSystem breakPointSystem;
    private final EditablePolylineRenderer renderer;
    private final OnPolylineGestureListener listener;
    private final PolylineEditingErrorHandler errorHandler;
    private final Handler handler = new Handler(Looper.getMainLooper());
    
    // Gesture state
    private boolean isLongPressActive = false;
    private boolean isDragging = false;
    private PointF initialTouchPoint;
    private PointF currentTouchPoint;
    private long gestureStartTime;
    private Runnable longPressRunnable;
    
    // Editing state
    private String activeLineId;
    private LatLng breakPointLocation;
    private int segmentIndex;
    private double distanceAlongSegment;
    
    /**
     * Interface for handling polyline gesture events.
     */
    public interface OnPolylineGestureListener {
        /**
         * Called when a polyline is broken by a long press gesture.
         * 
         * @param lineId The ID of the polyline that was broken
         * @param breakPoint The geographic location where the break occurred
         * @param segment1 The coordinates of the first segment
         * @param segment2 The coordinates of the second segment
         */
        void onPolylineBroken(@NonNull String lineId, @NonNull LatLng breakPoint, 
                             @NonNull List<LatLng> segment1, @NonNull List<LatLng> segment2);
        
        /**
         * Called when a polyline is modified by dragging a break point.
         * 
         * @param lineId The ID of the polyline that was modified
         * @param newCoordinates The updated coordinates of the polyline
         */
        void onPolylineModified(@NonNull String lineId, @NonNull List<LatLng> newCoordinates);
        
        /**
         * Called when an error occurs during polyline editing.
         * 
         * @param lineId The ID of the polyline where the error occurred
         * @param error The error message
         */
        void onPolylineEditingError(@NonNull String lineId, @NonNull String error);
    }
    
    /**
     * Creates a new PolylineGestureDetector.
     * 
     * @param mapLibreMap The MapLibre map instance
     * @param polylineEditingManager The polyline editing manager
     * @param breakPointSystem The break point system
     * @param renderer The polyline renderer for visual feedback
     * @param listener The gesture event listener
     */
    public PolylineGestureDetector(@NonNull MapLibreMap mapLibreMap, 
                                  @NonNull PolylineEditingManager polylineEditingManager,
                                  @NonNull PolylineBreakPointSystem breakPointSystem,
                                  @NonNull EditablePolylineRenderer renderer,
                                  @NonNull OnPolylineGestureListener listener) {
        this.mapLibreMap = mapLibreMap;
        this.polylineEditingManager = polylineEditingManager;
        this.breakPointSystem = breakPointSystem;
        this.renderer = renderer;
        this.listener = listener;
        this.errorHandler = new PolylineEditingErrorHandler();
    }
    
    /**
     * Handles touch events for polyline editing gestures.
     * 
     * @param event The motion event
     * @return true if the event was consumed, false otherwise
     */
    public boolean onTouchEvent(@NonNull MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                return handleActionDown(event);
                
            case MotionEvent.ACTION_MOVE:
                return handleActionMove(event);
                
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                return handleActionUp(event);
                
            default:
                return false;
        }
    }
    
    /**
     * Handles ACTION_DOWN events.
     */
    private boolean handleActionDown(@NonNull MotionEvent event) {
        try {
            // Only handle single finger touches
            if (event.getPointerCount() != 1) {
                return false;
            }
            
            initialTouchPoint = new PointF(event.getX(), event.getY());
            currentTouchPoint = new PointF(event.getX(), event.getY());
            gestureStartTime = System.currentTimeMillis();
            
            // Validate touch location
            PolylineEditingErrorHandler.ValidationResult validation = errorHandler.validateTouchLocation(
                event.getX(), event.getY(), mapLibreMap.getWidth(), mapLibreMap.getHeight());
            
            if (!validation.isValid) {
                Log.w(TAG, "Invalid touch location: " + validation.errorMessage);
                return false;
            }
            
            // Check if touch is on an editable polyline
            String touchedLineId = findEditablePolylineAtPoint(initialTouchPoint);
            if (touchedLineId != null) {
                activeLineId = touchedLineId;
                
                // Start long press detection
                longPressRunnable = new Runnable() {
                    @Override
                    public void run() {
                        if (!isDragging && activeLineId != null) {
                            handleLongPress();
                        }
                    }
                };
                handler.postDelayed(longPressRunnable, LONG_PRESS_DURATION_MS);
                
                Log.d(TAG, "Started gesture detection on polyline: " + activeLineId);
                return true; // Consume the event
            }
            
            return false;
        } catch (Exception e) {
            PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
                PolylineEditingErrorHandler.ErrorType.PLATFORM_INTEGRATION_ERROR,
                e,
                "Error in handleActionDown",
                null
            );
            
            if (!result.canContinue) {
                Log.e(TAG, "Critical error in handleActionDown, aborting gesture: " + result.message);
                cleanupGestureState();
            }
            
            return false;
        }
    }
    
    /**
     * Handles ACTION_MOVE events.
     */
    private boolean handleActionMove(@NonNull MotionEvent event) {
        if (activeLineId == null) {
            return false;
        }
        
        currentTouchPoint = new PointF(event.getX(), event.getY());
        
        // Check if movement exceeds threshold
        float deltaX = currentTouchPoint.x - initialTouchPoint.x;
        float deltaY = currentTouchPoint.y - initialTouchPoint.y;
        float distance = (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        
        if (distance > MOVEMENT_THRESHOLD_PX) {
            // Cancel long press if we're moving too much
            if (longPressRunnable != null) {
                handler.removeCallbacks(longPressRunnable);
                longPressRunnable = null;
            }
            
            // Start dragging if we have a break point
            if (isLongPressActive && breakPointLocation != null) {
                isDragging = true;
                
                // Update visual feedback for dragging state
                if (renderer != null) {
                    renderer.setBreakPointDragging(activeLineId, true);
                }
                
                handleDrag();
                return true;
            }
        }
        
        return activeLineId != null;
    }
    
    /**
     * Handles ACTION_UP and ACTION_CANCEL events.
     */
    private boolean handleActionUp(@NonNull MotionEvent event) {
        boolean wasHandling = activeLineId != null;
        
        // Clean up gesture state
        if (longPressRunnable != null) {
            handler.removeCallbacks(longPressRunnable);
            longPressRunnable = null;
        }
        
        if (isDragging && breakPointLocation != null) {
            // Finalize drag operation
            finalizeDrag();
        }
        
        // Reset state
        isLongPressActive = false;
        isDragging = false;
        activeLineId = null;
        breakPointLocation = null;
        segmentIndex = -1;
        distanceAlongSegment = 0.0;
        
        return wasHandling;
    }
    
    /**
     * Handles long press gesture on a polyline.
     */
    private void handleLongPress() {
        if (activeLineId == null || initialTouchPoint == null) {
            return;
        }
        
        Log.d(TAG, "Long press detected on polyline: " + activeLineId);
        isLongPressActive = true;
        
        try {
            // Convert screen point to geographic coordinate
            LatLng touchLatLng = mapLibreMap.getProjection().fromScreenLocation(initialTouchPoint);
            
            // Create break point using the break point system
            PolylineBreakPointSystem.BreakPointSession session = 
                breakPointSystem.createBreakPoint(activeLineId, touchLatLng);
            
            if (session != null) {
                breakPointLocation = session.breakPointLocation;
                segmentIndex = session.segmentIndex;
                distanceAlongSegment = session.distanceAlongSegment;
                
                // Notify listener of the break
                listener.onPolylineBroken(activeLineId, session.breakPointLocation, 
                                        session.segment1Coordinates, session.segment2Coordinates);
                
                Log.d(TAG, "Created break point at: " + breakPointLocation);
            } else {
                listener.onPolylineEditingError(activeLineId, "Could not create break point");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling long press: " + e.getMessage(), e);
            listener.onPolylineEditingError(activeLineId, "Error creating break point: " + e.getMessage());
        }
    }
    
    /**
     * Handles drag gesture for moving a break point.
     */
    private void handleDrag() {
        if (activeLineId == null || currentTouchPoint == null || breakPointLocation == null) {
            return;
        }
        
        try {
            // Convert current touch point to geographic coordinate
            LatLng newLocation = mapLibreMap.getProjection().fromScreenLocation(currentTouchPoint);
            
            // Update break point location using the break point system
            PolylineBreakPointSystem.BreakPointSession updatedSession = 
                breakPointSystem.updateBreakPoint(activeLineId, newLocation);
            
            if (updatedSession != null) {
                breakPointLocation = updatedSession.breakPointLocation;
                
                // Update visual feedback
                if (renderer != null) {
                    renderer.updateBreakPoint(activeLineId, breakPointLocation);
                    renderer.showPreviewLine(activeLineId, updatedSession.getCombinedCoordinates());
                }
                
                Log.d(TAG, "Updated break point to: " + breakPointLocation);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling drag: " + e.getMessage(), e);
            listener.onPolylineEditingError(activeLineId, "Error during drag: " + e.getMessage());
        }
    }
    
    /**
     * Finalizes the drag operation.
     */
    private void finalizeDrag() {
        if (activeLineId == null || breakPointLocation == null) {
            return;
        }
        
        Log.d(TAG, "Finalizing drag for polyline: " + activeLineId);
        
        try {
            // Finalize the break point and get the final coordinates
            List<LatLng> finalCoordinates = breakPointSystem.finalizeBreakPoint(activeLineId);
            if (finalCoordinates != null) {
                listener.onPolylineModified(activeLineId, finalCoordinates);
            } else {
                listener.onPolylineEditingError(activeLineId, "Could not finalize break point");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error finalizing drag: " + e.getMessage(), e);
            listener.onPolylineEditingError(activeLineId, "Error finalizing drag: " + e.getMessage());
        }
    }
    
    /**
     * Finds an editable polyline at the given screen point.
     * 
     * @param screenPoint The screen point to test
     * @return The ID of the editable polyline, or null if none found
     */
    @Nullable
    private String findEditablePolylineAtPoint(@NonNull PointF screenPoint) {
        try {
            // Query rendered features at the touch point
            List<Feature> features = mapLibreMap.queryRenderedFeatures(screenPoint, (String[]) null);
            
            for (Feature feature : features) {
                if (feature.geometry() instanceof LineString) {
                    // Check if this feature represents an editable polyline
                    String lineId = getLineIdFromFeature(feature);
                    if (lineId != null && polylineEditingManager.isLineEditable(lineId)) {
                        Log.d(TAG, "Found editable polyline: " + lineId);
                        return lineId;
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error finding polyline at point: " + e.getMessage(), e);
        }
        
        return null;
    }
    
    /**
     * Extracts the line ID from a feature.
     * 
     * @param feature The feature to extract the ID from
     * @return The line ID, or null if not found
     */
    @Nullable
    private String getLineIdFromFeature(@NonNull Feature feature) {
        // Try to get ID from feature properties
        if (feature.properties() != null && feature.properties().has("id")) {
            return feature.properties().get("id").getAsString();
        }
        
        // Try to get ID from feature ID
        if (feature.id() != null) {
            return feature.id();
        }
        
        return null;
    }
    
    /**
     * Cleans up gesture state and resources.
     */
    private void cleanupGestureState() {
        if (longPressRunnable != null) {
            handler.removeCallbacks(longPressRunnable);
            longPressRunnable = null;
        }
        
        isLongPressActive = false;
        isDragging = false;
        activeLineId = null;
        breakPointLocation = null;
        segmentIndex = -1;
        distanceAlongSegment = 0.0;
        
        Log.d(TAG, "Gesture state cleaned up");
    }
    
    /**
     * Cleans up resources when the detector is no longer needed.
     */
    public void cleanup() {
        cleanupGestureState();
        if (errorHandler != null) {
            errorHandler.cleanup();
        }
        Log.d(TAG, "PolylineGestureDetector cleanup complete");
    }

}