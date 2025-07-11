// Native MapLibre Measurement Tool Extension
// This extends the existing two-finger hold gesture to include measurement functionality

part of maplibre_gl;

/// Native measurement data from the platform
class NativeMeasurementData {
  final Point<double> screenPoint1;
  final Point<double> screenPoint2;
  final LatLng latLng1;
  final LatLng latLng2;
  final double distanceNauticalMiles;
  final double bearingDegrees;
  final int durationMs;

  const NativeMeasurementData({
    required this.screenPoint1,
    required this.screenPoint2,
    required this.latLng1,
    required this.latLng2,
    required this.distanceNauticalMiles,
    required this.bearingDegrees,
    required this.durationMs,
  });

  factory NativeMeasurementData.fromMap(Map<String, dynamic> map) {
    return NativeMeasurementData(
      screenPoint1: Point<double>(map['x1'] as double, map['y1'] as double),
      screenPoint2: Point<double>(map['x2'] as double, map['y2'] as double),
      latLng1: LatLng(map['lat1'] as double, map['lng1'] as double),
      latLng2: LatLng(map['lat2'] as double, map['lng2'] as double),
      distanceNauticalMiles: map['distance'] as double,
      bearingDegrees: map['bearing'] as double,
      durationMs: map['duration'] as int,
    );
  }
}

/// Callbacks for native measurement events
typedef OnNativeMeasurementStartCallback = void Function(NativeMeasurementData data);
typedef OnNativeMeasurementUpdateCallback = void Function(NativeMeasurementData data);
typedef OnNativeMeasurementEndCallback = void Function(NativeMeasurementData data);

/// Extensions to MapLibreMapController for native measurement
extension NativeMeasurement on MapLibreMapController {
  
  /// Enable or disable native two-finger measurement detection
  Future<void> enableNativeMeasurement(bool enabled) async {
    return _maplibrePlatform.enableNativeMeasurement(enabled);
  }
  
  /// Set measurement callbacks for native events
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
  
  /// Set measurement line style for native rendering
  Future<void> setNativeMeasurementStyle({
    String lineColor = "#FF6B35", // Orange color
    double lineWidth = 3.0,
    double lineOpacity = 0.8,
    String endpointColor = "#FFFFFF", // White endpoints
    double endpointRadius = 8.0,
  }) async {
    return _maplibrePlatform.setNativeMeasurementStyle(
      lineColor: lineColor,
      lineWidth: lineWidth,
      lineOpacity: lineOpacity,
      endpointColor: endpointColor,
      endpointRadius: endpointRadius,
    );
  }
  
  /// Clear any active native measurements
  Future<void> clearNativeMeasurement() async {
    return _maplibrePlatform.clearNativeMeasurement();
  }
}
