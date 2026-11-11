import 'dart:async';
import 'device_detection_service.dart';
import 'device_info.dart';
import '../logging/app_logger.dart';
import 'apple_device_database.dart';
import 'apple_usbmux_client.dart';
import 'external_idevice_tools.dart';
import 'native_windows_usb.dart';
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

      String name = 'Apple iPhone';
      String? model;
      String? modelIdentifier = raw.productType;
      String? chipFamily = raw.chipFamily;
      String? osVersion;
      String? serialNumber = raw.serialNumber;
      LockdownStatus lockdownStatus = LockdownStatus.available;

      if (raw.mode == DeviceMode.recovery || raw.mode == DeviceMode.dfu) {
        lockdownStatus = raw.mode == DeviceMode.recovery
            ? LockdownStatus.recoveryMode
            : LockdownStatus.dfuMode;

        // 2a. Query libirecovery (irecovery -q) if tool is available on system
        try {
          final recInfo = await ExternalIdeviceTools.queryRecoveryDevice();
          if (recInfo != null) {
            if (recInfo.productType != null) {
              modelIdentifier = recInfo.productType;
            }
            if (recInfo.model != null) {
              model = recInfo.model;
            }
            if (recInfo.serialNumber != null && recInfo.serialNumber!.isNotEmpty) {
              serialNumber = recInfo.serialNumber;
            }
            if (recInfo.chipFamily != null) {
              chipFamily = recInfo.chipFamily;
            }
          }
        } catch (_) {}

        if (modelIdentifier != null && model == null) {
          model = AppleDeviceDatabase.mapProductType(modelIdentifier);
        }

        name = raw.mode == DeviceMode.recovery
            ? (model != null ? '$model (Recovery Mode)' : 'Apple Mobile Device (Recovery Mode)')
            : (model != null ? '$model (DFU Mode)' : 'Apple Mobile Device (DFU Diagnostic Mode)');
      } else {
        // Normal mode (including Setup / Hello / Activation-Locked screen)
        lockdownStatus = LockdownStatus.setupScreen;

        // 2b. Query Usbmuxd for connected entries
        List<UsbmuxDeviceEntry> usbmuxEntries = [];
        try {
          usbmuxEntries = await AppleUsbmuxClient.listConnectedDevices(
            timeout: const Duration(milliseconds: 800),
          );
        } catch (_) {}

        if (usbmuxEntries.isNotEmpty) {
          serialNumber = usbmuxEntries.first.serialNumber;

          // 3. Query Lockdown service via usbmuxd tunnel for public keys
          // Queries individual public keys (ProductType, ProductVersion, etc.)
          // which succeed even on Activation-locked / Hello-screen devices without pairing.
          try {
            final (lockdownInfo, errorReason) = await AppleUsbmuxClient.queryLockdownWithRawResponse(
              usbmuxEntries.first.deviceId,
              timeout: const Duration(milliseconds: 2500),
            );

            if (lockdownInfo != null) {
              if (lockdownInfo.productType.isNotEmpty) {
                modelIdentifier = lockdownInfo.productType;
                model = AppleDeviceDatabase.mapProductType(lockdownInfo.productType);
              }
              if (lockdownInfo.productVersion.isNotEmpty) {
                osVersion = lockdownInfo.productVersion;
              }
              if (lockdownInfo.deviceName != null && lockdownInfo.deviceName!.isNotEmpty) {
                name = lockdownInfo.deviceName!;
              } else if (model != null) {
                name = model;
              }

              if (lockdownInfo.activationState == 'Unactivated') {
                lockdownStatus = LockdownStatus.setupScreen;
              } else {
                lockdownStatus = LockdownStatus.available;
              }
            } else {
              // Lockdownd direct query yielded no keys; check optional ideviceinfo helper
              final idev = await ExternalIdeviceTools.queryDeviceInfo();
              if (idev != null) {
                if (idev.productType != null) {
                  modelIdentifier = idev.productType;
                  model = AppleDeviceDatabase.mapProductType(idev.productType!);
                }
                if (idev.productVersion != null) {
                  osVersion = idev.productVersion;
                }
                if (idev.deviceName != null && idev.deviceName!.isNotEmpty) {
                  name = idev.deviceName!;
                }
              }

              if (errorReason == 'TIMEOUT') {
                lockdownStatus = LockdownStatus.timeout;
              } else {
                // Device is present on USB at Setup / Activation Lock screen
                lockdownStatus = LockdownStatus.setupScreen;
              }
            }
          } catch (e) {
            AppLogger().warning('Lockdown query exception: $e');
            lockdownStatus = LockdownStatus.setupScreen;
          }
        } else {
          // Usbmuxd returned no devices, but native USB detected Apple hardware!
          final idev = await ExternalIdeviceTools.queryDeviceInfo();
          if (idev != null) {
            if (idev.productType != null) {
              modelIdentifier = idev.productType;
              model = AppleDeviceDatabase.mapProductType(idev.productType!);
            }
            if (idev.productVersion != null) {
              osVersion = idev.productVersion;
            }
          }

          lockdownStatus = LockdownStatus.setupScreen;
        }

        if (model == null && modelIdentifier != null) {
          model = AppleDeviceDatabase.mapProductType(modelIdentifier);
        }
        if (model != null && (name == 'Apple iPhone' || name.isEmpty)) {
          name = model;
        } else if (model == null) {
          name = raw.friendlyName.isNotEmpty
              ? raw.friendlyName
              : 'Apple Mobile Device USB Device';
          model = 'Apple iPhone';
        }
      }

      // Preserve previously verified details on transient query failure if still on same device
      if (modelIdentifier == null &&
          _currentDevice != null &&
          _currentDevice!.serialNumber == serialNumber) {
        modelIdentifier = _currentDevice!.modelIdentifier;
        osVersion = _currentDevice!.osVersion;
        model = _currentDevice!.model;
        name = _currentDevice!.name;
        if (_currentDevice!.lockdownStatus == LockdownStatus.available ||
            _currentDevice!.lockdownStatus == LockdownStatus.setupScreen) {
          lockdownStatus = _currentDevice!.lockdownStatus;
        }
      }

      // Resolve chip family if still missing
      if (chipFamily == null && modelIdentifier != null) {
        chipFamily = AppleDeviceDatabase.lookupChipFamilyByProductType(modelIdentifier);
      }
      if (chipFamily == null && raw.cpid != null) {
        chipFamily = AppleDeviceDatabase.lookupChipFamilyByCpid(raw.cpid!);
      }

      final statusDesc = raw.mode == DeviceMode.dfu
          ? 'DFU Diagnostic interface active — Restore device to reach Setup screen'
          : raw.mode == DeviceMode.recovery
              ? 'Recovery interface active — Restore device to reach Setup screen'
              : 'USB communication ready (Setup / Activation Lock screen)';

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
        chipFamily: chipFamily ?? compatResult.chipFamily.label,
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
