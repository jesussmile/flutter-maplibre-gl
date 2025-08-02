// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of '../maplibre_gl_platform_interface.dart';

/// Callback interface for handling polyline editing events.
///
/// This class defines the callback functions that will be triggered during
/// interactive polyline editing operations such as breaking and modifying polylines.
class PolylineEditingCallbacks {
  /// Creates a set of polyline editing callbacks.
  ///
  /// All callbacks are optional and can be null if not needed.
  const PolylineEditingCallbacks({
    this.onPolylineBroken,
    this.onPolylineModified,
    this.onEditingError,
  });

  /// Called when a polyline is broken into two segments.
  ///
  /// [lineId] is the ID of the original polyline that was broken.
  /// [segment1] contains the coordinates of the first segment.
  /// [segment2] contains the coordinates of the second segment.
  final void Function(
          String lineId, List<LatLng> segment1, List<LatLng> segment2)?
      onPolylineBroken;

  /// Called when a polyline's coordinates are modified through dragging.
  ///
  /// [lineId] is the ID of the polyline that was modified.
  /// [newCoordinates] contains the updated coordinates of the polyline.
  final void Function(String lineId, List<LatLng> newCoordinates)?
      onPolylineModified;

  /// Called when an error occurs during polyline editing.
  ///
  /// [lineId] is the ID of the polyline where the error occurred.
  /// [error] is a descriptive error message.
  final void Function(String lineId, String error)? onEditingError;

  /// Creates a copy of this callback set with the given fields replaced with new values.
  PolylineEditingCallbacks copyWith({
    void Function(String lineId, List<LatLng> segment1, List<LatLng> segment2)?
        onPolylineBroken,
    void Function(String lineId, List<LatLng> newCoordinates)?
        onPolylineModified,
    void Function(String lineId, String error)? onEditingError,
  }) {
    return PolylineEditingCallbacks(
      onPolylineBroken: onPolylineBroken ?? this.onPolylineBroken,
      onPolylineModified: onPolylineModified ?? this.onPolylineModified,
      onEditingError: onEditingError ?? this.onEditingError,
    );
  }
}
