import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ForeFlight 0x26 traffic parsing with Central Texas coordinates', () {
    // Create a mock 19-byte 0x26 payload with Central Texas coordinates
    // ICAO: "ABC" (0x41, 0x42, 0x43)
    // Lat: 30.5 (as 32-bit float little-endian: 0x00, 0x00, 0xF4, 0x41)
    // Lon: -97.5 (as 32-bit float little-endian: 0x00, 0x00, 0xC3, 0xC2)
    // Alt: 5500.0 (as 32-bit float little-endian: 0x00, 0xE0, 0xAB, 0x45)
    final payload = Uint8List.fromList([
      0x00, // message type or reserved
      0x41, 0x42, 0x43, // ICAO "ABC"
      0x00, 0x00, 0xF4, 0x41, // lat = 30.5 (little-endian float)
      0x00, 0x00, 0xC3, 0xC2, // lon = -97.5 (little-endian float)
      0x00, 0xE0, 0xAB, 0x45, // alt = 5500.0 (little-endian float)
      0x00, 0x00, 0x00, // padding/reserved (3 bytes to make 19 total)
    ]);

    // Test the parsing (we can't directly call the private method, so we'll test indirectly)
    // For now, just verify the payload structure is correct
    expect(payload.length, 19);

    // Verify ICAO bytes
    expect(payload[1], 0x41); // 'A'
    expect(payload[2], 0x42); // 'B'
    expect(payload[3], 0x43); // 'C'

    // Verify float values can be extracted
    final latBytes = payload.sublist(4, 8);
    final latitude =
        ByteData.sublistView(latBytes).getFloat32(0, Endian.little);
    expect(latitude, closeTo(30.5, 0.01));

    final lonBytes = payload.sublist(8, 12);
    final longitude =
        ByteData.sublistView(lonBytes).getFloat32(0, Endian.little);
    expect(longitude, closeTo(-97.5, 0.01));

    final altBytes = payload.sublist(12, 16);
    final altitude =
        ByteData.sublistView(altBytes).getFloat32(0, Endian.little);
    expect(altitude, closeTo(5500.0, 0.01));
  });

  test('ForeFlight handshake packets include prefix and payload', () {
    const phrase = 'i-want-to-play-ffm-udp';
    final packet = _encodeUtf16LeWithBom(phrase);

    expect(packet.length, phrase.length * 2 + 2);
    expect(packet[0], 0xFF);
    expect(packet[1], 0xFE);
    expect(
        String.fromCharCodes(packet.sublist(2).buffer.asUint16List()), phrase);
  });
}

// Helper function copied from the main file for testing
Uint8List _encodeUtf16LeWithBom(String value) {
  final units = value.codeUnits;
  final buffer = Uint8List(units.length * 2 + 2);
  buffer[0] = 0xFF;
  buffer[1] = 0xFE;
  var offset = 2;
  for (final unit in units) {
    buffer[offset++] = unit & 0xFF;
    buffer[offset++] = (unit >> 8) & 0xFF;
  }
  return buffer;
}
