import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'apple_device_database.dart';
import 'device_info.dart';
import '../logging/app_logger.dart';

class UsbmuxDeviceEntry {
  final int deviceId;
  final String serialNumber;
  final int productId;
  final String connectionType;

  const UsbmuxDeviceEntry({
    required this.deviceId,
    required this.serialNumber,
    required this.productId,
    required this.connectionType,
  });
}

class LockdownDeviceInfo {
  final String productType;
  final String productVersion;
  final String? deviceName;
  final String? buildVersion;
  final String? udid;
  final String? activationState;
  final bool? passwordProtected;
  final String? chipId;

  const LockdownDeviceInfo({
    required this.productType,
    required this.productVersion,
    this.deviceName,
    this.buildVersion,
    this.udid,
    this.activationState,
    this.passwordProtected,
    this.chipId,
  });
}

class AppleUsbmuxClient {
  static const int usbmuxPort = 27015;
  static const String usbmuxHost = '127.0.0.1';

  // Test override hooks
  static Future<List<UsbmuxDeviceEntry>> Function()? mockListDevicesProvider;
  static Future<LockdownDeviceInfo?> Function(int deviceId)? mockLockdownProvider;



  /// Translates an Apple ProductType into a consumer friendly model name
  static String mapProductType(String rawProductType) {
    return AppleDeviceDatabase.mapProductType(rawProductType);
  }

  /// Checks if Apple Mobile Device Service (usbmuxd) is running on port 27015
  static Future<bool> isServiceAvailable() async {
    try {
      final socket = await Socket.connect(
        usbmuxHost,
        usbmuxPort,
        timeout: const Duration(milliseconds: 600),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Queries usbmuxd on 127.0.0.1:27015 for connected iOS devices via plist
  static Future<List<UsbmuxDeviceEntry>> listConnectedDevices({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (mockListDevicesProvider != null) {
      return await mockListDevicesProvider!();
    }

    Socket? socket;
    try {
      socket = await Socket.connect(usbmuxHost, usbmuxPort, timeout: timeout);

      const plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>MessageType</key>
    <string>ListDevices</string>
    <key>ClientVersionString</key>
    <string>414Unlock</string>
    <key>ProgName</key>
    <string>414Unlock</string>
</dict>
</plist>''';

      final plistBytes = utf8.encode(plist);
      final totalLen = 16 + plistBytes.length;

      final header = ByteData(16);
      header.setUint32(0, totalLen, Endian.little);
      header.setUint32(4, 1, Endian.little); // version = 1
      header.setUint32(8, 8, Endian.little); // request = 8 (plist)
      header.setUint32(12, 1, Endian.little); // tag = 1

      socket.add(header.buffer.asUint8List());
      socket.add(plistBytes);
      await socket.flush();

      final responseBuffer = BytesBuilder();
      final completer = Completer<List<UsbmuxDeviceEntry>>();

      final sub = socket.listen(
        (data) {
          responseBuffer.add(data);
          final rawBytes = responseBuffer.toBytes();
          if (rawBytes.length >= 16) {
            final expectedLen = ByteData.sublistView(rawBytes, 0, 4).getUint32(0, Endian.little);
            if (rawBytes.length >= expectedLen) {
              final payload = utf8.decode(rawBytes.sublist(16, expectedLen), allowMalformed: true);
              final devices = _parseDeviceListPlist(payload);
              if (!completer.isCompleted) completer.complete(devices);
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete([]);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete([]);
        },
        cancelOnError: true,
      );

      final devices = await completer.future.timeout(
        timeout,
        onTimeout: () => [],
      );

      await sub.cancel();
      await socket.close();
      return devices;
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return [];
    }
  }

  static List<UsbmuxDeviceEntry> _parseDeviceListPlist(String xml) {
    final list = <UsbmuxDeviceEntry>[];

    // Find dict blocks inside DeviceList
    final dictPattern = RegExp(r'<dict>([\s\S]*?)<\/dict>');
    final matches = dictPattern.allMatches(xml);

    for (final match in matches) {
      final block = match.group(1) ?? '';
      if (block.contains('SerialNumber')) {
        final idMatch = RegExp(r'<key>DeviceID<\/key>\s*<integer>(\d+)<\/integer>').firstMatch(block);
        final serialMatch = RegExp(r'<key>SerialNumber<\/key>\s*<string>([^<]+)<\/string>').firstMatch(block);
        final pidMatch = RegExp(r'<key>ProductID<\/key>\s*<integer>(\d+)<\/integer>').firstMatch(block);
        final connMatch = RegExp(r'<key>ConnectionType<\/key>\s*<string>([^<]+)<\/string>').firstMatch(block);

        final deviceId = int.tryParse(idMatch?.group(1) ?? '') ?? 0;
        final serial = serialMatch?.group(1)?.trim() ?? '';
        final productId = int.tryParse(pidMatch?.group(1) ?? '') ?? 0x12A8;
        final connType = connMatch?.group(1)?.trim() ?? 'USB';

        if (serial.isNotEmpty) {
          list.add(UsbmuxDeviceEntry(
            deviceId: deviceId,
            serialNumber: serial,
            productId: productId,
            connectionType: connType,
          ));
        }
      }
    }

    return list;
  }

  /// Queries the Apple device's lockdown service (port 62078) via usbmuxd tunnel for exact ProductType and ProductVersion.
  /// Uses individual key queries so that Activation-locked / Hello-screen devices respond without requiring pairing.
  static Future<LockdownDeviceInfo?> queryLockdownDeviceInfo(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final (info, _) = await queryLockdownWithRawResponse(deviceId, timeout: timeout);
    return info;
  }

  /// Establishes a tunnel through usbmuxd to the device's lockdownd service (port 62078).
  static Future<_LockdownSession?> _connectToLockdown(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(usbmuxHost, usbmuxPort, timeout: timeout);

      // Usbmux Connect request to port 62078 (lockdown)
      // Note: port 62078 in usbmux network-order format is ((62078 & 0xFF) << 8) | ((62078 >> 8) & 0xFF) = 32498
      final connectPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>MessageType</key>
    <string>Connect</string>
    <key>ClientVersionString</key>
    <string>414Unlock</string>
    <key>ProgName</key>
    <string>414Unlock</string>
    <key>DeviceID</key>
    <integer>$deviceId</integer>
    <key>PortNumber</key>
    <integer>32498</integer>
</dict>
</plist>''';

      final connectBytes = utf8.encode(connectPlist);
      final totalLen = 16 + connectBytes.length;

      final header = ByteData(16);
      header.setUint32(0, totalLen, Endian.little);
      header.setUint32(4, 1, Endian.little);
      header.setUint32(8, 8, Endian.little);
      header.setUint32(12, 1, Endian.little);

      socket.add(header.buffer.asUint8List());
      socket.add(connectBytes);
      await socket.flush();

      // Read usbmux response (connect confirmation)
      final connectRespBuffer = BytesBuilder();
      final connectCompleter = Completer<bool>();

      late final StreamSubscription<Uint8List> sub;
      sub = socket.listen(
        (data) {
          connectRespBuffer.add(data);
          final bytes = connectRespBuffer.toBytes();
          if (bytes.length >= 16) {
            final expectedLen = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
            if (bytes.length >= expectedLen) {
              final payload = utf8.decode(bytes.sublist(16, expectedLen), allowMalformed: true);
              final isSuccess = payload.contains('<key>Number</key>') && payload.contains('<integer>0</integer>');
              if (!connectCompleter.isCompleted) {
                connectCompleter.complete(isSuccess);
              }
            }
          }
        },
        onError: (_) {
          if (!connectCompleter.isCompleted) connectCompleter.complete(false);
        },
        onDone: () {
          if (!connectCompleter.isCompleted) connectCompleter.complete(false);
        },
        cancelOnError: true,
      );

      final isConnected = await connectCompleter.future.timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () => false,
      );

      await sub.cancel();

      if (!isConnected) {
        await socket.close();
        return null;
      }

      return _LockdownSession(socket);
    } catch (_) {
      try { await socket?.close(); } catch (_) {}
      return null;
    }
  }

  /// Enhanced lockdown query that returns raw error info alongside parsed data.
  /// Queries individual public keys so that devices on Setup / Hello / Activation Lock screens
  /// respond immediately without requiring device unlocking or pairing trust.
  static Future<(LockdownDeviceInfo?, String?)> queryLockdownWithRawResponse(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (mockLockdownProvider != null) {
      final info = await mockLockdownProvider!(deviceId);
      return (info, null);
    }

    _LockdownSession? session;
    try {
      session = await _connectToLockdown(deviceId, timeout: timeout);
      if (session == null) {
        return (null, 'CONNECT_FAILED');
      }

      String? productType;
      String? productVersion;
      String? udid;
      String? deviceName;
      String? buildVersion;
      String? activationState;
      bool? passwordProtected;
      String? chipId;
      String? lastError;

      // 1. ProductType (public, e.g. "iPhone14,5")
      final pTypeXml = await session.queryKey('ProductType');
      if (pTypeXml != null) {
        productType = _extractStringValue(pTypeXml);
        lastError ??= extractLockdownError(pTypeXml);
      }

      // 2. ProductVersion (public, e.g. "17.4.1")
      final pVerXml = await session.queryKey('ProductVersion');
      if (pVerXml != null) {
        productVersion = _extractStringValue(pVerXml);
        lastError ??= extractLockdownError(pVerXml);
      }

      // 3. UniqueDeviceID (UDID)
      final udidXml = await session.queryKey('UniqueDeviceID');
      if (udidXml != null) {
        udid = _extractStringValue(udidXml);
      }

      // 4. BuildVersion (e.g. "21E236")
      final bVerXml = await session.queryKey('BuildVersion');
      if (bVerXml != null) {
        buildVersion = _extractStringValue(bVerXml);
      }

      // 5. ActivationState ("Unactivated", "Activated", "FactoryActivated")
      final actXml = await session.queryKey('ActivationState');
      if (actXml != null) {
        activationState = _extractStringValue(actXml);
      }

      // 6. DeviceName (may be restricted without pairing)
      final nameXml = await session.queryKey('DeviceName');
      if (nameXml != null) {
        deviceName = _extractStringValue(nameXml);
      }

      // 7. PasswordProtected
      final pwXml = await session.queryKey('PasswordProtected');
      if (pwXml != null) {
        if (pwXml.contains('<true/>')) {
          passwordProtected = true;
        } else if (pwXml.contains('<false/>')) {
          passwordProtected = false;
        }
      }

      // 8. UniqueChipID (ECID)
      final chipXml = await session.queryKey('UniqueChipID');
      if (chipXml != null) {
        chipId = _extractIntegerValue(chipXml);
      }

      await session.close();

      if ((productType != null && productType.isNotEmpty) ||
          (productVersion != null && productVersion.isNotEmpty) ||
          (udid != null && udid.isNotEmpty)) {
        final info = LockdownDeviceInfo(
          productType: productType ?? '',
          productVersion: productVersion ?? '',
          deviceName: deviceName,
          buildVersion: buildVersion,
          udid: udid,
          activationState: activationState,
          passwordProtected: passwordProtected,
          chipId: chipId,
        );
        return (info, null);
      }

      return (null, lastError ?? 'NO_DATA');
    } catch (e) {
      AppLogger().warning('Lockdown query exception: $e');
      try { await session?.close(); } catch (_) {}
      return (null, 'EXCEPTION:$e');
    }
  }

  static String? _extractStringValue(String xml) {
    final match = RegExp(r'<key>Value<\/key>\s*<string>([^<]*)<\/string>').firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static String? _extractIntegerValue(String xml) {
    final match = RegExp(r'<key>Value<\/key>\s*<integer>(\d+)<\/integer>').firstMatch(xml);
    return match?.group(1)?.trim();
  }

  /// Extracts the lockdown error string from a response plist, if present.
  static String? extractLockdownError(String xml) {
    final errorMatch = RegExp(r'<key>Error</key>\s*<string>([^<]+)</string>').firstMatch(xml);
    return errorMatch?.group(1)?.trim();
  }

  /// Maps a lockdown error string to a [LockdownStatus].
  static LockdownStatus lockdownErrorToStatus(String? error) {
    if (error == null) return LockdownStatus.failed;
    final lower = error.toLowerCase();
    if (lower.contains('password') || lower.contains('passwordprotected')) {
      return LockdownStatus.passcodeLocked;
    }
    if (lower.contains('pairing') ||
        lower.contains('invalidhost') ||
        lower.contains('untrusted')) {
      return LockdownStatus.untrustedOrLocked;
    }
    return LockdownStatus.failed;
  }

  /// Tests if a device is unlocked and communicating as trusted/accessible.
  /// Used in Step 5 completion verification.
  static Future<bool> isDeviceTrustedAndAccessible(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final (info, error) = await queryLockdownWithRawResponse(deviceId, timeout: timeout);
    if (error != null) {
      final status = lockdownErrorToStatus(error);
      if (status == LockdownStatus.passcodeLocked ||
          status == LockdownStatus.untrustedOrLocked ||
          error == 'CONNECT_FAILED') {
        return false;
      }
    }
    return info != null;
  }
}

/// Helper managing length-prefixed packet communication with the iOS lockdownd daemon.
class _LockdownSession {
  final Socket _socket;
  final StreamSubscription<Uint8List> _sub;
  final _incoming = BytesBuilder();
  Completer<String>? _pendingCompleter;

  _LockdownSession(this._socket) : _sub = _socket.listen(null) {
    _sub.onData((chunk) {
      _incoming.add(chunk);
      _checkBuffer();
    });
    _sub.onError((_) {
      if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
        _pendingCompleter!.complete('');
      }
    });
    _sub.onDone(() {
      if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
        _pendingCompleter!.complete('');
      }
    });
  }

  void _checkBuffer() {
    final bytes = _incoming.toBytes();
    if (bytes.length >= 4) {
      final expectedLen = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      if (bytes.length >= 4 + expectedLen) {
        final payload = utf8.decode(bytes.sublist(4, 4 + expectedLen), allowMalformed: true);
        final remaining = bytes.sublist(4 + expectedLen);
        _incoming.clear();
        _incoming.add(remaining);

        final c = _pendingCompleter;
        _pendingCompleter = null;
        if (c != null && !c.isCompleted) {
          c.complete(payload);
        }
      }
    }
  }

  Future<String?> queryKey(String key, {Duration timeout = const Duration(milliseconds: 600)}) async {
    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>414Unlock</string>
    <key>Request</key>
    <string>GetValue</string>
    <key>Key</key>
    <string>$key</string>
</dict>
</plist>''';
    final bytes = utf8.encode(xml);
    final header = ByteData(4)..setUint32(0, bytes.length, Endian.big);

    final completer = Completer<String>();
    _pendingCompleter = completer;

    _socket.add(header.buffer.asUint8List());
    _socket.add(bytes);
    await _socket.flush();

    try {
      final resp = await completer.future.timeout(timeout);
      return resp;
    } catch (_) {
      _pendingCompleter = null;
      return null;
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await _socket.close();
  }
}

