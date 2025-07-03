part of '../maplibre_gl.dart';

/// Information about a decoded LERC file
class LercInfo {
  final int width;
  final int height;
  final int numBands;
  final int numValidPixels;
  final double minValue;
  final double maxValue;
  final double noDataValue;

  const LercInfo({
    required this.width,
    required this.height,
    required this.numBands,
    required this.numValidPixels,
    required this.minValue,
    required this.maxValue,
    required this.noDataValue,
  });

  factory LercInfo.fromMap(Map<String, dynamic> map) {
    return LercInfo(
      width: map['width'] as int,
      height: map['height'] as int,
      numBands: map['numBands'] as int,
      numValidPixels: map['numValidPixels'] as int,
      minValue: (map['minValue'] as num).toDouble(),
      maxValue: (map['maxValue'] as num).toDouble(),
      noDataValue: (map['noDataValue'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'width': width,
      'height': height,
      'numBands': numBands,
      'numValidPixels': numValidPixels,
      'minValue': minValue,
      'maxValue': maxValue,
      'noDataValue': noDataValue,
    };
  }

  @override
  String toString() {
    return 'LercInfo{width: $width, height: $height, bands: $numBands, '
        'range: $minValue to $maxValue}';
  }
}

/// Decoded LERC data with elevation values
class DecodedLercData {
  final List<double> data;
  final LercInfo info;

  const DecodedLercData({
    required this.data,
    required this.info,
  });

  /// Get elevation at specific pixel coordinates
  double getElevation(int x, int y) {
    if (x < 0 || x >= info.width || y < 0 || y >= info.height) {
      return double.nan;
    }
    return data[y * info.width + x];
  }

  /// Check if the decoded data is valid
  bool isValid() {
    return data.isNotEmpty && info.width > 0 && info.height > 0;
  }

  /// Get a region of elevation data
  List<double> getRegion(
    int startX,
    int startY,
    int regionWidth,
    int regionHeight,
  ) {
    if (startX < 0 ||
        startY < 0 ||
        startX + regionWidth > info.width ||
        startY + regionHeight > info.height) {
      throw RangeError('Invalid region coordinates');
    }

    final result = List<double>.filled(regionWidth * regionHeight, 0.0);
    for (var y = 0; y < regionHeight; y++) {
      final srcOffset = (startY + y) * info.width + startX;
      final destOffset = y * regionWidth;
      for (var x = 0; x < regionWidth; x++) {
        result[destOffset + x] = data[srcOffset + x];
      }
    }
    return result;
  }
}

/// Native LERC decoder integrated into MapLibre GL Flutter
class LercDecoder {
  static const MethodChannel _channel =
      MethodChannel('maplibre_gl/lerc_decoder');

  /// Get information about LERC compressed data
  static Future<LercInfo?> getLercInfo(Uint8List buffer) async {
    try {
      final result = await _channel.invokeMethod(
        'getLercInfo',
        {'buffer': buffer},
      );

      if (result == null) return null;

      // Convert to the expected type
      final resultMap = Map<String, dynamic>.from(result as Map);
      return LercInfo.fromMap(resultMap);
    } catch (e) {
      print('Error getting LERC info: $e');
      return null;
    }
  }

  /// Decode LERC compressed data
  static Future<DecodedLercData?> decodeLerc(
    Uint8List buffer,
    LercInfo info,
  ) async {
    try {
      final result = await _channel.invokeMethod(
        'decodeLerc',
        {
          'buffer': buffer,
          'info': info.toMap(),
        },
      );

      if (result == null) return null;

      // Convert dynamic list to List<double>
      final resultList = List<dynamic>.from(result as List);
      final data =
          resultList.map<double>((e) => (e as num).toDouble()).toList();

      return DecodedLercData(
        data: data,
        info: info,
      );
    } catch (e) {
      print('Error decoding LERC data: $e');
      return null;
    }
  }

  /// Decode LERC data in one step (get info and decode)
  static Future<DecodedLercData?> decode(Uint8List buffer) async {
    final info = await getLercInfo(buffer);
    if (info == null) return null;

    return await decodeLerc(buffer, info);
  }
}
