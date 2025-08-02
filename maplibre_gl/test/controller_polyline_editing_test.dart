// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';

void main() {
  group('MapLibreMapController Polyline Editing', () {
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
      });

      test('should serialize to JSON correctly', () {
        const style = PolylineEditingStyle(
          breakPointColor: '#0000FF',
          breakPointRadius: 10.0,
        );

        final json = style.toJson();

        expect(json['breakPointColor'], equals('#0000FF'));
        expect(json['breakPointRadius'], equals(10.0));
        expect(json['enableHapticFeedback'], isTrue);
      });
    });

    group('LineOptions editing extensions', () {
      test('should create LineOptions with editing properties', () {
        const options = LineOptions(
          editable: true,
          breakPointColor: '#FF0000',
          breakPointRadius: 8.0,
          previewLineColor: '#00FF00',
          previewLineOpacity: 0.8,
        );

        expect(options.editable, isTrue);
        expect(options.breakPointColor, equals('#FF0000'));
        expect(options.breakPointRadius, equals(8.0));
        expect(options.previewLineColor, equals('#00FF00'));
        expect(options.previewLineOpacity, equals(0.8));
      });

      test('should serialize editing properties to JSON', () {
        const options = LineOptions(
          editable: true,
          breakPointColor: '#FF0000',
          breakPointRadius: 8.0,
        );

        final json = options.toJson();

        expect(json['editable'], isTrue);
        expect(json['breakPointColor'], equals('#FF0000'));
        expect(json['breakPointRadius'], equals(8.0));
      });

      test('should copy with editing properties', () {
        const original = LineOptions(
          lineColor: '#000000',
          editable: false,
        );

        const changes = LineOptions(
          editable: true,
          breakPointColor: '#FF0000',
        );

        final newOptions = original.copyWith(changes);

        expect(newOptions.lineColor, equals('#000000'));
        expect(newOptions.editable, isTrue);
        expect(newOptions.breakPointColor, equals('#FF0000'));
      });
    });

    group('PolylineEditingCallbacks', () {
      test('should create callbacks with provided values', () {
        void onBroken(
            String lineId, List<LatLng> segment1, List<LatLng> segment2) {}
        void onModified(String lineId, List<LatLng> coordinates) {}
        void onError(String lineId, String error) {}

        final callbacks = PolylineEditingCallbacks(
          onPolylineBroken: onBroken,
          onPolylineModified: onModified,
          onEditingError: onError,
        );

        expect(callbacks.onPolylineBroken, equals(onBroken));
        expect(callbacks.onPolylineModified, equals(onModified));
        expect(callbacks.onEditingError, equals(onError));
      });

      test('should copy with new values', () {
        void onBroken(
            String lineId, List<LatLng> segment1, List<LatLng> segment2) {}
        void onModified(String lineId, List<LatLng> coordinates) {}
        void onError(String lineId, String error) {}
        void newOnError(String lineId, String error) {}

        final callbacks = PolylineEditingCallbacks(
          onPolylineBroken: onBroken,
          onPolylineModified: onModified,
          onEditingError: onError,
        );

        final newCallbacks = callbacks.copyWith(onEditingError: newOnError);

        expect(newCallbacks.onPolylineBroken, equals(onBroken));
        expect(newCallbacks.onPolylineModified, equals(onModified));
        expect(newCallbacks.onEditingError, equals(newOnError));
      });
    });
  });
}
