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
import java.util.Map;

import org.maplibre.android.maps.MapLibreMap;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

@RunWith(RobolectricTestRunner.class)
public class PolylineEditingManagerTest {

    @Mock
    private MapLibreMap mockMapLibreMap;

    private PolylineEditingManager polylineEditingManager;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        polylineEditingManager = new PolylineEditingManager(mockMapLibreMap);
    }

    @Test
    public void testInitialization() {
        assertNotNull(polylineEditingManager);
        assertEquals(0, polylineEditingManager.getEditablePolylineCount());
        
        // Check default style is set
        Map<String, Object> defaultStyle = polylineEditingManager.getGlobalEditingStyle();
        assertNotNull(defaultStyle);
        assertEquals("#FF0000", defaultStyle.get("breakPointColor"));
        assertEquals(8.0, defaultStyle.get("breakPointRadius"));
        assertEquals("#FFFFFF", defaultStyle.get("breakPointBorderColor"));
        assertEquals(2.0, defaultStyle.get("breakPointBorderWidth"));
        assertEquals("#00FF00", defaultStyle.get("previewLineColor"));
        assertEquals(0.7, defaultStyle.get("previewLineOpacity"));
        assertEquals(3.0, defaultStyle.get("previewLineWidth"));
        assertEquals(true, defaultStyle.get("enableHapticFeedback"));
    }

    @Test
    public void testEnableLineEditing() {
        String lineId = "test-line-1";
        
        // Initially not editable
        assertFalse(polylineEditingManager.isLineEditable(lineId));
        assertEquals(0, polylineEditingManager.getEditablePolylineCount());
        
        // Enable editing
        polylineEditingManager.enableLineEditing(lineId, true);
        assertTrue(polylineEditingManager.isLineEditable(lineId));
        assertEquals(1, polylineEditingManager.getEditablePolylineCount());
        
        // Disable editing
        polylineEditingManager.enableLineEditing(lineId, false);
        assertFalse(polylineEditingManager.isLineEditable(lineId));
        assertEquals(0, polylineEditingManager.getEditablePolylineCount());
    }

    @Test
    public void testMultiplePolylines() {
        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        String lineId3 = "test-line-3";
        
        // Enable editing for multiple polylines
        polylineEditingManager.enableLineEditing(lineId1, true);
        polylineEditingManager.enableLineEditing(lineId2, true);
        polylineEditingManager.enableLineEditing(lineId3, true);
        
        assertEquals(3, polylineEditingManager.getEditablePolylineCount());
        assertTrue(polylineEditingManager.isLineEditable(lineId1));
        assertTrue(polylineEditingManager.isLineEditable(lineId2));
        assertTrue(polylineEditingManager.isLineEditable(lineId3));
        
        // Disable one
        polylineEditingManager.enableLineEditing(lineId2, false);
        assertEquals(2, polylineEditingManager.getEditablePolylineCount());
        assertTrue(polylineEditingManager.isLineEditable(lineId1));
        assertFalse(polylineEditingManager.isLineEditable(lineId2));
        assertTrue(polylineEditingManager.isLineEditable(lineId3));
    }

    @Test
    public void testSetEditingStyle() {
        Map<String, Object> customStyle = new HashMap<>();
        customStyle.put("breakPointColor", "#0000FF");
        customStyle.put("breakPointRadius", 12.0);
        customStyle.put("previewLineOpacity", 0.5);
        
        polylineEditingManager.setEditingStyle(customStyle);
        
        Map<String, Object> retrievedStyle = polylineEditingManager.getGlobalEditingStyle();
        assertEquals("#0000FF", retrievedStyle.get("breakPointColor"));
        assertEquals(12.0, retrievedStyle.get("breakPointRadius"));
        assertEquals(0.5, retrievedStyle.get("previewLineOpacity"));
    }

    @Test
    public void testEditingConfigPersistence() {
        String lineId = "test-line-1";
        
        // Enable editing
        polylineEditingManager.enableLineEditing(lineId, true);
        
        // Get config
        PolylineEditingManager.PolylineEditingConfig config = 
            polylineEditingManager.getEditingConfig(lineId);
        assertNotNull(config);
        assertEquals(lineId, config.lineId);
        assertTrue(config.enabled);
        
        // Update style and check if existing polylines get updated
        Map<String, Object> newStyle = new HashMap<>();
        newStyle.put("breakPointColor", "#FF00FF");
        polylineEditingManager.setEditingStyle(newStyle);
        
        // Config should be updated with new style
        config = polylineEditingManager.getEditingConfig(lineId);
        assertNotNull(config);
        assertEquals("#FF00FF", config.style.get("breakPointColor"));
    }

    @Test
    public void testRemovePolyline() {
        String lineId = "test-line-1";
        
        // Enable editing
        polylineEditingManager.enableLineEditing(lineId, true);
        assertTrue(polylineEditingManager.isLineEditable(lineId));
        assertEquals(1, polylineEditingManager.getEditablePolylineCount());
        
        // Remove polyline
        polylineEditingManager.removePolyline(lineId);
        assertFalse(polylineEditingManager.isLineEditable(lineId));
        assertEquals(0, polylineEditingManager.getEditablePolylineCount());
        assertNull(polylineEditingManager.getEditingConfig(lineId));
    }

    @Test
    public void testClear() {
        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        
        // Enable editing for multiple polylines
        polylineEditingManager.enableLineEditing(lineId1, true);
        polylineEditingManager.enableLineEditing(lineId2, true);
        assertEquals(2, polylineEditingManager.getEditablePolylineCount());
        
        // Clear all
        polylineEditingManager.clear();
        assertEquals(0, polylineEditingManager.getEditablePolylineCount());
        assertFalse(polylineEditingManager.isLineEditable(lineId1));
        assertFalse(polylineEditingManager.isLineEditable(lineId2));
    }

    @Test
    public void testGetEditablePolylines() {
        String lineId1 = "test-line-1";
        String lineId2 = "test-line-2";
        
        // Enable editing for multiple polylines
        polylineEditingManager.enableLineEditing(lineId1, true);
        polylineEditingManager.enableLineEditing(lineId2, true);
        
        Map<String, PolylineEditingManager.PolylineEditingConfig> editablePolylines = 
            polylineEditingManager.getEditablePolylines();
        
        assertEquals(2, editablePolylines.size());
        assertTrue(editablePolylines.containsKey(lineId1));
        assertTrue(editablePolylines.containsKey(lineId2));
        
        // Verify it's a copy (modifications don't affect original)
        editablePolylines.clear();
        assertEquals(2, polylineEditingManager.getEditablePolylineCount());
    }

    @Test
    public void testEditingConfigImmutability() {
        String lineId = "test-line-1";
        Map<String, Object> initialStyle = new HashMap<>();
        initialStyle.put("breakPointColor", "#FF0000");
        
        polylineEditingManager.setEditingStyle(initialStyle);
        polylineEditingManager.enableLineEditing(lineId, true);
        
        PolylineEditingManager.PolylineEditingConfig config = 
            polylineEditingManager.getEditingConfig(lineId);
        assertNotNull(config);
        
        // Test withEnabled
        PolylineEditingManager.PolylineEditingConfig newConfig = config.withEnabled(false);
        assertNotEquals(config, newConfig);
        assertTrue(config.enabled);
        assertFalse(newConfig.enabled);
        assertEquals(config.lineId, newConfig.lineId);
        
        // Test withStyle
        Map<String, Object> newStyle = new HashMap<>();
        newStyle.put("breakPointColor", "#0000FF");
        PolylineEditingManager.PolylineEditingConfig styledConfig = config.withStyle(newStyle);
        assertNotEquals(config, styledConfig);
        assertEquals("#FF0000", config.style.get("breakPointColor"));
        assertEquals("#0000FF", styledConfig.style.get("breakPointColor"));
    }

    @Test
    public void testNullSafetyInEditingConfig() {
        String lineId = "test-line-1";
        
        // Test with null style
        PolylineEditingManager.PolylineEditingConfig config = 
            new PolylineEditingManager.PolylineEditingConfig(lineId, true, null);
        assertNotNull(config.style);
        assertTrue(config.style.isEmpty());
        
        // Test withStyle with null
        PolylineEditingManager.PolylineEditingConfig newConfig = config.withStyle(null);
        assertNotNull(newConfig.style);
        assertTrue(newConfig.style.isEmpty());
    }
}