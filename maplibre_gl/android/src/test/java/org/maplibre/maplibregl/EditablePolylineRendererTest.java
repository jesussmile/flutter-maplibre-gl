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

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.style.layers.CircleLayer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.android.style.Style;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@RunWith(RobolectricTestRunner.class)
public class EditablePolylineRendererTest {

    @Mock
    private MapLibreMap mockMapLibreMap;
    
    @Mock
    private Style mockStyle;
    
    @Mock
    private GeoJsonSource mockBreakPointSource;
    
    @Mock
    private GeoJsonSource mockPreviewLineSource;
    
    @Mock
    private CircleLayer mockBreakPointLayer;
    
    @Mock
    private LineLayer mockPreviewLineLayer;

    private EditablePolylineRenderer renderer;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        
        // Setup mock style
        when(mockMapLibreMap.getStyle()).thenReturn(mockStyle);
        when(mockStyle.getSource(anyString())).thenReturn(mockBreakPointSource);
        when(mockStyle.getLayer(anyString())).thenReturn(mockBreakPointLayer);
        
        renderer = new EditablePolylineRenderer(mockMapLibreMap);
    }

    @Test
    public void testInitialization() {
        assertNotNull(renderer);
        assertFalse(renderer.isInitialized());
        assertEquals(0, renderer.getActiveBreakPointCount());
        assertEquals(0, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testInitialize() {
        // Mock successful initialization
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));

        // Initialize renderer
        boolean result = renderer.initialize();

        // Verify initialization
        assertTrue(result);
        assertTrue(renderer.isInitialized());
        
        // Verify sources and layers were added
        verify(mockStyle, times(2)).addSource(any(GeoJsonSource.class));
        verify(mockStyle, times(1)).addLayer(any(CircleLayer.class));
        verify(mockStyle, times(1)).addLayer(any(LineLayer.class));
    }

    @Test
    public void testInitializeFailure() {
        // Mock initialization failure
        doThrow(new RuntimeException("Style error")).when(mockStyle).addSource(any(GeoJsonSource.class));

        // Initialize renderer
        boolean result = renderer.initialize();

        // Verify initialization failed
        assertFalse(result);
        assertFalse(renderer.isInitialized());
    }

    @Test
    public void testUpdateStyle() {
        Map<String, Object> style = new HashMap<>();
        style.put("breakPointColor", "#0000FF");
        style.put("breakPointRadius", 10.0);
        style.put("previewLineColor", "#FF00FF");
        style.put("previewLineOpacity", 0.5);

        // Update style (should not throw even if not initialized)
        renderer.updateStyle(style);

        // Verify no exceptions thrown
        assertTrue(true);
    }

    @Test
    public void testShowBreakPointWithoutInitialization() {
        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        // Try to show break point without initialization
        renderer.showBreakPoint(lineId, location);

        // Should not crash, but break point count should remain 0
        assertEquals(0, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testShowBreakPointWithInitialization() {
        // Initialize renderer first
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        // Show break point
        renderer.showBreakPoint(lineId, location);

        // Verify break point was added
        assertEquals(1, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testUpdateBreakPoint() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        LatLng initialLocation = new LatLng(37.7749, -122.4194);
        LatLng newLocation = new LatLng(37.7849, -122.4094);

        // Show initial break point
        renderer.showBreakPoint(lineId, initialLocation);
        assertEquals(1, renderer.getActiveBreakPointCount());

        // Update break point location
        renderer.updateBreakPoint(lineId, newLocation);

        // Should still have 1 break point
        assertEquals(1, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testUpdateNonExistentBreakPoint() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "non-existent-line";
        LatLng newLocation = new LatLng(37.7849, -122.4094);

        // Try to update non-existent break point (should not crash)
        renderer.updateBreakPoint(lineId, newLocation);

        // Should have no break points
        assertEquals(0, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testSetBreakPointDragging() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        // Show break point
        renderer.showBreakPoint(lineId, location);

        // Set dragging state
        renderer.setBreakPointDragging(lineId, true);

        // Should still have 1 break point
        assertEquals(1, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testHideBreakPoint() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        // Show break point
        renderer.showBreakPoint(lineId, location);
        assertEquals(1, renderer.getActiveBreakPointCount());

        // Hide break point
        renderer.hideBreakPoint(lineId);
        assertEquals(0, renderer.getActiveBreakPointCount());
    }

    @Test
    public void testShowPreviewLine() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        List<LatLng> coordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );

        // Show preview line
        renderer.showPreviewLine(lineId, coordinates);

        // Verify preview line was added
        assertEquals(1, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testShowPreviewLineWithInsufficientCoordinates() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        List<LatLng> coordinates = List.of(
            new LatLng(37.7749, -122.4194)
        ); // Only 1 coordinate

        // Try to show preview line with insufficient coordinates
        renderer.showPreviewLine(lineId, coordinates);

        // Should not add preview line
        assertEquals(0, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testUpdatePreviewLine() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        List<LatLng> initialCoordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );
        List<LatLng> newCoordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7799, -122.4144),
            new LatLng(37.7849, -122.4094)
        );

        // Show initial preview line
        renderer.showPreviewLine(lineId, initialCoordinates);
        assertEquals(1, renderer.getActivePreviewLineCount());

        // Update preview line
        renderer.updatePreviewLine(lineId, newCoordinates);

        // Should still have 1 preview line
        assertEquals(1, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testHidePreviewLine() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId = "test-line-1";
        List<LatLng> coordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );

        // Show preview line
        renderer.showPreviewLine(lineId, coordinates);
        assertEquals(1, renderer.getActivePreviewLineCount());

        // Hide preview line
        renderer.hidePreviewLine(lineId);
        assertEquals(0, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testClearAll() {
        // Initialize renderer
        doNothing().when(mockStyle).addSource(any(GeoJsonSource.class));
        doNothing().when(mockStyle).addLayer(any(CircleLayer.class));
        doNothing().when(mockStyle).addLayer(any(LineLayer.class));
        renderer.initialize();

        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        LatLng location = new LatLng(37.7749, -122.4194);
        List<LatLng> coordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );

        // Add multiple visual elements
        renderer.showBreakPoint(lineId1, location);
        renderer.showBreakPoint(lineId2, location);
        renderer.showPreviewLine(lineId1, coordinates);
        renderer.showPreviewLine(lineId2, coordinates);

        assertEquals(2, renderer.getActiveBreakPointCount());
        assertEquals(2, renderer.getActivePreviewLineCount());

        // Clear all
        renderer.clearAll();

        assertEquals(0, renderer.getActiveBreakPointCount());
        assertEquals(0, renderer.getActivePreviewLineCount());
    }

    @Test
    public void testBreakPointVisualStateProperties() {
        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        EditablePolylineRenderer.BreakPointVisualState state = 
            new EditablePolylineRenderer.BreakPointVisualState(lineId, location, true, false);

        assertEquals(lineId, state.lineId);
        assertEquals(location, state.location);
        assertTrue(state.isVisible);
        assertFalse(state.isDragging);
        assertTrue(state.createdTime > 0);
    }

    @Test
    public void testBreakPointVisualStateWithLocation() {
        String lineId = "test-line-1";
        LatLng initialLocation = new LatLng(37.7749, -122.4194);
        LatLng newLocation = new LatLng(37.7849, -122.4094);

        EditablePolylineRenderer.BreakPointVisualState initialState = 
            new EditablePolylineRenderer.BreakPointVisualState(lineId, initialLocation, true, false);

        EditablePolylineRenderer.BreakPointVisualState updatedState = 
            initialState.withLocation(newLocation);

        assertEquals(lineId, updatedState.lineId);
        assertEquals(newLocation, updatedState.location);
        assertTrue(updatedState.isVisible);
        assertFalse(updatedState.isDragging);
        assertEquals(initialState.createdTime, updatedState.createdTime);

        // Original state should be unchanged
        assertEquals(initialLocation, initialState.location);
    }

    @Test
    public void testBreakPointVisualStateWithDragging() {
        String lineId = "test-line-1";
        LatLng location = new LatLng(37.7749, -122.4194);

        EditablePolylineRenderer.BreakPointVisualState initialState = 
            new EditablePolylineRenderer.BreakPointVisualState(lineId, location, true, false);

        EditablePolylineRenderer.BreakPointVisualState updatedState = 
            initialState.withDragging(true);

        assertEquals(lineId, updatedState.lineId);
        assertEquals(location, updatedState.location);
        assertTrue(updatedState.isVisible);
        assertTrue(updatedState.isDragging);
        assertEquals(initialState.createdTime, updatedState.createdTime);

        // Original state should be unchanged
        assertFalse(initialState.isDragging);
    }

    @Test
    public void testPreviewLineVisualStateProperties() {
        String lineId = "test-line-1";
        List<LatLng> coordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );

        EditablePolylineRenderer.PreviewLineVisualState state = 
            new EditablePolylineRenderer.PreviewLineVisualState(lineId, coordinates, true);

        assertEquals(lineId, state.lineId);
        assertEquals(2, state.coordinates.size());
        assertTrue(state.isVisible);
        assertTrue(state.createdTime > 0);
    }

    @Test
    public void testPreviewLineVisualStateWithCoordinates() {
        String lineId = "test-line-1";
        List<LatLng> initialCoordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7849, -122.4094)
        );
        List<LatLng> newCoordinates = List.of(
            new LatLng(37.7749, -122.4194),
            new LatLng(37.7799, -122.4144),
            new LatLng(37.7849, -122.4094)
        );

        EditablePolylineRenderer.PreviewLineVisualState initialState = 
            new EditablePolylineRenderer.PreviewLineVisualState(lineId, initialCoordinates, true);

        EditablePolylineRenderer.PreviewLineVisualState updatedState = 
            initialState.withCoordinates(newCoordinates);

        assertEquals(lineId, updatedState.lineId);
        assertEquals(3, updatedState.coordinates.size());
        assertTrue(updatedState.isVisible);
        assertEquals(initialState.createdTime, updatedState.createdTime);

        // Original state should be unchanged
        assertEquals(2, initialState.coordinates.size());
    }
}