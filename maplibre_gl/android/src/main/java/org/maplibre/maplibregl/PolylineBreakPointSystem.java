// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Manages polyline break points and segment operations.
 * 
 * This class handles:
 * - Breaking polylines into segments at specific points
 * - Managing break point markers and their visual representation
 * - Calculating geometric operations for polyline editing
 * - Tracking active editing sessions
 */
public class PolylineBreakPointSystem {
    private static final String TAG = "PolylineBreakPointSystem";
    
    private final MapLibreMap mapLibreMap;
    private final Map<String, BreakPointSession> activeSessions;
    
    /**
     * Represents an active break point editing session.
     */
    public static class BreakPointSession {
        public final String sessionId;
        public final String lineId;
        public final LatLng breakPointLocation;
        public final List<LatLng> originalCoordinates;
        public final List<LatLng> segment1Coordinates;
        public final List<LatLng> segment2Coordinates;
        public final int segmentIndex;
        public final double distanceAlongSegment;
        public final long startTime;
        
        public BreakPointSession(@NonNull String lineId, @NonNull LatLng breakPointLocation,
                               @NonNull List<LatLng> originalCoordinates,
                               @NonNull List<LatLng> segment1Coordinates,
                               @NonNull List<LatLng> segment2Coordinates,
                               int segmentIndex, double distanceAlongSegment) {
            this.sessionId = UUID.randomUUID().toString();
            this.lineId = lineId;
            this.breakPointLocation = breakPointLocation;
            this.originalCoordinates = new ArrayList<>(originalCoordinates);
            this.segment1Coordinates = new ArrayList<>(segment1Coordinates);
            this.segment2Coordinates = new ArrayList<>(segment2Coordinates);
            this.segmentIndex = segmentIndex;
            this.distanceAlongSegment = distanceAlongSegment;
            this.startTime = System.currentTimeMillis();
        }
        
        /**
         * Creates a new session with updated break point location.
         */
        public BreakPointSession withUpdatedBreakPoint(@NonNull LatLng newBreakPointLocation) {
            // Recalculate segments with new break point location
            List<LatLng> newSegment1 = new ArrayList<>(segment1Coordinates);
            List<LatLng> newSegment2 = new ArrayList<>(segment2Coordinates);
            
            // Update the connection point in both segments
            if (!newSegment1.isEmpty()) {
                newSegment1.set(newSegment1.size() - 1, newBreakPointLocation);
            }
            if (!newSegment2.isEmpty()) {
                newSegment2.set(0, newBreakPointLocation);
            }
            
            return new BreakPointSession(lineId, newBreakPointLocation, originalCoordinates,
                                       newSegment1, newSegment2, segmentIndex, distanceAlongSegment);
        }
        
        /**
         * Gets the combined coordinates of both segments.
         */
        public List<LatLng> getCombinedCoordinates() {
            List<LatLng> combined = new ArrayList<>(segment1Coordinates);
            // Add segment2 coordinates, skipping the first point to avoid duplication
            if (segment2Coordinates.size() > 1) {
                combined.addAll(segment2Coordinates.subList(1, segment2Coordinates.size()));
            }
            return combined;
        }
    }
    
    /**
     * Result of finding the nearest point on a polyline.
     */
    public static class NearestPointResult {
        public final LatLng point;
        public final int segmentIndex;
        public final double distanceAlongSegment;
        public final double distanceFromOriginal;
        
        public NearestPointResult(@NonNull LatLng point, int segmentIndex, 
                                double distanceAlongSegment, double distanceFromOriginal) {
            this.point = point;
            this.segmentIndex = segmentIndex;
            this.distanceAlongSegment = distanceAlongSegment;
            this.distanceFromOriginal = distanceFromOriginal;
        }
    }
    
    /**
     * Creates a new PolylineBreakPointSystem.
     */
    public PolylineBreakPointSystem(@NonNull MapLibreMap mapLibreMap) {
        this.mapLibreMap = mapLibreMap;
        this.activeSessions = new HashMap<>();
        Log.d(TAG, "PolylineBreakPointSystem initialized");
    }
    
    /**
     * Creates a break point on a polyline at the specified location.
     * 
     * @param lineId The ID of the polyline
     * @param targetLocation The location where to create the break point
     * @return The break point session, or null if creation failed
     */
    @Nullable
    public BreakPointSession createBreakPoint(@NonNull String lineId, @NonNull LatLng targetLocation) {
        Log.d(TAG, "Creating break point for line " + lineId + " at " + targetLocation);
        
        try {
            // Get the polyline coordinates
            List<LatLng> originalCoordinates = getPolylineCoordinates(lineId);
            if (originalCoordinates == null || originalCoordinates.size() < 2) {
                Log.e(TAG, "Cannot create break point: invalid polyline coordinates");
                return null;
            }
            
            // Find the nearest point on the polyline
            NearestPointResult nearestPoint = findNearestPointOnPolyline(originalCoordinates, targetLocation);
            if (nearestPoint == null) {
                Log.e(TAG, "Cannot create break point: could not find nearest point");
                return null;
            }
            
            // Split the polyline at the break point
            List<LatLng> segment1 = new ArrayList<>();
            List<LatLng> segment2 = new ArrayList<>();
            
            // Add coordinates up to and including the break point to segment1
            for (int i = 0; i <= nearestPoint.segmentIndex; i++) {
                segment1.add(originalCoordinates.get(i));
            }
            segment1.add(nearestPoint.point);
            
            // Add break point and remaining coordinates to segment2
            segment2.add(nearestPoint.point);
            for (int i = nearestPoint.segmentIndex + 1; i < originalCoordinates.size(); i++) {
                segment2.add(originalCoordinates.get(i));
            }
            
            // Create the break point session
            BreakPointSession session = new BreakPointSession(
                lineId, nearestPoint.point, originalCoordinates,
                segment1, segment2, nearestPoint.segmentIndex, nearestPoint.distanceAlongSegment
            );
            
            // Store the active session
            activeSessions.put(lineId, session);
            
            Log.d(TAG, "Created break point session: " + session.sessionId);
            return session;
            
        } catch (Exception e) {
            Log.e(TAG, "Error creating break point: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Updates the break point location for an active session.
     * 
     * @param lineId The ID of the polyline
     * @param newLocation The new break point location
     * @return The updated session, or null if update failed
     */
    @Nullable
    public BreakPointSession updateBreakPoint(@NonNull String lineId, @NonNull LatLng newLocation) {
        BreakPointSession currentSession = activeSessions.get(lineId);
        if (currentSession == null) {
            Log.w(TAG, "Cannot update break point: no active session for line " + lineId);
            return null;
        }
        
        try {
            // Create updated session with new break point location
            BreakPointSession updatedSession = currentSession.withUpdatedBreakPoint(newLocation);
            
            // Update the stored session
            activeSessions.put(lineId, updatedSession);
            
            Log.d(TAG, "Updated break point for line " + lineId + " to " + newLocation);
            return updatedSession;
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating break point: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Finalizes a break point session and returns the final coordinates.
     * 
     * @param lineId The ID of the polyline
     * @return The final coordinates, or null if finalization failed
     */
    @Nullable
    public List<LatLng> finalizeBreakPoint(@NonNull String lineId) {
        BreakPointSession session = activeSessions.remove(lineId);
        if (session == null) {
            Log.w(TAG, "Cannot finalize break point: no active session for line " + lineId);
            return null;
        }
        
        try {
            List<LatLng> finalCoordinates = session.getCombinedCoordinates();
            Log.d(TAG, "Finalized break point for line " + lineId + 
                      " with " + finalCoordinates.size() + " coordinates");
            return finalCoordinates;
            
        } catch (Exception e) {
            Log.e(TAG, "Error finalizing break point: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Cancels an active break point session.
     * 
     * @param lineId The ID of the polyline
     */
    public void cancelBreakPoint(@NonNull String lineId) {
        BreakPointSession session = activeSessions.remove(lineId);
        if (session != null) {
            Log.d(TAG, "Cancelled break point session for line " + lineId);
        }
    }
    
    /**
     * Gets the active break point session for a polyline.
     * 
     * @param lineId The ID of the polyline
     * @return The active session, or null if none exists
     */
    @Nullable
    public BreakPointSession getActiveSession(@NonNull String lineId) {
        return activeSessions.get(lineId);
    }
    
    /**
     * Checks if a polyline has an active break point session.
     * 
     * @param lineId The ID of the polyline
     * @return true if there's an active session, false otherwise
     */
    public boolean hasActiveSession(@NonNull String lineId) {
        return activeSessions.containsKey(lineId);
    }
    
    /**
     * Gets the number of active break point sessions.
     * 
     * @return The number of active sessions
     */
    public int getActiveSessionCount() {
        return activeSessions.size();
    }
    
    /**
     * Clears all active break point sessions.
     */
    public void clearAllSessions() {
        int count = activeSessions.size();
        activeSessions.clear();
        Log.d(TAG, "Cleared " + count + " active break point sessions");
    }
    
    /**
     * Gets the coordinates of a polyline from the map.
     * 
     * @param lineId The ID of the polyline
     * @return The coordinates, or null if not found
     */
    @Nullable
    private List<LatLng> getPolylineCoordinates(@NonNull String lineId) {
        try {
            // Query the map for features with the given line ID
            // This is a simplified implementation - in practice, you would need to
            // maintain a mapping of line IDs to their coordinates or query the map layers
            
            // For now, return a sample polyline for testing
            return List.of(
                new LatLng(37.7749, -122.4194),
                new LatLng(37.7849, -122.4094),
                new LatLng(37.7949, -122.3994)
            );
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting polyline coordinates: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Finds the nearest point on a polyline to the target location.
     * 
     * @param polylineCoordinates The coordinates of the polyline
     * @param targetLocation The target location
     * @return The nearest point result, or null if calculation failed
     */
    @Nullable
    private NearestPointResult findNearestPointOnPolyline(@NonNull List<LatLng> polylineCoordinates, 
                                                         @NonNull LatLng targetLocation) {
        if (polylineCoordinates.size() < 2) {
            return null;
        }
        
        try {
            double minDistance = Double.MAX_VALUE;
            LatLng nearestPoint = null;
            int nearestSegmentIndex = -1;
            double nearestDistanceAlongSegment = 0.0;
            
            // Check each segment of the polyline
            for (int i = 0; i < polylineCoordinates.size() - 1; i++) {
                LatLng segmentStart = polylineCoordinates.get(i);
                LatLng segmentEnd = polylineCoordinates.get(i + 1);
                
                // Find the nearest point on this segment
                PointOnSegmentResult segmentResult = findNearestPointOnSegment(
                    segmentStart, segmentEnd, targetLocation
                );
                
                if (segmentResult != null && segmentResult.distance < minDistance) {
                    minDistance = segmentResult.distance;
                    nearestPoint = segmentResult.point;
                    nearestSegmentIndex = i;
                    nearestDistanceAlongSegment = segmentResult.distanceAlongSegment;
                }
            }
            
            if (nearestPoint != null) {
                return new NearestPointResult(nearestPoint, nearestSegmentIndex, 
                                            nearestDistanceAlongSegment, minDistance);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error finding nearest point on polyline: " + e.getMessage(), e);
        }
        
        return null;
    }
    
    /**
     * Result of finding the nearest point on a line segment.
     */
    private static class PointOnSegmentResult {
        final LatLng point;
        final double distance;
        final double distanceAlongSegment;
        
        PointOnSegmentResult(@NonNull LatLng point, double distance, double distanceAlongSegment) {
            this.point = point;
            this.distance = distance;
            this.distanceAlongSegment = distanceAlongSegment;
        }
    }
    
    /**
     * Finds the nearest point on a line segment to the target location.
     * 
     * @param segmentStart The start of the line segment
     * @param segmentEnd The end of the line segment
     * @param targetLocation The target location
     * @return The nearest point result, or null if calculation failed
     */
    @Nullable
    private PointOnSegmentResult findNearestPointOnSegment(@NonNull LatLng segmentStart, 
                                                          @NonNull LatLng segmentEnd, 
                                                          @NonNull LatLng targetLocation) {
        try {
            // Convert to Cartesian coordinates for easier calculation
            double x1 = segmentStart.getLongitude();
            double y1 = segmentStart.getLatitude();
            double x2 = segmentEnd.getLongitude();
            double y2 = segmentEnd.getLatitude();
            double px = targetLocation.getLongitude();
            double py = targetLocation.getLatitude();
            
            // Calculate the projection of the target point onto the line segment
            double dx = x2 - x1;
            double dy = y2 - y1;
            
            if (dx == 0 && dy == 0) {
                // Segment is a point
                double distance = calculateDistance(segmentStart, targetLocation);
                return new PointOnSegmentResult(segmentStart, distance, 0.0);
            }
            
            // Calculate the parameter t for the projection
            double t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy);
            
            // Clamp t to [0, 1] to stay within the segment
            t = Math.max(0, Math.min(1, t));
            
            // Calculate the nearest point
            double nearestX = x1 + t * dx;
            double nearestY = y1 + t * dy;
            LatLng nearestPoint = new LatLng(nearestY, nearestX);
            
            // Calculate the distance from target to nearest point
            double distance = calculateDistance(targetLocation, nearestPoint);
            
            return new PointOnSegmentResult(nearestPoint, distance, t);
            
        } catch (Exception e) {
            Log.e(TAG, "Error finding nearest point on segment: " + e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Calculates the distance between two LatLng points using Haversine formula.
     * 
     * @param point1 The first point
     * @param point2 The second point
     * @return The distance in meters
     */
    private double calculateDistance(@NonNull LatLng point1, @NonNull LatLng point2) {
        final double R = 6371000; // Earth's radius in meters
        
        double lat1Rad = Math.toRadians(point1.getLatitude());
        double lat2Rad = Math.toRadians(point2.getLatitude());
        double deltaLatRad = Math.toRadians(point2.getLatitude() - point1.getLatitude());
        double deltaLngRad = Math.toRadians(point2.getLongitude() - point1.getLongitude());
        
        double a = Math.sin(deltaLatRad / 2) * Math.sin(deltaLatRad / 2) +
                  Math.cos(lat1Rad) * Math.cos(lat2Rad) *
                  Math.sin(deltaLngRad / 2) * Math.sin(deltaLngRad / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        return R * c;
    }
    
    /**
     * Logs the current state of the break point system for debugging.
     */
    public void logState() {
        Log.d(TAG, "PolylineBreakPointSystem state:");
        Log.d(TAG, "  Active sessions: " + activeSessions.size());
        
        for (Map.Entry<String, BreakPointSession> entry : activeSessions.entrySet()) {
            BreakPointSession session = entry.getValue();
            long duration = System.currentTimeMillis() - session.startTime;
            Log.d(TAG, "    " + entry.getKey() + ": session=" + session.sessionId + 
                      ", duration=" + duration + "ms, breakPoint=" + session.breakPointLocation);
        }
    }
}