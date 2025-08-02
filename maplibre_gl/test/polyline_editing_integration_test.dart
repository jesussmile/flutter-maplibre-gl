import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';

void main() {
  group('Polyline Editing Integration Tests', () {
    test('PolylineEditingStyle creates correct JSON', () {
      final style = PolylineEditingStyle(
        breakPointColor: '#FF0000',
        breakPointRadius: 10.0,
        previewLineColor: '#00FF00',
        previewLineOpacity: 0.8,
      );

      final json = style.toJson();

      expect(json['breakPointColor'], '#FF0000');
      expect(json['breakPointRadius'], 10.0);
      expect(json['previewLineColor'], '#00FF00');
      expect(json['previewLineOpacity'], 0.8);
    });

    test('PolylineEditingCallbacks can be created', () {
      bool brokenCalled = false;
      bool modifiedCalled = false;
      bool errorCalled = false;

      final callbacks = PolylineEditingCallbacks(
        onPolylineBroken: (lineId, segment1, segment2) {
          brokenCalled = true;
        },
        onPolylineModified: (lineId, coordinates) {
          modifiedCalled = true;
        },
        onEditingError: (lineId, error) {
          errorCalled = true;
        },
      );

      expect(callbacks.onPolylineBroken, isNotNull);
      expect(callbacks.onPolylineModified, isNotNull);
      expect(callbacks.onEditingError, isNotNull);

      // Test callback execution
      callbacks.onPolylineBroken?.call('test', [], []);
      callbacks.onPolylineModified?.call('test', []);
      callbacks.onEditingError?.call('test', 'error');

      expect(brokenCalled, isTrue);
      expect(modifiedCalled, isTrue);
      expect(errorCalled, isTrue);
    });

    test('PolylineBreakPoint can be created and serialized', () {
      final breakPoint = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: const LatLng(1.0, 2.0),
        segmentIndex: 0,
        distanceAlongSegment: 0.5,
        isDragging: false,
      );

      expect(breakPoint.id, 'bp1');
      expect(breakPoint.parentLineId, 'line1');
      expect(breakPoint.coordinate.latitude, 1.0);
      expect(breakPoint.coordinate.longitude, 2.0);
      expect(breakPoint.segmentIndex, 0);
      expect(breakPoint.distanceAlongSegment, 0.5);
      expect(breakPoint.isDragging, false);

      final json = breakPoint.toJson();
      expect(json['id'], 'bp1');
      expect(json['parentLineId'], 'line1');
      expect(json['segmentIndex'], 0);
    });

    test('PolylineEditingSession can be created', () {
      final breakPoint = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: const LatLng(0.5, 0.5),
        segmentIndex: 0,
        distanceAlongSegment: 0.5,
        isDragging: false,
      );

      final session = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: [const LatLng(0.0, 0.0), const LatLng(1.0, 1.0)],
        segment1Coordinates: [const LatLng(0.0, 0.0), const LatLng(0.5, 0.5)],
        segment2Coordinates: [const LatLng(0.5, 0.5), const LatLng(1.0, 1.0)],
        startTime: DateTime.now(),
      );

      expect(session.lineId, 'line1');
      expect(session.breakPoint.id, 'bp1');
      expect(session.originalCoordinates.length, 2);
      expect(session.segment1Coordinates.length, 2);
      expect(session.segment2Coordinates.length, 2);
    });
  });
}
