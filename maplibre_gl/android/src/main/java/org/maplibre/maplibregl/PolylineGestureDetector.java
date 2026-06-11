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

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

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
    private float hitTestRadiusPx = 30f;
    
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
    private int activePointIndex = -1;
    private double distanceAlongSegment;
    private boolean draggingExistingPoint = false;

    private static class EditableHandleHit {
        final String lineId;
        final int pointIndex;

        EditableHandleHit(@NonNull String lineId, int pointIndex) {
            this.lineId = lineId;
            this.pointIndex = pointIndex;
        }
    }
    
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

        void onPolylineEditCompleted(
            @NonNull String lineId,
            @NonNull List<LatLng> newCoordinates,
            int pointIndex,
            boolean inserted);
        
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

    public void setHitTestRadiusPx(float radiusPx) {
        hitTestRadiusPx = Math.max(1f, radiusPx);
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
                event.getX(), event.getY(), (int) mapLibreMap.getWidth(), (int) mapLibreMap.getHeight());
            
            if (!validation.isValid) {
                Log.w(TAG, "Invalid touch location: " + validation.errorMessage);
                return false;
            }

            EditableHandleHit handleHit = findEditableHandleAtPoint(initialTouchPoint);
            if (handleHit != null) {
                PolylineBreakPointSystem.BreakPointSession session =
                    breakPointSystem.createExistingBreakPoint(
                        handleHit.lineId, handleHit.pointIndex);
                if (session != null) {
                    activeLineId = handleHit.lineId;
                    activePointIndex = handleHit.pointIndex;
                    breakPointLocation = session.breakPointLocation;
                    isLongPressActive = true;
                    isDragging = true;
                    draggingExistingPoint = true;
                    renderer.setBreakPointDragging(
                        activeLineId, activePointIndex, true);
                    return true;
                }
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
        
        if (draggingExistingPoint ||
                distance > MOVEMENT_THRESHOLD_PX) {
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
                    renderer.setBreakPointDragging(
                        activeLineId, activePointIndex, true);
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
        
        if (isLongPressActive && breakPointLocation != null) {
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
        activePointIndex = -1;
        draggingExistingPoint = false;
        
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
                activePointIndex = session.pointIndex;
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
                    renderer.updateBreakPoint(
                        activeLineId, activePointIndex, breakPointLocation);
                }
                
                // Send real-time updates to Flutter during dragging
                List<LatLng> combinedCoordinates =
                    updatedSession.getCombinedCoordinates();
                listener.onPolylineModified(activeLineId, combinedCoordinates);
                
                Log.d(TAG, "Updated break point to: " + breakPointLocation);
                Log.d(TAG, "Sent real-time update with " + combinedCoordinates.size() + " points");
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
                listener.onPolylineEditCompleted(
                    activeLineId,
                    finalCoordinates,
                    activePointIndex,
                    !draggingExistingPoint);
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
            String lineId = findPolylineFromStoredCoordinates(screenPoint);
            if (lineId != null) {
                return lineId;
            }

            // Fallback to rendered feature query if no stored geometry matched
            List<Feature> features = mapLibreMap.queryRenderedFeatures(screenPoint, (String[]) null);

            for (Feature feature : features) {
                if (feature.geometry() instanceof LineString) {
                    String candidateId = getLineIdFromFeature(feature);
                    if (candidateId != null && polylineEditingManager.isLineEditable(candidateId)) {
                        Log.d(TAG, "Found editable polyline via fallback query: " + candidateId);
                        return candidateId;
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
        
        // Clean up visual feedback elements
        if (activeLineId != null && renderer != null) {
            renderer.hideBreakPoint(activeLineId);
        }
        
        isLongPressActive = false;
        isDragging = false;
        activeLineId = null;
        breakPointLocation = null;
        segmentIndex = -1;
        distanceAlongSegment = 0.0;
        activePointIndex = -1;
        draggingExistingPoint = false;
        
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

    /**
     * Attempts to find an editable polyline by manually hit-testing stored coordinates.
     */
    @Nullable
    private String findPolylineFromStoredCoordinates(@NonNull PointF screenPoint) {
    if (polylineEditingManager == null || breakPointSystem == null) {
            return null;
        }

        Map<String, PolylineEditingManager.PolylineEditingConfig> editablePolylines =
            polylineEditingManager.getEditablePolylines();
        if (editablePolylines.isEmpty()) {
            return null;
        }

        Map<String, List<LatLng>> storedCoordinates =
            breakPointSystem.getStoredPolylineCoordinatesSnapshot();
        if (storedCoordinates.isEmpty()) {
            return null;
        }

        float closestDistance = Float.MAX_VALUE;
        String closestLineId = null;

        for (String lineId : editablePolylines.keySet()) {
            List<LatLng> coordinates = storedCoordinates.get(lineId);
            if (coordinates == null || coordinates.size() < 2) {
                continue;
            }

            float candidateDistance = distanceToPolyline(screenPoint, coordinates);
            if (candidateDistance < closestDistance && candidateDistance <= hitTestRadiusPx) {
                closestDistance = candidateDistance;
                closestLineId = lineId;
            }
        }

        if (closestLineId != null) {
            Log.d(TAG, "Manual hit-test found editable polyline: " + closestLineId
                    + " (distance=" + closestDistance + ")");
        }

        return closestLineId;
    }

    @Nullable
    private EditableHandleHit findEditableHandleAtPoint(
            @NonNull PointF screenPoint) {
        Map<String, List<LatLng>> storedCoordinates =
            breakPointSystem.getStoredPolylineCoordinatesSnapshot();
        float closestDistance = Float.MAX_VALUE;
        EditableHandleHit closest = null;
        for (Map.Entry<String, List<LatLng>> entry : storedCoordinates.entrySet()) {
            String lineId = entry.getKey();
            if (!polylineEditingManager.isLineEditable(lineId)) continue;
            List<LatLng> coordinates = entry.getValue();
            for (int index = 1; index < coordinates.size() - 1; index++) {
                if (breakPointSystem.isPointLocked(lineId, index)) continue;
                PointF point = mapLibreMap.getProjection()
                    .toScreenLocation(coordinates.get(index));
                float dx = point.x - screenPoint.x;
                float dy = point.y - screenPoint.y;
                float distance = (float) Math.sqrt(dx * dx + dy * dy);
                if (distance <= hitTestRadiusPx && distance < closestDistance) {
                    closestDistance = distance;
                    closest = new EditableHandleHit(lineId, index);
                }
            }
        }
        return closest;
    }

    private float distanceToPolyline(@NonNull PointF touchPoint, @NonNull List<LatLng> coordinates) {
        float minDistance = Float.MAX_VALUE;
        PointF previousPoint = null;

        for (LatLng location : coordinates) {
            PointF screenLocation;
            try {
                screenLocation = mapLibreMap.getProjection().toScreenLocation(location);
            } catch (Exception e) {
                Log.w(TAG, "Failed to project coordinate during hit test: " + e.getMessage());
                continue;
            }

            if (previousPoint != null) {
                float segmentDistance = distanceToSegment(touchPoint, previousPoint, screenLocation);
                if (segmentDistance < minDistance) {
                    minDistance = segmentDistance;
                    if (minDistance == 0f) {
                        // Perfect hit; no need to examine remaining segments.
                        break;
                    }
                }
            }

            previousPoint = screenLocation;
        }

        return minDistance;
    }

    private float distanceToSegment(@NonNull PointF p, @NonNull PointF v, @NonNull PointF w) {
        float dx = w.x - v.x;
        float dy = w.y - v.y;
        float lengthSquared = dx * dx + dy * dy;

        if (lengthSquared == 0f) {
            return distanceBetweenPoints(p, v);
        }

        float t = ((p.x - v.x) * dx + (p.y - v.y) * dy) / lengthSquared;
        t = Math.max(0f, Math.min(1f, t));

        float projectionX = v.x + t * dx;
        float projectionY = v.y + t * dy;
        return distanceBetweenPoints(p, new PointF(projectionX, projectionY));
    }

    private float distanceBetweenPoints(@NonNull PointF a, @NonNull PointF b) {
        float diffX = a.x - b.x;
        float diffY = a.y - b.y;
        return (float) Math.sqrt(diffX * diffX + diffY * diffY);
    }

}
