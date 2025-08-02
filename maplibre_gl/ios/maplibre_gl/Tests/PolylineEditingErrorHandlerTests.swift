import XCTest
import MapLibre
@testable import maplibre_gl

class PolylineEditingErrorHandlerTests: XCTestCase {
    
    var errorHandler: PolylineEditingErrorHandler!
    
    override func setUp() {
        super.setUp()
        errorHandler = PolylineEditingErrorHandler()
    }
    
    override func tearDown() {
        errorHandler = nil
        super.tearDown()
    }
    
    func testValidateTouchLocation_ValidLocation() {
        let point = CGPoint(x: 50, y: 100)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        
        let result = errorHandler.validateTouchLocation(point: point, mapBounds: bounds)
        
        XCTAssertTrue(result.isValid, "Valid touch location should pass validation")
        XCTAssertNil(result.errorMessage, "Valid location should have no error message")
    }
    
    func testValidateTouchLocation_OutOfBounds() {
        let point = CGPoint(x: -10, y: 100)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        
        let result = errorHandler.validateTouchLocation(point: point, mapBounds: bounds)
        
        XCTAssertFalse(result.isValid, "Out of bounds touch should fail validation")
        XCTAssertNotNil(result.errorMessage, "Invalid location should have error message")
        XCTAssertTrue(result.errorMessage?.contains("bounds") ?? false, "Error message should mention bounds")
    }
    
    func testValidateTouchLocation_NaNValues() {
        let point = CGPoint(x: CGFloat.nan, y: 100)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        
        let result = errorHandler.validateTouchLocation(point: point, mapBounds: bounds)
        
        XCTAssertFalse(result.isValid, "NaN touch coordinates should fail validation")
        XCTAssertNotNil(result.errorMessage, "NaN location should have error message")
        XCTAssertTrue(result.errorMessage?.contains("invalid") ?? false, "Error message should mention invalid values")
    }
    
    func testValidateCoordinates_ValidCoordinates() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: -122.0)
        
        let result = errorHandler.validateCoordinates(coordinate: coordinate)
        
        XCTAssertTrue(result.isValid, "Valid coordinates should pass validation")
        XCTAssertNil(result.errorMessage, "Valid coordinates should have no error message")
    }
    
    func testValidateCoordinates_InvalidLatitude() {
        let coordinate = CLLocationCoordinate2D(latitude: 95.0, longitude: -122.0)
        
        let result = errorHandler.validateCoordinates(coordinate: coordinate)
        
        XCTAssertFalse(result.isValid, "Invalid latitude should fail validation")
        XCTAssertNotNil(result.errorMessage, "Invalid latitude should have error message")
        XCTAssertTrue(result.errorMessage?.contains("Latitude") ?? false, "Error message should mention latitude")
    }
    
    func testValidateCoordinates_InvalidLongitude() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 200.0)
        
        let result = errorHandler.validateCoordinates(coordinate: coordinate)
        
        XCTAssertFalse(result.isValid, "Invalid longitude should fail validation")
        XCTAssertNotNil(result.errorMessage, "Invalid longitude should have error message")
        XCTAssertTrue(result.errorMessage?.contains("Longitude") ?? false, "Error message should mention longitude")
    }
    
    func testValidateCoordinates_NaNValues() {
        let coordinate = CLLocationCoordinate2D(latitude: Double.nan, longitude: -122.0)
        
        let result = errorHandler.validateCoordinates(coordinate: coordinate)
        
        XCTAssertFalse(result.isValid, "NaN coordinates should fail validation")
        XCTAssertNotNil(result.errorMessage, "NaN coordinates should have error message")
        XCTAssertTrue(result.errorMessage?.contains("NaN") ?? false, "Error message should mention NaN")
    }
    
    func testOptimizePolylineForPerformance_SmallPolyline() {
        let coordinates = createTestCoordinates(count: 10)
        
        let result = errorHandler.optimizePolylineForPerformance(coordinates: coordinates)
        
        XCTAssertFalse(result.wasOptimized, "Small polyline should not be optimized")
        XCTAssertEqual(coordinates.count, result.coordinates.count, "Coordinates should remain unchanged")
        XCTAssertTrue(result.message.contains("No optimization"), "Message should indicate no optimization")
    }
    
    func testOptimizePolylineForPerformance_LargePolyline() {
        let coordinates = createTestCoordinates(count: 1500)
        
        let result = errorHandler.optimizePolylineForPerformance(coordinates: coordinates)
        
        XCTAssertTrue(result.wasOptimized, "Large polyline should be optimized")
        XCTAssertLessThan(result.coordinates.count, coordinates.count, "Optimized polyline should have fewer points")
        XCTAssertTrue(result.message.contains("Simplified"), "Message should indicate simplification")
    }
    
    func testHandleError_LowSeverityError() {
        let result = errorHandler.handleError(
            errorType: .invalidTouchLocation,
            error: nil,
            context: "Test context",
            retryCallback: nil
        )
        
        XCTAssertTrue(result.canContinue, "Low severity error should allow continuation")
        XCTAssertTrue(result.message.contains("gracefully"), "Message should mention graceful handling")
    }
    
    func testHandleError_MediumSeverityErrorWithRetry() {
        let expectation = self.expectation(description: "Retry callback should be called")
        let retryCallback = {
            expectation.fulfill()
        }
        
        let result = errorHandler.handleError(
            errorType: .geometricCalculationFailure,
            error: nil,
            context: "Test context",
            retryCallback: retryCallback
        )
        
        XCTAssertTrue(result.canContinue, "Medium severity error with retry should allow continuation")
        XCTAssertTrue(result.message.contains("retry"), "Message should mention retry")
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testHandleError_MediumSeverityErrorWithoutRetry() {
        let result = errorHandler.handleError(
            errorType: .geometricCalculationFailure,
            error: nil,
            context: "Test context",
            retryCallback: nil
        )
        
        XCTAssertFalse(result.canContinue, "Medium severity error without retry should not allow continuation")
        XCTAssertTrue(result.message.contains("no retry"), "Message should mention no retry")
    }
    
    func testHandleError_HighSeverityError() {
        let result = errorHandler.handleError(
            errorType: .nativeSDKOperationFailure,
            error: nil,
            context: "Test context",
            retryCallback: nil
        )
        
        XCTAssertFalse(result.canContinue, "High severity error should not allow continuation")
        XCTAssertEqual(result.action, "ABORT_OPERATION", "Action should be ABORT_OPERATION")
    }
    
    func testHandleError_CriticalError() {
        let result = errorHandler.handleError(
            errorType: .memoryPressure,
            error: nil,
            context: "Test context",
            retryCallback: nil
        )
        
        XCTAssertFalse(result.canContinue, "Critical error should not allow continuation")
        XCTAssertEqual(result.action, "SYSTEM_CLEANUP_REQUIRED", "Action should be SYSTEM_CLEANUP_REQUIRED")
    }
    
    func testGetErrorStatistics() {
        // Handle some errors to increment the count
        _ = errorHandler.handleError(errorType: .invalidTouchLocation, error: nil, context: "Test 1", retryCallback: nil)
        _ = errorHandler.handleError(errorType: .invalidCoordinates, error: nil, context: "Test 2", retryCallback: nil)
        
        let stats = errorHandler.getErrorStatistics()
        
        XCTAssertEqual(stats.totalErrors, 2, "Error count should be 2")
    }
    
    func testResetErrorStatistics() {
        // Handle an error to increment the count
        _ = errorHandler.handleError(errorType: .invalidTouchLocation, error: nil, context: "Test", retryCallback: nil)
        
        var stats = errorHandler.getErrorStatistics()
        XCTAssertEqual(stats.totalErrors, 1, "Error count should be 1 before reset")
        
        errorHandler.resetErrorStatistics()
        
        stats = errorHandler.getErrorStatistics()
        XCTAssertEqual(stats.totalErrors, 0, "Error count should be 0 after reset")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCoordinates(count: Int) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        for i in 0..<count {
            let lat = 45.0 + (Double(i) * 0.001)
            let lng = -122.0 + (Double(i) * 0.001)
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        return coordinates
    }
}