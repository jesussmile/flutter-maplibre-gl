// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.view.MotionEvent;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.robolectric.RobolectricTestRunner;

import java.util.List;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.Projection;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@RunWith(RobolectricTestRunner.class)
public class PolylineGestureDetectorTest {

    @Mock
    private MapLibreMap mockMapLibreMap;
    
    @Mock
    private Projection mockProjection;
    
    @Mock
    private PolylineEditingManager mockPolylineEditingManager;
    
    @Mock
    private PolylineBreakPointSystem mockBreakPointSystem;
    
    @Mock
    private EditablePolylineRenderer mockRenderer;
    
    @Mock
    private PolylineGestureDetector.OnPolylineGestureListener mockListener;
    
    @Mock
    private MotionEvent mockMotionEvent;

    private PolylineGestureDetector polylineGestureDetector;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        
        // Setup mock map and projection
        when(mockMapLibreMap.getProjection()).thenReturn(mockProjection);
        when(mockProjection.fromScreenLocation(any(PointF.class)))
            .thenReturn(new LatLng(37.7749, -122.4194));
        
        polylineGestureDetector = new PolylineGestureDetector(
            mockMapLibreMap, 
            mockPolylineEditingManager, 
            mockBreakPointSystem,
            mockRenderer,
            mockListener
        );
    }

    @Test
    public void testInitialization() {
        assertNotNull(polylineGestureDetector);
    }

    @Test
    public void testActionDownOnNonEditablePolyline() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of());

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not consume event if no editable polyline found
    }

    @Test
    public void testActionDownOnEditablePolyline() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        // Create a mock feature representing a polyline
        Feature mockFeature = mock(Feature.class);
        LineString mockLineString = mock(LineString.class);
        when(mockFeature.geometry()).thenReturn(mockLineString);
        when(mockFeature.id()).thenReturn("test-line-1");
        
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of(mockFeature));
        when(mockPolylineEditingManager.isLineEditable("test-line-1")).thenReturn(true);

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertTrue(result); // Should consume event if editable polyline found
    }

    @Test
    public void testMultiFingerTouchIgnored() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(2); // Two fingers

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not handle multi-finger touches
    }

    @Test
    public void testActionMoveWithoutActiveGesture() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_MOVE);

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not handle move without active gesture
    }

    @Test
    public void testActionUpCleansUpState() {
        // Setup - first start a gesture
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        Feature mockFeature = mock(Feature.class);
        LineString mockLineString = mock(LineString.class);
        when(mockFeature.geometry()).thenReturn(mockLineString);
        when(mockFeature.id()).thenReturn("test-line-1");
        
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of(mockFeature));
        when(mockPolylineEditingManager.isLineEditable("test-line-1")).thenReturn(true);

        // Start gesture
        boolean downResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);
        assertTrue(downResult);

        // Setup ACTION_UP
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_UP);

        // Execute
        boolean upResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertTrue(upResult); // Should return true since it was handling a gesture
        
        // Subsequent events should not be handled
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_MOVE);
        boolean moveResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);
        assertFalse(moveResult);
    }

    @Test
    public void testActionCancelCleansUpState() {
        // Setup - first start a gesture
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        Feature mockFeature = mock(Feature.class);
        LineString mockLineString = mock(LineString.class);
        when(mockFeature.geometry()).thenReturn(mockLineString);
        when(mockFeature.id()).thenReturn("test-line-1");
        
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of(mockFeature));
        when(mockPolylineEditingManager.isLineEditable("test-line-1")).thenReturn(true);

        // Start gesture
        boolean downResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);
        assertTrue(downResult);

        // Setup ACTION_CANCEL
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_CANCEL);

        // Execute
        boolean cancelResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertTrue(cancelResult); // Should return true since it was handling a gesture
        
        // Subsequent events should not be handled
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_MOVE);
        boolean moveResult = polylineGestureDetector.onTouchEvent(mockMotionEvent);
        assertFalse(moveResult);
    }

    @Test
    public void testUnknownActionIgnored() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_HOVER_ENTER);

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not handle unknown actions
    }

    @Test
    public void testFeatureWithoutGeometryIgnored() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        // Create a mock feature without LineString geometry
        Feature mockFeature = mock(Feature.class);
        Point mockPoint = mock(Point.class);
        when(mockFeature.geometry()).thenReturn(mockPoint); // Not a LineString
        
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of(mockFeature));

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not handle non-LineString features
    }

    @Test
    public void testFeatureWithoutIdIgnored() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        // Create a mock feature without ID
        Feature mockFeature = mock(Feature.class);
        LineString mockLineString = mock(LineString.class);
        when(mockFeature.geometry()).thenReturn(mockLineString);
        when(mockFeature.id()).thenReturn(null); // No ID
        when(mockFeature.properties()).thenReturn(null); // No properties
        
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenReturn(List.of(mockFeature));

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should not handle features without ID
    }

    @Test
    public void testQueryRenderedFeaturesException() {
        // Setup
        when(mockMotionEvent.getActionMasked()).thenReturn(MotionEvent.ACTION_DOWN);
        when(mockMotionEvent.getPointerCount()).thenReturn(1);
        when(mockMotionEvent.getX()).thenReturn(100f);
        when(mockMotionEvent.getY()).thenReturn(100f);
        
        // Make queryRenderedFeatures throw an exception
        when(mockMapLibreMap.queryRenderedFeatures(any(PointF.class), (String[]) isNull()))
            .thenThrow(new RuntimeException("Query failed"));

        // Execute
        boolean result = polylineGestureDetector.onTouchEvent(mockMotionEvent);

        // Verify
        assertFalse(result); // Should handle exceptions gracefully
    }
}