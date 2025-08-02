package org.maplibre.maplibregl;

import android.util.Log;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Comprehensive error handling system for polyline editing operations.
 * 
 * This class provides:
 * - Error handling for invalid touch locations and geometric calculation failures
 * - Graceful degradation when native SDK operations fail
 * - Retry mechanisms with exponential backoff for platform integration errors
 * - Performance optimization for complex polylines with point simplification
 */
public class PolylineEditingErrorHandler {
    private static final String TAG = "PolylineEditingErrorHandler";
    
    // Error types
    public enum ErrorType {
        INVALID_TOUCH_LOCATION,
        GEOMETRIC_CALCULATION_FAILURE,
        NATIVE_SDK_OPERATION_FAILURE,
        PLATFORM_INTEGRATION_ERROR,
        PERFORMANCE_OPTIMIZATION_REQUIRED,
        INVALID_COORDINATES,
        MEMORY_PRESSURE,
        CONCURRENT_MODIFICATION
    }
    
    // Error severity levels
    public enum ErrorSeverity {
        LOW,      // Can continue with degraded functionality
        MEDIUM,   // Should retry operation
        HIGH,     // Must abort current operation
        CRITICAL  // System-level error requiring cleanup
    }
    
    // Retry configuration
    private static final int MAX_RETRY_ATTEMPTS = 3;
    private static final long INITIAL_RETRY_DELAY_MS = 100;
    private static final double BACKOFF_MULTIPLIER = 2.0;
    
    // Performance thresholds
    private static final int MAX_POLYLINE_POINTS = 1000;
    private static final double COORDINATE_SIMPLIFICATION_TOLERANCE = 0.0001; // ~11 meters
    
    private final ScheduledExecutorService retryExecutor;
    private final AtomicInteger errorCount;
    
    public PolylineEditingErrorHandler() {
        this.retryExecutor = Executors.newSingleThreadScheduledExecutor();
        this.errorCount = new AtomicInteger(0);
    }
    
    /**
     * Handles errors that occur during polyline editing operations.
     *
     * @param errorType The type of error that occurred
     * @param exception The exception that was thrown (can be null)
     * @param context Additional context about the error
     * @param retryCallback Callback to execute if retry is appropriate
     * @return ErrorHandlingResult indicating how to proceed
     */
    public ErrorHandlingResult handleError(ErrorType errorType, Exception exception, 
                                         String context, Runnable retryCallback) {
        errorCount.incrementAndGet();
        
        Log.w(TAG, String.format("Handling error: %s, Context: %s", errorType, context), exception);
        
        ErrorSeverity severity = determineErrorSeverity(errorType, exception);
        
        switch (severity) {
            case LOW:
                return handleLowSeverityError(errorType, context);
            case MEDIUM:
                return handleMediumSeverityError(errorType, context, retryCallback);
            case HIGH:
                return handleHighSeverityError(errorType, context);
            case CRITICAL:
                return handleCriticalError(errorType, context);
            default:
                return new ErrorHandlingResult(false, "Unknown error severity", null);
        }
    }
    
    /**
     * Validates touch location for polyline editing operations.
     *
     * @param x Screen X coordinate
     * @param y Screen Y coordinate
     * @param mapWidth Map view width
     * @param mapHeight Map view height
     * @return ValidationResult indicating if the touch location is valid
     */
    public ValidationResult validateTouchLocation(float x, float y, int mapWidth, int mapHeight) {
        // Check if coordinates are within map bounds
        if (x < 0 || x > mapWidth || y < 0 || y > mapHeight) {
            return new ValidationResult(false, "Touch location outside map bounds");
        }
        
        // Check for NaN or infinite values
        if (Float.isNaN(x) || Float.isNaN(y) || Float.isInfinite(x) || Float.isInfinite(y)) {
            return new ValidationResult(false, "Touch location contains invalid values");
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * Validates geographic coordinates for polyline operations.
     *
     * @param latitude Latitude coordinate
     * @param longitude Longitude coordinate
     * @return ValidationResult indicating if the coordinates are valid
     */
    public ValidationResult validateCoordinates(double latitude, double longitude) {
        // Check for NaN or infinite values
        if (Double.isNaN(latitude) || Double.isNaN(longitude) || 
            Double.isInfinite(latitude) || Double.isInfinite(longitude)) {
            return new ValidationResult(false, "Coordinates contain NaN or infinite values");
        }
        
        // Check latitude bounds
        if (latitude < -90.0 || latitude > 90.0) {
            return new ValidationResult(false, "Latitude out of valid range (-90 to 90)");
        }
        
        // Check longitude bounds
        if (longitude < -180.0 || longitude > 180.0) {
            return new ValidationResult(false, "Longitude out of valid range (-180 to 180)");
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * Optimizes polyline coordinates for performance if needed.
     *
     * @param coordinates Original coordinates
     * @return OptimizationResult with potentially simplified coordinates
     */
    public OptimizationResult optimizePolylineForPerformance(java.util.List<org.maplibre.android.geometry.LatLng> coordinates) {
        if (coordinates.size() <= MAX_POLYLINE_POINTS) {
            return new OptimizationResult(coordinates, false, "No optimization needed");
        }
        
        Log.i(TAG, String.format("Optimizing polyline with %d points (threshold: %d)", 
              coordinates.size(), MAX_POLYLINE_POINTS));
        
        // Simple point reduction using Douglas-Peucker-like algorithm
        java.util.List<org.maplibre.android.geometry.LatLng> optimized = simplifyPolyline(coordinates, COORDINATE_SIMPLIFICATION_TOLERANCE);
        
        String message = String.format("Simplified polyline from %d to %d points", 
                                      coordinates.size(), optimized.size());
        
        return new OptimizationResult(optimized, true, message);
    }
    
    /**
     * Determines the severity of an error based on its type and context.
     */
    private ErrorSeverity determineErrorSeverity(ErrorType errorType, Exception exception) {
        switch (errorType) {
            case INVALID_TOUCH_LOCATION:
                return ErrorSeverity.LOW;
            case GEOMETRIC_CALCULATION_FAILURE:
                return ErrorSeverity.MEDIUM;
            case NATIVE_SDK_OPERATION_FAILURE:
                return ErrorSeverity.HIGH;
            case PLATFORM_INTEGRATION_ERROR:
                return ErrorSeverity.MEDIUM;
            case PERFORMANCE_OPTIMIZATION_REQUIRED:
                return ErrorSeverity.LOW;
            case INVALID_COORDINATES:
                return ErrorSeverity.MEDIUM;
            case MEMORY_PRESSURE:
                return ErrorSeverity.HIGH;
            case CONCURRENT_MODIFICATION:
                return ErrorSeverity.MEDIUM;
            default:
                return ErrorSeverity.MEDIUM;
        }
    }
    
    /**
     * Handles low severity errors with graceful degradation.
     */
    private ErrorHandlingResult handleLowSeverityError(ErrorType errorType, String context) {
        String message = String.format("Low severity error handled gracefully: %s", errorType);
        Log.i(TAG, message);
        return new ErrorHandlingResult(true, message, null);
    }
    
    /**
     * Handles medium severity errors with retry logic.
     */
    private ErrorHandlingResult handleMediumSeverityError(ErrorType errorType, String context, Runnable retryCallback) {
        if (retryCallback != null) {
            scheduleRetry(retryCallback, 1);
            String message = String.format("Medium severity error, retry scheduled: %s", errorType);
            return new ErrorHandlingResult(true, message, null);
        } else {
            String message = String.format("Medium severity error, no retry available: %s", errorType);
            return new ErrorHandlingResult(false, message, null);
        }
    }
    
    /**
     * Handles high severity errors by aborting current operation.
     */
    private ErrorHandlingResult handleHighSeverityError(ErrorType errorType, String context) {
        String message = String.format("High severity error, aborting operation: %s", errorType);
        Log.e(TAG, message);
        return new ErrorHandlingResult(false, message, "ABORT_OPERATION");
    }
    
    /**
     * Handles critical errors requiring system cleanup.
     */
    private ErrorHandlingResult handleCriticalError(ErrorType errorType, String context) {
        String message = String.format("Critical error, system cleanup required: %s", errorType);
        Log.e(TAG, message);
        return new ErrorHandlingResult(false, message, "SYSTEM_CLEANUP_REQUIRED");
    }
    
    /**
     * Schedules a retry operation with exponential backoff.
     */
    private void scheduleRetry(Runnable retryCallback, int attemptNumber) {
        if (attemptNumber > MAX_RETRY_ATTEMPTS) {
            Log.w(TAG, "Maximum retry attempts exceeded");
            return;
        }
        
        long delay = (long) (INITIAL_RETRY_DELAY_MS * Math.pow(BACKOFF_MULTIPLIER, attemptNumber - 1));
        
        Log.i(TAG, String.format("Scheduling retry attempt %d with delay %d ms", attemptNumber, delay));
        
        retryExecutor.schedule(() -> {
            try {
                retryCallback.run();
            } catch (Exception e) {
                Log.w(TAG, String.format("Retry attempt %d failed", attemptNumber), e);
                scheduleRetry(retryCallback, attemptNumber + 1);
            }
        }, delay, TimeUnit.MILLISECONDS);
    }
    
    /**
     * Simplifies a polyline using a tolerance-based algorithm.
     */
    private java.util.List<org.maplibre.android.geometry.LatLng> simplifyPolyline(
            java.util.List<org.maplibre.android.geometry.LatLng> coordinates, double tolerance) {
        
        if (coordinates.size() <= 2) {
            return new java.util.ArrayList<>(coordinates);
        }
        
        java.util.List<org.maplibre.android.geometry.LatLng> simplified = new java.util.ArrayList<>();
        simplified.add(coordinates.get(0)); // Always keep first point
        
        org.maplibre.android.geometry.LatLng lastKept = coordinates.get(0);
        
        for (int i = 1; i < coordinates.size() - 1; i++) {
            org.maplibre.android.geometry.LatLng current = coordinates.get(i);
            
            // Calculate distance from last kept point
            double distance = calculateDistance(lastKept, current);
            
            if (distance >= tolerance) {
                simplified.add(current);
                lastKept = current;
            }
        }
        
        simplified.add(coordinates.get(coordinates.size() - 1)); // Always keep last point
        
        return simplified;
    }
    
    /**
     * Calculates distance between two coordinates in degrees.
     */
    private double calculateDistance(org.maplibre.android.geometry.LatLng coord1, org.maplibre.android.geometry.LatLng coord2) {
        double deltaLat = coord2.getLatitude() - coord1.getLatitude();
        double deltaLng = coord2.getLongitude() - coord1.getLongitude();
        return Math.sqrt(deltaLat * deltaLat + deltaLng * deltaLng);
    }
    
    /**
     * Gets error statistics for monitoring and debugging.
     */
    public ErrorStatistics getErrorStatistics() {
        return new ErrorStatistics(errorCount.get());
    }
    
    /**
     * Cleans up resources used by the error handler.
     */
    public void cleanup() {
        if (retryExecutor != null && !retryExecutor.isShutdown()) {
            retryExecutor.shutdown();
            try {
                if (!retryExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                    retryExecutor.shutdownNow();
                }
            } catch (InterruptedException e) {
                retryExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }
    
    // Result classes
    public static class ErrorHandlingResult {
        public final boolean canContinue;
        public final String message;
        public final String action;
        
        public ErrorHandlingResult(boolean canContinue, String message, String action) {
            this.canContinue = canContinue;
            this.message = message;
            this.action = action;
        }
    }
    
    public static class ValidationResult {
        public final boolean isValid;
        public final String errorMessage;
        
        public ValidationResult(boolean isValid, String errorMessage) {
            this.isValid = isValid;
            this.errorMessage = errorMessage;
        }
    }
    
    public static class OptimizationResult {
        public final java.util.List<org.maplibre.android.geometry.LatLng> coordinates;
        public final boolean wasOptimized;
        public final String message;
        
        public OptimizationResult(java.util.List<org.maplibre.android.geometry.LatLng> coordinates, 
                                boolean wasOptimized, String message) {
            this.coordinates = coordinates;
            this.wasOptimized = wasOptimized;
            this.message = message;
        }
    }
    
    public static class ErrorStatistics {
        public final int totalErrors;
        
        public ErrorStatistics(int totalErrors) {
            this.totalErrors = totalErrors;
        }
    }
}