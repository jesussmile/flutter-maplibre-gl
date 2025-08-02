package org.maplibre.maplibregl;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.maplibre.android.geometry.LatLng;

import java.util.ArrayList;
import java.util.List;

/**
 * Unit tests for PolylineEditingErrorHandler.
 */
@RunWith(RobolectricTestRunner.class)
public class PolylineEditingErrorHandlerTest {

    private PolylineEditingErrorHandler errorHandler;

    @Before
    public void setUp() {
        errorHandler = new PolylineEditingErrorHandler();
    }

    @Test
    public void testValidateTouchLocation_ValidLocation() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateTouchLocation(50f, 100f, 200, 300);
        
        assertTrue("Valid touch location should pass validation", result.isValid);
        assertNull("Valid location should have no error message", result.errorMessage);
    }

    @Test
    public void testValidateTouchLocation_OutOfBounds() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateTouchLocation(-10f, 100f, 200, 300);
        
        assertFalse("Out of bounds touch should fail validation", result.isValid);
        assertNotNull("Invalid location should have error message", result.errorMessage);
        assertTrue("Error message should mention bounds", 
                  result.errorMessage.contains("bounds"));
    }

    @Test
    public void testValidateTouchLocation_NaNValues() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateTouchLocation(Float.NaN, 100f, 200, 300);
        
        assertFalse("NaN touch coordinates should fail validation", result.isValid);
        assertNotNull("NaN location should have error message", result.errorMessage);
        assertTrue("Error message should mention invalid values", 
                  result.errorMessage.contains("invalid"));
    }

    @Test
    public void testValidateCoordinates_ValidCoordinates() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateCoordinates(45.0, -122.0);
        
        assertTrue("Valid coordinates should pass validation", result.isValid);
        assertNull("Valid coordinates should have no error message", result.errorMessage);
    }

    @Test
    public void testValidateCoordinates_InvalidLatitude() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateCoordinates(95.0, -122.0);
        
        assertFalse("Invalid latitude should fail validation", result.isValid);
        assertNotNull("Invalid latitude should have error message", result.errorMessage);
        assertTrue("Error message should mention latitude", 
                  result.errorMessage.contains("Latitude"));
    }

    @Test
    public void testValidateCoordinates_InvalidLongitude() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateCoordinates(45.0, 200.0);
        
        assertFalse("Invalid longitude should fail validation", result.isValid);
        assertNotNull("Invalid longitude should have error message", result.errorMessage);
        assertTrue("Error message should mention longitude", 
                  result.errorMessage.contains("Longitude"));
    }

    @Test
    public void testValidateCoordinates_NaNValues() {
        PolylineEditingErrorHandler.ValidationResult result = 
            errorHandler.validateCoordinates(Double.NaN, -122.0);
        
        assertFalse("NaN coordinates should fail validation", result.isValid);
        assertNotNull("NaN coordinates should have error message", result.errorMessage);
        assertTrue("Error message should mention NaN", 
                  result.errorMessage.contains("NaN"));
    }

    @Test
    public void testOptimizePolylineForPerformance_SmallPolyline() {
        List<LatLng> coordinates = createTestCoordinates(10);
        
        PolylineEditingErrorHandler.OptimizationResult result = 
            errorHandler.optimizePolylineForPerformance(coordinates);
        
        assertFalse("Small polyline should not be optimized", result.wasOptimized);
        assertEquals("Coordinates should remain unchanged", 
                    coordinates.size(), result.coordinates.size());
        assertTrue("Message should indicate no optimization", 
                  result.message.contains("No optimization"));
    }

    @Test
    public void testOptimizePolylineForPerformance_LargePolyline() {
        List<LatLng> coordinates = createTestCoordinates(1500);
        
        PolylineEditingErrorHandler.OptimizationResult result = 
            errorHandler.optimizePolylineForPerformance(coordinates);
        
        assertTrue("Large polyline should be optimized", result.wasOptimized);
        assertTrue("Optimized polyline should have fewer points", 
                  result.coordinates.size() < coordinates.size());
        assertTrue("Message should indicate simplification", 
                  result.message.contains("Simplified"));
    }

    @Test
    public void testHandleError_LowSeverityError() {
        Runnable mockCallback = mock(Runnable.class);
        
        PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.INVALID_TOUCH_LOCATION,
            null,
            "Test context",
            mockCallback
        );
        
        assertTrue("Low severity error should allow continuation", result.canContinue);
        assertNotNull("Result should have a message", result.message);
        assertTrue("Message should mention graceful handling", 
                  result.message.contains("gracefully"));
    }

    @Test
    public void testHandleError_MediumSeverityErrorWithRetry() {
        Runnable mockCallback = mock(Runnable.class);
        
        PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.GEOMETRIC_CALCULATION_FAILURE,
            null,
            "Test context",
            mockCallback
        );
        
        assertTrue("Medium severity error with retry should allow continuation", result.canContinue);
        assertNotNull("Result should have a message", result.message);
        assertTrue("Message should mention retry", 
                  result.message.contains("retry"));
    }

    @Test
    public void testHandleError_MediumSeverityErrorWithoutRetry() {
        PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.GEOMETRIC_CALCULATION_FAILURE,
            null,
            "Test context",
            null
        );
        
        assertFalse("Medium severity error without retry should not allow continuation", result.canContinue);
        assertNotNull("Result should have a message", result.message);
        assertTrue("Message should mention no retry", 
                  result.message.contains("no retry"));
    }

    @Test
    public void testHandleError_HighSeverityError() {
        PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.NATIVE_SDK_OPERATION_FAILURE,
            null,
            "Test context",
            null
        );
        
        assertFalse("High severity error should not allow continuation", result.canContinue);
        assertNotNull("Result should have a message", result.message);
        assertEquals("Action should be ABORT_OPERATION", "ABORT_OPERATION", result.action);
    }

    @Test
    public void testHandleError_CriticalError() {
        PolylineEditingErrorHandler.ErrorHandlingResult result = errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.MEMORY_PRESSURE,
            null,
            "Test context",
            null
        );
        
        assertFalse("Critical error should not allow continuation", result.canContinue);
        assertNotNull("Result should have a message", result.message);
        assertEquals("Action should be SYSTEM_CLEANUP_REQUIRED", 
                    "SYSTEM_CLEANUP_REQUIRED", result.action);
    }

    @Test
    public void testGetErrorStatistics() {
        // Handle some errors to increment the count
        errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.INVALID_TOUCH_LOCATION,
            null, "Test 1", null);
        errorHandler.handleError(
            PolylineEditingErrorHandler.ErrorType.INVALID_COORDINATES,
            null, "Test 2", null);
        
        PolylineEditingErrorHandler.ErrorStatistics stats = errorHandler.getErrorStatistics();
        
        assertEquals("Error count should be 2", 2, stats.totalErrors);
    }

    @Test
    public void testCleanup() {
        // This test mainly ensures cleanup doesn't throw exceptions
        assertDoesNotThrow("Cleanup should not throw exceptions", () -> {
            errorHandler.cleanup();
        });
    }

    /**
     * Helper method to create test coordinates.
     */
    private List<LatLng> createTestCoordinates(int count) {
        List<LatLng> coordinates = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            double lat = 45.0 + (i * 0.001);
            double lng = -122.0 + (i * 0.001);
            coordinates.add(new LatLng(lat, lng));
        }
        return coordinates;
    }

    /**
     * Helper method for assertDoesNotThrow (for older JUnit versions).
     */
    private void assertDoesNotThrow(String message, Runnable runnable) {
        try {
            runnable.run();
        } catch (Exception e) {
            fail(message + ": " + e.getMessage());
        }
    }
}