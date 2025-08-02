// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';

void main() {
  group('PolylineBreakPoint', () {
    test('should create break point with required properties', () {
      const breakPoint = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
      );

      expect(breakPoint.id, equals('bp1'));
      expect(breakPoint.parentLineId, equals('line1'));
      expect(breakPoint.coordinate, equals(const LatLng(37.7749, -122.4194)));
      expect(breakPoint.segmentIndex, equals(2));
      expect(breakPoint.distanceAlongSegment, equals(0.5));
      expect(breakPoint.isDragging, isFalse);
    });

    test('should create break point with dragging state', () {
      const breakPoint = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
        isDragging: true,
      );

      expect(breakPoint.isDragging, isTrue);
    });

    test('should copy with new values', () {
      const original = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
      );

      final copied = original.copyWith(
        isDragging: true,
        coordinate: const LatLng(40.7128, -74.0060),
      );

      expect(copied.id, equals('bp1'));
      expect(copied.parentLineId, equals('line1'));
      expect(copied.coordinate, equals(const LatLng(40.7128, -74.0060)));
      expect(copied.segmentIndex, equals(2));
      expect(copied.distanceAlongSegment, equals(0.5));
      expect(copied.isDragging, isTrue);
    });

    test('should serialize to and from JSON', () {
      const original = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
        isDragging: true,
      );

      final json = original.toJson();
      final restored = PolylineBreakPoint.fromJson(json);

      expect(restored, equals(original));
    });

    test('should have proper equality and hashCode', () {
      const bp1 = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
      );

      const bp2 = PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
      );

      const bp3 = PolylineBreakPoint(
        id: 'bp2',
        parentLineId: 'line1',
        coordinate: LatLng(37.7749, -122.4194),
        segmentIndex: 2,
        distanceAlongSegment: 0.5,
      );

      expect(bp1, equals(bp2));
      expect(bp1.hashCode, equals(bp2.hashCode));
      expect(bp1, isNot(equals(bp3)));
    });
  });

  group('PolylineEditingSession', () {
    late DateTime testTime;
    late List<LatLng> originalCoords;
    late List<LatLng> segment1Coords;
    late List<LatLng> segment2Coords;
    late PolylineBreakPoint breakPoint;

    setUp(() {
      testTime = DateTime(2023, 1, 1, 12, 0, 0);
      originalCoords = const [
        LatLng(37.7749, -122.4194),
        LatLng(37.7849, -122.4094),
        LatLng(37.7949, -122.3994),
      ];
      segment1Coords = const [
        LatLng(37.7749, -122.4194),
        LatLng(37.7799, -122.4144),
      ];
      segment2Coords = const [
        LatLng(37.7799, -122.4144),
        LatLng(37.7849, -122.4094),
        LatLng(37.7949, -122.3994),
      ];
      breakPoint = const PolylineBreakPoint(
        id: 'bp1',
        parentLineId: 'line1',
        coordinate: LatLng(37.7799, -122.4144),
        segmentIndex: 0,
        distanceAlongSegment: 0.5,
      );
    });

    test('should create editing session with all properties', () {
      final session = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: testTime,
      );

      expect(session.lineId, equals('line1'));
      expect(session.breakPoint, equals(breakPoint));
      expect(session.originalCoordinates, equals(originalCoords));
      expect(session.segment1Coordinates, equals(segment1Coords));
      expect(session.segment2Coordinates, equals(segment2Coords));
      expect(session.startTime, equals(testTime));
    });

    test('should calculate duration correctly', () {
      final session = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: DateTime.now().subtract(const Duration(seconds: 5)),
      );

      expect(session.duration.inSeconds, greaterThanOrEqualTo(4));
      expect(session.duration.inSeconds, lessThanOrEqualTo(6));
    });

    test('should copy with new values', () {
      final original = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: testTime,
      );

      final newBreakPoint = breakPoint.copyWith(isDragging: true);
      final copied = original.copyWith(breakPoint: newBreakPoint);

      expect(copied.lineId, equals('line1'));
      expect(copied.breakPoint.isDragging, isTrue);
      expect(copied.originalCoordinates, equals(originalCoords));
    });

    test('should serialize to and from JSON', () {
      final original = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: testTime,
      );

      final json = original.toJson();
      final restored = PolylineEditingSession.fromJson(json);

      expect(restored, equals(original));
    });

    test('should have proper equality', () {
      final session1 = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: testTime,
      );

      final session2 = PolylineEditingSession(
        lineId: 'line1',
        breakPoint: breakPoint,
        originalCoordinates: originalCoords,
        segment1Coordinates: segment1Coords,
        segment2Coordinates: segment2Coords,
        startTime: testTime,
      );

      expect(session1, equals(session2));
      expect(session1.hashCode, equals(session2.hashCode));
    });
  });

  group('PolylineEditingStyle', () {
    test('should create style with default values', () {
      const style = PolylineEditingStyle();

      expect(style.breakPointColor, equals('#FF0000'));
      expect(style.breakPointRadius, equals(8.0));
      expect(style.breakPointBorderColor, equals('#FFFFFF'));
      expect(style.breakPointBorderWidth, equals(2.0));
      expect(style.previewLineColor, equals('#00FF00'));
      expect(style.previewLineOpacity, equals(0.7));
      expect(style.previewLineWidth, equals(3.0));
      expect(style.enableHapticFeedback, isTrue);
    });

    test('should create style with custom values', () {
      const style = PolylineEditingStyle(
        breakPointColor: '#0000FF',
        breakPointRadius: 10.0,
        previewLineOpacity: 0.5,
        enableHapticFeedback: false,
      );

      expect(style.breakPointColor, equals('#0000FF'));
      expect(style.breakPointRadius, equals(10.0));
      expect(style.previewLineOpacity, equals(0.5));
      expect(style.enableHapticFeedback, isFalse);
      // Default values should still be present
      expect(style.breakPointBorderColor, equals('#FFFFFF'));
    });

    test('should copy with new values', () {
      const original = PolylineEditingStyle();
      final copied = original.copyWith(
        breakPointColor: '#0000FF',
        enableHapticFeedback: false,
      );

      expect(copied.breakPointColor, equals('#0000FF'));
      expect(copied.enableHapticFeedback, isFalse);
      expect(copied.breakPointRadius, equals(8.0)); // unchanged
    });

    test('should serialize to and from JSON', () {
      const original = PolylineEditingStyle(
        breakPointColor: '#0000FF',
        previewLineOpacity: 0.5,
      );

      final json = original.toJson();
      final restored = PolylineEditingStyle.fromJson(json);

      expect(restored, equals(original));
    });

    test('should handle missing JSON fields with defaults', () {
      final json = <String, dynamic>{
        'breakPointColor': '#0000FF',
        // Missing other fields should use defaults
      };

      final style = PolylineEditingStyle.fromJson(json);

      expect(style.breakPointColor, equals('#0000FF'));
      expect(style.breakPointRadius, equals(8.0)); // default
      expect(style.enableHapticFeedback, isTrue); // default
    });

    test('should have proper equality and hashCode', () {
      const style1 = PolylineEditingStyle(breakPointColor: '#0000FF');
      const style2 = PolylineEditingStyle(breakPointColor: '#0000FF');
      const style3 = PolylineEditingStyle(breakPointColor: '#FF0000');

      expect(style1, equals(style2));
      expect(style1.hashCode, equals(style2.hashCode));
      expect(style1, isNot(equals(style3)));
    });
  });

  group('PolylineEditingError', () {
    test('should create error with required properties', () {
      const error = PolylineEditingError(
        type: PolylineEditingErrorType.geometricCalculation,
        message: 'Failed to calculate intersection',
      );

      expect(error.type, equals(PolylineEditingErrorType.geometricCalculation));
      expect(error.message, equals('Failed to calculate intersection'));
      expect(error.lineId, isNull);
      expect(error.details, isNull);
    });

    test('should create error with all properties', () {
      const error = PolylineEditingError(
        type: PolylineEditingErrorType.platformIntegration,
        message: 'Native SDK error',
        lineId: 'line1',
        details: {'code': 500, 'platform': 'android'},
      );

      expect(error.type, equals(PolylineEditingErrorType.platformIntegration));
      expect(error.message, equals('Native SDK error'));
      expect(error.lineId, equals('line1'));
      expect(error.details, equals({'code': 500, 'platform': 'android'}));
    });

    test('should copy with new values', () {
      const original = PolylineEditingError(
        type: PolylineEditingErrorType.geometricCalculation,
        message: 'Original message',
      );

      final copied = original.copyWith(
        message: 'Updated message',
        lineId: 'line1',
      );

      expect(
          copied.type, equals(PolylineEditingErrorType.geometricCalculation));
      expect(copied.message, equals('Updated message'));
      expect(copied.lineId, equals('line1'));
    });

    test('should serialize to and from JSON', () {
      const original = PolylineEditingError(
        type: PolylineEditingErrorType.performance,
        message: 'Too many points',
        lineId: 'line1',
        details: {'pointCount': 10000},
      );

      final json = original.toJson();
      final restored = PolylineEditingError.fromJson(json);

      expect(restored, equals(original));
    });

    test('should handle unknown error type in JSON', () {
      final json = {
        'type': 'unknownErrorType',
        'message': 'Some error',
      };

      final error = PolylineEditingError.fromJson(json);

      expect(error.type, equals(PolylineEditingErrorType.unknown));
      expect(error.message, equals('Some error'));
    });

    test('should have proper equality and hashCode', () {
      const error1 = PolylineEditingError(
        type: PolylineEditingErrorType.invalidInput,
        message: 'Invalid coordinates',
        lineId: 'line1',
      );

      const error2 = PolylineEditingError(
        type: PolylineEditingErrorType.invalidInput,
        message: 'Invalid coordinates',
        lineId: 'line1',
      );

      const error3 = PolylineEditingError(
        type: PolylineEditingErrorType.invalidInput,
        message: 'Different message',
        lineId: 'line1',
      );

      expect(error1, equals(error2));
      expect(error1.hashCode, equals(error2.hashCode));
      expect(error1, isNot(equals(error3)));
    });
  });

  group('PolylineEditingErrorType', () {
    test('should have all expected error types', () {
      expect(PolylineEditingErrorType.values,
          contains(PolylineEditingErrorType.geometricCalculation));
      expect(PolylineEditingErrorType.values,
          contains(PolylineEditingErrorType.platformIntegration));
      expect(PolylineEditingErrorType.values,
          contains(PolylineEditingErrorType.performance));
      expect(PolylineEditingErrorType.values,
          contains(PolylineEditingErrorType.invalidInput));
      expect(PolylineEditingErrorType.values,
          contains(PolylineEditingErrorType.unknown));
    });

    test('should have proper string representation', () {
      expect(PolylineEditingErrorType.geometricCalculation.name,
          equals('geometricCalculation'));
      expect(PolylineEditingErrorType.platformIntegration.name,
          equals('platformIntegration'));
      expect(PolylineEditingErrorType.performance.name, equals('performance'));
      expect(
          PolylineEditingErrorType.invalidInput.name, equals('invalidInput'));
      expect(PolylineEditingErrorType.unknown.name, equals('unknown'));
    });
  });
}
