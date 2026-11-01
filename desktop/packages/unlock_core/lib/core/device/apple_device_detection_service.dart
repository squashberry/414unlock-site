import 'dart:async';
import 'device_detection_service.dart';
import 'device_info.dart';
import '../logging/app_logger.dart';
import 'native_windows_usb.dart';
import 'apple_usbmux_client.dart';
import '../compatibility/device_compatibility_service.dart';

class AppleDeviceDetectionService extends DeviceDetectionService {
  DeviceInfo? _currentDevice;
  bool _isMonitoring = false;
  Timer? _pollTimer;
  bool _isQuerying = false;
  int _consecutiveAbsences = 0;

  final StreamController<DeviceInfo?> _deviceController =
      StreamController<DeviceInfo?>.broadcast();

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
    _consecutiveAbsences = 0;
    AppLogger().hardware('USB monitor started (Apple subsystem - Native Windows)');

    // Immediate initial check
    queryDevices();

    // Polling interval using native CfgMgr32 / Usbmuxd (execution takes < 2ms)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      queryDevices();
    });
    notifyListeners();
  }

  @override
  void stopMonitoring() {
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _isQuerying = false;
    AppLogger().hardware('USB monitor stopped (Apple subsystem)');
    notifyListeners();
  }

  @override
  Future<DeviceInfo?> queryDevices() async {
    // Concurrency guard: only one discovery query at a time
    if (_isQuerying) return _currentDevice;
    _isQuerying = true;

    try {
      await Future<void>.delayed(Duration.zero);
      // 1. Fast, low-overhead native Windows enumeration via CfgMgr32 FFI
      final rawDevices = NativeWindowsUsb.getConnectedAppleDevices();

      if (rawDevices.isEmpty) {
        _consecutiveAbsences++;
        // Debounce transient disconnects: require 2 consecutive empty scans before reporting disconnection
        if (_consecutiveAbsences >= 2 && _currentDevice != null) {
          _currentDevice = null;
          _deviceController.add(null);
          notifyListeners();
          AppLogger().hardware('Apple device disconnected');
        }
        return _currentDevice;
      }

      // Reset absence counter as a device is present on USB bus
      _consecutiveAbsences = 0;
      final raw = rawDevices.first;

      // 2. Query Usbmuxd for additional details if in normal mode
      List<UsbmuxDeviceEntry> usbmuxEntries = [];
      if (raw.mode == DeviceMode.normal) {
        try {
          usbmuxEntries = await AppleUsbmuxClient.listConnectedDevices(
            timeout: const Duration(milliseconds: 800),
          );
        } catch (_) {}
      }

      final serialNumber = usbmuxEntries.isNotEmpty
          ? usbmuxEntries.first.serialNumber
          : raw.serialNumber;

      String name = 'Apple iPhone';
      String? model;
      String? modelIdentifier;
      String? osVersion;
      LockdownStatus lockdownStatus = LockdownStatus.available;

      // 3. Query Lockdown service via usbmuxd tunnel for exact ProductType and iOS version
      if (usbmuxEntries.isNotEmpty && raw.mode == DeviceMode.normal) {
        try {
          final (lockdownInfo, errorReason) = await AppleUsbmuxClient.queryLockdownWithRawResponse(
            usbmuxEntries.first.deviceId,
            timeout: const Duration(milliseconds: 2500),
          );
          if (lockdownInfo != null) {
            modelIdentifier = lockdownInfo.productType;
            osVersion = lockdownInfo.productVersion;
            model = AppleUsbmuxClient.mapProductType(lockdownInfo.productType);
            name = (lockdownInfo.deviceName != null && lockdownInfo.deviceName!.isNotEmpty)
                ? lockdownInfo.deviceName!
                : model;
            lockdownStatus = LockdownStatus.setupScreen;
          } else {
            // Determine specific failure reason
            if (errorReason == 'TIMEOUT') {
              lockdownStatus = LockdownStatus.timeout;
              AppLogger().warning('Lockdown query timed out for device');
            } else if (errorReason == 'CONNECT_FAILED') {
              lockdownStatus = LockdownStatus.untrustedOrLocked;
              AppLogger().warning('Lockdown connect failed — device may be locked or untrusted');
            } else if (errorReason != null) {
              lockdownStatus = AppleUsbmuxClient.lockdownErrorToStatus(errorReason);
              AppLogger().warning('Lockdown query failed: $errorReason');
            } else {
              lockdownStatus = LockdownStatus.failed;
              AppLogger().warning('Lockdown query returned no data');
            }
          }
        } catch (e) {
          lockdownStatus = LockdownStatus.failed;
          AppLogger().warning('Lockdown query exception: $e');
        }
      } else if (usbmuxEntries.isEmpty && raw.mode == DeviceMode.normal) {
        lockdownStatus = LockdownStatus.serviceUnavailable;
        AppLogger().warning('usbmuxd returned no devices — service may be unavailable');
      } else if (raw.mode == DeviceMode.recovery) {
        lockdownStatus = LockdownStatus.recoveryMode;
      } else if (raw.mode == DeviceMode.dfu) {
        lockdownStatus = LockdownStatus.dfuMode;
      } else {
        lockdownStatus = LockdownStatus.notApplicable;
      }

      // Preserve previously verified details on transient query failure if still on same device
      if (modelIdentifier == null &&
          _currentDevice != null &&
          _currentDevice!.serialNumber == serialNumber) {
        modelIdentifier = _currentDevice!.modelIdentifier;
        osVersion = _currentDevice!.osVersion;
        model = _currentDevice!.model;
        name = _currentDevice!.name;
        // Keep previous lockdown status if it was successful
        if (_currentDevice!.lockdownStatus == LockdownStatus.available ||
            _currentDevice!.lockdownStatus == LockdownStatus.setupScreen) {
          lockdownStatus = _currentDevice!.lockdownStatus;
        }
      }

      if (raw.mode == DeviceMode.recovery) {
        name = 'Apple Mobile Device (Recovery Mode)';
        model = 'iPhone (Recovery)';
      } else if (raw.mode == DeviceMode.dfu) {
        name = 'Apple Mobile Device (DFU Diagnostic Mode)';
        model = 'iPhone (DFU)';
      } else if (model == null) {
        name = raw.friendlyName.isNotEmpty
            ? raw.friendlyName
            : 'Apple Mobile Device USB Device';
        model = 'Apple iPhone';
      }

      final statusDesc = raw.mode == DeviceMode.dfu
          ? 'DFU Diagnostic interface active — Restore device to reach Setup screen'
          : raw.mode == DeviceMode.recovery
              ? 'Recovery interface active — Restore device to reach Setup screen'
              : lockdownStatus == LockdownStatus.passcodeLocked
                  ? 'Passcode locked — Put into Recovery Mode and restore'
                  : 'USB communication ready (Setup screen)';

      // 4. Evaluate compatibility against published vendor documentation
      final compatResult = DeviceCompatibilityService.evaluate(
        modelIdentifier: modelIdentifier,
        modelName: model,
        osVersion: osVersion,
        mode: raw.mode,
      );

      final detected = DeviceInfo(
        platform: DevicePlatform.ios,
        name: name,
        model: model,
        modelIdentifier: modelIdentifier,
        chipFamily: compatResult.chipFamily.label,
        serialNumber: serialNumber,
        osVersion: osVersion,
        mode: raw.mode,
        connectionType: 'USB (Lightning / Type-C)',
        hardwareId: raw.instanceId,
        statusDescription: statusDesc,
        compatibilityResult: compatResult,
        lockdownStatus: lockdownStatus,
      );

      // Deduplicate state updates: only notify listeners if state actually changed
      if (_hasDeviceChanged(_currentDevice, detected)) {
        _currentDevice = detected;
        _deviceController.add(_currentDevice);
        notifyListeners();

        AppLogger().hardware(
          'iPhone detected: ${detected.name} (${detected.mode.label})',
          'Model ID: ${detected.modelIdentifier ?? "Unconfirmed"} · iOS: ${detected.osVersion ?? "Unconfirmed"} · Compatibility: ${compatResult.statusBadge}',
        );
      }

      return _currentDevice;
    } catch (e) {
      AppLogger().error('Error scanning for Apple USB devices', e.toString());
      return _currentDevice;
    } finally {
      _isQuerying = false;
    }
  }

  bool _hasDeviceChanged(DeviceInfo? oldDev, DeviceInfo? newDev) {
    if (oldDev == null && newDev == null) return false;
    if (oldDev == null || newDev == null) return true;
    return oldDev.hardwareId != newDev.hardwareId ||
        oldDev.mode != newDev.mode ||
        oldDev.serialNumber != newDev.serialNumber ||
        oldDev.modelIdentifier != newDev.modelIdentifier ||
        oldDev.osVersion != newDev.osVersion ||
        oldDev.lockdownStatus != newDev.lockdownStatus;
  }

  @override
  void dispose() {
    stopMonitoring();
    _deviceController.close();
    super.dispose();
  }
}
