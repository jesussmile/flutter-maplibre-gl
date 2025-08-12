// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of '../maplibre_gl.dart';

/// Configuration for experimental features in MapLibre GL.
/// 
/// This class allows enabling/disabling experimental features that may not be
/// fully stable or supported across all platforms.
class MapLibreExperimentalFeatures {
  /// Enable native triangle layer rendering.
  /// 
  /// When enabled, triangle layers use native GPU shaders for rendering,
  /// providing better performance and visual quality compared to symbol-based
  /// alternatives.
  /// 
  /// **Platform Support:**
  /// - Android: ✅ Supported via OpenGL ES custom layer
  /// - iOS: ✅ Supported via OpenGL ES custom layer  
  /// - Web: ❌ Not supported in this phase
  /// - macOS: ❌ Not supported in this phase
  /// 
  /// **Status:** Experimental - API may change
  /// 
  /// **Default:** `false`
  final bool enableNativeTriangleLayers;

  /// Create experimental features configuration.
  const MapLibreExperimentalFeatures({
    this.enableNativeTriangleLayers = false,
  });

  /// Default configuration with all experimental features disabled.
  static const MapLibreExperimentalFeatures none = MapLibreExperimentalFeatures();

  /// Configuration with triangle layers enabled.
  /// 
  /// Use this for testing and development of triangle layer functionality.
  static const MapLibreExperimentalFeatures triangles = MapLibreExperimentalFeatures(
    enableNativeTriangleLayers: true,
  );

  /// Copy configuration with modified values.
  MapLibreExperimentalFeatures copyWith({
    bool? enableNativeTriangleLayers,
  }) {
    return MapLibreExperimentalFeatures(
      enableNativeTriangleLayers: enableNativeTriangleLayers ?? this.enableNativeTriangleLayers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapLibreExperimentalFeatures &&
        other.enableNativeTriangleLayers == enableNativeTriangleLayers;
  }

  @override
  int get hashCode => enableNativeTriangleLayers.hashCode;

  @override
  String toString() => 'MapLibreExperimentalFeatures(enableNativeTriangleLayers: $enableNativeTriangleLayers)';
}

/// Exception thrown when an experimental feature is used but not enabled.
class ExperimentalFeatureException implements Exception {
  /// The feature that was used without being enabled.
  final String feature;
  
  /// How to enable the feature.
  final String enableInstruction;

  /// Create an experimental feature exception.
  const ExperimentalFeatureException(this.feature, this.enableInstruction);

  @override
  String toString() => 
    'ExperimentalFeatureException: $feature is not enabled. $enableInstruction';
}
