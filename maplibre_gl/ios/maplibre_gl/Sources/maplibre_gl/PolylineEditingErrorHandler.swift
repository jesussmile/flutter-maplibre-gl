import Foundation
import MapLibre

/**
 * Comprehensive error handling system for polyline editing operations on iOS.
 * 
 * This class provides:
 * - Error handling for invalid touch locations and geometric calculation failures
 * - Graceful degradation when native SDK operations fail
 * - Retry mechanisms with exponential backoff for platform integration errors
 * - Performance optimization for complex polylines with point simplification
 */
class PolylineEditingErrorHandler {
    private static let TAG = "PolylineEditingErrorHandler"
    
    // Error types
    enum ErrorType {
        case invalidTouchLocation
        case geometricCalculationFailure
        case nativeSDKOperationFailure
        case platformIntegrationError
        case performanceOptimizationRequired
        case invalidCoordinates
        case memoryPressure
        case concurrentModification
    }
    
    // Error severity levels
    enum ErrorSeverity {
        case low      // Can continue with degraded functionality
        case medium   // Should retry operation
        case high     // Must abort current operation
        case critical // System-level error requiring cleanup
    }
    
    // Retry configuration
    private static let maxRetryAttempts = 3
    private static let initialRetryDelayMs: TimeInterval = 0.1
    private static let backoffMultiplier: Double = 2.0
    
    // Performance thresholds
    private static let maxPolylinePoints = 1000
    private static let coordinateSimplificationTolerance: Double = 0.0001 // ~11 meters
    
    private let retryQueue: DispatchQueue
    private var errorCount: Int = 0
    private let errorCountLock = NSLock()
    
    init() {
        self.retryQueue = DispatchQueue(label: "polyline.editing.retry", qos: .utility)
    }
    
    /**
     * Handles errors that occur during polyline editing operations.
     *
     * @param errorType The type of error that occurred
     * @param error The error that was thrown (can be nil)
     * @param context Additional context about the error
     * @param retryCallback Callback to execute if retry is appropriate
     * @return ErrorHandlingResult indicating how to proceed
     */
    func handleError(errorType: ErrorType, error: Error?, context: String, retryCallback: (() -> Void)?) -> ErrorHandlingResult {
        errorCountLock.lock()
        errorCount += 1
        errorCountLock.unlock()
        
        NSLog("\(PolylineEditingErrorHandler.TAG): Handling error: \(errorType), Context: \(context)")
        if let error = error {
            NSLog("\(PolylineEditingErrorHandler.TAG): Error details: \(error.localizedDescription)")
        }
        
        let severity = determineErrorSeverity(errorType: errorType, error: error)
        
        switch severity {
        case .low:
            return handleLowSeverityError(errorType: errorType, context: context)
        case .medium:
            return handleMediumSeverityError(errorType: errorType, context: context, retryCallback: retryCallback)
        case .high:
            return handleHighSeverityError(errorType: errorType, context: context)
        case .critical:
            return handleCriticalError(errorType: errorType, context: context)
        }
    }
    
    /**
     * Validates touch location for polyline editing operations.
     *
     * @param point Screen point coordinates
     * @param mapBounds Map view bounds
     * @return ValidationResult indicating if the touch location is valid
     */
    func validateTouchLocation(point: CGPoint, mapBounds: CGRect) -> ValidationResult {
        // Check if coordinates are within map bounds
        if !mapBounds.contains(point) {
            return ValidationResult(isValid: false, errorMessage: "Touch location outside map bounds")
        }
        
        // Check for NaN or infinite values
        if point.x.isNaN || point.y.isNaN || point.x.isInfinite || point.y.isInfinite {
            return ValidationResult(isValid: false, errorMessage: "Touch location contains invalid values")
        }
        
        return ValidationResult(isValid: true, errorMessage: nil)
    }
    
    /**
     * Validates geographic coordinates for polyline operations.
     *
     * @param coordinate Geographic coordinate
     * @return ValidationResult indicating if the coordinates are valid
     */
    func validateCoordinates(coordinate: CLLocationCoordinate2D) -> ValidationResult {
        // Check for NaN or infinite values
        if coordinate.latitude.isNaN || coordinate.longitude.isNaN ||
           coordinate.latitude.isInfinite || coordinate.longitude.isInfinite {
            return ValidationResult(isValid: false, errorMessage: "Coordinates contain NaN or infinite values")
        }
        
        // Check latitude bounds
        if coordinate.latitude < -90.0 || coordinate.latitude > 90.0 {
            return ValidationResult(isValid: false, errorMessage: "Latitude out of valid range (-90 to 90)")
        }
        
        // Check longitude bounds
        if coordinate.longitude < -180.0 || coordinate.longitude > 180.0 {
            return ValidationResult(isValid: false, errorMessage: "Longitude out of valid range (-180 to 180)")
        }
        
        // Use CLLocationCoordinate2DIsValid for additional validation
        if !CLLocationCoordinate2DIsValid(coordinate) {
            return ValidationResult(isValid: false, errorMessage: "Coordinates are not valid according to Core Location")
        }
        
        return ValidationResult(isValid: true, errorMessage: nil)
    }
    
    /**
     * Optimizes polyline coordinates for performance if needed.
     *
     * @param coordinates Original coordinates
     * @return OptimizationResult with potentially simplified coordinates
     */
    func optimizePolylineForPerformance(coordinates: [CLLocationCoordinate2D]) -> OptimizationResult {
        if coordinates.count <= PolylineEditingErrorHandler.maxPolylinePoints {
            return OptimizationResult(coordinates: coordinates, wasOptimized: false, message: "No optimization needed")
        }
        
        NSLog("\(PolylineEditingErrorHandler.TAG): Optimizing polyline with \(coordinates.count) points (threshold: \(PolylineEditingErrorHandler.maxPolylinePoints))")
        
        // Simple point reduction using Douglas-Peucker-like algorithm
        let optimized = simplifyPolyline(coordinates: coordinates, tolerance: PolylineEditingErrorHandler.coordinateSimplificationTolerance)
        
        let message = "Simplified polyline from \(coordinates.count) to \(optimized.count) points"
        
        return OptimizationResult(coordinates: optimized, wasOptimized: true, message: message)
    }
    
    /**
     * Determines the severity of an error based on its type and context.
     */
    private func determineErrorSeverity(errorType: ErrorType, error: Error?) -> ErrorSeverity {
        switch errorType {
        case .invalidTouchLocation:
            return .low
        case .geometricCalculationFailure:
            return .medium
        case .nativeSDKOperationFailure:
            return .high
        case .platformIntegrationError:
            return .medium
        case .performanceOptimizationRequired:
            return .low
        case .invalidCoordinates:
            return .medium
        case .memoryPressure:
            return .high
        case .concurrentModification:
            return .medium
        }
    }
    
    /**
     * Handles low severity errors with graceful degradation.
     */
    private func handleLowSeverityError(errorType: ErrorType, context: String) -> ErrorHandlingResult {
        let message = "Low severity error handled gracefully: \(errorType)"
        NSLog("\(PolylineEditingErrorHandler.TAG): \(message)")
        return ErrorHandlingResult(canContinue: true, message: message, action: nil)
    }
    
    /**
     * Handles medium severity errors with retry logic.
     */
    private func handleMediumSeverityError(errorType: ErrorType, context: String, retryCallback: (() -> Void)?) -> ErrorHandlingResult {
        if let retryCallback = retryCallback {
            scheduleRetry(retryCallback: retryCallback, attemptNumber: 1)
            let message = "Medium severity error, retry scheduled: \(errorType)"
            return ErrorHandlingResult(canContinue: true, message: message, action: nil)
        } else {
            let message = "Medium severity error, no retry available: \(errorType)"
            return ErrorHandlingResult(canContinue: false, message: message, action: nil)
        }
    }
    
    /**
     * Handles high severity errors by aborting current operation.
     */
    private func handleHighSeverityError(errorType: ErrorType, context: String) -> ErrorHandlingResult {
        let message = "High severity error, aborting operation: \(errorType)"
        NSLog("\(PolylineEditingErrorHandler.TAG): \(message)")
        return ErrorHandlingResult(canContinue: false, message: message, action: "ABORT_OPERATION")
    }
    
    /**
     * Handles critical errors requiring system cleanup.
     */
    private func handleCriticalError(errorType: ErrorType, context: String) -> ErrorHandlingResult {
        let message = "Critical error, system cleanup required: \(errorType)"
        NSLog("\(PolylineEditingErrorHandler.TAG): \(message)")
        return ErrorHandlingResult(canContinue: false, message: message, action: "SYSTEM_CLEANUP_REQUIRED")
    }
    
    /**
     * Schedules a retry operation with exponential backoff.
     */
    private func scheduleRetry(retryCallback: @escaping () -> Void, attemptNumber: Int) {
        if attemptNumber > PolylineEditingErrorHandler.maxRetryAttempts {
            NSLog("\(PolylineEditingErrorHandler.TAG): Maximum retry attempts exceeded")
            return
        }
        
        let delay = PolylineEditingErrorHandler.initialRetryDelayMs * pow(PolylineEditingErrorHandler.backoffMultiplier, Double(attemptNumber - 1))
        
        NSLog("\(PolylineEditingErrorHandler.TAG): Scheduling retry attempt \(attemptNumber) with delay \(delay * 1000) ms")
        
        retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            do {
                retryCallback()
            } catch {
                NSLog("\(PolylineEditingErrorHandler.TAG): Retry attempt \(attemptNumber) failed: \(error.localizedDescription)")
                self?.scheduleRetry(retryCallback: retryCallback, attemptNumber: attemptNumber + 1)
            }
        }
    }
    
    /**
     * Simplifies a polyline using a tolerance-based algorithm.
     */
    private func simplifyPolyline(coordinates: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        if coordinates.count <= 2 {
            return coordinates
        }
        
        var simplified: [CLLocationCoordinate2D] = []
        simplified.append(coordinates[0]) // Always keep first point
        
        var lastKept = coordinates[0]
        
        for i in 1..<(coordinates.count - 1) {
            let current = coordinates[i]
            
            // Calculate distance from last kept point
            let distance = calculateDistance(coord1: lastKept, coord2: current)
            
            if distance >= tolerance {
                simplified.append(current)
                lastKept = current
            }
        }
        
        simplified.append(coordinates[coordinates.count - 1]) // Always keep last point
        
        return simplified
    }
    
    /**
     * Calculates distance between two coordinates in degrees.
     */
    private func calculateDistance(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let deltaLat = coord2.latitude - coord1.latitude
        let deltaLng = coord2.longitude - coord1.longitude
        return sqrt(deltaLat * deltaLat + deltaLng * deltaLng)
    }
    
    /**
     * Gets error statistics for monitoring and debugging.
     */
    func getErrorStatistics() -> ErrorStatistics {
        errorCountLock.lock()
        let count = errorCount
        errorCountLock.unlock()
        return ErrorStatistics(totalErrors: count)
    }
    
    /**
     * Resets error statistics.
     */
    func resetErrorStatistics() {
        errorCountLock.lock()
        errorCount = 0
        errorCountLock.unlock()
    }
}

// MARK: - Result Structures

extension PolylineEditingErrorHandler {
    
    struct ErrorHandlingResult {
        let canContinue: Bool
        let message: String
        let action: String?
    }
    
    struct ValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }
    
    struct OptimizationResult {
        let coordinates: [CLLocationCoordinate2D]
        let wasOptimized: Bool
        let message: String
    }
    
    struct ErrorStatistics {
        let totalErrors: Int
    }
}