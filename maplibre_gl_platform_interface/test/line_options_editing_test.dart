import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';

void main() {
  group('LineOptions Editing Properties', () {
    test('should create LineOptions with editing properties', () {
      final callbacks = PolylineEditingCallbacks(
        onPolylineBroken: (lineId, segment1, segment2) {},
        onPolylineModified: (lineId, coordinates) {},
        onEditingError: (lineId, error) {},
      );

      final lineOptions = LineOptions(
        geometry: [
          const LatLng(37.7749, -122.4194),
          const LatLng(40.7128, -74.0060),
        ],
        lineColor: '#FF0000',
        lineWidth: 4.0,
        editable: true,
        editingCallbacks: callbacks,
        breakPointColor: '#00FF00',
        breakPointRadius: 10.0,
        previewLineColor: '#0000FF',
        previewLineOpacity: 0.8,
      );

      expect(lineOptions.editable, isTrue);
      expect(lineOptions.editingCallbacks, equals(callbacks));
      expect(lineOptions.breakPointColor, equals('#00FF00'));
      expect(lineOptions.breakPointRadius, equals(10.0));
      expect(lineOptions.previewLineColor, equals('#0000FF'));
      expect(lineOptions.previewLineOpacity, equals(0.8));
    });

    test('should serialize LineOptions with editing properties to JSON', () {
      final lineOptions = LineOptions(
        geometry: [
          const LatLng(37.7749, -122.4194),
          const LatLng(40.7128, -74.0060),
        ],
        lineColor: '#FF0000',
        lineWidth: 4.0,
        editable: true,
        breakPointColor: '#00FF00',
        breakPointRadius: 10.0,
        previewLineColor: '#0000FF',
        previewLineOpacity: 0.8,
      );

      final json = lineOptions.toJson();

      expect(json['lineColor'], equals('#FF0000'));
      expect(json['lineWidth'], equals(4.0));
      expect(json['editable'], isTrue);
      expect(json['breakPointColor'], equals('#00FF00'));
      expect(json['breakPointRadius'], equals(10.0));
      expect(json['previewLineColor'], equals('#0000FF'));
      expect(json['previewLineOpacity'], equals(0.8));
      expect(json['geometry'], hasLength(2));
      
      // Verify editingCallbacks are not serialized (as they contain function references)
      expect(json.containsKey('editingCallbacks'), isFalse);
    });

    test('should copy LineOptions with editing properties', () {
      final originalCallbacks = PolylineEditingCallbacks(
        onPolylineBroken: (lineId, segment1, segment2) {},
      );

      final original = LineOptions(
        lineColor: '#FF0000',
        editable: true,
        editingCallbacks: originalCallbacks,
        breakPointColor: '#00FF00',
      );

      final newCallbacks = PolylineEditingCallbacks(
        onPolylineModified: (lineId, coordinates) {},
      );

      final copied = original.copyWith(LineOptions(
        lineColor: '#0000FF',
        editingCallbacks: newCallbacks,
        breakPointRadius: 12.0,
      ));

      expect(copied.lineColor, equals('#0000FF'));
      expect(copied.editable, isTrue); // Inherited from original
      expect(copied.editingCallbacks, equals(newCallbacks));
      expect(copied.breakPointColor, equals('#00FF00')); // Inherited from original
      expect(copied.breakPointRadius, equals(12.0)); // New value
    });

    test('should handle null editing properties gracefully', () {
      final lineOptions = LineOptions(
        geometry: [
          const LatLng(37.7749, -122.4194),
          const LatLng(40.7128, -74.0060),
        ],
        lineColor: '#FF0000', 
        // All editing properties are null by default
      );

      expect(lineOptions.editable, isNull);
      expect(lineOptions.editingCallbacks, isNull);
      expect(lineOptions.breakPointColor, isNull);
      expect(lineOptions.breakPointRadius, isNull);
      expect(lineOptions.previewLineColor, isNull);
      expect(lineOptions.previewLineOpacity, isNull);

      // Should still serialize normally
      final json = lineOptions.toJson();
      expect(json['lineColor'], equals('#FF0000'));
      expect(json.containsKey('editable'), isFalse);
      expect(json.containsKey('breakPointColor'), isFalse);
    });
  });
}