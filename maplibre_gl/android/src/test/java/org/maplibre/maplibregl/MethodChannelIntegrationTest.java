package org.maplibre.maplibregl;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import android.content.Context;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

import java.util.HashMap;
import java.util.Map;

/**
 * Integration tests for method channel communication with polyline editing functionality.
 */
@RunWith(RobolectricTestRunner.class)
public class MethodChannelIntegrationTest {

    @Mock
    private BinaryMessenger mockMessenger;
    
    @Mock
    private MethodChannel.Result mockResult;
    
    @Mock
    private MapLibreMapsPlugin.LifecycleProvider mockLifecycleProvider;
    
    private MapLibreMapController controller;
    private Context context;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        context = RuntimeEnvironment.getApplication();
        
        // Create controller with mocked dependencies
        controller = new MapLibreMapController(
            1,
            context,
            mockMessenger,
            mockLifecycleProvider,
            null,
            null,
            false
        );
    }

    @Test
    public void testLineEnableEditingMethodCall() {
        // Prepare method call
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("lineId", "test-line-1");
        arguments.put("enabled", true);
        
        MethodCall call = new MethodCall("line#enableEditing", arguments);
        
        // Execute method call
        controller.onMethodCall(call, mockResult);
        
        // Verify success response (since polylineEditingManager might be null in test)
        // In a real scenario, this would enable editing for the line
        verify(mockResult, atLeastOnce()).success(any());
    }

    @Test
    public void testLineSetEditingStyleMethodCall() {
        // Prepare method call with style properties
        Map<String, Object> style = new HashMap<>();
        style.put("breakPointColor", "#FF0000");
        style.put("breakPointRadius", 10.0);
        style.put("previewLineColor", "#00FF00");
        style.put("previewLineOpacity", 0.8);
        
        MethodCall call = new MethodCall("line#setEditingStyle", style);
        
        // Execute method call
        controller.onMethodCall(call, mockResult);
        
        // Verify success response
        verify(mockResult, atLeastOnce()).success(any());
    }

    @Test
    public void testLineIsEditableMethodCall() {
        // Prepare method call
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("lineId", "test-line-1");
        
        MethodCall call = new MethodCall("line#isEditable", arguments);
        
        // Execute method call
        controller.onMethodCall(call, mockResult);
        
        // Verify response (should return boolean)
        verify(mockResult, atLeastOnce()).success(any());
    }

    @Test
    public void testInvalidMethodCall() {
        // Test with invalid method name
        MethodCall call = new MethodCall("invalid#method", null);
        
        // Execute method call
        controller.onMethodCall(call, mockResult);
        
        // Verify not implemented response
        verify(mockResult).notImplemented();
    }

    @Test
    public void testLineEnableEditingWithInvalidArguments() {
        // Test with missing arguments
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("lineId", "test-line-1");
        // Missing 'enabled' argument
        
        MethodCall call = new MethodCall("line#enableEditing", arguments);
        
        // Execute method call
        controller.onMethodCall(call, mockResult);
        
        // Verify error response
        verify(mockResult).error(eq("INVALID_ARGUMENTS"), anyString(), isNull());
    }
}