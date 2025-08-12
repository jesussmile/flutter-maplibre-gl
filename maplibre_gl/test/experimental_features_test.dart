import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  group('MapLibreExperimentalFeatures', () {
    test('should create default configuration with all features disabled', () {
      const features = MapLibreExperimentalFeatures.none;
      expect(features.enableNativeTriangleLayers, false);
    });

    test('should create triangle configuration with triangle layers enabled', () {
      const features = MapLibreExperimentalFeatures.triangles;
      expect(features.enableNativeTriangleLayers, true);
    });

    test('should create custom configuration', () {
      const features = MapLibreExperimentalFeatures(
        enableNativeTriangleLayers: true,
      );
      expect(features.enableNativeTriangleLayers, true);
    });

    test('should support copyWith', () {
      const original = MapLibreExperimentalFeatures.none;
      final updated = original.copyWith(enableNativeTriangleLayers: true);
      
      expect(original.enableNativeTriangleLayers, false);
      expect(updated.enableNativeTriangleLayers, true);
    });

    test('should support equality', () {
      const features1 = MapLibreExperimentalFeatures.none;
      const features2 = MapLibreExperimentalFeatures.none;
      const features3 = MapLibreExperimentalFeatures.triangles;
      
      expect(features1, equals(features2));
      expect(features1, isNot(equals(features3)));
    });

    test('should support hashCode', () {
      const features1 = MapLibreExperimentalFeatures.none;
      const features2 = MapLibreExperimentalFeatures.none;
      const features3 = MapLibreExperimentalFeatures.triangles;
      
      expect(features1.hashCode, equals(features2.hashCode));
      expect(features1.hashCode, isNot(equals(features3.hashCode)));
    });

    test('should have meaningful toString', () {
      const features = MapLibreExperimentalFeatures.triangles;
      final string = features.toString();
      
      expect(string, contains('MapLibreExperimentalFeatures'));
      expect(string, contains('enableNativeTriangleLayers'));
      expect(string, contains('true'));
    });
  });

  group('ExperimentalFeatureException', () {
    test('should create exception with feature and instruction', () {
      const exception = ExperimentalFeatureException(
        'Native triangle layers',
        'Enable by setting experimentalFeatures: MapLibreExperimentalFeatures.triangles',
      );
      
      expect(exception.feature, 'Native triangle layers');
      expect(exception.enableInstruction, 'Enable by setting experimentalFeatures: MapLibreExperimentalFeatures.triangles');
    });

    test('should have meaningful toString', () {
      const exception = ExperimentalFeatureException(
        'Feature',
        'Enable instruction',
      );
      final string = exception.toString();
      
      expect(string, contains('ExperimentalFeatureException'));
      expect(string, contains('Feature is not enabled'));
      expect(string, contains('Enable instruction'));
    });
  });
}
