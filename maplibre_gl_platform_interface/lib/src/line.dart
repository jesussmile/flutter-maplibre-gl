// This file is generated.

// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of '../maplibre_gl_platform_interface.dart';

class Line implements Annotation {
  Line(this._id, this.options, [this._data]);

  /// A unique identifier for this line.
  ///
  /// The identifier is an arbitrary unique string.
  final String _id;

  @override
  String get id => _id;

  final Map<String, dynamic>? _data;
  Map<String, dynamic>? get data => _data;

  /// The line configuration options most recently applied programmatically
  /// via the map controller.
  ///
  /// The returned value does not reflect any changes made to the line through
  /// touch events. Add listeners to the owning map controller to track those.
  LineOptions options;

  @override
  Map<String, dynamic> toGeoJson() {
    final geojson = options.toGeoJson();
    geojson["id"] = id;
    geojson["properties"]["id"] = id;
    if (_data != null) {
      geojson["properties"].addAll(_data);
    }

    return geojson;
  }

  @override
  void translate(LatLng delta) {
    options = options.copyWith(
      LineOptions(geometry: options.geometry?.map((e) => e + delta).toList()),
    );
  }
}

/// Configuration options for [Line] instances.
///
/// When used to change configuration, null values will be interpreted as
/// "do not change this configuration option".
class LineOptions {
  /// Creates a set of line configuration options.
  ///
  /// By default, every non-specified field is null, meaning no desire to change
  /// line defaults or current configuration.
  const LineOptions({
    this.lineJoin,
    this.lineOpacity,
    this.lineColor,
    this.lineWidth,
    this.lineGapWidth,
    this.lineOffset,
    this.lineBlur,
    this.linePattern,
    this.geometry,
    this.draggable,
    this.editable,
    this.editingCallbacks,
    this.breakPointColor,
    this.breakPointRadius,
    this.previewLineColor,
    this.previewLineOpacity,
  });

  final String? lineJoin;
  final double? lineOpacity;
  final String? lineColor;
  final double? lineWidth;
  final double? lineGapWidth;
  final double? lineOffset;
  final double? lineBlur;
  final String? linePattern;
  final List<LatLng>? geometry;
  final bool? draggable;

  /// Whether this polyline can be interactively edited by the user.
  ///
  /// When set to true, users can long press on the polyline to break it into
  /// segments and drag the break points to modify the path. Defaults to false
  /// for backward compatibility.
  final bool? editable;

  /// Callback functions for handling polyline editing events.
  ///
  /// These callbacks will be triggered when the user interacts with an editable
  /// polyline, such as breaking it or modifying its coordinates.
  final PolylineEditingCallbacks? editingCallbacks;

  /// Color of the break point marker displayed during editing.
  ///
  /// This should be a hex color string (e.g., "#FF0000" for red).
  /// Defaults to a platform-specific color if not specified.
  final String? breakPointColor;

  /// Radius of the break point marker in pixels.
  ///
  /// Defaults to a platform-specific size if not specified.
  final double? breakPointRadius;

  /// Color of the preview line shown during drag operations.
  ///
  /// This should be a hex color string (e.g., "#00FF00" for green).
  /// Defaults to a semi-transparent version of the original line color.
  final String? previewLineColor;

  /// Opacity of the preview line shown during drag operations.
  ///
  /// Should be a value between 0.0 (transparent) and 1.0 (opaque).
  /// Defaults to 0.7 if not specified.
  final double? previewLineOpacity;

  static const LineOptions defaultOptions = LineOptions();

  LineOptions copyWith(LineOptions changes) {
    return LineOptions(
      lineJoin: changes.lineJoin ?? lineJoin,
      lineOpacity: changes.lineOpacity ?? lineOpacity,
      lineColor: changes.lineColor ?? lineColor,
      lineWidth: changes.lineWidth ?? lineWidth,
      lineGapWidth: changes.lineGapWidth ?? lineGapWidth,
      lineOffset: changes.lineOffset ?? lineOffset,
      lineBlur: changes.lineBlur ?? lineBlur,
      linePattern: changes.linePattern ?? linePattern,
      geometry: changes.geometry ?? geometry,
      draggable: changes.draggable ?? draggable,
      editable: changes.editable ?? editable,
      editingCallbacks: changes.editingCallbacks ?? editingCallbacks,
      breakPointColor: changes.breakPointColor ?? breakPointColor,
      breakPointRadius: changes.breakPointRadius ?? breakPointRadius,
      previewLineColor: changes.previewLineColor ?? previewLineColor,
      previewLineOpacity: changes.previewLineOpacity ?? previewLineOpacity,
    );
  }

  dynamic toJson([bool addGeometry = true]) {
    final json = <String, dynamic>{};

    void addIfPresent(String fieldName, dynamic value) {
      if (value != null) {
        json[fieldName] = value;
      }
    }

    addIfPresent('lineJoin', lineJoin);
    addIfPresent('lineOpacity', lineOpacity);
    addIfPresent('lineColor', lineColor);
    addIfPresent('lineWidth', lineWidth);
    addIfPresent('lineGapWidth', lineGapWidth);
    addIfPresent('lineOffset', lineOffset);
    addIfPresent('lineBlur', lineBlur);
    addIfPresent('linePattern', linePattern);
    if (addGeometry) {
      addIfPresent(
        'geometry',
        geometry?.map((latLng) => latLng.toJson()).toList(),
      );
    }
    addIfPresent('draggable', draggable);
    addIfPresent('editable', editable);
    // Note: editingCallbacks are not serialized as they contain function references
    // and are handled separately by the method channel layer
    addIfPresent('breakPointColor', breakPointColor);
    addIfPresent('breakPointRadius', breakPointRadius);
    addIfPresent('previewLineColor', previewLineColor);
    addIfPresent('previewLineOpacity', previewLineOpacity);
    return json;
  }

  Map<String, dynamic> toGeoJson() {
    return {
      "type": "Feature",
      "properties": toJson(false),
      "geometry": {
        "type": "LineString",
        "coordinates": geometry!.map((c) => c.toGeoJsonCoordinates()).toList(),
      },
    };
  }
}
