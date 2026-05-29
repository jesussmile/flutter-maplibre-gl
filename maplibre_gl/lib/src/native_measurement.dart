part of '../maplibre_gl.dart';

class NativeMeasurementData {
  const NativeMeasurementData({
    required this.screenPoint1,
    required this.screenPoint2,
    required this.latLng1,
    required this.latLng2,
    required this.distanceNauticalMiles,
    required this.bearingDegrees,
    required this.durationMs,
  });

  final Point<double> screenPoint1;
  final Point<double> screenPoint2;
  final LatLng latLng1;
  final LatLng latLng2;
  final double distanceNauticalMiles;
  final double bearingDegrees;
  final int durationMs;

  factory NativeMeasurementData.fromMap(Map<String, dynamic> map) {
    return NativeMeasurementData(
      screenPoint1: Point<double>(
        (map['x1'] as num).toDouble(),
        (map['y1'] as num).toDouble(),
      ),
      screenPoint2: Point<double>(
        (map['x2'] as num).toDouble(),
        (map['y2'] as num).toDouble(),
      ),
      latLng1: LatLng(
        (map['lat1'] as num).toDouble(),
        (map['lng1'] as num).toDouble(),
      ),
      latLng2: LatLng(
        (map['lat2'] as num).toDouble(),
        (map['lng2'] as num).toDouble(),
      ),
      distanceNauticalMiles: (map['distance'] as num).toDouble(),
      bearingDegrees: (map['bearing'] as num).toDouble(),
      durationMs: (map['duration'] as num).toInt(),
    );
  }
}

typedef OnNativeMeasurementStartCallback = void Function(
  NativeMeasurementData data,
);
typedef OnNativeMeasurementUpdateCallback = void Function(
  NativeMeasurementData data,
);
typedef OnNativeMeasurementEndCallback = void Function(
  NativeMeasurementData data,
);

extension NativeMeasurement on MapLibreMapController {
  Future<void> enableNativeMeasurement(bool enabled) {
    return _maplibrePlatform.enableNativeMeasurement(enabled);
  }

  Future<void> setNativeMeasurementStyle({
    String lineColor = '#00BFFF',
    double lineWidth = 4.0,
    double lineOpacity = 0.9,
    String endpointColor = '#00BFFF',
    double endpointRadius = 0.0,
  }) {
    return _maplibrePlatform.setNativeMeasurementStyle(
      lineColor: lineColor,
      lineWidth: lineWidth,
      lineOpacity: lineOpacity,
      endpointColor: endpointColor,
      endpointRadius: endpointRadius,
    );
  }

  Future<void> clearNativeMeasurement() {
    return _maplibrePlatform.clearNativeMeasurement();
  }

  Future<void> ensureMeasurementLayersOnTop() {
    return _maplibrePlatform.ensureMeasurementLayersOnTop();
  }

  void setNativeMeasurementCallbacks({
    OnNativeMeasurementStartCallback? onStart,
    OnNativeMeasurementUpdateCallback? onUpdate,
    OnNativeMeasurementEndCallback? onEnd,
  }) {
    if (onStart != null) {
      _maplibrePlatform.onNativeMeasurementStart.add((data) {
        onStart(NativeMeasurementData.fromMap(data));
      });
    }
    if (onUpdate != null) {
      _maplibrePlatform.onNativeMeasurementUpdate.add((data) {
        onUpdate(NativeMeasurementData.fromMap(data));
      });
    }
    if (onEnd != null) {
      _maplibrePlatform.onNativeMeasurementEnd.add((data) {
        onEnd(NativeMeasurementData.fromMap(data));
      });
    }
  }
}
