import Foundation
import MapLibre

/**
 * Represents a break point on a polyline during editing.
 */
struct PolylineBreakPoint {
    let id: String
    let parentLineId: String
    let coordinate: CLLocationCoordinate2D
    let segmentIndex: Int
    let distanceAlongSegment: Double
    let isDragging: Bool
    
    init(id: String, parentLineId: String, coordinate: CLLocationCoordinate2D, segmentIndex: Int, distanceAlongSegment: Double, isDragging: Bool = false) {
        self.id = id
        self.parentLineId = parentLineId
        self.coordinate = coordinate
        self.segmentIndex = segmentIndex
        self.distanceAlongSegment = distanceAlongSegment
        self.isDragging = isDragging
    }
}

/**
 * Manages polyline break points and provides geometric calculations for polyline editing.
 * 
 * This class handles:
 * - Break point creation and management
 * - Polyline splitting logic compatible with MLNPolyline geometry
 * - Geometric utility methods for polyline intersection and distance calculations
 * - Tracking active editing sessions
 */
class PolylineBreakPointSystem {
    private static let TAG = "PolylineBreakPointSystem"
    
    private let mapView: MLNMapView
    private var breakPoints: [String: PolylineBreakPoint] = [:]
    private var breakPointsByLine: [String: Set<String>] = [:]
    
    // Geometric calculation constants
    private let earthRadius: Double = 6371000.0 // Earth radius in meters
    private let coordinateTolerance: Double = 1e-6
    
    init(mapView: MLNMapView) {
        self.mapView = mapView
        NSLog("\(PolylineBreakPointSystem.TAG): Initialized break point system")
    }
    
    /**
     * Adds a break point to the system.
     *
     * @param breakPoint The break point to add
     */
    func addBreakPoint(_ breakPoint: PolylineBreakPoint) {
        breakPoints[breakPoint.id] = breakPoint
        
        // Add to line-specific tracking
        if breakPointsByLine[breakPoint.parentLineId] == nil {
            breakPointsByLine[breakPoint.parentLineId] = Set<String>()
        }
        breakPointsByLine[breakPoint.parentLineId]?.insert(breakPoint.id)
        
        NSLog("\(PolylineBreakPointSystem.TAG): Added break point \(breakPoint.id) for line \(breakPoint.parentLineId)")
    }
    
    /**
     * Removes a break point from the system.
     *
     * @param breakPointId The ID of the break point to remove
     */
    func removeBreakPoint(breakPointId: String) {
        guard let breakPoint = breakPoints[breakPointId] else {
            NSLog("\(PolylineBreakPointSystem.TAG): Break point \(breakPointId) not found for removal")
            return
        }
        
        breakPoints.removeValue(forKey: breakPointId)
        breakPointsByLine[breakPoint.parentLineId]?.remove(breakPointId)
        
        // Clean up empty line entries
        if breakPointsByLine[breakPoint.parentLineId]?.isEmpty == true {
            breakPointsByLine.removeValue(forKey: breakPoint.parentLineId)
        }
        
        NSLog("\(PolylineBreakPointSystem.TAG): Removed break point \(breakPointId)")
    }
    
    /**
     * Updates an existing break point.
     *
     * @param breakPoint The updated break point
     */
    func updateBreakPoint(_ breakPoint: PolylineBreakPoint) {
        guard breakPoints[breakPoint.id] != nil else {
            NSLog("\(PolylineBreakPointSystem.TAG): Cannot update non-existent break point \(breakPoint.id)")
            return
        }
        
        breakPoints[breakPoint.id] = breakPoint
        NSLog("\(PolylineBreakPointSystem.TAG): Updated break point \(breakPoint.id)")
    }
    
    /**
     * Gets a break point by its ID.
     *
     * @param breakPointId The ID of the break point to retrieve
     * @return The break point, or nil if not found
     */
    func getBreakPoint(breakPointId: String) -> PolylineBreakPoint? {
        return breakPoints[breakPointId]
    }
    
    /**
     * Gets all break points for a specific line.
     *
     * @param lineId The ID of the line to get break points for
     * @return An array of break points for the line
     */
    func getBreakPointsForLine(lineId: String) -> [PolylineBreakPoint] {
        guard let breakPointIds = breakPointsByLine[lineId] else {
            return []
        }
        
        return breakPointIds.compactMap { breakPoints[$0] }
    }
    
    /**
     * Gets all break points in the system.
     *
     * @return An array of all break points
     */
    func getAllBreakPoints() -> [PolylineBreakPoint] {
        return Array(breakPoints.values)
    }
    
    /**
     * Removes all break points for a specific line.
     *
     * @param lineId The ID of the line to remove break points for
     */
    func removeBreakPointsForLine(lineId: String) {
        guard let breakPointIds = breakPointsByLine[lineId] else {
            return
        }
        
        for breakPointId in breakPointIds {
            breakPoints.removeValue(forKey: breakPointId)
        }
        
        breakPointsByLine.removeValue(forKey: lineId)
        NSLog("\(PolylineBreakPointSystem.TAG): Removed \(breakPointIds.count) break points for line \(lineId)")
    }
    
    /**
     * Clears all break points from the system.
     */
    func clearAllBreakPoints() {
        let count = breakPoints.count
        breakPoints.removeAll()
        breakPointsByLine.removeAll()
        NSLog("\(PolylineBreakPointSystem.TAG): Cleared \(count) break points")
    }
    
    /**
     * Creates a break point at the nearest point on a polyline segment.
     *
     * @param lineId The ID of the line to create a break point on
     * @param coordinates The coordinates of the polyline
     * @param targetCoordinate The coordinate where the break point should be created
     * @return A break point if one could be created, nil otherwise
     */
    func createBreakPointAtNearestSegment(lineId: String, coordinates: [CLLocationCoordinate2D], targetCoordinate: CLLocationCoordinate2D) -> PolylineBreakPoint? {
        guard coordinates.count >= 2 else {
            NSLog("\(PolylineBreakPointSystem.TAG): Cannot create break point on line with less than 2 coordinates")
            return nil
        }
        
        var nearestSegmentIndex = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        var nearestPointOnSegment = coordinates[0]
        var distanceAlongSegment = 0.0
        
        // Find the nearest segment
        for i in 0..<(coordinates.count - 1) {
            let segmentStart = coordinates[i]
            let segmentEnd = coordinates[i + 1]
            
            let (pointOnSegment, distance, t) = nearestPointOnLineSegment(
                point: targetCoordinate,
                lineStart: segmentStart,
                lineEnd: segmentEnd
            )
            
            if distance < nearestDistance {
                nearestDistance = distance
                nearestSegmentIndex = i
                nearestPointOnSegment = pointOnSegment
                distanceAlongSegment = t
            }
        }
        
        // Create the break point
        let breakPoint = PolylineBreakPoint(
            id: UUID().uuidString,
            parentLineId: lineId,
            coordinate: nearestPointOnSegment,
            segmentIndex: nearestSegmentIndex,
            distanceAlongSegment: distanceAlongSegment,
            isDragging: false
        )
        
        NSLog("\(PolylineBreakPointSystem.TAG): Created break point at segment \(nearestSegmentIndex) with distance \(nearestDistance)m")
        return breakPoint
    }
    
    /**
     * Splits a polyline at a break point into two segments.
     *
     * @param coordinates The original polyline coordinates
     * @param breakPoint The break point to split at
     * @return A tuple containing the two segments
     */
    func splitPolylineAtBreakPoint(coordinates: [CLLocationCoordinate2D], breakPoint: PolylineBreakPoint) -> ([CLLocationCoordinate2D], [CLLocationCoordinate2D]) {
        guard breakPoint.segmentIndex < coordinates.count - 1 else {
            NSLog("\(PolylineBreakPointSystem.TAG): Invalid segment index for break point")
            return (coordinates, [])
        }
        
        let splitIndex = breakPoint.segmentIndex + 1
        
        // First segment: from start to break point
        var segment1 = Array(coordinates[0..<splitIndex])
        segment1.append(breakPoint.coordinate)
        
        // Second segment: from break point to end
        var segment2 = [breakPoint.coordinate]
        segment2.append(contentsOf: coordinates[splitIndex...])
        
        NSLog("\(PolylineBreakPointSystem.TAG): Split polyline into segments of \(segment1.count) and \(segment2.count) points")
        return (segment1, segment2)
    }
    
    /**
     * Calculates the distance between two coordinates using the Haversine formula.
     *
     * @param coord1 The first coordinate
     * @param coord2 The second coordinate
     * @return The distance in meters
     */
    func distanceBetweenCoordinates(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let lat1Rad = coord1.latitude * .pi / 180
        let lat2Rad = coord2.latitude * .pi / 180
        let deltaLatRad = (coord2.latitude - coord1.latitude) * .pi / 180
        let deltaLonRad = (coord2.longitude - coord1.longitude) * .pi / 180
        
        let a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    /**
     * Finds the nearest point on a line segment to a given point.
     *
     * @param point The point to find the nearest point to
     * @param lineStart The start of the line segment
     * @param lineEnd The end of the line segment
     * @return A tuple containing the nearest point, distance, and parameter t (0-1)
     */
    func nearestPointOnLineSegment(point: CLLocationCoordinate2D, lineStart: CLLocationCoordinate2D, lineEnd: CLLocationCoordinate2D) -> (CLLocationCoordinate2D, Double, Double) {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        
        if abs(dx) < coordinateTolerance && abs(dy) < coordinateTolerance {
            // Line segment is essentially a point
            let distance = distanceBetweenCoordinates(coord1: point, coord2: lineStart)
            return (lineStart, distance, 0.0)
        }
        
        // Calculate parameter t for the nearest point on the line
        let t = max(0, min(1, ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)))
        
        // Calculate the nearest point
        let nearestPoint = CLLocationCoordinate2D(
            latitude: lineStart.latitude + t * dy,
            longitude: lineStart.longitude + t * dx
        )
        
        let distance = distanceBetweenCoordinates(coord1: point, coord2: nearestPoint)
        
        return (nearestPoint, distance, t)
    }
    
    /**
     * Calculates the total length of a polyline.
     *
     * @param coordinates The coordinates of the polyline
     * @return The total length in meters
     */
    func calculatePolylineLength(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0.0 }
        
        var totalLength = 0.0
        for i in 0..<(coordinates.count - 1) {
            totalLength += distanceBetweenCoordinates(coord1: coordinates[i], coord2: coordinates[i + 1])
        }
        
        return totalLength
    }
    
    /**
     * Simplifies a polyline by removing points that are closer than the specified tolerance.
     *
     * @param coordinates The original coordinates
     * @param tolerance The minimum distance between points in meters
     * @return The simplified coordinates
     */
    func simplifyPolyline(coordinates: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        
        var simplified = [coordinates[0]] // Always keep the first point
        
        for i in 1..<(coordinates.count - 1) {
            let distance = distanceBetweenCoordinates(coord1: simplified.last!, coord2: coordinates[i])
            if distance >= tolerance {
                simplified.append(coordinates[i])
            }
        }
        
        simplified.append(coordinates.last!) // Always keep the last point
        
        NSLog("\(PolylineBreakPointSystem.TAG): Simplified polyline from \(coordinates.count) to \(simplified.count) points")
        return simplified
    }
    
    /**
     * Validates that a coordinate is valid (not NaN or infinite).
     *
     * @param coordinate The coordinate to validate
     * @return true if the coordinate is valid, false otherwise
     */
    func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return CLLocationCoordinate2DIsValid(coordinate) &&
               !coordinate.latitude.isNaN && !coordinate.latitude.isInfinite &&
               !coordinate.longitude.isNaN && !coordinate.longitude.isInfinite
    }
    
    /**
     * Gets statistics about the break point system.
     *
     * @return A dictionary containing system statistics
     */
    func getSystemStatistics() -> [String: Any] {
        return [
            "totalBreakPoints": breakPoints.count,
            "linesWithBreakPoints": breakPointsByLine.count,
            "averageBreakPointsPerLine": breakPointsByLine.isEmpty ? 0 : Double(breakPoints.count) / Double(breakPointsByLine.count)
        ]
    }
}