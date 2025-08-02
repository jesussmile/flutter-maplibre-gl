import XCTest
import MapLibre
@testable import maplibre_gl

class PolylineBreakPointSystemTests: XCTestCase {
    
    var mapView: MLNMapView!
    var breakPointSystem: PolylineBreakPointSystem!
    
    override func setUp() {
        super.setUp()
        mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        breakPointSystem = PolylineBreakPointSystem(mapView: mapView)
    }
    
    override func tearDown() {
        breakPointSystem = nil
        mapView = nil
        super.tearDown()
    }
    
    func testAddAndGetBreakPoint() {
        let breakPoint = PolylineBreakPoint(
            id: "bp1",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.5,
            isDragging: false
        )
        
        // Add break point
        breakPointSystem.addBreakPoint(breakPoint)
        
        // Verify it was added
        let retrieved = breakPointSystem.getBreakPoint(breakPointId: "bp1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "bp1")
        XCTAssertEqual(retrieved?.parentLineId, "line1")
        XCTAssertEqual(retrieved?.coordinate.latitude, 1.0, accuracy: 0.001)
        XCTAssertEqual(retrieved?.coordinate.longitude, 2.0, accuracy: 0.001)
        XCTAssertEqual(retrieved?.segmentIndex, 0)
        XCTAssertEqual(retrieved?.distanceAlongSegment, 0.5, accuracy: 0.001)
        XCTAssertFalse(retrieved?.isDragging ?? true)
    }
    
    func testRemoveBreakPoint() {
        let breakPoint = PolylineBreakPoint(
            id: "bp1",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.5
        )
        
        // Add and then remove
        breakPointSystem.addBreakPoint(breakPoint)
        XCTAssertNotNil(breakPointSystem.getBreakPoint(breakPointId: "bp1"))
        
        breakPointSystem.removeBreakPoint(breakPointId: "bp1")
        XCTAssertNil(breakPointSystem.getBreakPoint(breakPointId: "bp1"))
    }
    
    func testGetBreakPointsForLine() {
        let breakPoint1 = PolylineBreakPoint(
            id: "bp1",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.5
        )
        
        let breakPoint2 = PolylineBreakPoint(
            id: "bp2",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 2.0, longitude: 3.0),
            segmentIndex: 1,
            distanceAlongSegment: 0.3
        )
        
        let breakPoint3 = PolylineBreakPoint(
            id: "bp3",
            parentLineId: "line2",
            coordinate: CLLocationCoordinate2D(latitude: 3.0, longitude: 4.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.7
        )
        
        // Add break points
        breakPointSystem.addBreakPoint(breakPoint1)
        breakPointSystem.addBreakPoint(breakPoint2)
        breakPointSystem.addBreakPoint(breakPoint3)
        
        // Get break points for line1
        let line1BreakPoints = breakPointSystem.getBreakPointsForLine(lineId: "line1")
        XCTAssertEqual(line1BreakPoints.count, 2)
        
        let line1Ids = Set(line1BreakPoints.map { $0.id })
        XCTAssertTrue(line1Ids.contains("bp1"))
        XCTAssertTrue(line1Ids.contains("bp2"))
        
        // Get break points for line2
        let line2BreakPoints = breakPointSystem.getBreakPointsForLine(lineId: "line2")
        XCTAssertEqual(line2BreakPoints.count, 1)
        XCTAssertEqual(line2BreakPoints[0].id, "bp3")
    }
    
    func testDistanceBetweenCoordinates() {
        let coord1 = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let coord2 = CLLocationCoordinate2D(latitude: 0.0, longitude: 1.0)
        
        let distance = breakPointSystem.distanceBetweenCoordinates(coord1: coord1, coord2: coord2)
        
        // Distance should be approximately 111,320 meters (1 degree longitude at equator)
        XCTAssertGreaterThan(distance, 100000)
        XCTAssertLessThan(distance, 120000)
    }
    
    func testSplitPolylineAtBreakPoint() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 1.0, longitude: 1.0),
            CLLocationCoordinate2D(latitude: 2.0, longitude: 2.0),
            CLLocationCoordinate2D(latitude: 3.0, longitude: 3.0)
        ]
        
        let breakPoint = PolylineBreakPoint(
            id: "bp1",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 1.5, longitude: 1.5),
            segmentIndex: 1,
            distanceAlongSegment: 0.5
        )
        
        let (segment1, segment2) = breakPointSystem.splitPolylineAtBreakPoint(
            coordinates: coordinates,
            breakPoint: breakPoint
        )
        
        // Segment 1 should have coordinates [0,0], [1,1], [1.5,1.5]
        XCTAssertEqual(segment1.count, 3)
        XCTAssertEqual(segment1[0].latitude, 0.0, accuracy: 0.001)
        XCTAssertEqual(segment1[1].latitude, 1.0, accuracy: 0.001)
        XCTAssertEqual(segment1[2].latitude, 1.5, accuracy: 0.001)
        
        // Segment 2 should have coordinates [1.5,1.5], [2,2], [3,3]
        XCTAssertEqual(segment2.count, 3)
        XCTAssertEqual(segment2[0].latitude, 1.5, accuracy: 0.001)
        XCTAssertEqual(segment2[1].latitude, 2.0, accuracy: 0.001)
        XCTAssertEqual(segment2[2].latitude, 3.0, accuracy: 0.001)
    }
    
    func testCalculatePolylineLength() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: 1.0),
            CLLocationCoordinate2D(latitude: 1.0, longitude: 1.0)
        ]
        
        let length = breakPointSystem.calculatePolylineLength(coordinates: coordinates)
        
        // Should be approximately 2 * 111,320 meters (2 degrees)
        XCTAssertGreaterThan(length, 200000)
        XCTAssertLessThan(length, 250000)
    }
    
    func testIsValidCoordinate() {
        // Valid coordinates
        XCTAssertTrue(breakPointSystem.isValidCoordinate(CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)))
        XCTAssertTrue(breakPointSystem.isValidCoordinate(CLLocationCoordinate2D(latitude: 45.0, longitude: -122.0)))
        
        // Invalid coordinates
        XCTAssertFalse(breakPointSystem.isValidCoordinate(CLLocationCoordinate2D(latitude: Double.nan, longitude: 0.0)))
        XCTAssertFalse(breakPointSystem.isValidCoordinate(CLLocationCoordinate2D(latitude: 0.0, longitude: Double.infinity)))
        XCTAssertFalse(breakPointSystem.isValidCoordinate(CLLocationCoordinate2D(latitude: 200.0, longitude: 0.0))) // Invalid latitude
    }
    
    func testClearAllBreakPoints() {
        let breakPoint1 = PolylineBreakPoint(
            id: "bp1",
            parentLineId: "line1",
            coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.5
        )
        
        let breakPoint2 = PolylineBreakPoint(
            id: "bp2",
            parentLineId: "line2",
            coordinate: CLLocationCoordinate2D(latitude: 2.0, longitude: 3.0),
            segmentIndex: 0,
            distanceAlongSegment: 0.5
        )
        
        // Add break points
        breakPointSystem.addBreakPoint(breakPoint1)
        breakPointSystem.addBreakPoint(breakPoint2)
        XCTAssertEqual(breakPointSystem.getAllBreakPoints().count, 2)
        
        // Clear all
        breakPointSystem.clearAllBreakPoints()
        XCTAssertEqual(breakPointSystem.getAllBreakPoints().count, 0)
        XCTAssertTrue(breakPointSystem.getBreakPointsForLine(lineId: "line1").isEmpty)
        XCTAssertTrue(breakPointSystem.getBreakPointsForLine(lineId: "line2").isEmpty)
    }
}