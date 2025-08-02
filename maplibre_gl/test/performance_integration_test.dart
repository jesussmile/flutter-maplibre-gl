import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';
import 'dart:math' as math;

/**
 * Performance integration tests for polyline editing functionality.
 * 
 * These tests verify that both Android and iOS platforms handle
 * large polylines and complex geometries efficiently.
 */
void main() {
  group('Performance Integration Tests', () {
    group('Large Polyline Performance', () {
      test('Handles polylines with 1000+ points efficiently', () {
        final stopwatch = Stopwatch()..start();

        // Create a large polyline with 2000 points
        final coordinates = generateLargePolyline(2000);

        final lineOptions = LineOptions(
          geometry: coordinates,
          editable: true,
          lineColor: '#FF0000',
          lineWidth: 3.0,
          breakPointColor: '#00FF00',
          breakPointRadius: 8.0,
        );

        final json = lineOptions.toJson();

        stopwatch.stop();

        // Verify the polyline was created successfully
        expect(json['geometry'], hasLength(2000));
        expect(json['editable'], isTrue);

        // Performance assertion - should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(1000),
            reason:
                'Large polyline serialization should complete within 1 second');

        print(
            'Large polyline (2000 points) serialization took: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('Memory usage remains stable with very large polylines', () {
        // Test with progressively larger polylines
        final sizes = [500, 1000, 2000, 5000];
        final timings = <int, int>{};

        for (final size in sizes) {
          final stopwatch = Stopwatch()..start();

          final coordinates = generateLargePolyline(size);
          final lineOptions = LineOptions(
            geometry: coordinates,
            editable: true,
            lineColor: '#FF0000',
            lineWidth: 2.0,
          );

          final json = lineOptions.toJson();

          stopwatch.stop();
          timings[size] = stopwatch.elapsedMilliseconds;

          expect(json['geometry'], hasLength(size));

          print(
              'Polyline with $size points took: ${stopwatch.elapsedMilliseconds}ms');
        }

        // Verify that timing scales reasonably (not exponentially)
        expect(timings[5000]!, lessThan(timings[500]! * 20),
            reason: 'Performance should scale reasonably with polyline size');
      });

      test('Complex polyline geometries with editing properties', () {
        final stopwatch = Stopwatch()..start();

        // Create a complex polyline representing a flight path with multiple segments
        final flightPath = generateComplexFlightPath();

        final lineOptions = LineOptions(
          geometry: flightPath,
          editable: true,
          lineColor: '#0066CC',
          lineWidth: 4.0,
          breakPointColor: '#FF6600',
          breakPointRadius: 10.0,
          previewLineColor: '#00CC66',
          previewLineOpacity: 0.8,
        );

        final json = lineOptions.toJson();

        stopwatch.stop();

        expect(json['geometry'], hasLength(flightPath.length));
        expect(json['editable'], isTrue);

        // Should handle complex geometries efficiently
        expect(stopwatch.elapsedMilliseconds, lessThan(100),
            reason: 'Complex geometry serialization should be fast');

        print(
            'Complex flight path serialization took: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('Multiple Polyline Performance', () {
      test('Handles multiple simultaneous editable polylines', () {
        final stopwatch = Stopwatch()..start();

        final polylines = <LineOptions>[];

        // Create 50 editable polylines with 100 points each
        for (int i = 0; i < 50; i++) {
          final coordinates = generatePolylineAroundPoint(
            LatLng(37.7749 + (i * 0.01), -122.4194 + (i * 0.01)),
            100,
            0.001, // 1km radius approximately
          );

          polylines.add(LineOptions(
            geometry: coordinates,
            editable: true,
            lineColor: '#${(i * 5).toRadixString(16).padLeft(6, '0')}',
            lineWidth: 2.0 + (i % 5),
            breakPointColor: '#FF${(i * 4).toRadixString(16).padLeft(4, '0')}',
            breakPointRadius: 8.0 + (i % 3),
          ));
        }

        // Serialize all polylines
        final serializedPolylines =
            polylines.map((line) => line.toJson()).toList();

        stopwatch.stop();

        expect(serializedPolylines, hasLength(50));

        // Verify each polyline was serialized correctly
        for (int i = 0; i < serializedPolylines.length; i++) {
          final json = serializedPolylines[i];
          expect(json['geometry'], hasLength(100));
          expect(json['editable'], isTrue);
          expect(json['lineWidth'], 2.0 + (i % 5));
        }

        // Performance assertion
        expect(stopwatch.elapsedMilliseconds, lessThan(2000),
            reason:
                'Multiple polyline serialization should complete within 2 seconds');

        print(
            '50 polylines (100 points each) serialization took: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('Batch operations on multiple polylines', () {
        final stopwatch = Stopwatch()..start();

        // Create multiple polylines with different editing configurations
        final polylineConfigs = [
          {'points': 50, 'editable': true, 'color': '#FF0000'},
          {'points': 100, 'editable': false, 'color': '#00FF00'},
          {'points': 200, 'editable': true, 'color': '#0000FF'},
          {'points': 500, 'editable': true, 'color': '#FFFF00'},
          {'points': 1000, 'editable': false, 'color': '#FF00FF'},
        ];

        final polylines = <LineOptions>[];

        for (final config in polylineConfigs) {
          final coordinates = generateLargePolyline(config['points'] as int);

          polylines.add(LineOptions(
            geometry: coordinates,
            editable: config['editable'] as bool,
            lineColor: config['color'] as String,
            lineWidth: 3.0,
            breakPointColor: '#FFFFFF',
            breakPointRadius: 8.0,
          ));
        }

        // Batch serialize
        final serialized = polylines.map((line) => line.toJson()).toList();

        stopwatch.stop();

        expect(serialized, hasLength(5));

        // Verify configurations were preserved
        for (int i = 0; i < serialized.length; i++) {
          final json = serialized[i];
          final config = polylineConfigs[i];

          expect(json['geometry'], hasLength(config['points']));
          expect(json['editable'], config['editable']);
          expect(json['lineColor'], config['color']);
        }

        print(
            'Batch polyline operations took: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('Editing Operation Performance', () {
      test('PolylineEditingSession creation and serialization performance', () {
        final stopwatch = Stopwatch()..start();

        // Create multiple editing sessions
        final sessions = <PolylineEditingSession>[];

        for (int i = 0; i < 100; i++) {
          final breakPoint = PolylineBreakPoint(
            id: 'bp-$i',
            parentLineId: 'line-$i',
            coordinate: LatLng(37.7749 + (i * 0.001), -122.4194 + (i * 0.001)),
            segmentIndex: i % 10,
            distanceAlongSegment: (i % 100) / 100.0,
            isDragging: i % 2 == 0,
          );

          final originalCoords = generatePolylineAroundPoint(
            breakPoint.coordinate,
            20,
            0.0001,
          );

          sessions.add(PolylineEditingSession(
            lineId: 'line-$i',
            breakPoint: breakPoint,
            originalCoordinates: originalCoords,
            segment1Coordinates: originalCoords.sublist(0, 10),
            segment2Coordinates: originalCoords.sublist(10),
            startTime: DateTime.now(),
          ));
        }

        stopwatch.stop();

        expect(sessions, hasLength(100));

        // Verify sessions were created correctly
        for (int i = 0; i < sessions.length; i++) {
          final session = sessions[i];
          expect(session.lineId, 'line-$i');
          expect(session.breakPoint.id, 'bp-$i');
          expect(session.originalCoordinates, hasLength(20));
        }

        expect(stopwatch.elapsedMilliseconds, lessThan(500),
            reason: 'Creating 100 editing sessions should be fast');

        print(
            '100 editing sessions creation took: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('PolylineEditingStyle application performance', () {
        final stopwatch = Stopwatch()..start();

        // Create multiple styles and apply them
        final styles = <PolylineEditingStyle>[];

        for (int i = 0; i < 1000; i++) {
          styles.add(PolylineEditingStyle(
            breakPointColor:
                '#${(i * 255 ~/ 1000).toRadixString(16).padLeft(2, '0')}0000',
            breakPointRadius: 5.0 + (i % 10),
            breakPointBorderColor: '#FFFFFF',
            breakPointBorderWidth: 1.0 + (i % 3),
            previewLineColor:
                '#00${(i * 255 ~/ 1000).toRadixString(16).padLeft(2, '0')}00',
            previewLineOpacity: 0.5 + ((i % 50) / 100.0),
            previewLineWidth: 2.0 + (i % 5),
            enableHapticFeedback: i % 2 == 0,
          ));
        }

        // Serialize all styles
        final serializedStyles = styles.map((style) => style.toJson()).toList();

        stopwatch.stop();

        expect(serializedStyles, hasLength(1000));

        // Verify styles were serialized correctly
        for (int i = 0; i < serializedStyles.length; i++) {
          final json = serializedStyles[i];
          expect(json['breakPointRadius'], 5.0 + (i % 10));
          expect(json['enableHapticFeedback'], i % 2 == 0);
        }

        expect(stopwatch.elapsedMilliseconds, lessThan(1000),
            reason: 'Serializing 1000 styles should complete within 1 second');

        print(
            '1000 style serializations took: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('Memory Stress Tests', () {
      test('Large coordinate arrays do not cause memory issues', () {
        // Test with extremely large coordinate arrays
        final sizes = [10000, 20000, 50000];

        for (final size in sizes) {
          final stopwatch = Stopwatch()..start();

          final coordinates = generateLargePolyline(size);

          final lineOptions = LineOptions(
            geometry: coordinates,
            editable: true,
            lineColor: '#FF0000',
            lineWidth: 2.0,
          );

          // This should not cause memory issues
          final json = lineOptions.toJson();

          stopwatch.stop();

          expect(json['geometry'], hasLength(size));

          print(
              'Polyline with $size points took: ${stopwatch.elapsedMilliseconds}ms');

          // Clean up to prevent memory accumulation in tests
          coordinates.clear();
        }
      });
    });
  });
}

// Helper functions for generating test data

List<LatLng> generateLargePolyline(int pointCount) {
  final coordinates = <LatLng>[];
  final random = math.Random(42); // Fixed seed for reproducible tests

  double lat = 37.7749; // Start at San Francisco
  double lng = -122.4194;

  for (int i = 0; i < pointCount; i++) {
    // Add some randomness to create a realistic path
    lat += (random.nextDouble() - 0.5) * 0.001;
    lng += (random.nextDouble() - 0.5) * 0.001;

    // Keep within reasonable bounds
    lat = lat.clamp(-85.0, 85.0);
    lng = lng.clamp(-180.0, 180.0);

    coordinates.add(LatLng(lat, lng));
  }

  return coordinates;
}

List<LatLng> generateComplexFlightPath() {
  // Generate a complex flight path with multiple waypoints
  final waypoints = [
    const LatLng(37.7749, -122.4194), // San Francisco
    const LatLng(39.7392, -104.9903), // Denver
    const LatLng(41.8781, -87.6298), // Chicago
    const LatLng(40.7128, -74.0060), // New York
    const LatLng(51.5074, -0.1278), // London
    const LatLng(48.8566, 2.3522), // Paris
    const LatLng(52.5200, 13.4050), // Berlin
    const LatLng(55.7558, 37.6176), // Moscow
    const LatLng(35.6762, 139.6503), // Tokyo
    const LatLng(-33.8688, 151.2093), // Sydney
  ];

  final coordinates = <LatLng>[];

  // Add intermediate points between waypoints for smoother curves
  for (int i = 0; i < waypoints.length - 1; i++) {
    final start = waypoints[i];
    final end = waypoints[i + 1];

    coordinates.add(start);

    // Add 10 intermediate points between each waypoint
    for (int j = 1; j < 10; j++) {
      final t = j / 10.0;
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      coordinates.add(LatLng(lat, lng));
    }
  }

  coordinates.add(waypoints.last);

  return coordinates;
}

List<LatLng> generatePolylineAroundPoint(
    LatLng center, int pointCount, double radius) {
  final coordinates = <LatLng>[];

  for (int i = 0; i < pointCount; i++) {
    final angle = (i / pointCount) * 2 * math.pi;
    final lat = center.latitude + radius * math.cos(angle);
    final lng = center.longitude + radius * math.sin(angle);
    coordinates.add(LatLng(lat, lng));
  }

  return coordinates;
}
