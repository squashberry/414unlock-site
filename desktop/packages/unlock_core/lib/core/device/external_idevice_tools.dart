import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../logging/app_logger.dart';
import '../prerequisites/windows_checker_helper.dart';
import 'apple_device_database.dart';

class RecoveryQueryInfo {
  final String? cpid;
  final String? bdid;
  final String? ecid;
  final String? serialNumber;
  final String? model;
  final String? productType;
  final String? chipFamily;

  const RecoveryQueryInfo({
    this.cpid,
    this.bdid,
    this.ecid,
    this.serialNumber,
    this.model,
    this.productType,
    this.chipFamily,
  });
}

class IdeviceInfoResult {
  final String? productType;
  final String? productVersion;
  final String? uniqueDeviceId;
  final String? deviceName;
  final String? buildVersion;
  final String? activationState;

  const IdeviceInfoResult({
    this.productType,
    this.productVersion,
    this.uniqueDeviceId,
    this.deviceName,
    this.buildVersion,
    this.activationState,
  });
}

/// Optional external diagnostic tools wrapper (libirecovery & libimobiledevice).
/// Operates in a non-blocking, fail-safe manner. Never makes device pairing or
/// user trust a requirement.
class ExternalIdeviceTools {
  ExternalIdeviceTools._();

  static String? _cachedIrecoveryPath;
  static String? _cachedIdeviceinfoPath;
  static bool _searched = false;

  /// Test injection hooks
  static Future<RecoveryQueryInfo?> Function()? mockRecoveryQueryProvider;
  static Future<IdeviceInfoResult?> Function()? mockIdeviceInfoProvider;

  static Future<void> _ensureResolved() async {
    if (_searched) return;
    _searched = true;

    if (!Platform.isWindows) return;

    _cachedIrecoveryPath =
        await WindowsCheckerHelper.findExecutableOnPath('irecovery.exe') ??
            WindowsCheckerHelper.findFirstExisting([
              r'%LOCALAPPDATA%\414Unlock\tools\irecovery.exe',
              r'%PROGRAMFILES%\414Unlock\tools\irecovery.exe',
              r'C:\tools\irecovery.exe',
              r'C:\libirecovery\irecovery.exe',
            ]);

    _cachedIdeviceinfoPath =
        await WindowsCheckerHelper.findExecutableOnPath('ideviceinfo.exe') ??
            WindowsCheckerHelper.findFirstExisting([
              r'%LOCALAPPDATA%\414Unlock\tools\ideviceinfo.exe',
              r'%PROGRAMFILES%\414Unlock\tools\ideviceinfo.exe',
              r'C:\tools\ideviceinfo.exe',
              r'C:\libimobiledevice\ideviceinfo.exe',
            ]);
  }

  /// Run `irecovery -q` for a device in Recovery or DFU mode.
  /// Safely returns parsed hardware details or null on failure.
  static Future<RecoveryQueryInfo?> queryRecoveryDevice({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (mockRecoveryQueryProvider != null) {
      return await mockRecoveryQueryProvider!();
    }

    try {
      await _ensureResolved();
      final exe = _cachedIrecoveryPath;
      if (exe == null) return null;

      final result = await Process.run(
        exe,
        ['-q'],
        runInShell: false,
      ).timeout(timeout);

      if (result.exitCode != 0) return null;

      final stdoutStr = result.stdout as String;
      return parseIrecoveryOutput(stdoutStr);
    } catch (e) {
      AppLogger().warning('irecovery -q failed or timed out: $e');
      return null;
    }
  }

  /// Parses output from `irecovery -q`
  static RecoveryQueryInfo parseIrecoveryOutput(String output) {
    String? cpid;
    String? bdid;
    String? ecid;
    String? srnm;
    String? model;

    final lines = LineSplitter.split(output);
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        final key = parts[0].trim().toUpperCase();
        final value = parts.sublist(1).join(':').trim();

        switch (key) {
          case 'CPID':
            cpid = value.replaceAll('0x', '').toUpperCase();
            break;
          case 'BDID':
            bdid = value.replaceAll('0x', '').toUpperCase();
            break;
          case 'ECID':
            ecid = value.replaceAll('0x', '').toUpperCase();
            break;
          case 'SRNM':
            srnm = value;
            break;
          case 'MODEL':
            model = value;
            break;
        }
      }
    }

    String? productType;
    String? chipFamily;
    String? resolvedModel = model;

    if (cpid != null && bdid != null) {
      productType = AppleDeviceDatabase.lookupProductTypeByCpidBdid(
        cpidHex: cpid,
        bdidHex: bdid,
      );
      if (productType != null) {
        resolvedModel = AppleDeviceDatabase.mapProductType(productType);
      }
    }

    if (cpid != null) {
      chipFamily = AppleDeviceDatabase.lookupChipFamilyByCpid(cpid);
    }

    return RecoveryQueryInfo(
      cpid: cpid,
      bdid: bdid,
      ecid: ecid,
      serialNumber: srnm,
      model: resolvedModel,
      productType: productType,
      chipFamily: chipFamily,
    );
  }

  /// Optional query via `ideviceinfo` targeting only public non-restricted keys
  /// (`-k ProductType`, `-k ProductVersion`, etc.) so it succeeds on activation-locked devices.
  static Future<IdeviceInfoResult?> queryDeviceInfo({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (mockIdeviceInfoProvider != null) {
      return await mockIdeviceInfoProvider!();
    }

    try {
      await _ensureResolved();
      final exe = _cachedIdeviceinfoPath;
      if (exe == null) return null;

      final pType = await _runIdeviceInfoKey(exe, 'ProductType', timeout);
      final pVer = await _runIdeviceInfoKey(exe, 'ProductVersion', timeout);
      final udid = await _runIdeviceInfoKey(exe, 'UniqueDeviceID', timeout);
      final name = await _runIdeviceInfoKey(exe, 'DeviceName', timeout);
      final build = await _runIdeviceInfoKey(exe, 'BuildVersion', timeout);
      final state = await _runIdeviceInfoKey(exe, 'ActivationState', timeout);

      if (pType == null && pVer == null && udid == null) {
        return null;
      }

      return IdeviceInfoResult(
        productType: pType,
        productVersion: pVer,
        uniqueDeviceId: udid,
        deviceName: name,
        buildVersion: build,
        activationState: state,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _runIdeviceInfoKey(
    String exe,
    String key,
    Duration timeout,
  ) async {
    try {
      final res = await Process.run(
        exe,
        ['-k', key],
        runInShell: false,
      ).timeout(timeout);
      if (res.exitCode == 0) {
        final val = (res.stdout as String).trim();
        if (val.isNotEmpty && !val.toLowerCase().contains('error')) {
          return val;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
