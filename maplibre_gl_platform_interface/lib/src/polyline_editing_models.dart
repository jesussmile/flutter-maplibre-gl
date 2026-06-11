// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of '../maplibre_gl_platform_interface.dart';

/// Represents a break point on a polyline during editing.
///
/// A break point is created when a user long presses on a polyline and is used
/// to split the polyline into two segments that can be independently modified.
@immutable
class PolylineBreakPoint {
  /// Creates a polyline break point.
  const PolylineBreakPoint({
    required this.id,
    required this.parentLineId,
    required this.coordinate,
    required this.segmentIndex,
    required this.distanceAlongSegment,
    this.isDragging = false,
  });

  /// Unique identifier for this break point.
  final String id;

  /// ID of the parent polyline that this break point belongs to.
  final String parentLineId;

  /// Geographic coordinate of the break point.
  final LatLng coordinate;

  /// Index of the segment where this break point was created.
  ///
  /// This refers to the segment between two consecutive points in the
  /// original polyline geometry.
  final int segmentIndex;

  /// Distance along the segment where the break point was created.
  ///
  /// This is a normalized value between 0.0 and 1.0, where 0.0 represents
  /// the start of the segment and 1.0 represents the end.
  final double distanceAlongSegment;

  /// Whether this break point is currently being dragged by the user.
  final bool isDragging;

  /// Creates a copy of this break point with the given fields replaced.
  PolylineBreakPoint copyWith({
    String? id,
    String? parentLineId,
    LatLng? coordinate,
    int? segmentIndex,
    double? distanceAlongSegment,
    bool? isDragging,
  }) {
    return PolylineBreakPoint(
      id: id ?? this.id,
      parentLineId: parentLineId ?? this.parentLineId,
      coordinate: coordinate ?? this.coordinate,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      distanceAlongSegment: distanceAlongSegment ?? this.distanceAlongSegment,
      isDragging: isDragging ?? this.isDragging,
    );
  }

  /// Converts this break point to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentLineId': parentLineId,
      'coordinate': coordinate.toJson(),
      'segmentIndex': segmentIndex,
      'distanceAlongSegment': distanceAlongSegment,
      'isDragging': isDragging,
    };
  }

  /// Creates a break point from a JSON representation.
  factory PolylineBreakPoint.fromJson(Map<String, dynamic> json) {
    return PolylineBreakPoint(
      id: json['id'] as String,
      parentLineId: json['parentLineId'] as String,
      coordinate: LatLng._fromJson(json['coordinate']),
      segmentIndex: json['segmentIndex'] as int,
      distanceAlongSegment: json['distanceAlongSegment'] as double,
      isDragging: json['isDragging'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PolylineBreakPoint &&
        other.id == id &&
        other.parentLineId == parentLineId &&
        other.coordinate == coordinate &&
        other.segmentIndex == segmentIndex &&
        other.distanceAlongSegment == distanceAlongSegment &&
        other.isDragging == isDragging;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      parentLineId,
      coordinate,
      segmentIndex,
      distanceAlongSegment,
      isDragging,
    );
  }

  @override
  String toString() {
    return 'PolylineBreakPoint(id: $id, parentLineId: $parentLineId, '
        'coordinate: $coordinate, segmentIndex: $segmentIndex, '
        'distanceAlongSegment: $distanceAlongSegment, isDragging: $isDragging)';
  }
}

/// Tracks the state of an active polyline editing session.
///
/// An editing session is created when a user starts editing a polyline and
/// contains all the information needed to manage the editing operation.
@immutable
class PolylineEditingSession {
  /// Creates a polyline editing session.
  const PolylineEditingSession({
    required this.lineId,
    required this.breakPoint,
    required this.originalCoordinates,
    required this.segment1Coordinates,
    required this.segment2Coordinates,
    required this.startTime,
  });

  /// ID of the polyline being edited.
  final String lineId;

  /// The break point that was created for this editing session.
  final PolylineBreakPoint breakPoint;

  /// Original coordinates of the polyline before editing began.
  final List<LatLng> originalCoordinates;

  /// Coordinates of the first segment after breaking the polyline.
  final List<LatLng> segment1Coordinates;

  /// Coordinates of the second segment after breaking the polyline.
  final List<LatLng> segment2Coordinates;

  /// When this editing session started.
  final DateTime startTime;

  /// Duration of this editing session.
  Duration get duration => DateTime.now().difference(startTime);

  /// Creates a copy of this editing session with the given fields replaced.
  PolylineEditingSession copyWith({
    String? lineId,
    PolylineBreakPoint? breakPoint,
    List<LatLng>? originalCoordinates,
    List<LatLng>? segment1Coordinates,
    List<LatLng>? segment2Coordinates,
    DateTime? startTime,
  }) {
    return PolylineEditingSession(
      lineId: lineId ?? this.lineId,
      breakPoint: breakPoint ?? this.breakPoint,
      originalCoordinates: originalCoordinates ?? this.originalCoordinates,
      segment1Coordinates: segment1Coordinates ?? this.segment1Coordinates,
      segment2Coordinates: segment2Coordinates ?? this.segment2Coordinates,
      startTime: startTime ?? this.startTime,
    );
  }

  /// Converts this editing session to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'lineId': lineId,
      'breakPoint': breakPoint.toJson(),
      'originalCoordinates':
          originalCoordinates.map((c) => c.toJson()).toList(),
      'segment1Coordinates':
          segment1Coordinates.map((c) => c.toJson()).toList(),
      'segment2Coordinates':
          segment2Coordinates.map((c) => c.toJson()).toList(),
      'startTime': startTime.toIso8601String(),
    };
  }

  /// Creates an editing session from a JSON representation.
  factory PolylineEditingSession.fromJson(Map<String, dynamic> json) {
    return PolylineEditingSession(
      lineId: json['lineId'] as String,
      breakPoint: PolylineBreakPoint.fromJson(json['breakPoint']),
      originalCoordinates:
          (json['originalCoordinates'] as List)
              .map((c) => LatLng._fromJson(c))
              .cast<LatLng>()
              .toList(),
      segment1Coordinates:
          (json['segment1Coordinates'] as List)
              .map((c) => LatLng._fromJson(c))
              .cast<LatLng>()
              .toList(),
      segment2Coordinates:
          (json['segment2Coordinates'] as List)
              .map((c) => LatLng._fromJson(c))
              .cast<LatLng>()
              .toList(),
      startTime: DateTime.parse(json['startTime'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PolylineEditingSession &&
        other.lineId == lineId &&
        other.breakPoint == breakPoint &&
        _listEquals(other.originalCoordinates, originalCoordinates) &&
        _listEquals(other.segment1Coordinates, segment1Coordinates) &&
        _listEquals(other.segment2Coordinates, segment2Coordinates) &&
        other.startTime == startTime;
  }

  @override
  int get hashCode {
    return Object.hash(
      lineId,
      breakPoint,
      Object.hashAll(originalCoordinates),
      Object.hashAll(segment1Coordinates),
      Object.hashAll(segment2Coordinates),
      startTime,
    );
  }

  @override
  String toString() {
    return 'PolylineEditingSession(lineId: $lineId, breakPoint: $breakPoint, '
        'originalCoordinates: ${originalCoordinates.length} points, '
        'segment1Coordinates: ${segment1Coordinates.length} points, '
        'segment2Coordinates: ${segment2Coordinates.length} points, '
        'startTime: $startTime)';
  }

  /// Helper method to compare lists of LatLng objects.
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Configuration for visual appearance during polyline editing.
///
/// This class defines how editing elements like break points and preview lines
/// should be styled during interactive editing operations.
@immutable
class PolylineEditingStyle {
  /// Creates a polyline editing style configuration.
  const PolylineEditingStyle({
    this.breakPointColor = '#FF0000',
    this.breakPointRadius = 8.0,
    this.breakPointBorderColor = '#FFFFFF',
    this.breakPointBorderWidth = 2.0,
    this.previewLineColor = '#00FF00',
    this.previewLineOpacity = 0.7,
    this.previewLineWidth = 3.0,
    this.hitTestTolerance = 24.0,
    this.enableHapticFeedback = true,
  });

  /// Color of the break point marker.
  ///
  /// Should be a hex color string (e.g., "#FF0000" for red).
  final String breakPointColor;

  /// Radius of the break point marker in pixels.
  final double breakPointRadius;

  /// Color of the break point marker border.
  ///
  /// Should be a hex color string (e.g., "#FFFFFF" for white).
  final String breakPointBorderColor;

  /// Width of the break point marker border in pixels.
  final double breakPointBorderWidth;

  /// Color of the preview line shown during drag operations.
  ///
  /// Should be a hex color string (e.g., "#00FF00" for green).
  final String previewLineColor;

  /// Opacity of the preview line shown during drag operations.
  ///
  /// Should be a value between 0.0 (transparent) and 1.0 (opaque).
  final double previewLineOpacity;

  /// Width of the preview line in pixels.
  final double previewLineWidth;

  /// Logical-pixel radius used to select route segments and edit handles.
  final double hitTestTolerance;

  /// Whether to enable haptic feedback during editing operations.
  ///
  /// Only applies to platforms that support haptic feedback.
  final bool enableHapticFeedback;

  /// Creates a copy of this style with the given fields replaced.
  PolylineEditingStyle copyWith({
    String? breakPointColor,
    double? breakPointRadius,
    String? breakPointBorderColor,
    double? breakPointBorderWidth,
    String? previewLineColor,
    double? previewLineOpacity,
    double? previewLineWidth,
    double? hitTestTolerance,
    bool? enableHapticFeedback,
  }) {
    return PolylineEditingStyle(
      breakPointColor: breakPointColor ?? this.breakPointColor,
      breakPointRadius: breakPointRadius ?? this.breakPointRadius,
      breakPointBorderColor:
          breakPointBorderColor ?? this.breakPointBorderColor,
      breakPointBorderWidth:
          breakPointBorderWidth ?? this.breakPointBorderWidth,
      previewLineColor: previewLineColor ?? this.previewLineColor,
      previewLineOpacity: previewLineOpacity ?? this.previewLineOpacity,
      previewLineWidth: previewLineWidth ?? this.previewLineWidth,
      hitTestTolerance: hitTestTolerance ?? this.hitTestTolerance,
      enableHapticFeedback: enableHapticFeedback ?? this.enableHapticFeedback,
    );
  }

  /// Converts this style to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'breakPointColor': breakPointColor,
      'breakPointRadius': breakPointRadius,
      'breakPointBorderColor': breakPointBorderColor,
      'breakPointBorderWidth': breakPointBorderWidth,
      'previewLineColor': previewLineColor,
      'previewLineOpacity': previewLineOpacity,
      'previewLineWidth': previewLineWidth,
      'hitTestTolerance': hitTestTolerance,
      'enableHapticFeedback': enableHapticFeedback,
    };
  }

  /// Creates a style from a JSON representation.
  factory PolylineEditingStyle.fromJson(Map<String, dynamic> json) {
    return PolylineEditingStyle(
      breakPointColor: json['breakPointColor'] as String? ?? '#FF0000',
      breakPointRadius: json['breakPointRadius'] as double? ?? 8.0,
      breakPointBorderColor:
          json['breakPointBorderColor'] as String? ?? '#FFFFFF',
      breakPointBorderWidth: json['breakPointBorderWidth'] as double? ?? 2.0,
      previewLineColor: json['previewLineColor'] as String? ?? '#00FF00',
      previewLineOpacity: json['previewLineOpacity'] as double? ?? 0.7,
      previewLineWidth: json['previewLineWidth'] as double? ?? 3.0,
      hitTestTolerance: json['hitTestTolerance'] as double? ?? 24.0,
      enableHapticFeedback: json['enableHapticFeedback'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PolylineEditingStyle &&
        other.breakPointColor == breakPointColor &&
        other.breakPointRadius == breakPointRadius &&
        other.breakPointBorderColor == breakPointBorderColor &&
        other.breakPointBorderWidth == breakPointBorderWidth &&
        other.previewLineColor == previewLineColor &&
        other.previewLineOpacity == previewLineOpacity &&
        other.previewLineWidth == previewLineWidth &&
        other.hitTestTolerance == hitTestTolerance &&
        other.enableHapticFeedback == enableHapticFeedback;
  }

  @override
  int get hashCode {
    return Object.hash(
      breakPointColor,
      breakPointRadius,
      breakPointBorderColor,
      breakPointBorderWidth,
      previewLineColor,
      previewLineOpacity,
      previewLineWidth,
      hitTestTolerance,
      enableHapticFeedback,
    );
  }

  @override
  String toString() {
    return 'PolylineEditingStyle(breakPointColor: $breakPointColor, '
        'breakPointRadius: $breakPointRadius, '
        'breakPointBorderColor: $breakPointBorderColor, '
        'breakPointBorderWidth: $breakPointBorderWidth, '
        'previewLineColor: $previewLineColor, '
        'previewLineOpacity: $previewLineOpacity, '
        'previewLineWidth: $previewLineWidth, '
        'hitTestTolerance: $hitTestTolerance, '
        'enableHapticFeedback: $enableHapticFeedback)';
  }
}

/// Error types that can occur during polyline editing operations.
enum PolylineEditingErrorType {
  /// Error occurred during geometric calculations.
  geometricCalculation,

  /// Error occurred during platform integration.
  platformIntegration,

  /// Error occurred due to performance constraints.
  performance,

  /// Error occurred due to invalid user input.
  invalidInput,

  /// Unknown or unspecified error.
  unknown,
}

/// Represents an error that occurred during polyline editing.
@immutable
class PolylineEditingError {
  /// Creates a polyline editing error.
  const PolylineEditingError({
    required this.type,
    required this.message,
    this.lineId,
    this.details,
  });

  /// The type of error that occurred.
  final PolylineEditingErrorType type;

  /// Human-readable error message.
  final String message;

  /// ID of the polyline where the error occurred, if applicable.
  final String? lineId;

  /// Additional error details, if available.
  final Map<String, dynamic>? details;

  /// Creates a copy of this error with the given fields replaced.
  PolylineEditingError copyWith({
    PolylineEditingErrorType? type,
    String? message,
    String? lineId,
    Map<String, dynamic>? details,
  }) {
    return PolylineEditingError(
      type: type ?? this.type,
      message: message ?? this.message,
      lineId: lineId ?? this.lineId,
      details: details ?? this.details,
    );
  }

  /// Converts this error to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'message': message,
      if (lineId != null) 'lineId': lineId,
      if (details != null) 'details': details,
    };
  }

  /// Creates an error from a JSON representation.
  factory PolylineEditingError.fromJson(Map<String, dynamic> json) {
    return PolylineEditingError(
      type: PolylineEditingErrorType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PolylineEditingErrorType.unknown,
      ),
      message: json['message'] as String,
      lineId: json['lineId'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PolylineEditingError &&
        other.type == type &&
        other.message == message &&
        other.lineId == lineId &&
        _mapEquals(other.details, details);
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      message,
      lineId,
      details != null ? Object.hashAll(details!.entries) : null,
    );
  }

  @override
  String toString() {
    return 'PolylineEditingError(type: $type, message: $message, '
        'lineId: $lineId, details: $details)';
  }

  /// Helper method to compare maps.
  static bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
