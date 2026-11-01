import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  const LockdownDeviceInfo({
    required this.productType,
    required this.productVersion,
    this.deviceName,
    this.buildVersion,
    this.udid,
  });
}

class AppleUsbmuxClient {
  static const int usbmuxPort = 27015;
  static const String usbmuxHost = '127.0.0.1';

  // Test override hooks
  static Future<List<UsbmuxDeviceEntry>> Function()? mockListDevicesProvider;
  static Future<LockdownDeviceInfo?> Function(int deviceId)? mockLockdownProvider;

  /// Map of known Apple ProductType identifiers to consumer model names
  static const Map<String, String> _appleModelMap = {
    // iPhone 16
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',
    // iPhone 15
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',
    // iPhone 14
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',
    // iPhone 13
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,3': 'iPhone 13 Pro Max',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',
    // iPhone 12
    'iPhone13,1': 'iPhone 12 mini',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone13,4': 'iPhone 12 Pro Max',
    // iPhone 11
    'iPhone12,1': 'iPhone 11',
    'iPhone12,3': 'iPhone 11 Pro',
    'iPhone12,5': 'iPhone 11 Pro Max',
    // iPhone SE
    'iPhone8,4': 'iPhone SE (1st gen)',
    'iPhone12,8': 'iPhone SE (2nd gen)',
    'iPhone14,6': 'iPhone SE (3rd gen)',
    // iPhone X / XS / XR
    'iPhone11,2': 'iPhone XS',
    'iPhone11,4': 'iPhone XS Max',
    'iPhone11,6': 'iPhone XS Max',
    'iPhone11,8': 'iPhone XR',
    'iPhone10,3': 'iPhone X',
    'iPhone10,6': 'iPhone X',
    // iPhone 8 / 7 / 6s
    'iPhone10,1': 'iPhone 8',
    'iPhone10,4': 'iPhone 8',
    'iPhone10,2': 'iPhone 8 Plus',
    'iPhone10,5': 'iPhone 8 Plus',
    'iPhone9,1': 'iPhone 7',
    'iPhone9,3': 'iPhone 7',
    'iPhone9,2': 'iPhone 7 Plus',
    'iPhone9,4': 'iPhone 7 Plus',
    'iPhone8,1': 'iPhone 6s',
    'iPhone8,2': 'iPhone 6s Plus',
  };

  /// Translates an Apple ProductType into a consumer friendly model name
  static String mapProductType(String rawProductType) {
    final clean = rawProductType.trim();
    if (_appleModelMap.containsKey(clean)) {
      return _appleModelMap[clean]!;
    }
    if (clean.toLowerCase().startsWith('iphone')) {
      return 'Apple iPhone ($clean)';
    }
    if (clean.toLowerCase().startsWith('ipad')) {
      return 'Apple iPad ($clean)';
    }
    return 'Apple Device ($clean)';
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
  /// Returns null safely if the device is locked, untrusted, or fails to respond.
  static Future<LockdownDeviceInfo?> queryLockdownDeviceInfo(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (mockLockdownProvider != null) {
      return await mockLockdownProvider!(deviceId);
    }

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
        const Duration(milliseconds: 600),
        onTimeout: () => false,
      );

      if (!isConnected) {
        await sub.cancel();
        await socket.close();
        return null;
      }

      await sub.cancel();

      // Now connected to lockdownd directly through usbmuxd tunnel.
      // Lockdown messages: 4-byte big-endian length + XML plist.
      const getValuePlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>414Unlock</string>
    <key>Request</key>
    <string>GetValue</string>
</dict>
</plist>''';

      final getValueBytes = utf8.encode(getValuePlist);
      final lockHeader = ByteData(4);
      lockHeader.setUint32(0, getValueBytes.length, Endian.big);

      socket.add(lockHeader.buffer.asUint8List());
      socket.add(getValueBytes);
      await socket.flush();

      final lockRespBuffer = BytesBuilder();
      final lockCompleter = Completer<LockdownDeviceInfo?>();

      final lockSub = socket.listen(
        (data) {
          lockRespBuffer.add(data);
          final bytes = lockRespBuffer.toBytes();
          if (bytes.length >= 4) {
            final expectedLen = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
            if (bytes.length >= 4 + expectedLen) {
              final xml = utf8.decode(bytes.sublist(4, 4 + expectedLen), allowMalformed: true);
              final info = _parseLockdownPlist(xml);
              if (!lockCompleter.isCompleted) lockCompleter.complete(info);
            }
          }
        },
        onError: (_) {
          if (!lockCompleter.isCompleted) lockCompleter.complete(null);
        },
        onDone: () {
          if (!lockCompleter.isCompleted) lockCompleter.complete(null);
        },
        cancelOnError: true,
      );

      final result = await lockCompleter.future.timeout(
        timeout,
        onTimeout: () => null,
      );

      await lockSub.cancel();
      await socket.close();
      return result;
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return null;
    }
  }

  static LockdownDeviceInfo? _parseLockdownPlist(String xml) {
    try {
      // Check for error response (device locked/untrusted)
      final errorStr = extractLockdownError(xml);
      if (errorStr != null) {
        AppLogger().warning('Lockdown error from device: $errorStr');
        return null;
      }

      final typeMatch = RegExp(r'<key>ProductType<\/key>\s*<string>([^<]+)<\/string>').firstMatch(xml);
      final verMatch = RegExp(r'<key>ProductVersion<\/key>\s*<string>([^<]+)<\/string>').firstMatch(xml);
      final nameMatch = RegExp(r'<key>DeviceName<\/key>\s*<string>([^<]+)<\/string>').firstMatch(xml);
      final buildMatch = RegExp(r'<key>BuildVersion<\/key>\s*<string>([^<]+)<\/string>').firstMatch(xml);
      final udidMatch = RegExp(r'<key>UniqueDeviceID<\/key>\s*<string>([^<]+)<\/string>').firstMatch(xml);

      final productType = typeMatch?.group(1)?.trim() ?? '';
      final productVersion = verMatch?.group(1)?.trim() ?? '';

      if (productType.isNotEmpty || productVersion.isNotEmpty) {
        return LockdownDeviceInfo(
          productType: productType,
          productVersion: productVersion,
          deviceName: nameMatch?.group(1)?.trim(),
          buildVersion: buildMatch?.group(1)?.trim(),
          udid: udidMatch?.group(1)?.trim(),
        );
      }
    } catch (e) {
      AppLogger().warning('Failed to parse lockdown plist: $e');
    }
    return null;
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

  /// Enhanced lockdown query that returns raw error info alongside parsed data.
  /// Returns (info, errorReason) where errorReason is non-null on failure.
  static Future<(LockdownDeviceInfo?, String?)> queryLockdownWithRawResponse(
    int deviceId, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (mockLockdownProvider != null) {
      final info = await mockLockdownProvider!(deviceId);
      return (info, null);
    }

    Socket? socket;
    try {
      socket = await Socket.connect(usbmuxHost, usbmuxPort, timeout: timeout);

      // Usbmux Connect request to port 62078 (lockdown)
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
        const Duration(milliseconds: 1200),
        onTimeout: () => false,
      );

      if (!isConnected) {
        await sub.cancel();
        await socket.close();
        return (null, 'CONNECT_FAILED');
      }

      await sub.cancel();

      // Now connected to lockdownd directly through usbmuxd tunnel.
      const getValuePlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>414Unlock</string>
    <key>Request</key>
    <string>GetValue</string>
</dict>
</plist>''';

      final getValueBytes = utf8.encode(getValuePlist);
      final lockHeader = ByteData(4);
      lockHeader.setUint32(0, getValueBytes.length, Endian.big);

      socket.add(lockHeader.buffer.asUint8List());
      socket.add(getValueBytes);
      await socket.flush();

      final lockRespBuffer = BytesBuilder();
      final lockCompleter = Completer<String>();

      final lockSub = socket.listen(
        (data) {
          lockRespBuffer.add(data);
          final bytes = lockRespBuffer.toBytes();
          if (bytes.length >= 4) {
            final expectedLen = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
            if (bytes.length >= 4 + expectedLen) {
              final xml = utf8.decode(bytes.sublist(4, 4 + expectedLen), allowMalformed: true);
              if (!lockCompleter.isCompleted) lockCompleter.complete(xml);
            }
          }
        },
        onError: (_) {
          if (!lockCompleter.isCompleted) lockCompleter.complete('');
        },
        onDone: () {
          if (!lockCompleter.isCompleted) lockCompleter.complete('');
        },
        cancelOnError: true,
      );

      final rawXml = await lockCompleter.future.timeout(
        timeout,
        onTimeout: () => 'TIMEOUT',
      );

      await lockSub.cancel();
      await socket.close();

      if (rawXml == 'TIMEOUT') {
        return (null, 'TIMEOUT');
      }
      if (rawXml.isEmpty) {
        return (null, 'EMPTY_RESPONSE');
      }

      final info = _parseLockdownPlist(rawXml);
      final errorStr = info == null ? extractLockdownError(rawXml) : null;
      return (info, errorStr);
    } on TimeoutException {
      try { await socket?.close(); } catch (_) {}
      return (null, 'TIMEOUT');
    } catch (e) {
      AppLogger().warning('Lockdown query error: $e');
      try { await socket?.close(); } catch (_) {}
      return (null, 'EXCEPTION:$e');
    }
  }
}

