// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.robolectric.RobolectricTestRunner;

import java.util.List;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

@RunWith(RobolectricTestRunner.class)
public class PolylineBreakPointSystemTest {

    @Mock
    private MapLibreMap mockMapLibreMap;

    private PolylineBreakPointSystem breakPointSystem;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        breakPointSystem = new PolylineBreakPointSystem(mockMapLibreMap);
    }

    @Test
    public void testInitialization() {
        assertNotNull(breakPointSystem);
        assertEquals(0, breakPointSystem.getActiveSessionCount());
        assertFalse(breakPointSystem.hasActiveSession("test-line"));
    }

    @Test
    public void testCreateBreakPoint() {
        String lineId = "test-line-1";
        LatLng targetLocation = new LatLng(37.7799, -122.4144);

        // Create break point
        PolylineBreakPointSystem.BreakPointSession session = 
            breakPointSystem.createBreakPoint(lineId, targetLocation);

        // Verify session was created
        assertNotNull(session);
        assertEquals(lineId, session.lineId);
        assertNotNull(session.breakPointLocation);
        assertNotNull(session.originalCoordinates);
        assertNotNull(session.segment1Coordinates);
        assertNotNull(session.segment2Coordinates);
        assertTrue(session.segmentIndex >= 0);
        assertTrue(session.distanceAlongSegment >= 0.0 && session.distanceAlongSegment <= 1.0);
        assertTrue(session.startTime > 0);

        // Verify system state
        assertEquals(1, breakPointSystem.getActiveSessionCount());
        assertTrue(breakPointSystem.hasActiveSession(lineId));
        assertEquals(session, breakPointSystem.getActiveSession(lineId));
    }

    @Test
    public void testCreateMultipleBreakPoints() {
        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        LatLng targetLocation1 = new LatLng(37.7799, -122.4144);
        LatLng targetLocation2 = new LatLng(37.7899, -122.4044);

        // Create break points
        PolylineBreakPointSystem.BreakPointSession session1 = 
            breakPointSystem.createBreakPoint(lineId1, targetLocation1);
        PolylineBreakPointSystem.BreakPointSession session2 = 
            breakPointSystem.createBreakPoint(lineId2, targetLocation2);

        // Verify both sessions were created
        assertNotNull(session1);
        assertNotNull(session2);
        assertNotEquals(session1.sessionId, session2.sessionId);

        // Verify system state
        assertEquals(2, breakPointSystem.getActiveSessionCount());
        assertTrue(breakPointSystem.hasActiveSession(lineId1));
        assertTrue(breakPointSystem.hasActiveSession(lineId2));
    }

    @Test
    public void testUpdateBreakPoint() {
        String lineId = "test-line-1";
        LatLng initialLocation = new LatLng(37.7799, -122.4144);
        LatLng newLocation = new LatLng(37.7809, -122.4134);

        // Create initial break point
        PolylineBreakPointSystem.BreakPointSession initialSession = 
            breakPointSystem.createBreakPoint(lineId, initialLocation);
        assertNotNull(initialSession);

        // Update break point location
        PolylineBreakPointSystem.BreakPointSession updatedSession = 
            breakPointSystem.updateBreakPoint(lineId, newLocation);

        // Verify update
        assertNotNull(updatedSession);
        assertEquals(initialSession.sessionId, updatedSession.sessionId);
        assertEquals(lineId, updatedSession.lineId);
        assertEquals(newLocation, updatedSession.breakPointLocation);
        
        // Verify system state
        assertEquals(1, breakPointSystem.getActiveSessionCount());
        assertEquals(updatedSession, breakPointSystem.getActiveSession(lineId));
    }

    @Test
    public void testUpdateNonExistentBreakPoint() {
        String lineId = "non-existent-line";
        LatLng newLocation = new LatLng(37.7809, -122.4134);

        // Try to update non-existent break point
        PolylineBreakPointSystem.BreakPointSession updatedSession = 
            breakPointSystem.updateBreakPoint(lineId, newLocation);

        // Verify update failed
        assertNull(updatedSession);
        assertEquals(0, breakPointSystem.getActiveSessionCount());
    }

    @Test
    public void testFinalizeBreakPoint() {
        String lineId = "test-line-1";
        LatLng targetLocation = new LatLng(37.7799, -122.4144);

        // Create break point
        PolylineBreakPointSystem.BreakPointSession session = 
            breakPointSystem.createBreakPoint(lineId, targetLocation);
        assertNotNull(session);
        assertEquals(1, breakPointSystem.getActiveSessionCount());

        // Finalize break point
        List<LatLng> finalCoordinates = breakPointSystem.finalizeBreakPoint(lineId);

        // Verify finalization
        assertNotNull(finalCoordinates);
        assertFalse(finalCoordinates.isEmpty());
        
        // Verify session was removed
        assertEquals(0, breakPointSystem.getActiveSessionCount());
        assertFalse(breakPointSystem.hasActiveSession(lineId));
        assertNull(breakPointSystem.getActiveSession(lineId));
    }

    @Test
    public void testFinalizeNonExistentBreakPoint() {
        String lineId = "non-existent-line";

        // Try to finalize non-existent break point
        List<LatLng> finalCoordinates = breakPointSystem.finalizeBreakPoint(lineId);

        // Verify finalization failed
        assertNull(finalCoordinates);
        assertEquals(0, breakPointSystem.getActiveSessionCount());
    }

    @Test
    public void testCancelBreakPoint() {
        String lineId = "test-line-1";
        LatLng targetLocation = new LatLng(37.7799, -122.4144);

        // Create break point
        PolylineBreakPointSystem.BreakPointSession session = 
            breakPointSystem.createBreakPoint(lineId, targetLocation);
        assertNotNull(session);
        assertEquals(1, breakPointSystem.getActiveSessionCount());

        // Cancel break point
        breakPointSystem.cancelBreakPoint(lineId);

        // Verify cancellation
        assertEquals(0, breakPointSystem.getActiveSessionCount());
        assertFalse(breakPointSystem.hasActiveSession(lineId));
        assertNull(breakPointSystem.getActiveSession(lineId));
    }

    @Test
    public void testCancelNonExistentBreakPoint() {
        String lineId = "non-existent-line";

        // Try to cancel non-existent break point (should not throw)
        breakPointSystem.cancelBreakPoint(lineId);

        // Verify state unchanged
        assertEquals(0, breakPointSystem.getActiveSessionCount());
    }

    @Test
    public void testClearAllSessions() {
        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        LatLng targetLocation1 = new LatLng(37.7799, -122.4144);
        LatLng targetLocation2 = new LatLng(37.7899, -122.4044);

        // Create multiple break points
        breakPointSystem.createBreakPoint(lineId1, targetLocation1);
        breakPointSystem.createBreakPoint(lineId2, targetLocation2);
        assertEquals(2, breakPointSystem.getActiveSessionCount());

        // Clear all sessions
        breakPointSystem.clearAllSessions();

        // Verify all sessions were cleared
        assertEquals(0, breakPointSystem.getActiveSessionCount());
        assertFalse(breakPointSystem.hasActiveSession(lineId1));
        assertFalse(breakPointSystem.hasActiveSession(lineId2));
    }

    @Test
    public void testBreakPointSessionProperties() {
        String lineId = "test-line-1";
        LatLng targetLocation = new LatLng(37.7799, -122.4144);

        // Create break point
        PolylineBreakPointSystem.BreakPointSession session = 
            breakPointSystem.createBreakPoint(lineId, targetLocation);
        assertNotNull(session);

        // Verify session properties
        assertNotNull(session.sessionId);
        assertFalse(session.sessionId.isEmpty());
        assertEquals(lineId, session.lineId);
        assertNotNull(session.breakPointLocation);
        assertNotNull(session.originalCoordinates);
        assertNotNull(session.segment1Coordinates);
        assertNotNull(session.segment2Coordinates);
        assertTrue(session.segmentIndex >= 0);
        assertTrue(session.distanceAlongSegment >= 0.0);
        assertTrue(session.startTime > 0);

        // Verify segments are not empty
        assertFalse(session.segment1Coordinates.isEmpty());
        assertFalse(session.segment2Coordinates.isEmpty());

        // Verify combined coordinates
        List<LatLng> combined = session.getCombinedCoordinates();
        assertNotNull(combined);
        assertFalse(combined.isEmpty());
        assertTrue(combined.size() >= session.segment1Coordinates.size());
    }

    @Test
    public void testBreakPointSessionWithUpdatedBreakPoint() {
        String lineId = "test-line-1";
        LatLng initialLocation = new LatLng(37.7799, -122.4144);
        LatLng newLocation = new LatLng(37.7809, -122.4134);

        // Create initial break point
        PolylineBreakPointSystem.BreakPointSession initialSession = 
            breakPointSystem.createBreakPoint(lineId, initialLocation);
        assertNotNull(initialSession);

        // Create updated session
        PolylineBreakPointSystem.BreakPointSession updatedSession = 
            initialSession.withUpdatedBreakPoint(newLocation);

        // Verify updated session
        assertNotNull(updatedSession);
        assertEquals(initialSession.sessionId, updatedSession.sessionId);
        assertEquals(initialSession.lineId, updatedSession.lineId);
        assertEquals(newLocation, updatedSession.breakPointLocation);
        assertEquals(initialSession.segmentIndex, updatedSession.segmentIndex);
        assertEquals(initialSession.distanceAlongSegment, updatedSession.distanceAlongSegment);
        assertEquals(initialSession.startTime, updatedSession.startTime);

        // Verify original session unchanged
        assertEquals(initialLocation, initialSession.breakPointLocation);
    }

    @Test
    public void testBreakPointSessionCombinedCoordinates() {
        String lineId = "test-line-1";
        LatLng targetLocation = new LatLng(37.7799, -122.4144);

        // Create break point
        PolylineBreakPointSystem.BreakPointSession session = 
            breakPointSystem.createBreakPoint(lineId, targetLocation);
        assertNotNull(session);

        // Get combined coordinates
        List<LatLng> combined = session.getCombinedCoordinates();
        assertNotNull(combined);
        assertFalse(combined.isEmpty());

        // Verify combined coordinates contain all points from both segments
        // without duplication of the break point
        int expectedSize = session.segment1Coordinates.size() + session.segment2Coordinates.size() - 1;
        assertEquals(expectedSize, combined.size());

        // Verify first point matches segment1 first point
        assertEquals(session.segment1Coordinates.get(0), combined.get(0));

        // Verify last point matches segment2 last point
        assertEquals(session.segment2Coordinates.get(session.segment2Coordinates.size() - 1), 
                    combined.get(combined.size() - 1));
    }
}