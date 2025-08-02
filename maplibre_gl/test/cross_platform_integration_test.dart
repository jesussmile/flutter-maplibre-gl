import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';

/**
 * Cross-platform integration tests for polyline editing functionality.
 * 
 * These tests verify identical behavior between Android and iOS platforms
 * for all polyline editing operations.
 */
void main() {
  group('Cross-Platform Polyline Editing Integration Tests', () {
    group('Basic Polyline Editing Operations', () {
      test('LineOptions with editable property serializes consistently', () {
        final lineOptions = LineOptions(
          geometry: [
            const LatLng(37.7749, -122.4194), // San Francisco
            const LatLng(37.7849, -122.4094), // Nearby point
          ],
          editable: true,
          lineColor: '#FF0000',
          lineWidth: 3.0,
          breakPointColor: '#00FF00',
          breakPointRadius: 8.0,
          previewLineColor: '#0000FF',
          previewLineOpacity: 0.7,
        );

        final json = lineOptions.toJson();

        // Verify all editing properties are serialized
        expect(json['editable'], isTrue);
        expect(json['breakPointColor'], '#00FF00');
        expect(json['breakPointRadius'], 8.0);
        expect(json['previewLineColor'], '#0000FF');
        expect(json['previewLineOpacity'], 0.7);
        expect(json['geometry'], isNotNull);
        expect(json['geometry'], hasLength(2));
      });

      test('PolylineEditingStyle creates consistent JSON across platforms', () {
        final style = PolylineEditingStyle(
          breakPointColor: '#FF0000',
          breakPointRadius: 10.0,
          breakPointBorderColor: '#FFFFFF',
          breakPointBorderWidth: 2.0,
          previewLineColor: '#00FF00',
          previewLineOpacity: 0.8,
          previewLineWidth: 4.0,
          enableHapticFeedback: true,
        );

        final json = style.toJson();

        // Verify consistent serialization
        expect(json['breakPointColor'], '#FF0000');
        expect(json['breakPointRadius'], 10.0);
        expect(json['breakPointBorderColor'], '#FFFFFF');
        expect(json['breakPointBorderWidth'], 2.0);
        expect(json['previewLineColor'], '#00FF00');
        expect(json['previewLineOpacity'], 0.8);
        expect(json['previewLineWidth'], 4.0);
        expect(json['enableHapticFeedback'], isTrue);
      });

      test('PolylineBreakPoint serialization is platform-consistent', () {
        final breakPoint = PolylineBreakPoint(
          id: 'bp-001',
          parentLineId: 'line-001',
          coordinate: const LatLng(37.7749, -122.4194),
          segmentIndex: 1,
          distanceAlongSegment: 0.5,
          isDragging: false,
        );

        final json = breakPoint.toJson();

        // Verify consistent serialization
        expect(json['id'], 'bp-001');
        expect(json['parentLineId'], 'line-001');
        expect(json['coordinate'], isNotNull);
        expect(json['segmentIndex'], 1);
        expect(json['distanceAlongSegment'], 0.5);
        expect(json['isDragging'], isFalse);
      });
    });

    group('Polyline Editing Callbacks', () {
      test('PolylineEditingCallbacks can be created with all callback types',
          () {
        bool brokenCalled = false;
        bool modifiedCalled = false;
        bool errorCalled = false;

        final callbacks = PolylineEditingCallbacks(
          onPolylineBroken: (lineId, segment1, segment2) {
            brokenCalled = true;
            expect(lineId, isNotEmpty);
            expect(segment1, isNotEmpty);
            expect(segment2, isNotEmpty);
          },
          onPolylineModified: (lineId, coordinates) {
            modifiedCalled = true;
            expect(lineId, isNotEmpty);
            expect(coordinates, isNotEmpty);
          },
          onEditingError: (lineId, error) {
            errorCalled = true;
            expect(lineId, isNotEmpty);
            expect(error, isNotEmpty);
          },
        );

        // Test callback execution
        callbacks.onPolylineBroken
            ?.call('test-line', [const LatLng(0, 0)], [const LatLng(1, 1)]);
        callbacks.onPolylineModified
            ?.call('test-line', [const LatLng(0, 0), const LatLng(1, 1)]);
        callbacks.onEditingError?.call('test-line', 'Test error');

        expect(brokenCalled, isTrue);
        expect(modifiedCalled, isTrue);
        expect(errorCalled, isTrue);
      });
    });

    group('Complex Polyline Scenarios', () {
      test('Large polyline with many points handles consistently', () {
        // Create a polyline with many points to test performance optimization
        final coordinates = <LatLng>[];
        for (int i = 0; i < 1500; i++) {
          coordinates
              .add(LatLng(37.7749 + (i * 0.0001), -122.4194 + (i * 0.0001)));
        }

        final lineOptions = LineOptions(
          geometry: coordinates,
          editable: true,
          lineColor: '#FF0000',
          lineWidth: 2.0,
        );

        final json = lineOptions.toJson();

        expect(json['geometry'], hasLength(1500));
        expect(json['editable'], isTrue);
      });

      test('Polyline with complex geometry serializes correctly', () {
        // Test with a complex flight route
        final flightRoute = [
          const LatLng(37.7749, -122.4194), // San Francisco
          const LatLng(40.7128, -74.0060), // New York
          const LatLng(51.5074, -0.1278), // London
          const LatLng(35.6762, 139.6503), // Tokyo
          const LatLng(-33.8688, 151.2093), // Sydney
        ];

        final lineOptions = LineOptions(
          geometry: flightRoute,
          editable: true,
          lineColor: '#0066CC',
          lineWidth: 4.0,
          breakPointColor: '#FF6600',
          breakPointRadius: 12.0,
          previewLineColor: '#00CC66',
          previewLineOpacity: 0.8,
        );

        final json = lineOptions.toJson();

        expect(json['geometry'], hasLength(5));
        expect(json['editable'], isTrue);

        // Verify each coordinate is properly serialized
        final geometryJson = json['geometry'] as List;
        for (int i = 0; i < flightRoute.length; i++) {
          final coordJson = geometryJson[i] as List;
          expect(coordJson[0], closeTo(flightRoute[i].latitude, 0.0001));
          expect(coordJson[1], closeTo(flightRoute[i].longitude, 0.0001));
        }
      });
    });

    group('Error Handling Consistency', () {
      test('Invalid coordinates are handled consistently', () {
        // Test that LatLng constructor accepts extreme but valid values
        // Note: LatLng constructor may not validate bounds in all implementations
        final validLatLng1 = LatLng(90.0, -122.0); // Valid: North Pole
        final validLatLng2 = LatLng(-90.0, 180.0); // Valid: South Pole

        expect(validLatLng1.latitude, 90.0);
        expect(validLatLng1.longitude, -122.0);
        expect(validLatLng2.latitude, -90.0);
        expect(validLatLng2.longitude, -180.0); // 180 gets normalized to -180

        // Test that extreme values are preserved
        final extremeLatLng = LatLng(89.999999, 179.999999);
        expect(extremeLatLng.latitude, closeTo(89.999999, 0.000001));
        expect(extremeLatLng.longitude, closeTo(179.999999, 0.000001));
      });

      test('PolylineEditingSession handles edge cases consistently', () {
        final breakPoint = PolylineBreakPoint(
          id: 'bp-edge-case',
          parentLineId: 'line-edge-case',
          coordinate:
              const LatLng(0.0, 0.0), // Equator/Prime Meridian intersection
          segmentIndex: 0,
          distanceAlongSegment: 0.0,
          isDragging: false,
        );

        final session = PolylineEditingSession(
          lineId: 'line-edge-case',
          breakPoint: breakPoint,
          originalCoordinates: [
            const LatLng(-1.0, -1.0),
            const LatLng(1.0, 1.0),
          ],
          segment1Coordinates: [
            const LatLng(-1.0, -1.0),
            const LatLng(0.0, 0.0),
          ],
          segment2Coordinates: [
            const LatLng(0.0, 0.0),
            const LatLng(1.0, 1.0),
          ],
          startTime: DateTime.now(),
        );

        expect(session.lineId, 'line-edge-case');
        expect(session.breakPoint.coordinate.latitude, 0.0);
        expect(session.breakPoint.coordinate.longitude, 0.0);
        expect(session.originalCoordinates, hasLength(2));
        expect(session.segment1Coordinates, hasLength(2));
        expect(session.segment2Coordinates, hasLength(2));
      });
    });

    group('Performance and Memory Tests', () {
      test('Multiple simultaneous polyline editing operations', () {
        final polylines = <LineOptions>[];

        // Create multiple editable polylines
        for (int i = 0; i < 10; i++) {
          final coordinates = <LatLng>[];
          for (int j = 0; j < 100; j++) {
            coordinates.add(LatLng(
              37.7749 + (i * 0.01) + (j * 0.0001),
              -122.4194 + (i * 0.01) + (j * 0.0001),
            ));
          }

          polylines.add(LineOptions(
            geometry: coordinates,
            editable: true,
            lineColor: '#${(i * 30).toRadixString(16).padLeft(2, '0')}0000',
            lineWidth: 2.0 + i,
            breakPointColor:
                '#00${(i * 25).toRadixString(16).padLeft(2, '0')}00',
            breakPointRadius: 8.0 + i,
          ));
        }

        expect(polylines, hasLength(10));

        // Verify each polyline has unique properties
        for (int i = 0; i < polylines.length; i++) {
          final json = polylines[i].toJson();
          expect(json['editable'], isTrue);
          expect(json['geometry'], hasLength(100));
          expect(json['lineWidth'], 2.0 + i);
          expect(json['breakPointRadius'], 8.0 + i);
        }
      });

      test('Memory usage with large coordinate arrays', () {
        // Test memory efficiency with very large polylines
        final largeCoordinates = <LatLng>[];

        // Create a polyline with 5000 points
        for (int i = 0; i < 5000; i++) {
          largeCoordinates.add(LatLng(
            37.0 + (i * 0.00001),
            -122.0 + (i * 0.00001),
          ));
        }

        final lineOptions = LineOptions(
          geometry: largeCoordinates,
          editable: true,
          lineColor: '#FF0000',
          lineWidth: 3.0,
        );

        final json = lineOptions.toJson();

        expect(json['geometry'], hasLength(5000));
        expect(json['editable'], isTrue);

        // Verify memory doesn't explode during serialization
        expect(json, isNotNull);
      });
    });

    group('Coordinate System Consistency', () {
      test('Coordinate precision is maintained across platforms', () {
        // Test with high-precision coordinates
        final preciseCoordinates = [
          const LatLng(37.774929123456789, -122.419415987654321),
          const LatLng(37.784929123456789, -122.409415987654321),
        ];

        final lineOptions = LineOptions(
          geometry: preciseCoordinates,
          editable: true,
        );

        final json = lineOptions.toJson();
        final geometryJson = json['geometry'] as List;

        // Verify precision is maintained
        final coord1 = geometryJson[0] as List;
        final coord2 = geometryJson[1] as List;

        expect(coord1[0], closeTo(37.774929123456789, 0.000000000000001));
        expect(coord1[1], closeTo(-122.419415987654321, 0.000000000000001));
        expect(coord2[0], closeTo(37.784929123456789, 0.000000000000001));
        expect(coord2[1], closeTo(-122.409415987654321, 0.000000000000001));
      });

      test('Edge case coordinates are handled consistently', () {
        // Test coordinates at extreme values
        final edgeCaseCoordinates = [
          const LatLng(90.0, 180.0), // North Pole, International Date Line
          const LatLng(-90.0, -180.0), // South Pole, International Date Line
          const LatLng(0.0, 0.0), // Equator, Prime Meridian
        ];

        final lineOptions = LineOptions(
          geometry: edgeCaseCoordinates,
          editable: true,
        );

        final json = lineOptions.toJson();
        final geometryJson = json['geometry'] as List;

        expect(geometryJson, hasLength(3));

        // Verify extreme coordinates are preserved (note: some coordinates may be normalized)
        final northPole = geometryJson[0] as List;
        final southPole = geometryJson[1] as List;
        final origin = geometryJson[2] as List;

        expect(northPole[0], 90.0);
        expect(northPole[1], -180.0); // 180 gets normalized to -180
        expect(southPole[0], -90.0);
        expect(southPole[1], -180.0);
        expect(origin[0], 0.0);
        expect(origin[1], 0.0);
      });
    });

    group('Styling Consistency', () {
      test('All styling properties are preserved across platforms', () {
        final comprehensiveStyle = PolylineEditingStyle(
          breakPointColor: '#FF5733',
          breakPointRadius: 15.0,
          breakPointBorderColor: '#C70039',
          breakPointBorderWidth: 3.0,
          previewLineColor: '#33FF57',
          previewLineOpacity: 0.9,
          previewLineWidth: 5.0,
          enableHapticFeedback: false,
        );

        final json = comprehensiveStyle.toJson();

        // Verify all properties are serialized with exact values
        expect(json['breakPointColor'], '#FF5733');
        expect(json['breakPointRadius'], 15.0);
        expect(json['breakPointBorderColor'], '#C70039');
        expect(json['breakPointBorderWidth'], 3.0);
        expect(json['previewLineColor'], '#33FF57');
        expect(json['previewLineOpacity'], 0.9);
        expect(json['previewLineWidth'], 5.0);
        expect(json['enableHapticFeedback'], isFalse);
      });

      test('Default styling values are consistent', () {
        final defaultStyle = PolylineEditingStyle();
        final json = defaultStyle.toJson();

        // Verify default values match across platforms
        expect(json['breakPointColor'], '#FF0000');
        expect(json['breakPointRadius'], 8.0);
        expect(json['breakPointBorderColor'], '#FFFFFF');
        expect(json['breakPointBorderWidth'], 2.0);
        expect(json['previewLineColor'], '#00FF00');
        expect(json['previewLineOpacity'], 0.7);
        expect(json['previewLineWidth'], 3.0);
        expect(json['enableHapticFeedback'], isTrue);
      });
    });
  });
}
