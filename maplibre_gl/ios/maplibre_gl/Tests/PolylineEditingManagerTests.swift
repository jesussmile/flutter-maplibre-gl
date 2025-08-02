import XCTest
import MapLibre
@testable import maplibre_gl

class PolylineEditingManagerTests: XCTestCase {
    
    var mapView: MLNMapView!
    var editingManager: PolylineEditingManager!
    
    override func setUp() {
        super.setUp()
        mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        editingManager = PolylineEditingManager(mapView: mapView)
    }
    
    override func tearDown() {
        editingManager = nil
        mapView = nil
        super.tearDown()
    }
    
    func testEnableLineEditing() {
        let lineId = "test-line-1"
        
        // Initially, line should not be editable
        XCTAssertFalse(editingManager.isLineEditable(lineId: lineId))
        
        // Enable editing
        editingManager.enableLineEditing(lineId: lineId, enabled: true)
        XCTAssertTrue(editingManager.isLineEditable(lineId: lineId))
        
        // Disable editing
        editingManager.enableLineEditing(lineId: lineId, enabled: false)
        XCTAssertFalse(editingManager.isLineEditable(lineId: lineId))
    }
    
    func testSetEditingStyle() {
        let style: [String: Any] = [
            "breakPointColor": "#FF0000",
            "breakPointRadius": 10.0,
            "previewLineColor": "#00FF00",
            "previewLineOpacity": 0.8
        ]
        
        editingManager.setEditingStyle(style: style)
        let currentStyle = editingManager.getEditingStyle()
        
        XCTAssertEqual(currentStyle["breakPointColor"] as? String, "#FF0000")
        XCTAssertEqual(currentStyle["breakPointRadius"] as? Double, 10.0)
        XCTAssertEqual(currentStyle["previewLineColor"] as? String, "#00FF00")
        XCTAssertEqual(currentStyle["previewLineOpacity"] as? Double, 0.8)
    }
    
    func testGetEditableLineIds() {
        let lineId1 = "test-line-1"
        let lineId2 = "test-line-2"
        
        // Initially, no lines should be editable
        XCTAssertTrue(editingManager.getEditableLineIds().isEmpty)
        
        // Enable editing for first line
        editingManager.enableLineEditing(lineId: lineId1, enabled: true)
        XCTAssertEqual(editingManager.getEditableLineIds().count, 1)
        XCTAssertTrue(editingManager.getEditableLineIds().contains(lineId1))
        
        // Enable editing for second line
        editingManager.enableLineEditing(lineId: lineId2, enabled: true)
        XCTAssertEqual(editingManager.getEditableLineIds().count, 2)
        XCTAssertTrue(editingManager.getEditableLineIds().contains(lineId1))
        XCTAssertTrue(editingManager.getEditableLineIds().contains(lineId2))
        
        // Disable editing for first line
        editingManager.enableLineEditing(lineId: lineId1, enabled: false)
        XCTAssertEqual(editingManager.getEditableLineIds().count, 1)
        XCTAssertFalse(editingManager.getEditableLineIds().contains(lineId1))
        XCTAssertTrue(editingManager.getEditableLineIds().contains(lineId2))
    }
    
    func testUpdateLineCoordinates() {
        let lineId = "test-line-1"
        let coordinates = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 1.0, longitude: 1.0)
        ]
        
        // Enable editing first
        editingManager.enableLineEditing(lineId: lineId, enabled: true)
        
        // Update coordinates
        editingManager.updateLineCoordinates(lineId: lineId, coordinates: coordinates)
        
        // Verify coordinates were stored
        let config = editingManager.getLineConfig(lineId: lineId)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.coordinates.count, 2)
        XCTAssertEqual(config?.coordinates[0].latitude, 0.0, accuracy: 0.001)
        XCTAssertEqual(config?.coordinates[0].longitude, 0.0, accuracy: 0.001)
        XCTAssertEqual(config?.coordinates[1].latitude, 1.0, accuracy: 0.001)
        XCTAssertEqual(config?.coordinates[1].longitude, 1.0, accuracy: 0.001)
    }
    
    func testClearAllEditableLines() {
        let lineId1 = "test-line-1"
        let lineId2 = "test-line-2"
        
        // Enable editing for multiple lines
        editingManager.enableLineEditing(lineId: lineId1, enabled: true)
        editingManager.enableLineEditing(lineId: lineId2, enabled: true)
        XCTAssertEqual(editingManager.getEditableLineIds().count, 2)
        
        // Clear all
        editingManager.clearAllEditableLines()
        XCTAssertTrue(editingManager.getEditableLineIds().isEmpty)
        XCTAssertFalse(editingManager.isLineEditable(lineId: lineId1))
        XCTAssertFalse(editingManager.isLineEditable(lineId: lineId2))
    }
}