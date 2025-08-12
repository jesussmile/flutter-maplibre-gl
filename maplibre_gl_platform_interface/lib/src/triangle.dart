// This file is generated.

// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of '../maplibre_gl_platform_interface.dart';

class Triangle implements Annotation {
  Triangle(this._id, this.options, [this._data]);

  /// A unique identifier for this triangle.
  ///
  /// The identifier is an arbitrary unique string.
  final String _id;

  @override
  String get id => _id;

  final Map? _data;

  Map? get data => _data;

  /// The triangle configuration options most recently applied programmatically
  /// via the map controller.
  ///
  /// The returned value does not reflect any changes made to the triangle through
  /// touch events. Add listeners to the owning map controller to track those.
  TriangleOptions options;

  @override
  Map<String, dynamic> toGeoJson() {
    final geojson = options.toGeoJson();
    geojson["id"] = id;
    geojson["properties"]["id"] = id;

    return geojson;
  }

  @override
  void translate(LatLng delta) {
    options =
        options.copyWith(TriangleOptions(geometry: options.geometry! + delta));
  }
}

/// Configuration options for [Triangle] instances.
///
/// When used to change configuration, null values will be interpreted as
/// "do not change this configuration option".
class TriangleOptions {
  /// Creates a set of triangle configuration options.
  ///
  /// By default, every non-specified field is null, meaning no desire to change
  /// triangle defaults or current configuration.
  const TriangleOptions({
    this.triangleSize,
    this.triangleColor,
    this.triangleBlur,
    this.triangleOpacity,
    this.triangleStrokeWidth,
    this.triangleStrokeColor,
    this.triangleStrokeOpacity,
    this.triangleRotation,
    this.geometry,
    this.draggable,
  });

  final double? triangleSize;
  final String? triangleColor;
  final double? triangleBlur;
  final double? triangleOpacity;
  final double? triangleStrokeWidth;
  final String? triangleStrokeColor;
  final double? triangleStrokeOpacity;
  final double? triangleRotation;
  final LatLng? geometry;
  final bool? draggable;

  static const TriangleOptions defaultOptions = TriangleOptions();

  TriangleOptions copyWith(TriangleOptions changes) {
    return TriangleOptions(
      triangleSize: changes.triangleSize ?? triangleSize,
      triangleColor: changes.triangleColor ?? triangleColor,
      triangleBlur: changes.triangleBlur ?? triangleBlur,
      triangleOpacity: changes.triangleOpacity ?? triangleOpacity,
      triangleStrokeWidth: changes.triangleStrokeWidth ?? triangleStrokeWidth,
      triangleStrokeColor: changes.triangleStrokeColor ?? triangleStrokeColor,
      triangleStrokeOpacity: changes.triangleStrokeOpacity ?? triangleStrokeOpacity,
      triangleRotation: changes.triangleRotation ?? triangleRotation,
      geometry: changes.geometry ?? geometry,
      draggable: changes.draggable ?? draggable,
    );
  }

  dynamic toJson([bool addGeometry = true]) {
    final json = <String, dynamic>{};

    void addIfPresent(String fieldName, dynamic value) {
      if (value != null) {
        json[fieldName] = value;
      }
    }

    addIfPresent('triangleSize', triangleSize);
    addIfPresent('triangleColor', triangleColor);
    addIfPresent('triangleBlur', triangleBlur);
    addIfPresent('triangleOpacity', triangleOpacity);
    addIfPresent('triangleStrokeWidth', triangleStrokeWidth);
    addIfPresent('triangleStrokeColor', triangleStrokeColor);
    addIfPresent('triangleStrokeOpacity', triangleStrokeOpacity);
    addIfPresent('triangleRotation', triangleRotation);
    if (addGeometry) {
      addIfPresent('geometry', geometry?.toJson());
    }
    addIfPresent('draggable', draggable);
    return json;
  }

  Map<String, dynamic> toGeoJson() {
    return {
      "type": "Feature",
      "properties": toJson(false),
      "geometry": {
        "type": "Point",
        "coordinates": geometry!.toGeoJsonCoordinates()
      }
    };
  }
}
