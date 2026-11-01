import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'device_detection_service.dart';
import 'device_info.dart';
import '../logging/app_logger.dart';
import '../prerequisites/windows_checker_helper.dart';

class AndroidDeviceDetectionService extends DeviceDetectionService {
  DeviceInfo? _currentDevice;
  bool _isMonitoring = false;
  Timer? _pollTimer;
  final StreamController<DeviceInfo?> _deviceController =
      StreamController<DeviceInfo?>.broadcast();

  String? _adbPath;
  String? _fastbootPath;

  @override
  DeviceInfo? get currentDevice => _currentDevice;

  @override
  bool get isMonitoring => _isMonitoring;

  @override
  Stream<DeviceInfo?> get deviceStream => _deviceController.stream;

  @override
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    AppLogger().hardware('USB monitor started (Android subsystem)');
    _resolvePaths();
    queryDevices();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      queryDevices();
    });
    notifyListeners();
  }

  @override
  void stopMonitoring() {
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    AppLogger().hardware('USB monitor stopped (Android subsystem)');
    notifyListeners();
  }

  Future<void> _resolvePaths() async {
    _adbPath = await WindowsCheckerHelper.findExecutableOnPath('adb.exe') ??
        WindowsCheckerHelper.findFirstExisting([
          r'%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe',
          r'C:\Android\platform-tools\adb.exe',
          r'C:\platform-tools\adb.exe',
        ]);

    _fastbootPath =
        await WindowsCheckerHelper.findExecutableOnPath('fastboot.exe') ??
            WindowsCheckerHelper.findFirstExisting([
              r'%LOCALAPPDATA%\Android\Sdk\platform-tools\fastboot.exe',
              r'C:\Android\platform-tools\fastboot.exe',
              r'C:\platform-tools\fastboot.exe',
            ]);
  }

  @override
  Future<DeviceInfo?> queryDevices() async {
    try {
      DeviceInfo? detected;

      // 1. Try ADB first if tool is found
      if (_adbPath != null) {
        detected = await _checkAdb();
      }

      // 2. Try Fastboot if not found via ADB
      if (detected == null && _fastbootPath != null) {
        detected = await _checkFastboot();
      }

      // 3. Fallback to Windows PnP USB query
      detected ??= await _checkWindowsPnp();

      if (_hasDeviceChanged(_currentDevice, detected)) {
        _currentDevice = detected;
        _deviceController.add(_currentDevice);
        notifyListeners();

        if (detected != null) {
          AppLogger().hardware(
            'Android device detected: ${detected.name} (${detected.mode.label})',
            'Manufacturer: ${detected.manufacturer ?? "Unknown"}, Model: ${detected.model ?? "Generic"}',
          );
        } else {
          AppLogger().hardware('Android device disconnected');
        }
      }

      return detected;
    } catch (e) {
      AppLogger().error('Error scanning for Android devices', e.toString());
      return null;
    }
  }

  Future<DeviceInfo?> _checkAdb() async {
    try {
      final result = await Process.run(
        _adbPath!,
        ['devices', '-l'],
      ).timeout(const Duration(seconds: 2));

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('List of devices attached')) {
            continue;
          }

          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final serial = parts[0];
            final state = parts[1];

            DeviceMode mode = DeviceMode.adb;
            if (state == 'unauthorized') {
              mode = DeviceMode.adbUnauthorized;
            } else if (state == 'recovery') {
              mode = DeviceMode.recovery;
            } else if (state == 'sideload') {
              mode = DeviceMode.sideload;
            }

            String? model;
            String? product;
            for (final token in parts) {
              if (token.startsWith('model:')) {
                model = token.substring(6).replaceAll('_', ' ');
              } else if (token.startsWith('product:')) {
                product = token.substring(8);
              }
            }

            return DeviceInfo(
              platform: DevicePlatform.android,
              name: model ?? 'Android Device',
              model: model,
              manufacturer: _guessManufacturer(product ?? model ?? ''),
              serialNumber: serial,
              mode: mode,
              connectionType: 'USB (ADB)',
              hardwareId: 'ADB:$serial',
              statusDescription: mode == DeviceMode.adbUnauthorized
                  ? 'Device locked or unauthorized - accept RSA prompt on phone'
                  : 'USB communication available via ADB',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<DeviceInfo?> _checkFastboot() async {
    try {
      final result = await Process.run(
        _fastbootPath!,
        ['devices'],
      ).timeout(const Duration(seconds: 2));

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2 && parts[1].toLowerCase().contains('fastboot')) {
            return DeviceInfo(
              platform: DevicePlatform.android,
              name: 'Android Bootloader Device',
              serialNumber: parts[0],
              mode: DeviceMode.fastboot,
              connectionType: 'USB (Fastboot)',
              hardwareId: 'FASTBOOT:${parts[0]}',
              statusDescription: 'Fastboot / Bootloader protocol ready',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<DeviceInfo?> _checkWindowsPnp() async {
    try {
      // Query Windows PnP for Android Vendor IDs:
      // 18D1 (Google), 04E8 (Samsung), 2717 (Xiaomi), 12D1 (Huawei), 2A70 (OnePlus), 22B8 (Motorola)
      const script = r'''
$knownVids = "VID_18D1", "VID_04E8", "VID_2717", "VID_12D1", "VID_2A70", "VID_22B8", "VID_1004"
$devices = Get-PnpDevice -PresentOnly | Where-Object {
    $id = $_.InstanceId
    $friendly = $_.FriendlyName
    ($knownVids | Where-Object { $id -like "*$_*" }) -or
    ($id -like "*Class_ff&SubClass_42*") -or
    ($friendly -like "*Android*") -or
    ($friendly -like "*Galaxy*")
}
if ($devices) {
    $devices | ForEach-Object {
        [PSCustomObject]@{
            FriendlyName = $_.FriendlyName
            InstanceId = $_.InstanceId
            Class = $_.Class
        }
    } | ConvertTo-Json -Compress
} else {
    ""
}
''';

      final output = await WindowsCheckerHelper.runPowerShell(
        script,
        timeout: const Duration(seconds: 3),
      );

      if (output != null && output.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(output);
          final List<dynamic> deviceList = decoded is List ? decoded : [decoded];

          for (final item in deviceList) {
            final friendlyName = (item['FriendlyName'] ?? '').toString();
            final instanceId = (item['InstanceId'] ?? '').toString();

            String name = friendlyName.isNotEmpty ? friendlyName : 'Android Device';
            String? mfg = _guessManufacturerFromVid(instanceId);

            return DeviceInfo(
              platform: DevicePlatform.android,
              name: name,
              model: name,
              manufacturer: mfg,
              mode: DeviceMode.mtp,
              connectionType: 'USB',
              hardwareId: instanceId,
              statusDescription: 'USB communication available',
            );
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  String _guessManufacturer(String str) {
    final lower = str.toLowerCase();
    if (lower.contains('samsung') || lower.contains('sm-')) return 'Samsung';
    if (lower.contains('pixel') || lower.contains('google')) return 'Google';
    if (lower.contains('xiaomi') || lower.contains('redmi') || lower.contains('poco')) return 'Xiaomi';
    if (lower.contains('oneplus')) return 'OnePlus';
    if (lower.contains('motorola') || lower.contains('moto')) return 'Motorola';
    if (lower.contains('huawei') || lower.contains('honor')) return 'Huawei';
    return 'Android OEM';
  }

  String _guessManufacturerFromVid(String instanceId) {
    final upper = instanceId.toUpperCase();
    if (upper.contains('VID_18D1')) return 'Google';
    if (upper.contains('VID_04E8')) return 'Samsung';
    if (upper.contains('VID_2717')) return 'Xiaomi';
    if (upper.contains('VID_2A70')) return 'OnePlus';
    if (upper.contains('VID_12D1')) return 'Huawei';
    if (upper.contains('VID_22B8')) return 'Motorola';
    if (upper.contains('VID_1004')) return 'LG';
    return 'Android OEM';
  }

  bool _hasDeviceChanged(DeviceInfo? oldDev, DeviceInfo? newDev) {
    if (oldDev == null && newDev == null) return false;
    if (oldDev == null || newDev == null) return true;
    return oldDev.hardwareId != newDev.hardwareId || oldDev.mode != newDev.mode;
  }

  @override
  void dispose() {
    stopMonitoring();
    _deviceController.close();
    super.dispose();
  }
}
