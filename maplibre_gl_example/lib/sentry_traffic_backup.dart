import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'page.dart';

class SentryTrafficPage extends ExamplePage {
  const SentryTrafficPage({super.key})
      : super(const Icon(Icons.radar), 'Sentry Traffic');

  @override
  Widget build(BuildContext context) {
    return const SentryTrafficBody();
  }
}

class TrafficTarget {
  TrafficTarget({
    required this.icao,
    required this.position,
    required this.altitude,
    required this.track,
    required this.speed,
    required this.lastSeen,
    this.tail,
  });

  final int icao;
  final LatLng position;
  final double altitude;
  final double track;
  final double speed;
  final DateTime lastSeen;
  final String? tail;
}

class SentryTrafficBody extends StatefulWidget {
  const SentryTrafficBody({super.key});

  @override
  State<SentryTrafficBody> createState() => _SentryTrafficBodyState();
}

class _SentryTrafficBodyState extends State<SentryTrafficBody> {
  static const String _sentryHost = '192.168.4.1';
  static const int _gdl90DataPort = 4000; // Port to receive GDL90 data
  static const String _foreFlightApp = 'ForeFlight';
  static const int _foreFlightDiscoveryPort = 63093;
  static const int _foreFlightHandshakePort = 50113;
  static const int _handshakeBroadcastTotal = 3;
  static const Duration _handshakeRetryInterval = Duration(seconds: 5);
  static const String _handshakeDeviceName = 'Flight Canvas';
  static const String _handshakeVersion = '1.0.0';
  static const String _missingSubnetMessage =
      'No 192.168.4.x interface detected';
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(37.3346, -122.0090),
    zoom: 9.5,
  );
  static const int _maxLogEntries = 200;

  MapLibreMapController? _mapController;
  bool _styleReady = false;
  final Map<int, TrafficTarget> _traffic = {};
  final Map<int, Circle> _trafficCircles = {};
  RawDatagramSocket? _udpSocket;
  Timer? _cleanupTimer;
  Timer? _discoveryTimer; // FIXED: renamed from _handshakeTimer
  Timer? _foreFlightBeaconTimer;
  Timer? _handshakeRepeatTimer;
  DateTime? _lastUdpUpdate;
  DateTime? _lastUdpAttempt;
  DateTime? _lastDiscovery; // FIXED: renamed from _lastHandshake
  DateTime? _lastHandshake;
  String _status = 'Press Connect to begin';
  String? _discoveryError; // FIXED: renamed from _handshakeError
  bool _isConnecting = false;
  bool _debugLogging = true;
  bool _panelExpanded = false;
  String? _lastUdpStatus;
  final List<String> _logs = <String>[];
  bool _loggedCrcSample = false;
  bool _loggedVendorFrame = false;
  bool _loggedBeacon = false;
  bool _loggedTrafficMessage = false; // Track if we've seen 0x14
  bool _loggedSentryStatus = false; // Track if we've seen 0x26
  bool _loggedFirstHeartbeat = false;
  bool _loggedHeartbeatSummary = false;
  int _handshakeAttempt = 0;
  final Set<String> _localAddresses = <String>{};
  bool _notifiedMissingSubnet = false;

  bool get _hasSentrySubnet =>
      _localAddresses.any((address) => address.startsWith('192.168.4.'));

  @override
  void initState() {
    super.initState();
    _log('Initialized traffic view – awaiting manual connect');
  }

  @override
  void dispose() {
    _cancelLifecycle();
    _traffic.clear();
    super.dispose();
  }

  void _cancelLifecycle() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _discoveryTimer?.cancel(); // FIXED
    _discoveryTimer = null;
    _handshakeRepeatTimer?.cancel();
    _handshakeRepeatTimer = null;
    _foreFlightBeaconTimer?.cancel();
    _foreFlightBeaconTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
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
        if (mounted) {
          setState(() {
            _status = 'Waiting for Sentry Wi-Fi connection';
            _discoveryError = _missingSubnetMessage;
          });
        } else {
          _status = 'Waiting for Sentry Wi-Fi connection';
          _discoveryError = _missingSubnetMessage;
        }
      } else {
        if (_notifiedMissingSubnet) {
          _log('Sentry Wi-Fi detected, resuming discovery');
        }
        _notifiedMissingSubnet = false;
        if (_discoveryError == _missingSubnetMessage) {
          if (mounted) {
            setState(() {
              _discoveryError = null;
            });
          } else {
            _discoveryError = null;
          }
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
    _loggedCrcSample = false;
    _loggedVendorFrame = false;
    _loggedBeacon = false;
    _loggedTrafficMessage = false;
    _loggedSentryStatus = false;
    _loggedFirstHeartbeat = false;
    _loggedHeartbeatSummary = false;
    _handshakeAttempt = 0;
    _lastHandshake = null;
    if (mounted) {
      setState(() {
        _isConnecting = true;
        _status = 'Connecting to Sentry...';
      });
    }
    try {
      // Start UDP listener first
      await _startUdpListener();

      // Discover our local interface addresses so we can ignore self echoes
      await _refreshLocalAddresses();

      // CRITICAL: Perform HTTP configuration handshake like ForeFlight does
      if (mounted) {
        setState(() {
          _status = 'Configuring Sentry device';
        });
      }
      await _performHttpHandshake();

      if (mounted) {
        setState(() {
          _status = 'Broadcasting ForeFlight handshake';
        });
      } else {
        _status = 'Broadcasting ForeFlight handshake';
      }
      await _startForeFlightHandshakeLoop();

      // Start broadcasting discovery messages
      if (mounted) {
        setState(() {
          _status = 'Sending discovery packets';
        });
      }
      await _broadcastDiscovery();
      _discoveryTimer = Timer.periodic(
        const Duration(
            seconds: 1), // Send discovery packet every 1 second initially
        (_) => unawaited(_broadcastDiscovery()),
      );

      // Start cleanup timer (run every 5 seconds to remove stale aircraft)
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _cleanupTraffic(),
      );

      // Start ForeFlight discovery beacon loop
      await _sendForeFlightBeacon();
      _foreFlightBeaconTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_sendForeFlightBeacon()),
      );

      if (mounted) {
        setState(() {
          _status = 'Listening for traffic data';
        });
      }
      _log('Connection workflow complete');
    } on Object catch (error) {
      _log('Connection workflow failed: $error', force: true);
      _cancelLifecycle();
      if (mounted) {
        setState(() {
          _status = 'Connection error: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
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
        setState(() {
          _lastHandshake = now;
        });
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
        _log(
          'Broadcast send failed on listener socket: $error',
          force: true,
        );
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

  // FIXED: Send GDL90-style discovery packet matching successful iPad connection
  Future<void> _broadcastDiscovery() async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      return;
    }

    // Send the same 8-byte packet observed from successful iPad connection
    // This is a GDL90 frame: 7e 29 00 08 07 79 b4 7e
    const discoveryPacket = [0x7e, 0x29, 0x00, 0x08, 0x07, 0x79, 0xb4, 0x7e];
    final discoveryBytes = Uint8List.fromList(discoveryPacket);

    final sentryAddress = InternetAddress(_sentryHost);

    final primarySocket = _udpSocket;
    if (primarySocket != null) {
      try {
        // Send discovery packet directly to Sentry on port 4000
        primarySocket.send(discoveryBytes, sentryAddress, _gdl90DataPort);

        _log('GDL90 discovery packet sent to $_sentryHost:$_gdl90DataPort');

        if (mounted) {
          setState(() {
            _lastDiscovery = DateTime.now();
            if (_discoveryError != null) {
              _discoveryError = null;
            }
          });
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
          'GDL90 discovery packet sent to $_sentryHost:$_gdl90DataPort (ephemeral)');

      if (mounted) {
        setState(() {
          _lastDiscovery = DateTime.now();
          if (_discoveryError != null) {
            _discoveryError = null;
          }
        });
      } else {
        _lastDiscovery = DateTime.now();
      }
    } on Object catch (error) {
      _log('Discovery send failed: $error', force: true);
      if (mounted) {
        setState(() {
          _discoveryError = error.toString();
        });
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
        if (!_loggedBeacon) {
          _loggedBeacon = true;
          _log('ForeFlight discovery beacon sent (listener socket)');
        }
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
      if (!_loggedBeacon) {
        _loggedBeacon = true;
        _log('ForeFlight discovery beacon sent (ephemeral socket)');
      }
    } on Object catch (error) {
      _log('ForeFlight beacon broadcast failed: $error', force: true);
    }
  }

  // CRITICAL: Perform HTTP configuration handshake like ForeFlight does
  // This is the missing piece that makes the Sentry device start sending data
  Future<void> _performHttpHandshake() async {
    if (!_hasSentrySubnet) {
      await _refreshLocalAddresses();
    }
    if (!_hasSentrySubnet) {
      throw Exception('No Sentry Wi-Fi subnet detected');
    }

    try {
      // First HTTP request: GET device info (like ForeFlight does)
      await _sendHttpRequest('/?action=get', method: 'POST');
      _log('HTTP handshake: Device info request sent');

      // Second HTTP request: GET settings (like ForeFlight does)
      await _sendHttpRequest('/settings?action=get', method: 'POST');
      _log('HTTP handshake: Settings request sent');

      // Optional: Third HTTP request: SET settings (like ForeFlight does)
      // For now, we'll skip this as it might change device configuration
      // await _sendHttpRequest('/settings?action=set', method: 'POST', body: '{}');
      // _log('HTTP handshake: Settings update sent');

      _log('HTTP handshake complete - Sentry should now be configured');
    } on Object catch (error) {
      _log('HTTP handshake failed: $error', force: true);
      // Don't throw here - UDP discovery might still work
    }
  }

  Future<void> _sendHttpRequest(String path,
      {required String method, String? body}) async {
    final sentryAddress = InternetAddress(_sentryHost);
    final socket = await Socket.connect(sentryAddress, 80,
        timeout: const Duration(seconds: 5));

    try {
      // Send HTTP request matching ForeFlight's format
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

      // Read response (but don't wait too long)
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

      // Wait a bit for response
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      socket.close();
    }
  }

  Future<void> _startUdpListener() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _gdl90DataPort, // FIXED: Use correct port
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
      if (mounted) {
        setState(() {
          _status = 'Listening for UDP traffic';
        });
      }
    } on Object catch (e) {
      _log('UDP listener error: $e', force: true);
      if (mounted) {
        setState(() {
          _status = 'UDP listener error: $e';
        });
      }
    }
  }

  void _processUdpPayload(
    Uint8List data, {
    InternetAddress? origin,
    int? port,
  }) {
    final attemptTime = DateTime.now();
    if (mounted) {
      setState(() {
        _lastUdpAttempt = attemptTime;
      });
    } else {
      _lastUdpAttempt = attemptTime;
    }

    final originAddress = origin?.address;
    final originLabel = originAddress != null ? ' from $originAddress' : '';

    if (_handleHandshakeResponse(
      data,
      origin: origin,
      port: port,
    )) {
      return;
    }

    final frames = _splitGdl90Frames(data);
    if (frames.isEmpty) {
      const summary = '0 frames detected';
      _log('UDP payload ${data.length} bytes$originLabel contained no frames');
      if (mounted) {
        setState(() {
          _lastUdpStatus = '$summary (bytes ${data.length})';
        });
      } else {
        _lastUdpStatus = '$summary (bytes ${data.length})';
      }
      return;
    }

    final now = DateTime.now();
    var parsedCount = 0;
    var crcRejected = 0;
    var typeRejected = 0;
    var shortRejected = 0;
    var vendorRejected = 0;
    var heartbeatCount = 0;
    var ownshipCount = 0;
    var invalidTraffic = 0; // Track filtered invalid traffic
    final messageIdCounts = <int, int>{}; // Track all message IDs we see
    TrafficTarget? sampleTarget;

    for (final frame in frames) {
      final unescaped = _unescapeGdl90(frame);
      if (unescaped.length < 5) {
        shortRejected++;
        continue;
      }

      final messageId = unescaped.first;

      // Track ALL message IDs we receive
      messageIdCounts[messageId] = (messageIdCounts[messageId] ?? 0) + 1;

      // DEBUG: Log ALL message IDs we see (first time only)
      if (messageId == 0x14 && !_loggedTrafficMessage) {
        _loggedTrafficMessage = true;
        _log('*** TRAFFIC FRAMES DETECTED (0x14) ***', force: true);
      }

      if (!_isLikelyGdl90Message(messageId)) {
        vendorRejected++;
        _logVendorSample(unescaped, originAddress);
        continue;
      }

      // FIXED: Skip CRC validation for Sentry-specific messages 0x25 and 0x26
      // Sentry vendor messages don't use standard GDL90 CRC
      final skipCrc = messageId == 0x25 || messageId == 0x26;

      if (!skipCrc && !_validateCrc(unescaped, origin: originAddress)) {
        crcRejected++;
        continue;
      }

      // Handle different GDL90 message types
      if (messageId == 0x00) {
        // Heartbeat message
        heartbeatCount++;
        if (!_loggedFirstHeartbeat) {
          _loggedFirstHeartbeat = true;
          final source = originAddress ?? 'unknown source';
          _log(
            'Received first heartbeat frame (0x00) from $source – ${unescaped.length} bytes',
          );
        }
        continue;
      } else if (messageId == 0x0A) {
        // Ownship Report
        ownshipCount++;
        continue;
      } else if (messageId == 0x14) {
        // Standard GDL90 traffic report
        final payload = unescaped.sublist(1, unescaped.length - 2);
        final target = _trafficFromGdl90(payload, now);
        if (target != null) {
          _recordTraffic(target, source: 'udp');
          parsedCount++;
          sampleTarget ??= target;
        } else {
          invalidTraffic++;
        }
      } else if (messageId == 0x25) {
        // Sentry extended message (0x25 = 37 decimal)
        // Appears to be status/configuration message
        heartbeatCount++;
        continue;
      } else if (messageId == 0x26) {
        // Sentry vendor frame (likely weather/status)
        heartbeatCount++;
        if (!_loggedSentryStatus) {
          _loggedSentryStatus = true;
          _log(
            'Sentry vendor frame 0x26 detected – treating as status/weather, not traffic',
          );
        }
        continue;
      } else {
        typeRejected++;
        continue;
      }
    }

    final summary =
        'Frames ${frames.length}, traffic $parsedCount, hb $heartbeatCount, own $ownshipCount, invalid $invalidTraffic, crc $crcRejected, type $typeRejected, vendor $vendorRejected, short $shortRejected';

    if (messageIdCounts.isNotEmpty && parsedCount == 0 && heartbeatCount > 0) {
      final msgIds = messageIdCounts.entries
          .map((e) => '0x${e.key.toRadixString(16)}=${e.value}')
          .join(', ');
      if (!_loggedHeartbeatSummary) {
        _loggedHeartbeatSummary = true;
        _log('Heartbeat/status-only UDP payload – message IDs: $msgIds',
            force: true);
      } else if (heartbeatCount > 50) {
        _log('Continuing heartbeat-only UDP payload – message IDs: $msgIds',
            force: true);
      }
    }

    if (parsedCount > 0 || heartbeatCount > 0) {
      if (mounted) {
        setState(() {
          _lastUdpUpdate = now;
          _status = parsedCount > 0
              ? 'Receiving traffic from UDP'
              : 'Connected - awaiting traffic';
          _lastUdpStatus = summary;
        });
      } else {
        _lastUdpUpdate = now;
        _status = parsedCount > 0
            ? 'Receiving traffic from UDP'
            : 'Connected - awaiting traffic';
        _lastUdpStatus = summary;
      }
      _log(
          'UDP payload ${data.length} bytes$originLabel -> $summary, unique aircraft: ${_traffic.length}');
      final sample = sampleTarget;
      if (sample != null) {
        _log(
          'UDP sample target: ICAO ${sample.icao.toRadixString(16).padLeft(6, '0').toUpperCase()} '
          'lat ${sample.position.latitude.toStringAsFixed(5)} '
          'lon ${sample.position.longitude.toStringAsFixed(5)} '
          'alt ${sample.altitude.toStringAsFixed(0)} '
          'track ${sample.track.toStringAsFixed(0)} '
          'speed ${sample.speed.toStringAsFixed(0)}',
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _lastUdpStatus = summary;
        });
      } else {
        _lastUdpStatus = summary;
      }
      _log(
          'UDP payload ${data.length} bytes$originLabel contained no traffic -> $summary');
    }
  }

  List<Uint8List> _splitGdl90Frames(Uint8List data) {
    final result = <Uint8List>[];
    var start = -1;
    for (var i = 0; i < data.length; i++) {
      if (data[i] == 0x7e) {
        if (start >= 0 && i > start + 1) {
          result.add(Uint8List.sublistView(data, start + 1, i));
        }
        start = i;
      }
    }
    return result;
  }

  Uint8List _unescapeGdl90(Uint8List frame) {
    final buffer = BytesBuilder();
    var escape = false;
    for (final byte in frame) {
      if (escape) {
        buffer.addByte(byte ^ 0x20);
        escape = false;
      } else if (byte == 0x7d) {
        escape = true;
      } else {
        buffer.addByte(byte);
      }
    }
    return buffer.takeBytes();
  }

  bool _isLikelyGdl90Message(int messageId) {
    return _knownGdl90MessageTypes.contains(messageId);
  }

  void _logVendorSample(Uint8List frame, String? origin) {
    if (_loggedVendorFrame) {
      return;
    }
    _loggedVendorFrame = true;
    final preview = frame.length > 32 ? frame.sublist(0, 32) : frame;
    final sourceLabel = origin != null ? ' from $origin' : '';
    _log(
      'Non-GDL90 frame detected${sourceLabel.isEmpty ? '' : sourceLabel}: ${_hexDump(preview)} (len=${frame.length})',
      force: true,
    );
  }

  // FIXED: Corrected CRC validation
  bool _validateCrc(Uint8List message, {String? origin}) {
    if (message.length < 3) return false;

    // Data is everything except the last 2 bytes (which are the CRC)
    final data = message.sublist(0, message.length - 2);

    // CRC is last 2 bytes, LSB first
    final providedCrc =
        (message[message.length - 1] << 8) | message[message.length - 2];

    // Calculate expected CRC
    final calculatedCrc = _crc16Ccitt(data);

    final isMatch = calculatedCrc == providedCrc;
    if (!isMatch && !_loggedCrcSample) {
      _loggedCrcSample = true;
      _log(
        'CRC mismatch provided=0x${providedCrc.toRadixString(16).padLeft(4, '0')} '
        'calculated=0x${calculatedCrc.toRadixString(16).padLeft(4, '0')} '
        'frame=${_hexDump(message)}${origin != null ? ' from $origin' : ''}',
        force: true,
      );
    }

    return isMatch;
  }

  // FIXED: Proper CRC-16-CCITT implementation for GDL90
  int _crc16Ccitt(Uint8List data) {
    var crc = 0xFFFF; // Standard CCITT seed for GDL90 frames
    for (final byte in data) {
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

  // FIXED: Simplified - Sentry doesn't send text handshake responses
  // It just starts sending GDL90 data immediately after receiving discovery packet
  bool _handleHandshakeResponse(
    Uint8List data, {
    InternetAddress? origin,
    int? port,
  }) {
    // Sentry doesn't use text-based handshake protocol
    // It responds by sending GDL90 traffic directly
    // This method kept for compatibility but always returns false
    // to let GDL90 processing handle all incoming data
    return false;
  }

  TrafficTarget? _trafficFromGdl90(Uint8List payload, DateTime now) {
    if (payload.length < 20) return null;

    // Skip status byte (payload[0]) and alert status (payload[1])
    final icao = (payload[2] << 16) | (payload[3] << 8) | payload[4];

    final latRaw = _signed24(payload[5], payload[6], payload[7]);
    final lonRaw = _signed24(payload[8], payload[9], payload[10]);
    final lat = latRaw * 180.0 / 8388608.0;
    final lon = lonRaw * 180.0 / 8388608.0;
    if (!lat.isFinite || !lon.isFinite) return null;

    final altitudeRaw = ((payload[11] << 4) | (payload[12] >> 4)) & 0x0fff;
    final altitude = altitudeRaw * 25.0 - 1000.0;

    final trackRaw = payload[13];
    final track = trackRaw * 360.0 / 256.0;

    final speedRaw = payload[14];
    final speed = speedRaw.toDouble();

    final tailCode = icao.toRadixString(16).padLeft(6, '0').toUpperCase();

    return TrafficTarget(
      icao: icao,
      position: LatLng(lat, lon),
      altitude: altitude,
      track: track,
      speed: speed,
      lastSeen: now,
      tail: tailCode,
    );
  }

  int _signed24(int b1, int b2, int b3) {
    var value = (b1 << 16) | (b2 << 8) | b3;
    if ((value & 0x800000) != 0) {
      value -= 0x1000000;
    }
    return value;
  }

  void _recordTraffic(TrafficTarget target, {required String source}) {
    _traffic[target.icao] = target;
    if (_styleReady && _mapController != null) {
      unawaited(_updateCircles());
    }
  }

  Future<void> _updateCircles() async {
    final controller = _mapController;
    if (controller == null) return;

    // Create snapshots to avoid concurrent modification
    final trafficSnapshot = Map<int, TrafficTarget>.from(_traffic);
    final circlesSnapshot = Map<int, Circle>.from(_trafficCircles);
    final stale = <int>[];

    for (final entry in trafficSnapshot.entries) {
      final target = entry.value;
      final circle = circlesSnapshot[entry.key];
      if (circle == null) {
        final newCircle = await controller.addCircle(
          CircleOptions(
            geometry: target.position,
            circleRadius: 6,
            circleColor: _colorForAltitude(target.altitude),
            circleOpacity: 0.85,
          ),
        );
        _trafficCircles[entry.key] = newCircle;
      } else {
        await controller.updateCircle(
          circle,
          CircleOptions(
            geometry: target.position,
            circleColor: _colorForAltitude(target.altitude),
          ),
        );
      }
    }

    for (final entry in circlesSnapshot.entries) {
      if (!trafficSnapshot.containsKey(entry.key)) {
        stale.add(entry.key);
      }
    }

    for (final key in stale) {
      final circle = _trafficCircles.remove(key);
      if (circle != null) {
        await controller.removeCircle(circle);
      }
    }
  }

  void _cleanupTraffic() {
    final now = DateTime.now();
    final expired = <int>[];
    // Remove aircraft not seen in last 15 seconds (more aggressive cleanup)
    for (final entry in _traffic.entries) {
      if (now.difference(entry.value.lastSeen).inSeconds > 15) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _traffic.remove(key);
      final circle = _trafficCircles.remove(key);
      if (circle != null) {
        unawaited(_mapController?.removeCircle(circle));
      }
    }
    if (expired.isNotEmpty) {
      _log(
          'Removed ${expired.length} stale targets, now tracking ${_traffic.length}');
    }
  }

  String _colorForAltitude(double altitude) {
    if (!altitude.isFinite) return '#FF8800';
    if (altitude > 20000) return '#FF0000';
    if (altitude > 10000) return '#FF8800';
    if (altitude > 5000) return '#FFD400';
    return '#00C853';
  }

  String _hexDump(Uint8List bytes, {int maxBytes = 64}) {
    final length = bytes.length;
    final view = length <= maxBytes ? bytes : bytes.sublist(0, maxBytes);
    final hex = view.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    if (length > maxBytes) {
      return '$hex …(${length - maxBytes} more)';
    }
    return hex;
  }

  Widget _buildOverlayPanel(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width < 420 ? width - 24 : 360.0;
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCollapsedSummary(theme),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      height: 36,
                      child: FilledButton(
                        onPressed:
                            _isConnecting ? null : () => unawaited(_connect()),
                        child: Text(_isConnecting ? 'Connecting' : 'Connect'),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          _panelExpanded ? 'Collapse panel' : 'Expand panel',
                      onPressed: () {
                        setState(() {
                          _panelExpanded = !_panelExpanded;
                        });
                      },
                      icon: Icon(
                        _panelExpanded
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                      ),
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _panelExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildExpandedContent(theme),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedSummary(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _status,
          style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ) ??
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _infoPill('UDP Attempt', _formatTimestamp(_lastUdpAttempt)),
            _infoPill('UDP Data', _formatTimestamp(_lastUdpUpdate)),
            _infoPill('Targets', _traffic.length.toString()),
            _infoPill('Discovery', _formatTimestamp(_lastDiscovery)),
            _infoPill('Handshake', _formatTimestamp(_lastHandshake)),
            if (_discoveryError != null) _infoPill('Discovery', 'Error'),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                final next = !_debugLogging;
                setState(() {
                  _debugLogging = next;
                });
                _log(
                  next ? 'Debug logging enabled' : 'Debug logging disabled',
                  force: true,
                );
              },
              icon: Icon(
                _debugLogging ? Icons.bug_report : Icons.bug_report_outlined,
              ),
              label: Text(
                _debugLogging ? 'Disable Debug Logs' : 'Enable Debug Logs',
              ),
            ),
            TextButton.icon(
              onPressed: _logs.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _logs.clear();
                      });
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear Logs'),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_broadcastDiscovery()),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Send Discovery'),
            ),
          ],
        ),
        if (_discoveryError != null) ...[
          const SizedBox(height: 4),
          Text(
            'Discovery error: $_discoveryError',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_lastUdpStatus != null) ...[
          const SizedBox(height: 12),
          Text(
            'Data Feed',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'UDP: ${_lastUdpStatus!}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Logs',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          _buildLogView(maxHeight: 180),
        ],
      ],
    );
  }

  Widget _infoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildLogView({double maxHeight = 180}) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        shrinkWrap: true,
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final entry = _logs[_logs.length - 1 - index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(entry, style: const TextStyle(fontSize: 11)),
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return '—';
    final diff = DateTime.now().difference(value);
    if (diff.inSeconds < 1) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              initialCameraPosition: _initialCamera,
              styleString: MapLibreStyles.demo,
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onStyleLoadedCallback: () {
                _styleReady = true;
                if (_traffic.isNotEmpty) {
                  unawaited(_updateCircles());
                }
              },
            ),
          ),
          _buildOverlayPanel(context),
        ],
      ),
    );
  }
}

const Set<int> _knownGdl90MessageTypes = <int>{
  0x00, // Heartbeat
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07, // Uplink (FIS-B)
  0x08,
  0x09,
  0x0A, // Ownship
  0x0B,
  0x0C,
  0x0D,
  0x0E,
  0x0F,
  0x10,
  0x11,
  0x12,
  0x13,
  0x14, // Traffic report
  0x15,
  0x1E,
  0x1F,
  0x25, // Sentry-specific message (observed in Android logs)
  0x26, // Sentry-specific message (observed in pcap)
  0x65, // Extended (AHRS/device info)
};
