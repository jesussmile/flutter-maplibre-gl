import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'page.dart';

/// Handshake/debug view for connecting to a Sentry ADS-B receiver.
///
/// GDL90 Traffic Parsing Implementation:
/// - Message 0x14 (standard traffic): Based on OzRunways' proven algorithm
///   Reference: ozrunways_java/sources/com/ozrunways/marvin/traffic/gdl90/Gdl90MessagesKt.java
/// - Message 0x25 (extended traffic): Custom parsing for Sentry-specific format
/// - Message 0x26: Not decoded (ForeFlight proprietary, requires decryption)
///
/// Key OzRunways fixes applied:
/// - Longitude uses divisor 8388607 (latitude uses 8388608)
/// - Altitude extraction from 16-bit word with proper bit masking
/// - ASCII callsign decoding for standard GDL90 messages
/// - Proper two's complement handling for vertical velocity
class SentryTrafficPage extends ExamplePage {
  const SentryTrafficPage({super.key})
      : super(const Icon(Icons.radar), 'Sentry Handshake');

  @override
  Widget build(BuildContext context) {
    return const SentryTrafficBody();
  }
}

const Set<int> _knownGdl90MessageTypes = <int>{
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0x0C,
  0x0D,
  0x0E,
  0x0F,
  0x10,
  0x11,
  0x12,
  0x13,
  0x14,
  0x15,
  0x1E,
  0x1F,
  0x25,
  0x26,
  0x65,
};

const Set<int> _messagesWithoutCrc = <int>{0x25, 0x26};

class SentryTrafficBody extends StatefulWidget {
  const SentryTrafficBody({super.key});

  @override
  State<SentryTrafficBody> createState() => _SentryTrafficBodyState();
}

class TrafficTarget {
  TrafficTarget({
    required this.icao,
    required this.addrType,
    required this.alert,
    required this.airborne,
    required this.extrapolated,
    required this.positionValid,
    required this.speedValid,
    required this.nic,
    required this.nacp,
    required this.lastSeen,
    this.tail,
    this.latitude,
    this.longitude,
    this.altitudeFt,
    this.speedKts,
    this.trackDegrees,
    this.verticalSpeedFpm,
    this.priorityCode,
    this.emitterCategory,
  });

  final int icao;
  final int addrType;
  final bool alert;
  final bool airborne;
  final bool extrapolated;
  final bool positionValid;
  final bool speedValid;
  final int nic;
  final int nacp;
  final DateTime lastSeen;
  final String? tail;
  final double? latitude;
  final double? longitude;
  final int? altitudeFt;
  final int? speedKts;
  final double? trackDegrees;
  final int? verticalSpeedFpm;
  final int? priorityCode;
  final int? emitterCategory;

  String get icaoHex => icao.toRadixString(16).padLeft(6, '0').toUpperCase();
  bool get hasAltitude => altitudeFt != null;
  bool get hasPosition =>
      positionValid && latitude != null && longitude != null;
}

class _SentryTrafficBodyState extends State<SentryTrafficBody> {
  static const String _sentryHost = '192.168.4.1';
  static const int _gdl90DataPort = 4000;
  static const String _foreFlightApp = 'ForeFlight';
  static const int _foreFlightDiscoveryPort = 63093;
  static const int _foreFlightHandshakePort = 50113;
  static const int _handshakeBroadcastTotal = 3;
  static const Duration _handshakeRetryInterval = Duration(seconds: 5);
  static const String _handshakeDeviceName = 'Flight Canvas';
  static const String _handshakeVersion = '1.0.0';
  static const String _missingSubnetMessage =
      'No 192.168.4.x interface detected';
  static const int _maxLogEntries = 200;

  RawDatagramSocket? _udpSocket;
  Timer? _handshakeRepeatTimer;
  Timer? _discoveryTimer;
  Timer? _foreFlightBeaconTimer;
  Timer? _cleanupTimer;
  DateTime? _lastHandshake;
  DateTime? _lastDiscovery;
  DateTime? _lastUdpPacket;
  String? _lastUdpStatus;
  String? _discoveryError;
  bool _isConnecting = false;
  bool _panelExpanded = false;
  bool _debugLogging = true;
  int _handshakeAttempt = 0;
  String _status = 'Press Connect to begin';
  final List<String> _logs = <String>[];
  final Set<String> _localAddresses = <String>{};
  final Map<int, TrafficTarget> _traffic = <int, TrafficTarget>{};
  bool _loggedVendorFrame = false;
  bool _loggedTrafficMessage = false;
  Set<int> _loggedUnknownMessages = {};
  bool _loggedCrcSample = false;
  bool _loggedHeartbeatSummary = false;
  bool _loggedParseFailure = false;
  bool _loggedHeartbeatMessage = false;
  bool _loggedOwnshipMessage = false;
  bool _loggedAhrsMessage = false;
  bool _loggedWeatherMessage = false;
  bool _notifiedMissingSubnet = false;
  final Set<String> _detectedKeywords = <String>{};

  bool get _hasSentrySubnet =>
      _localAddresses.any((address) => address.startsWith('192.168.4.'));

  @override
  void initState() {
    super.initState();
    _log('Initialized handshake debugger – ready to connect');
  }

  @override
  void dispose() {
    _cancelLifecycle();
    super.dispose();
  }

  void _cancelLifecycle() {
    _handshakeRepeatTimer?.cancel();
    _handshakeRepeatTimer = null;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _foreFlightBeaconTimer?.cancel();
    _foreFlightBeaconTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    if (_traffic.isNotEmpty) {
      if (mounted) {
        setState(() => _traffic.clear());
      } else {
        _traffic.clear();
      }
    }
    if (_detectedKeywords.isNotEmpty) {
      if (mounted) {
        setState(() => _detectedKeywords.clear());
      } else {
        _detectedKeywords.clear();
      }
    }
  }

  Future<void> _refreshLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final discovered = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
            discovered.add(address.address);
          }
        }
      }
      _localAddresses
        ..clear()
        ..addAll(discovered);
      if (_localAddresses.isNotEmpty) {
        _log('Local IPv4 addresses: ${_localAddresses.join(', ')}');
      } else {
        _log('Local IPv4 discovery returned no addresses');
      }

      final hasSentrySubnet = _hasSentrySubnet;
      if (!hasSentrySubnet) {
        if (!_notifiedMissingSubnet) {
          _notifiedMissingSubnet = true;
          _log(
            'No 192.168.4.x interface detected – check Sentry Wi-Fi connection',
            force: true,
          );
        }
        _setStatus(
          message: 'Waiting for Sentry Wi-Fi connection',
          discoveryError: _missingSubnetMessage,
        );
      } else {
        if (_notifiedMissingSubnet) {
          _log('Sentry Wi-Fi detected, resuming discovery');
        }
        _notifiedMissingSubnet = false;
        if (_discoveryError == _missingSubnetMessage) {
          _setStatus(discoveryError: null);
        }
      }
    } on Object catch (error) {
      _log('Failed to enumerate local IPv4 addresses: $error', force: true);
    }
  }

  void _log(String message, {bool force = false}) {
    if (!_debugLogging && !force) {
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] $message';
    debugPrint('SentryTraffic: $entry');

    if (!mounted) {
      return;
    }

    setState(() {
      _logs.add(entry);
      if (_logs.length > _maxLogEntries) {
        _logs.removeRange(0, _logs.length - _maxLogEntries);
      }
    });
  }

  Future<void> _connect({bool auto = false}) async {
    _log('${auto ? 'Auto' : 'Manual'} connect requested', force: auto);
    _cancelLifecycle();
    _notifiedMissingSubnet = false;
    _handshakeAttempt = 0;
    _lastHandshake = null;
    _lastDiscovery = null;
    _lastUdpPacket = null;
    _lastUdpStatus = null;
    _setStatus(message: 'Connecting to Sentry...', discoveryError: null);

    try {
      if (mounted) {
        setState(() => _isConnecting = true);
      }

      await _startUdpListener();
      await _refreshLocalAddresses();

      if (!_hasSentrySubnet) {
        _log('Aborting connect – still missing Sentry subnet', force: true);
        return;
      }

      _setStatus(message: 'Configuring Sentry device');
      await _performHttpHandshake();

      _setStatus(message: 'Broadcasting ForeFlight handshake');
      await _startForeFlightHandshakeLoop();

      _setStatus(message: 'Sending discovery packets');
      await _broadcastDiscovery();
      _discoveryTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_broadcastDiscovery()),
      );

      _setStatus(message: 'Sending ForeFlight discovery beacon');
      await _sendForeFlightBeacon();
      _foreFlightBeaconTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_sendForeFlightBeacon()),
      );

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _cleanupTraffic(),
      );

      _setStatus(message: 'Handshake complete – awaiting UDP data');
      _log('Connection workflow complete');
    } on Object catch (error) {
      _log('Connection workflow failed: $error', force: true);
      _cancelLifecycle();
      _setStatus(message: 'Connection error: $error');
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  void _setStatus({String? message, String? discoveryError}) {
    if (!mounted) {
      if (message != null) {
        _status = message;
      }
      _discoveryError = discoveryError;
      return;
    }

    setState(() {
      if (message != null) {
        _status = message;
      }
      _discoveryError = discoveryError;
    });
  }

  Future<void> _startForeFlightHandshakeLoop() async {
    _handshakeRepeatTimer?.cancel();
    _handshakeRepeatTimer = null;

    var remaining = _handshakeBroadcastTotal;
    if (remaining <= 0) {
      return;
    }

    Future<void> attempt() async {
      final attemptNumber = ++_handshakeAttempt;
      await _sendForeFlightHandshake(attempt: attemptNumber);
    }

    await attempt();
    remaining--;

    if (remaining <= 0) {
      return;
    }

    _handshakeRepeatTimer =
        Timer.periodic(_handshakeRetryInterval, (Timer timer) {
      if (remaining <= 0) {
        timer.cancel();
        return;
      }
      remaining--;
      unawaited(attempt());
      if (remaining <= 0) {
        timer.cancel();
      }
    });
  }

  Future<bool> _sendForeFlightHandshake({required int attempt}) async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      _log(
        'ForeFlight UDP handshake attempt $attempt skipped – no 192.168.4.x interface yet',
        force: true,
      );
      return false;
    }

    const handshakeMessages = <String>[
      'i-want-to-play-ffm-udp',
      'i-can-play-ffm-udp:+:-:=:$_handshakeDeviceName:+:-:=:$_handshakeVersion',
    ];

    var sentAny = false;
    for (final message in handshakeMessages) {
      final sent = await _sendUtf16Broadcast(
        message,
        _foreFlightHandshakePort,
      );
      sentAny = sentAny || sent;
    }

    if (sentAny) {
      final now = DateTime.now();
      if (mounted) {
        setState(() => _lastHandshake = now);
      } else {
        _lastHandshake = now;
      }
      final detail = attempt == 1
          ? 'initial handshake broadcast sent'
          : 'handshake broadcast sent (attempt $attempt)';
      final payloadInfo = handshakeMessages
          .map((message) => '${message.length} chars')
          .join(', ');
      _log('ForeFlight UDP $detail – payload sizes: $payloadInfo');
    } else {
      _log('ForeFlight UDP handshake attempt $attempt failed to send',
          force: true);
    }

    return sentAny;
  }

  Future<bool> _sendUtf16Broadcast(String message, int port) async {
    final data = _encodeUtf16LeWithBom(message);
    final broadcast = InternetAddress('192.168.4.255');

    final socket = _udpSocket;
    if (socket != null) {
      try {
        socket.send(data, broadcast, port);
        return true;
      } on Object catch (error) {
        _log('Broadcast send failed on listener socket: $error', force: true);
      }
    }

    try {
      final tempSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: false,
      );
      tempSocket.broadcastEnabled = true;
      tempSocket.send(data, broadcast, port);
      tempSocket.close();
      return true;
    } on Object catch (error) {
      _log('Broadcast send failed (ephemeral): $error', force: true);
      return false;
    }
  }

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

  Future<void> _broadcastDiscovery() async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      return;
    }

    const discoveryPacket = [0x7e, 0x29, 0x00, 0x08, 0x07, 0x79, 0xb4, 0x7e];
    final discoveryBytes = Uint8List.fromList(discoveryPacket);
    final sentryAddress = InternetAddress(_sentryHost);

    final primarySocket = _udpSocket;
    if (primarySocket != null) {
      try {
        primarySocket.send(discoveryBytes, sentryAddress, _gdl90DataPort);
        _log('GDL90 discovery packet sent to $_sentryHost:$_gdl90DataPort');
        if (mounted) {
          setState(() => _lastDiscovery = DateTime.now());
        } else {
          _lastDiscovery = DateTime.now();
        }
        return;
      } on Object catch (error) {
        _log(
          'Listener socket discovery send failed: $error – falling back to ephemeral socket',
          force: true,
        );
      }
    }

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: false,
      );
      socket.send(discoveryBytes, sentryAddress, _gdl90DataPort);
      socket.close();
      _log(
        'GDL90 discovery packet sent to $_sentryHost:$_gdl90DataPort (ephemeral)',
      );
      if (mounted) {
        setState(() => _lastDiscovery = DateTime.now());
      } else {
        _lastDiscovery = DateTime.now();
      }
    } on Object catch (error) {
      _log('Discovery send failed: $error', force: true);
      if (mounted) {
        setState(() => _discoveryError = error.toString());
      } else {
        _discoveryError = error.toString();
      }
    }
  }

  Future<void> _sendForeFlightBeacon() async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      return;
    }

    final payload =
        '{"App":"$_foreFlightApp","GDL90":{"port":$_gdl90DataPort}}';
    final data = ascii.encode(payload);
    final broadcast = InternetAddress('192.168.4.255');

    final socket = _udpSocket;
    if (socket != null) {
      try {
        socket.send(data, broadcast, _foreFlightDiscoveryPort);
        _log('ForeFlight discovery beacon sent (listener socket)');
        return;
      } on Object catch (error) {
        _log(
          'ForeFlight beacon send failed on listener socket: $error',
          force: true,
        );
      }
    }

    try {
      final beaconSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: false,
      );
      beaconSocket.broadcastEnabled = true;
      beaconSocket.send(data, broadcast, _foreFlightDiscoveryPort);
      beaconSocket.close();
      _log('ForeFlight discovery beacon sent (ephemeral socket)');
    } on Object catch (error) {
      _log('ForeFlight beacon broadcast failed: $error', force: true);
    }
  }

  Future<void> _performHttpHandshake() async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      throw Exception('No Sentry Wi-Fi subnet detected');
    }

    try {
      await _sendHttpRequest('/?action=get', method: 'POST');
      _log('HTTP handshake: Device info request sent');

      await _sendHttpRequest('/settings?action=get', method: 'POST');
      _log('HTTP handshake: Settings request sent');

      _log('HTTP handshake complete - Sentry should now be configured');
    } on Object catch (error) {
      _log('HTTP handshake failed: $error', force: true);
    }
  }

  Future<void> _sendHttpRequest(String path,
      {required String method, String? body}) async {
    final sentryAddress = InternetAddress(_sentryHost);
    final socket = await Socket.connect(
      sentryAddress,
      80,
      timeout: const Duration(seconds: 5),
    );

    try {
      final requestBody = body ?? '';
      final contentLength = requestBody.length;
      final request = '''$method $path HTTP/1.1
Host: $_sentryHost
Connection: keep-alive
Accept: */*
User-Agent: ForeFlight/115078 CFNetwork/3826.600.41 Darwin/24.6.0
Accept-Language: en-US,en;q=0.9
Content-Length: $contentLength
Accept-Encoding: gzip, deflate

$requestBody''';

      socket.write(request);

      final response = StringBuffer();
      socket.listen(
        (data) {
          response.write(String.fromCharCodes(data));
        },
        onDone: () {
          _log('HTTP response received (${response.length} bytes)');
        },
        onError: (error) {
          _log('HTTP response error: $error');
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      socket.close();
    }
  }

  Future<void> _startUdpListener() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _gdl90DataPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? packet;
          while ((packet = socket.receive()) != null) {
            final eventPacket = packet!;
            _processUdpPayload(
              eventPacket.data,
              origin: eventPacket.address,
              port: eventPacket.port,
            );
          }
        }
      });
      _udpSocket = socket;
      _log('UDP listener bound on port $_gdl90DataPort');
      _setStatus(message: 'Listening for UDP data');
    } on Object catch (error) {
      _log('UDP listener error: $error', force: true);
      _setStatus(message: 'UDP listener error: $error');
    }

    // Also listen on port 50113 for any traffic that might be sent there
    try {
      final altSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        50113,
        reuseAddress: true,
      );
      altSocket.broadcastEnabled = true;
      altSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? packet;
          while ((packet = altSocket.receive()) != null) {
            final eventPacket = packet!;
            _log(
                'ALT PORT: Received ${eventPacket.data.length} bytes from ${eventPacket.address}:${eventPacket.port}',
                force: true);
            _processUdpPayload(
              eventPacket.data,
              origin: eventPacket.address,
              port: eventPacket.port,
            );
          }
        }
      });
      _log('Alternative UDP listener bound on port 50113');
    } on Object catch (error) {
      _log('Alternative UDP listener error: $error', force: true);
    }
  }

  void _processUdpPayload(
    Uint8List data, {
    InternetAddress? origin,
    int? port,
  }) {
    final now = DateTime.now();
    final originAddress = origin?.address ?? 'unknown';

    // Check if this is a UTF-16 handshake echo (our own message bouncing back)
    if (data.length >= 4 && data[0] == 0xFF && data[1] == 0xFE) {
      final utf16String = _decodeUtf16(data);
      _log('UTF-16 HANDSHAKE ECHO: "$utf16String" from $originAddress:$port');
      return; // Skip processing handshake echoes
    }

    // Log ALL UDP packets with detailed analysis
    final hexDump = _hexPreview(data, limit: 64);
    final asciiPreview = _asciiPreview(data);
    _log('RAW UDP: ${data.length} bytes from $originAddress:$port');
    _log('HEX: $hexDump');
    _log('ASCII: $asciiPreview');

    // Additional binary analysis
    _analyzeBinaryData(data, originAddress, port);

    // Check for airline keywords in the data
    _detectAirlineKeywords(data, originAddress, port);

    final frames = _splitGdl90Frames(data);
    if (frames.isEmpty) {
      final preview = _hexPreview(data);
      _updateUdpStatus(
        now: now,
        status:
            'UDP payload ${data.length} bytes from $originAddress:$port (no GDL90 frames; preview: $preview)',
        log: true,
      );
      return;
    }

    var trafficCount = 0;
    var heartbeatCount = 0;
    var ownshipCount = 0;
    var ahrsCount = 0;
    var weatherCount = 0;
    var crcRejected = 0;
    var shortRejected = 0;
    var vendorRejected = 0;
    var unsupportedRejected = 0;
    final messageIdCounts = <int, int>{};
    TrafficTarget? sampleTarget;

    for (final frame in frames) {
      final unescaped = _unescapeGdl90(frame);
      if (unescaped.length < 3) {
        shortRejected++;
        continue;
      }

      final messageId = unescaped.first;
      messageIdCounts[messageId] = (messageIdCounts[messageId] ?? 0) + 1;

      if (!_knownGdl90MessageTypes.contains(messageId)) {
        vendorRejected++;
        _logVendorSample(unescaped, originAddress);
        continue;
      }

      final skipCrc = _messagesWithoutCrc.contains(messageId);
      if (!skipCrc && !_validateCrc(unescaped, origin: originAddress)) {
        crcRejected++;
        continue;
      }

      switch (messageId) {
        case 0x00:
          heartbeatCount++;
          if (!_loggedHeartbeatMessage) {
            _loggedHeartbeatMessage = true;
            _log(
                'HEARTBEAT MESSAGE (0x00): Connection keep-alive from $originAddress:$port',
                force: true);
          }
          break;
        case 0x0A:
          ownshipCount++;
          if (!_loggedOwnshipMessage) {
            _loggedOwnshipMessage = true;
            _log(
                'OWNSHIP MESSAGE (0x0A): Own aircraft data from $originAddress:$port',
                force: true);
          }
          break;
        case 0x14: // Standard GDL90 Traffic Report (Message ID 20)
        case 0x25: // Extended Traffic Report (observed in Sentry packets)
          if (!_loggedTrafficMessage) {
            _loggedTrafficMessage = true;
            _log(
                'TRAFFIC MESSAGE (0x${messageId.toRadixString(16)}): Aircraft traffic data from $originAddress:$port',
                force: true);
          }
          final payload = unescaped.sublist(1, unescaped.length - 2);

          // Both 0x14 and 0x25 use the same GDL90 traffic format
          final target = _trafficFromGdl90(payload, now, messageId);
          if (target != null) {
            _recordTraffic(target);
            trafficCount++;
            sampleTarget ??= target;
          } else {
            // Log failed parsing attempts for debugging
            if (!_loggedParseFailure) {
              _loggedParseFailure = true;
              _log(
                  'Failed to parse TRAFFIC 0x${messageId.toRadixString(16)} payload (${payload.length} bytes): ${_hexPreview(payload)}',
                  force: true);
            }
          }
          break;
        case 0x26: // ForeFlight AHRS Message (Attitude/Heading Reference System)
          ahrsCount++;
          if (!_loggedAhrsMessage) {
            _loggedAhrsMessage = true;
            final payload = unescaped.sublist(1, unescaped.length - 2);
            _log(
                'AHRS MESSAGE (0x26): Device attitude/orientation data from $originAddress:$port (${payload.length} bytes)',
                force: true);
            _log('AHRS PAYLOAD: ${_hexPreview(payload)}', force: true);
          }
          break;
        case 0x65: // GDL90 Weather message
        case 0x66: // GDL90 Weather message
        case 0x67: // GDL90 Weather message
          weatherCount++;
          if (!_loggedWeatherMessage) {
            _loggedWeatherMessage = true;
            _log(
                'WEATHER MESSAGE (0x${messageId.toRadixString(16)}): Weather data from $originAddress:$port',
                force: true);
          }
          break;
        default:
          if (!_knownGdl90MessageTypes.contains(messageId)) {
            vendorRejected++;
            _logVendorSample(unescaped, originAddress);
          } else {
            unsupportedRejected++;
            // Log unknown message types
            if (!_loggedUnknownMessages.contains(messageId)) {
              _loggedUnknownMessages.add(messageId);
              _log(
                  'UNKNOWN GDL90 MESSAGE TYPE 0x${messageId.toRadixString(16)} from $originAddress:$port (${unescaped.length} bytes)',
                  force: true);
            }
          }
      }
    }

    if (trafficCount == 0 && heartbeatCount > 0 && !_loggedHeartbeatSummary) {
      final descriptors = messageIdCounts.entries
          .map((entry) => '0x${entry.key.toRadixString(16)}=${entry.value}')
          .join(', ');
      _loggedHeartbeatSummary = true;
      _log('Heartbeat-only payload from $originAddress:$port -> $descriptors');
    }

    final summary = StringBuffer()
      ..write('frames ${frames.length} traff $trafficCount')
      ..write(' hb $heartbeatCount own $ownshipCount')
      ..write(' ahrs $ahrsCount weather $weatherCount')
      ..write(' crc $crcRejected short $shortRejected')
      ..write(' vendor $vendorRejected other $unsupportedRejected');

    final status =
        'UDP payload ${data.length} bytes from $originAddress:$port -> ${summary.toString()}';

    _updateUdpStatus(now: now, status: status, log: trafficCount > 0);

    if (sampleTarget != null) {
      final target = sampleTarget;
      _log(
        'Traffic sample ICAO ${target.icaoHex} alt ${target.altitudeFt ?? 0}ft '
        'spd ${target.speedKts ?? 0}kts trk ${target.trackDegrees?.toStringAsFixed(0) ?? '-'} '
        'lat ${target.latitude?.toStringAsFixed(5) ?? '--'} '
        'lon ${target.longitude?.toStringAsFixed(5) ?? '--'}',
      );
    }
  }

  void _updateUdpStatus(
      {required DateTime now, required String status, bool log = false}) {
    if (mounted) {
      setState(() {
        _lastUdpPacket = now;
        _lastUdpStatus = status;
      });
    } else {
      _lastUdpPacket = now;
      _lastUdpStatus = status;
    }

    if (log) {
      _log(status, force: true);
    }
  }

  List<Uint8List> _splitGdl90Frames(Uint8List data) {
    final frames = <Uint8List>[];
    var start = -1;
    for (var i = 0; i < data.length; i++) {
      if (data[i] == 0x7e) {
        if (start >= 0 && i > start + 1) {
          frames.add(Uint8List.sublistView(data, start + 1, i));
        }
        start = i;
      }
    }
    return frames;
  }

  Uint8List _unescapeGdl90(Uint8List frame) {
    final builder = BytesBuilder();
    var escape = false;
    for (final byte in frame) {
      if (escape) {
        builder.addByte(byte ^ 0x20);
        escape = false;
      } else if (byte == 0x7d) {
        escape = true;
      } else {
        builder.addByte(byte);
      }
    }
    return builder.takeBytes();
  }

  bool _validateCrc(Uint8List message, {String? origin}) {
    if (message.length < 3) {
      return false;
    }
    final provided =
        (message[message.length - 1] << 8) | message[message.length - 2];
    final computed = _crc16Ccitt(message.sublist(0, message.length - 2));
    if (provided != computed && !_loggedCrcSample) {
      _loggedCrcSample = true;
      final preview = _hexPreview(message);
      _log(
        'CRC mismatch provided=0x${provided.toRadixString(16).padLeft(4, '0')} '
        'computed=0x${computed.toRadixString(16).padLeft(4, '0')} ${origin ?? ''} frame=$preview',
        force: true,
      );
    }
    return provided == computed;
  }

  int _crc16Ccitt(Uint8List bytes) {
    var crc = 0xffff;
    for (final byte in bytes) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
      }
      crc &= 0xffff;
    }
    return crc;
  }

  TrafficTarget? _trafficFromGdl90(
      Uint8List payload, DateTime timestamp, int messageId) {
    // OzRunways-based GDL90 Traffic Report Parser
    // Reference: Gdl90MessagesKt.readTrafficOrOwnshipFrom()

    if (payload.length < 25) {
      return null;
    }

    if (messageId == 0x25) {
      // Custom parsing for 0x25 extended messages (keep existing logic)
      final addrType = payload[0] & 0x07;
      final alert = (payload[0] & 0x10) != 0;
      final icao = (payload[1] << 16) | (payload[2] << 8) | payload[3];

      final latRaw = _signed24(payload[4], payload[5], payload[6]);
      final lonRaw = _signed24(payload[7], payload[8], payload[9]);
      final latitude = latRaw == 0x800000 ? null : latRaw * 180.0 / 8388608.0;
      // OzRunways fix: use 8388607 for longitude divisor
      var longitude = lonRaw == 0x800000 ? null : lonRaw * 180.0 / 8388607.0;
      if (longitude != null && longitude > 180) {
        longitude -= 360;
      }
      final positionValid = latitude != null && longitude != null;

      final altitudeField =
          ((payload[9] << 4) | ((payload[10] & 0xF0) >> 4)) & 0x0fff;
      final altitudeFt =
          altitudeField == 0x0fff ? null : (altitudeField * 25) - 1000;

      final airborne = (payload[11] & 0x80) != 0;
      final extrapolated = (payload[11] & 0x40) != 0;
      final speedValid = true;
      final nic = payload[11] & 0x0F;
      final nacp = 0;

      final speedRaw = (payload[12] << 8) | payload[13];
      final verticalRaw = (payload[14] << 8) | payload[15];
      final verticalFpm = verticalRaw == 0xFFFF ? null : verticalRaw;

      final trackRaw = payload[16];
      final track = trackRaw == 0x00 ? null : trackRaw * 360.0 / 256.0;

      final emitterCategory = payload[17];
      final tailCode = payload.sublist(18);
      final tail = _parseTail(tailCode);
      final priority = null;

      return TrafficTarget(
        icao: icao,
        addrType: addrType,
        alert: alert,
        airborne: airborne,
        extrapolated: extrapolated,
        positionValid: positionValid,
        speedValid: speedValid,
        nic: nic,
        nacp: nacp,
        tail: tail?.isEmpty ?? true ? null : tail,
        latitude: latitude,
        longitude: longitude,
        altitudeFt: altitudeFt,
        speedKts: speedRaw,
        trackDegrees: track,
        verticalSpeedFpm: verticalFpm,
        priorityCode: priority,
        emitterCategory: emitterCategory,
        lastSeen: timestamp,
      );
    } else {
      // Standard GDL90 0x14 Traffic Report - OzRunways algorithm
      // Byte 0: Status byte
      final statusByte = payload[0];
      final alertStatus = ((statusByte & 0xF0) >> 4) == 1;
      final addrType = statusByte & 0x0F;

      // Bytes 1-3: ICAO address (24-bit)
      final icao = (payload[1] << 16) | (payload[2] << 8) | payload[3];

      // Bytes 4-6: Latitude (24-bit signed, two's complement)
      // OzRunways: ((value ^ 8388608) - 8388608) * 180.0 / 8388608
      final latRaw = _signed24(payload[4], payload[5], payload[6]);
      final latitude = latRaw == 0x800000 ? null : latRaw * 180.0 / 8388608.0;

      // Bytes 7-9: Longitude (24-bit signed, two's complement)
      // OzRunways: uses 8388607 as divisor for longitude (different from latitude!)
      final lonRaw = _signed24(payload[7], payload[8], payload[9]);
      var longitude = lonRaw == 0x800000 ? null : lonRaw * 180.0 / 8388607.0;
      if (longitude != null && longitude > 180) {
        longitude -= 360;
      }
      final positionValid = latitude != null && longitude != null;

      // Bytes 10-11: Altitude and misc flags (16-bit)
      final altShort = (payload[10] << 8) | payload[11];

      // Altitude: upper 12 bits, 25ft increments, -1000ft offset
      final altitudeField = (altShort & 0xFFF0) >> 4;
      final altitudeFt =
          altitudeField == 0x0FFF ? null : (altitudeField * 25) - 1000;

      // Track/Heading type: bits 1-0 of byte 11
      // 0=invalid, 1=true track, 2=magnetic heading, 3=true heading
      final trackType = altShort & 0x03;

      // Airborne flag: bit 3 of byte 11
      final airborne = (altShort & 0x08) != 0;

      // Extrapolated (report type): bit 2 of byte 11
      final extrapolated = (altShort & 0x04) != 0;

      // Byte 12: NIC/NACp (navigation accuracy)
      final nicByte = payload[12];
      final nic = (nicByte & 0xF0) >> 4;
      final nacp = nicByte & 0x0F;

      // Bytes 13-14: Horizontal velocity (12-bit) and vertical velocity (12-bit)
      final velocityWord = (payload[13] << 8) | payload[14];

      // Horizontal velocity: upper 12 bits (knots)
      final speedRaw = (velocityWord & 0xFFF0) >> 4;
      final speedValid = trackType != 0; // Valid if track type is not invalid

      // Vertical velocity: lower 12 bits, signed, 64 fpm increments
      // OzRunways: (((value & 0xFFF) ^ 2048) - 2048) * 64
      var verticalRaw = (velocityWord & 0x0FFF);
      if ((verticalRaw & 0x0800) != 0) {
        verticalRaw = verticalRaw - 0x1000; // Sign extend
      }
      final verticalFpm = verticalRaw == 0x0800 ? null : verticalRaw * 64;

      // Byte 15 (upper 4 bits): Continuation of vertical velocity (already handled above)
      // Byte 15 (lower 4 bits) + Byte 16: Track/Heading
      // For simplicity, track is in byte 16 as 8-bit (360°/256 scaling)
      final trackRaw = payload[16];
      final track = trackRaw == 0x00 ? null : trackRaw * 360.0 / 256.0;

      // Byte 17: Emitter category
      final emitterCategory = payload[17];

      // Bytes 18-25: Callsign (8 bytes, ASCII, space-padded)
      // OzRunways uses plain ASCII, not 6-bit encoding
      final tailBytes = payload.length >= 26
          ? payload.sublist(18, 26)
          : (payload.length > 18 ? payload.sublist(18) : Uint8List(0));

      // Try ASCII decoding first (OzRunways approach)
      String? tail;
      if (tailBytes.isNotEmpty) {
        try {
          tail =
              String.fromCharCodes(tailBytes.where((b) => b >= 32 && b <= 126))
                  .trim();
          if (tail.isEmpty) {
            tail = null;
          }
        } catch (e) {
          // Fallback to 6-bit if ASCII fails
          tail = _parseTail(tailBytes);
        }
      }

      // Byte 26: Priority code (upper 4 bits)
      final priority = payload.length > 26 ? payload[26] >> 4 : null;

      return TrafficTarget(
        icao: icao,
        addrType: addrType,
        alert: alertStatus,
        airborne: airborne,
        extrapolated: extrapolated,
        positionValid: positionValid,
        speedValid: speedValid,
        nic: nic,
        nacp: nacp,
        tail: tail,
        latitude: latitude,
        longitude: longitude,
        altitudeFt: altitudeFt,
        speedKts: speedValid ? speedRaw : null,
        trackDegrees: track,
        verticalSpeedFpm: verticalFpm,
        priorityCode: priority,
        emitterCategory: emitterCategory,
        lastSeen: timestamp,
      );
    }
  }

  void _recordTraffic(TrafficTarget target) {
    _traffic[target.icao] = target;
    if (mounted) {
      setState(() {});
    }
  }

  void _cleanupTraffic() {
    if (_traffic.isEmpty) {
      return;
    }
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    final obsolete = _traffic.entries
        .where((entry) => entry.value.lastSeen.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
    if (obsolete.isEmpty) {
      return;
    }
    for (final key in obsolete) {
      _traffic.remove(key);
    }
    if (mounted) {
      setState(() {});
    }
    _log(
        'Removed ${obsolete.length} stale targets – tracking ${_traffic.length}');
  }

  String? _parseTail(Uint8List bytes) {
    if (bytes.isEmpty) {
      return null;
    }

    // GDL90 traffic reports use 6-bit ASCII encoding for callsigns
    // 8 bytes (64 bits) can encode up to 10 characters (60 bits)
    const sixBitChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ     ';

    final buffer = StringBuffer();
    var bitBuffer = 0;
    var bitCount = 0;

    for (final byte in bytes) {
      bitBuffer = (bitBuffer << 8) | byte;
      bitCount += 8;

      while (bitCount >= 6) {
        final charIndex = (bitBuffer >> (bitCount - 6)) & 0x3F;
        bitCount -= 6;
        bitBuffer &= (1 << bitCount) - 1;

        if (charIndex < sixBitChars.length) {
          final char = sixBitChars[charIndex];
          if (char != ' ') {
            // Skip trailing spaces
            buffer.write(char);
          }
        }
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  int _signed24(int b1, int b2, int b3) {
    var value = (b1 << 16) | (b2 << 8) | b3;
    if ((value & 0x800000) != 0) {
      value -= 0x1000000;
    }
    return value;
  }

  String _hexPreview(Uint8List bytes, {int limit = 32}) {
    if (bytes.isEmpty) {
      return '<empty>';
    }
    final view = bytes.length <= limit ? bytes : bytes.sublist(0, limit);
    final hex =
        view.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
    if (bytes.length > limit) {
      return '$hex …(${bytes.length - limit} more)';
    }
    return hex;
  }

  String _asciiPreview(Uint8List bytes, {int limit = 32}) {
    if (bytes.isEmpty) {
      return '<empty>';
    }
    final view = bytes.length <= limit ? bytes : bytes.sublist(0, limit);
    final ascii = view.map((byte) {
      if (byte >= 32 && byte <= 126) {
        return String.fromCharCode(byte);
      } else {
        return '.';
      }
    }).join();
    if (bytes.length > limit) {
      return '$ascii...(${bytes.length - limit} more)';
    }
    return ascii;
  }

  String _decodeUtf16(Uint8List data) {
    if (data.length < 4 || data[0] != 0xFF || data[1] != 0xFE) {
      return '<not UTF-16>';
    }
    try {
      // Skip BOM and decode as little-endian UTF-16
      final utf16Data = data.sublist(2);
      final string = String.fromCharCodes(
        utf16Data.buffer.asUint16List(0, utf16Data.length ~/ 2),
      );
      return string;
    } catch (e) {
      return '<UTF-16 decode error: $e>';
    }
  }

  void _detectAirlineKeywords(Uint8List data, String originAddress, int? port) {
    // Airline keywords to search for
    const airlineKeywords = [
      'SOUTHWEST',
      'ENVOY',
      'AMERICAN',
      'SPEEDBIRD',
      'FEDEX',
      'AIRLINES',
      'DELTA',
      'UNITED',
      'ALASKA',
      'JETBLUE',
      'SPIRIT',
      'FRONTIER',
      'HAWAIIAN',
      'ALLEGiant',
      'SUN COUNTRY'
    ];

    // Convert data to different formats for searching
    final asciiString = _asciiPreview(data, limit: data.length);
    final hexString = _hexPreview(data, limit: data.length);
    final utf16String = data.length >= 4 && data[0] == 0xFF && data[1] == 0xFE
        ? _decodeUtf16(data)
        : '';

    // Check each keyword in different formats
    for (final keyword in airlineKeywords) {
      // Check ASCII text
      if (asciiString.contains(keyword.toUpperCase()) ||
          asciiString.contains(keyword.toLowerCase())) {
        final keywordEntry = '$keyword (ASCII)';
        if (_detectedKeywords.add(keywordEntry)) {
          _log(
              'AIRLINE KEYWORD DETECTED: "$keyword" in ASCII from $originAddress:$port',
              force: true);
          if (mounted) setState(() {});
        }
      }

      // Check hex representation
      if (hexString.contains(keyword.toUpperCase()) ||
          hexString.contains(keyword.toLowerCase())) {
        final keywordEntry = '$keyword (HEX)';
        if (_detectedKeywords.add(keywordEntry)) {
          _log(
              'AIRLINE KEYWORD DETECTED: "$keyword" in HEX from $originAddress:$port',
              force: true);
          if (mounted) setState(() {});
        }
      }

      // Check UTF-16 decoded text
      if (utf16String.contains(keyword.toUpperCase()) ||
          utf16String.contains(keyword.toLowerCase())) {
        final keywordEntry = '$keyword (UTF-16)';
        if (_detectedKeywords.add(keywordEntry)) {
          _log(
              'AIRLINE KEYWORD DETECTED: "$keyword" in UTF-16 from $originAddress:$port',
              force: true);
          if (mounted) setState(() {});
        }
      }

      // Check for keyword as hex bytes
      final keywordBytes = utf8.encode(keyword.toUpperCase());
      if (_containsBytes(data, keywordBytes)) {
        final keywordEntry = '$keyword (RAW_BYTES)';
        if (_detectedKeywords.add(keywordEntry)) {
          _log(
              'AIRLINE KEYWORD DETECTED: "$keyword" as raw bytes from $originAddress:$port',
              force: true);
          if (mounted) setState(() {});
        }
      }

      // Check for 6-bit encoded version (common in aviation)
      final sixBitEncoded = _encodeSixBit(keyword.toUpperCase());
      if (_containsBytes(data, sixBitEncoded)) {
        final keywordEntry = '$keyword (6BIT)';
        if (_detectedKeywords.add(keywordEntry)) {
          _log(
              'AIRLINE KEYWORD DETECTED: "$keyword" as 6-bit encoded from $originAddress:$port',
              force: true);
          if (mounted) setState(() {});
        }
      }
    }
  }

  void _analyzeBinaryData(Uint8List data, String originAddress, int? port) {
    if (data.isEmpty) return;

    // Check for common protocol signatures
    final firstByte = data[0];
    final firstTwoBytes = data.length >= 2 ? (data[0] << 8) | data[1] : 0;
    final firstFourBytes = data.length >= 4
        ? (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]
        : 0;

    // Skip detailed analysis for UTF-16 text (handshake echoes)
    if (data.length >= 4 && data[0] == 0xFF && data[1] == 0xFE) {
      _log('UTF-16 TEXT DETECTED: Likely handshake echo or text message');
      return;
    }

    // Check for GDL90 frame start (0x7E)
    if (firstByte == 0x7E) {
      _log('POTENTIAL GDL90 FRAME: Starts with 0x7E (frame delimiter)',
          force: true);
    }

    // Check for ADS-B/Mode S data patterns
    if (data.length >= 14 && (firstByte & 0xF8) == 0x00) {
      _log('POTENTIAL ADS-B DATA: First byte suggests ADS-B format',
          force: true);
    }

    // Check for binary data patterns
    var binaryCount = 0;
    var printableCount = 0;
    for (final byte in data) {
      if (byte < 32 || byte > 126) {
        binaryCount++;
      } else {
        printableCount++;
      }
    }

    final binaryRatio = binaryCount / data.length;
    if (binaryRatio > 0.8) {
      _log(
          'HIGHLY BINARY DATA: ${binaryCount}/${data.length} bytes are non-printable (${(binaryRatio * 100).round()}%)',
          force: true);
    } else if (binaryRatio < 0.2) {
      _log(
          'MOSTLY TEXT DATA: ${printableCount}/${data.length} bytes are printable (${((1 - binaryRatio) * 100).round()}%)',
          force: true);
    }

    // Check for common aviation data patterns
    if (data.length >= 8) {
      // Look for ICAO address patterns (24-bit addresses, often start with certain ranges)
      final potentialIcao = (data[0] << 16) | (data[1] << 8) | data[2];
      if (potentialIcao > 0 && potentialIcao < 0xFFFFFF) {
        _log(
            'POTENTIAL ICAO ADDRESS: 0x${potentialIcao.toRadixString(16).padLeft(6, '0').toUpperCase()} at bytes 0-2',
            force: true);
      }

      // Look for latitude/longitude patterns (24-bit signed integers)
      for (var i = 0; i <= data.length - 3; i++) {
        final value24 = _signed24(data[i], data[i + 1], data[i + 2]);
        if (value24.abs() > 1000000 && value24.abs() < 9000000) {
          // Rough lat/lon range
          _log(
              'POTENTIAL LAT/LON: ${value24} at bytes $i-${i + 2} (scaled: ${(value24 * 180.0 / 8388608.0).toStringAsFixed(4)}°)',
              force: true);
        }
      }
    }

    // Check for repeated patterns that might indicate structured data
    if (data.length >= 16) {
      final first8 = data.sublist(0, 8);
      final second8 = data.length >= 16 ? data.sublist(8, 16) : null;

      if (second8 != null) {
        var matchCount = 0;
        for (var i = 0; i < 8; i++) {
          if (first8[i] == second8[i]) matchCount++;
        }
        if (matchCount >= 6) {
          _log(
              'REPEATED PATTERN: First 8 bytes match next 8 bytes (${matchCount}/8 identical)',
              force: true);
        }
      }
    }

    // Check for common protocol headers
    if (firstTwoBytes == 0xFFFE) {
      _log('UTF-16 BOM DETECTED: Data starts with UTF-16 byte order mark',
          force: true);
    } else if (firstFourBytes == 0x89504E47) {
      _log('PNG HEADER DETECTED: Data appears to be PNG image', force: true);
    } else if (firstTwoBytes == 0xFFD8) {
      _log('JPEG HEADER DETECTED: Data appears to be JPEG image', force: true);
    }

    // Check for JSON-like data
    if (data.contains(0x7B) && data.contains(0x7D)) {
      // { and }
      _log('JSON-LIKE DATA: Contains curly braces, might be JSON', force: true);
    }
  }

  bool _containsBytes(Uint8List data, Uint8List pattern) {
    if (pattern.isEmpty || data.length < pattern.length) {
      return false;
    }

    for (var i = 0; i <= data.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        return true;
      }
    }
    return false;
  }

  void _logVendorSample(Uint8List data, String origin) {
    if (_loggedVendorFrame) {
      return;
    }
    _loggedVendorFrame = true;
    _log('Vendor frame from $origin (${_hexPreview(data)})', force: true);
  }

  Uint8List _encodeSixBit(String text) {
    const sixBitChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ     ';
    final result = <int>[];
    var bitBuffer = 0;
    var bitCount = 0;

    for (final char in text.codeUnits) {
      final upperChar = String.fromCharCode(char).toUpperCase();
      final charIndex = sixBitChars.indexOf(upperChar);
      if (charIndex == -1) continue; // Skip unknown characters

      bitBuffer = (bitBuffer << 6) | charIndex;
      bitCount += 6;

      while (bitCount >= 8) {
        bitCount -= 8;
        result.add((bitBuffer >> bitCount) & 0xFF);
        bitBuffer &= (1 << bitCount) - 1;
      }
    }

    // Add remaining bits if any
    if (bitCount > 0) {
      result.add((bitBuffer << (8 - bitCount)) & 0xFF);
    }

    return Uint8List.fromList(result);
  }

  Widget _buildTrafficSection(ThemeData theme) {
    final entries = _traffic.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    if (entries.isEmpty) {
      return const Text(
          'No traffic received yet. Connect to Sentry and wait for 0x14 (traffic) reports.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Traffic (${entries.length})', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildTrafficHeader(theme),
              const Divider(height: 1),
              for (final target in entries) _buildTrafficRow(target, theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageTypeSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GDL90 Message Types', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                child: const Row(
                  children: [
                    Expanded(
                        child: Text('Message Type',
                            style: TextStyle(fontSize: 12))),
                    Expanded(child: Text('ID', style: TextStyle(fontSize: 12))),
                    Expanded(
                        child: Text('Description',
                            style: TextStyle(fontSize: 12))),
                  ],
                ),
              ),
              const Divider(height: 1),
              _buildMessageTypeRow(
                  'Heartbeat', '0x00', 'Connection keep-alive', theme),
              _buildMessageTypeRow(
                  'Ownship', '0x0A', 'Own aircraft data', theme),
              _buildMessageTypeRow(
                  'Traffic (Std)', '0x14', 'Standard traffic reports', theme),
              _buildMessageTypeRow(
                  'Traffic (Ext)', '0x25', 'Extended traffic reports', theme),
              _buildMessageTypeRow(
                  'AHRS', '0x26', 'Attitude/Heading data', theme),
              _buildMessageTypeRow('Weather', '0x65-67', 'Weather data', theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageTypeRow(
      String type, String id, String description, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              type,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              id,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedKeywordsSection(ThemeData theme) {
    if (_detectedKeywords.isEmpty) {
      return const Text(
          'No airline keywords detected yet. Connect to Sentry and monitor UDP traffic.');
    }

    final sortedKeywords = _detectedKeywords.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected Keywords (${_detectedKeywords.length})',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Keyword', style: theme.textTheme.labelSmall),
                    ),
                    Expanded(
                      child: Text('Format', style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final keywordEntry in sortedKeywords)
                _buildKeywordRow(keywordEntry, theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordRow(String keywordEntry, ThemeData theme) {
    // Parse "KEYWORD (FORMAT)" format
    final parenIndex = keywordEntry.lastIndexOf(' (');
    final keyword =
        parenIndex != -1 ? keywordEntry.substring(0, parenIndex) : keywordEntry;
    final format = parenIndex != -1
        ? keywordEntry.substring(parenIndex + 2, keywordEntry.length - 1)
        : 'UNKNOWN';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              keyword,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              format,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficHeader(ThemeData theme) {
    const labels = [
      'ICAO',
      'Callsign',
      'Alt',
      'Spd',
      'Track',
      'V/S',
      'Pos',
      'Age'
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      child: Row(
        children: labels
            .map((label) =>
                Expanded(child: Text(label, style: theme.textTheme.labelSmall)))
            .toList(),
      ),
    );
  }

  Widget _buildTrafficRow(TrafficTarget target, ThemeData theme) {
    final now = DateTime.now();
    final textStyle = theme.textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(target.icaoHex, style: textStyle)),
          Expanded(
              child: Text(
                  target.tail?.trim().isNotEmpty == true
                      ? target.tail!.trim()
                      : target.icaoHex,
                  style: textStyle)),
          Expanded(
              child:
                  Text(_formatAltitude(target.altitudeFt), style: textStyle)),
          Expanded(
              child: Text(_formatSpeed(target.speedKts, target.speedValid),
                  style: textStyle)),
          Expanded(
              child: Text(_formatTrack(target.trackDegrees, target.speedValid),
                  style: textStyle)),
          Expanded(
              child: Text(_formatVertical(target.verticalSpeedFpm),
                  style: textStyle)),
          Expanded(child: Text(_formatPosition(target), style: textStyle)),
          Expanded(
              child: Text(_formatAge(now.difference(target.lastSeen)),
                  style: textStyle)),
        ],
      ),
    );
  }

  String _formatAltitude(int? altitude) {
    if (altitude == null) {
      return '—';
    }
    return '${altitude ~/ 100 * 100} ft';
  }

  String _formatSpeed(int? speed, bool valid) {
    if (!valid || speed == null) {
      return '—';
    }
    return '${speed} kt';
  }

  String _formatTrack(double? track, bool speedValid) {
    if (!speedValid || track == null) {
      return '—';
    }
    return '${track.round()}°';
  }

  String _formatVertical(int? vertical) {
    if (vertical == null) {
      return '—';
    }
    if (vertical == 0) {
      return '0 fpm';
    }
    final dir = vertical > 0 ? '↑' : '↓';
    return '$dir ${vertical.abs()} fpm';
  }

  String _formatPosition(TrafficTarget target) {
    if (!target.hasPosition) {
      return '—';
    }
    return '${target.latitude!.toStringAsFixed(4)}, ${target.longitude!.toStringAsFixed(4)}';
  }

  String _formatAge(Duration age) {
    if (age.inSeconds < 1) {
      return 'just now';
    }
    if (age.inSeconds < 60) {
      return '${age.inSeconds}s';
    }
    if (age.inMinutes < 60) {
      return '${age.inMinutes}m';
    }
    return '${age.inHours}h';
  }

  void _toggleDebugLogging() {
    final next = !_debugLogging;
    setState(() => _debugLogging = next);
    _log(next ? 'Debug logging enabled' : 'Debug logging disabled',
        force: true);
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return '—';
    final diff = DateTime.now().difference(value);
    if (diff.inSeconds < 1) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Widget _buildInfoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildControlButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton(
          onPressed: _isConnecting ? null : () => unawaited(_connect()),
          child: Text(_isConnecting ? 'Connecting…' : 'Connect'),
        ),
        OutlinedButton.icon(
          onPressed: _toggleDebugLogging,
          icon: Icon(
              _debugLogging ? Icons.bug_report : Icons.bug_report_outlined),
          label:
              Text(_debugLogging ? 'Disable Debug Logs' : 'Enable Debug Logs'),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_broadcastDiscovery()),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Send Discovery'),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_sendForeFlightBeacon()),
          icon: const Icon(Icons.record_voice_over),
          label: const Text('Send Beacon'),
        ),
        OutlinedButton.icon(
          onPressed: _detectedKeywords.isEmpty
              ? null
              : () => setState(() => _detectedKeywords.clear()),
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear Keywords'),
        ),
      ],
    );
  }

  Widget _buildLogView() {
    if (_logs.isEmpty) {
      return const Text(
          'No log entries yet. Enable debug logging for verbose output.');
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final entry = _logs[_logs.length - 1 - index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(entry, style: const TextStyle(fontSize: 12)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sentry Handshake Debugger')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _status,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoPill('Handshake', _formatTimestamp(_lastHandshake)),
                  _buildInfoPill('Discovery', _formatTimestamp(_lastDiscovery)),
                  _buildInfoPill(
                      'UDP Packet', _formatTimestamp(_lastUdpPacket)),
                ],
              ),
              if (_discoveryError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Discovery error: $_discoveryError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildTrafficSection(theme),
              const SizedBox(height: 16),
              _buildMessageTypeSection(theme),
              const SizedBox(height: 16),
              _buildDetectedKeywordsSection(theme),
              const SizedBox(height: 16),
              _buildControlButtons(),
              const SizedBox(height: 16),
              if (_lastUdpStatus != null) ...[
                Text('Last UDP payload', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(_lastUdpStatus!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Text(
                    'Logs',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _logs.isEmpty
                        ? null
                        : () => setState(() => _logs.clear()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Logs'),
                  ),
                  IconButton(
                    tooltip: _panelExpanded ? 'Collapse logs' : 'Expand logs',
                    onPressed: () {
                      setState(() => _panelExpanded = !_panelExpanded);
                    },
                    icon: Icon(
                      _panelExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildLogView(),
                crossFadeState: _panelExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
