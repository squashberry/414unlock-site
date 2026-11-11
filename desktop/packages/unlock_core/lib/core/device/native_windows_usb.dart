import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../logging/app_logger.dart';
import 'apple_device_database.dart';
import 'device_info.dart';

typedef _CMGetDeviceIDListSizeWNative = Int32 Function(
    Pointer<Uint32> pulLen, Pointer<Utf16> pszFilter, Uint32 ulFlags);
typedef _CMGetDeviceIDListSizeWDart = int Function(
    Pointer<Uint32> pulLen, Pointer<Utf16> pszFilter, int ulFlags);

typedef _CMGetDeviceIDListWNative = Int32 Function(
    Pointer<Utf16> pszFilter, Pointer<Uint16> buffer, Uint32 bufferLen, Uint32 ulFlags);
typedef _CMGetDeviceIDListWDart = int Function(
    Pointer<Utf16> pszFilter, Pointer<Uint16> buffer, int bufferLen, int ulFlags);

class RawUsbDevice {
  final String instanceId;
  final String vid;
  final String pid;
  final String? serialNumber;
  final DeviceMode mode;
  final String friendlyName;
  final String? cpid;
  final String? bdid;
  final String? ecid;
  final String? productType;
  final String? chipFamily;

  const RawUsbDevice({
    required this.instanceId,
    required this.vid,
    required this.pid,
    this.serialNumber,
    required this.mode,
    required this.friendlyName,
    this.cpid,
    this.bdid,
    this.ecid,
    this.productType,
    this.chipFamily,
  });
}

/// Provides low-overhead native Windows USB enumeration via CfgMgr32.
/// Eliminates child PowerShell subprocesses and avoids timeout storms.
class NativeWindowsUsb {
  static const int _cmGetIdListFilterPresent = 0x00000100;

  static DynamicLibrary? _cfgmgr32Lib;
  static _CMGetDeviceIDListSizeWDart? _getSize;
  static _CMGetDeviceIDListWDart? _getList;
  static bool _initAttempted = false;

  // Test hook for mocking in unit tests
  static List<RawUsbDevice> Function()? mockDevicesProvider;

  static void _ensureInitialized() {
    if (_initAttempted) return;
    _initAttempted = true;

    if (!Platform.isWindows) return;

    try {
      _cfgmgr32Lib = DynamicLibrary.open('cfgmgr32.dll');
      _getSize = _cfgmgr32Lib!.lookupFunction<_CMGetDeviceIDListSizeWNative, _CMGetDeviceIDListSizeWDart>(
          'CM_Get_Device_ID_List_SizeW');
      _getList = _cfgmgr32Lib!.lookupFunction<_CMGetDeviceIDListWNative, _CMGetDeviceIDListWDart>(
          'CM_Get_Device_ID_ListW');
    } catch (e) {
      AppLogger().warning('Could not load cfgmgr32.dll for native USB enumeration: $e');
    }
  }

  /// Enumerates present USB devices and returns those matching Apple VID 05AC
  static List<RawUsbDevice> getConnectedAppleDevices() {
    if (mockDevicesProvider != null) {
      return mockDevicesProvider!();
    }

    if (!Platform.isWindows) return [];

    _ensureInitialized();
    if (_getSize == null || _getList == null) {
      return _fallbackRegQuery();
    }

    try {
      return using((Arena arena) {
        final pulLen = arena<Uint32>();
        final filter = 'USB'.toNativeUtf16(allocator: arena);

        final resSize = _getSize!(pulLen, filter, _cmGetIdListFilterPresent);
        final len = pulLen.value;
        if (resSize != 0 || len == 0) return <RawUsbDevice>[];

        final buffer = arena<Uint16>(len);
        final resList = _getList!(filter, buffer, len, _cmGetIdListFilterPresent);
        if (resList != 0) return <RawUsbDevice>[];

        final appleDevices = <RawUsbDevice>[];
        int start = 0;

        for (int i = 0; i < len; i++) {
          if (buffer[i] == 0) {
            if (i > start) {
              final sliceLen = i - start;
              final strBuffer = arena<Uint16>(sliceLen + 1);
              for (int j = 0; j < sliceLen; j++) {
                strBuffer[j] = buffer[start + j];
              }
              strBuffer[sliceLen] = 0;
              final instanceId = strBuffer.cast<Utf16>().toDartString();

              if (instanceId.toUpperCase().contains('VID_05AC')) {
                final dev = _parseInstanceId(instanceId);
                if (dev != null) {
                  appleDevices.add(dev);
                }
              }
            }
            start = i + 1;
            if (i + 1 < len && buffer[i + 1] == 0) break;
          }
        }

        return appleDevices;
      });
    } catch (e) {
      AppLogger().warning('Native USB device query error: $e');
      return _fallbackRegQuery();
    }
  }

  @visibleForTesting
  static RawUsbDevice? parseInstanceId(String instanceId) => _parseInstanceId(instanceId);

  static RawUsbDevice? _parseInstanceId(String instanceId) {
    final upper = instanceId.toUpperCase();
    final vidMatch = RegExp(r'VID_([0-9A-F]{4})').firstMatch(upper);
    final pidMatch = RegExp(r'PID_([0-9A-F]{4})').firstMatch(upper);

    if (vidMatch == null) return null;
    final vid = vidMatch.group(1) ?? '05AC';
    final pid = pidMatch?.group(1) ?? '12A8';

    DeviceMode mode = DeviceMode.normal;
    String friendly = 'Apple Mobile Device USB Device';

    if (pid == '1281') {
      mode = DeviceMode.recovery;
      friendly = 'Apple Mobile Device (Recovery Mode)';
    } else if (pid == '1227') {
      mode = DeviceMode.dfu;
      friendly = 'Apple Mobile Device (DFU Mode)';
    } else if (pid == '1222') {
      mode = DeviceMode.normal;
      friendly = 'Apple Mobile Device (Diagnostic Mode)';
    } else if (pid == '12A8') {
      mode = DeviceMode.normal;
      friendly = 'Apple Mobile Device USB Device';
    }

    // Extract device serial / ECID / UDID descriptor from last path token
    String? rawCandidate;
    final parts = instanceId.split(r'\');
    if (parts.length > 2) {
      final candidate = parts.last.trim();
      // On Windows, composite device child interfaces contain &MI_
      if (!candidate.contains('&')) {
        rawCandidate = candidate;
      }
    }

    String? serial = rawCandidate;
    String? cpid;
    String? bdid;
    String? ecid;
    String? productType;
    String? chipFamily;

    final descriptorStr = rawCandidate ?? instanceId;

    if (mode == DeviceMode.recovery || mode == DeviceMode.dfu) {
      // Parse recovery/DFU descriptor tags: CPID:8110, BDID:0A, ECID:..., SRNM:...
      final cpidMatch = RegExp(r'CPID:([0-9A-F]{4})').firstMatch(descriptorStr);
      final bdidMatch = RegExp(r'BDID:([0-9A-F]{1,2})').firstMatch(descriptorStr);
      final ecidMatch = RegExp(r'ECID:([0-9A-F]+)').firstMatch(descriptorStr);
      final srnmMatch = RegExp(r'SRNM:\[?([A-Z0-9]+)\]?').firstMatch(descriptorStr);

      if (cpidMatch != null) cpid = cpidMatch.group(1);
      if (bdidMatch != null) bdid = bdidMatch.group(1)!.padLeft(2, '0');
      if (ecidMatch != null) ecid = ecidMatch.group(1);
      if (srnmMatch != null && srnmMatch.group(1)!.isNotEmpty) {
        serial = srnmMatch.group(1);
      } else if (ecid != null) {
        serial = ecid;
      }

      if (cpid != null && bdid != null) {
        productType = AppleDeviceDatabase.lookupProductTypeByCpidBdid(
          cpidHex: cpid,
          bdidHex: bdid,
        );
      }
      if (cpid != null) {
        chipFamily = AppleDeviceDatabase.lookupChipFamilyByCpid(cpid);
      }
    } else {
      // Normal mode: check for 24-char serial "0000<CPID:4><ECID:16>" or formatted "00008110-000A184214D0201E"
      if (rawCandidate != null) {
        final clean = rawCandidate.replaceAll('-', '').trim();
        if (clean.length == 24 && clean.startsWith('0000')) {
          cpid = clean.substring(4, 8);
          ecid = clean.substring(8, 24);
          chipFamily = AppleDeviceDatabase.lookupChipFamilyByCpid(cpid);
        } else if (clean.length == 40) {
          // 40-character SHA1 UDID (iPhone 5s through iPhone X)
          serial = clean;
        }
      }
    }

    return RawUsbDevice(
      instanceId: instanceId,
      vid: vid,
      pid: pid,
      serialNumber: serial,
      mode: mode,
      friendlyName: friendly,
      cpid: cpid,
      bdid: bdid,
      ecid: ecid,
      productType: productType,
      chipFamily: chipFamily,
    );
  }

  /// Fast fallback via reg.exe if cfgmgr32 is unavailable (< 100ms vs 3500ms PowerShell)
  static List<RawUsbDevice> _fallbackRegQuery() {
    try {
      final result = Process.runSync(
        'reg.exe',
        ['query', r'HKLM\SYSTEM\CurrentControlSet\Enum\USB', '/s', '/f', 'VID_05AC'],
        runInShell: false,
      );

      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
      final devices = <RawUsbDevice>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith(r'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\VID_05AC')) {
          final instanceId = trimmed.replaceFirst(r'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\', '');
          // Exclude child subkeys
          if (!instanceId.endsWith(r'\Device Parameters') && !instanceId.endsWith(r'\LogConf')) {
            final dev = _parseInstanceId(instanceId);
            if (dev != null && !devices.any((d) => d.instanceId == dev.instanceId)) {
              devices.add(dev);
            }
          }
        }
      }
      return devices;
    } catch (_) {
      return [];
    }
  }
}
