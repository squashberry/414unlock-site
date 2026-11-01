import '../compatibility/device_compatibility_service.dart';

enum DevicePlatform {
  ios,
  android,
}

/// iPhone hardware archetype for realistic device illustration matching connected model.
enum IPhoneDesignFamily {
  /// iPhone 5s, 6, 6s, 7, 8, SE (1st, 2nd, 3rd gen) with Touch ID Home button
  touchId,
  /// iPhone X, XS, XR, 11, 12, 13, 14 with Face ID notch
  notched,
  /// iPhone 14 Pro, 15, 16 series with Dynamic Island
  dynamicIsland,
}

enum DeviceMode {
  normal,
  recovery,
  dfu,
  adb,
  adbUnauthorized,
  fastboot,
  sideload,
  mtp,
  unknown,
}

extension DeviceModeX on DeviceMode {
  String get label {
    switch (this) {
      case DeviceMode.normal:
        return 'Normal Mode';
      case DeviceMode.recovery:
        return 'Recovery Mode';
      case DeviceMode.dfu:
        return 'DFU Mode (Diagnostic)';
      case DeviceMode.adb:
        return 'ADB Authorized';
      case DeviceMode.adbUnauthorized:
        return 'ADB Unauthorized (Check Phone)';
      case DeviceMode.fastboot:
        return 'Fastboot / Bootloader';
      case DeviceMode.sideload:
        return 'Sideload Mode';
      case DeviceMode.mtp:
        return 'USB Device (MTP)';
      case DeviceMode.unknown:
        return 'Connected';
    }
  }

  bool get isDiagnosticState =>
      this == DeviceMode.recovery || this == DeviceMode.dfu;
}

/// Status of the lockdown service query for detailed device information.
enum LockdownStatus {
  /// Lockdown query succeeded and device info was retrieved.
  available,
  /// Device detected at the Hello / Setup / Activation Lock screen.
  setupScreen,
  /// Device is passcode locked; user must restore via Recovery/DFU mode to reach Setup screen.
  passcodeLocked,
  /// Device is in Recovery Mode.
  recoveryMode,
  /// Device is in DFU Diagnostic Mode.
  dfuMode,
  /// Lockdown service was not queried (device in recovery/DFU mode).
  notApplicable,
  /// Device is locked or untrusted.
  untrustedOrLocked,
  /// Lockdown connection timed out.
  timeout,
  /// Usbmuxd service is not available.
  serviceUnavailable,
  /// Query failed for an unknown reason.
  failed,
}

extension LockdownStatusX on LockdownStatus {
  String get userMessage {
    switch (this) {
      case LockdownStatus.available:
        return 'Device information verified';
      case LockdownStatus.setupScreen:
        return 'Device detected at Setup / Activation Lock screen — Ready for unlock';
      case LockdownStatus.passcodeLocked:
        return 'Device is passcode-locked. Put into Recovery Mode and restore via iTunes to reach the Setup screen.';
      case LockdownStatus.recoveryMode:
        return 'Device in Recovery Mode. Restore via iTunes/Finder to reach the Setup screen.';
      case LockdownStatus.dfuMode:
        return 'Device in DFU Mode. Restore via iTunes/Finder to reach the Setup screen.';
      case LockdownStatus.notApplicable:
        return 'Diagnostic mode active — restore required';
      case LockdownStatus.untrustedOrLocked:
        return 'Device is locked. If passcode-locked, put into Recovery Mode and restore.';
      case LockdownStatus.timeout:
        return 'Device query timed out — reconnect cable or restart iPhone';
      case LockdownStatus.serviceUnavailable:
        return 'Apple Mobile Device Service not responding';
      case LockdownStatus.failed:
        return 'Could not retrieve device details';
    }
  }

  bool get showsWarning =>
      this == LockdownStatus.passcodeLocked ||
      this == LockdownStatus.untrustedOrLocked ||
      this == LockdownStatus.timeout ||
      this == LockdownStatus.serviceUnavailable ||
      this == LockdownStatus.failed;
}

class DeviceInfo {
  final DevicePlatform platform;
  final String name;
  final String? model;
  final String? modelIdentifier;
  final String? chipFamily;
  final String? manufacturer;
  final String? serialNumber;
  final String? osVersion;
  final DeviceMode mode;
  final String connectionType;
  final String? hardwareId;
  final String statusDescription;
  final DeviceCompatibilityResult? compatibilityResult;
  final LockdownStatus lockdownStatus;
  final DateTime connectedAt;

  DeviceInfo({
    required this.platform,
    required this.name,
    this.model,
    this.modelIdentifier,
    this.chipFamily,
    this.manufacturer,
    this.serialNumber,
    this.osVersion,
    this.mode = DeviceMode.normal,
    this.connectionType = 'USB',
    this.hardwareId,
    this.statusDescription = 'USB communication available',
    this.compatibilityResult,
    this.lockdownStatus = LockdownStatus.available,
    DateTime? connectedAt,
  }) : connectedAt = connectedAt ?? DateTime.now();

  String get modelName => (model != null && model!.isNotEmpty) ? model! : name;

  /// Whether device is in a state ready to begin the unlock process (normal/setup mode, not locked or needing restore)
  bool get isReadyForUnlock =>
      mode == DeviceMode.normal &&
      (lockdownStatus == LockdownStatus.available ||
          lockdownStatus == LockdownStatus.setupScreen);

  /// Design archetype for realistic UI illustration
  IPhoneDesignFamily get iphoneDesignFamily {
    final lowerName = name.toLowerCase();
    final lowerModel = (model ?? '').toLowerCase();
    final lowerId = (modelIdentifier ?? '').toLowerCase();
    final combined = '$lowerName $lowerModel $lowerId';

    if (combined.contains('se') ||
        combined.contains('iphone 5') ||
        combined.contains('iphone 6') ||
        combined.contains('iphone 7') ||
        combined.contains('iphone 8') ||
        lowerId.startsWith('iphone6,') ||
        lowerId.startsWith('iphone7,') ||
        lowerId.startsWith('iphone8,') ||
        lowerId.startsWith('iphone9,') ||
        lowerId.startsWith('iphone10,1') ||
        lowerId.startsWith('iphone10,2') ||
        lowerId.startsWith('iphone10,4') ||
        lowerId.startsWith('iphone10,5') ||
        lowerId.startsWith('iphone12,8') ||
        lowerId.startsWith('iphone14,6')) {
      return IPhoneDesignFamily.touchId;
    }

    if (combined.contains('14 pro') ||
        combined.contains('15') ||
        combined.contains('16') ||
        lowerId.startsWith('iphone15,2') ||
        lowerId.startsWith('iphone15,3') ||
        lowerId.startsWith('iphone15,4') ||
        lowerId.startsWith('iphone15,5') ||
        lowerId.startsWith('iphone16,') ||
        lowerId.startsWith('iphone17,')) {
      return IPhoneDesignFamily.dynamicIsland;
    }

    if (combined.contains('iphone x') ||
        combined.contains('xr') ||
        combined.contains('xs') ||
        combined.contains('11') ||
        combined.contains('12') ||
        combined.contains('13') ||
        combined.contains('14')) {
      return IPhoneDesignFamily.notched;
    }

    return IPhoneDesignFamily.dynamicIsland;
  }

  /// Whether device requires manual restore/wipe to reach the Hello / Setup screen
  bool get requiresRestore =>
      mode.isDiagnosticState ||
      lockdownStatus == LockdownStatus.passcodeLocked ||
      lockdownStatus == LockdownStatus.recoveryMode ||
      lockdownStatus == LockdownStatus.dfuMode;

  /// Legitimate detected hardware identifier and its kind without fabrication.
  /// Returns (identifierKind, sanitizedIdentifier) where kind is 'imei', 'udid', or 'serial'.
  /// Returns null if no valid hardware identifier is present.
  (String, String)? get detectedIdentifier {
    final raw = (serialNumber != null && serialNumber!.trim().isNotEmpty)
        ? serialNumber!.trim()
        : (hardwareId != null && hardwareId!.trim().isNotEmpty
            ? _extractFromHardwareId(hardwareId!.trim())
            : null);
    if (raw == null || raw.isEmpty) return null;
    final sanitized = raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (sanitized.isEmpty) return null;

    if (RegExp(r'^\d{14,16}$').hasMatch(sanitized)) {
      return ('imei', sanitized);
    }
    if (sanitized.length >= 20 && sanitized.length <= 64) {
      return ('udid', sanitized);
    }
    if (sanitized.length >= 6 && sanitized.length <= 64) {
      return ('serial', sanitized);
    }
    return null;
  }

  static String? _extractFromHardwareId(String hid) {
    final parts = hid.split(r'\');
    if (parts.length > 2) {
      final last = parts.last;
      if (!last.contains('&') && last.length >= 6) {
        return last;
      }
    }
    return null;
  }

  /// Safe masked identifier label, e.g. "Serial Number (masked)" or "IMEI (masked)"
  String get identifierLabel {
    final pair = detectedIdentifier;
    if (pair == null) return 'Identifier';
    switch (pair.$1) {
      case 'imei':
        return 'IMEI (masked)';
      case 'udid':
        return 'UDID (masked)';
      case 'serial':
      default:
        return 'Serial Number (masked)';
    }
  }

  /// Privacy-safe masked identifier, e.g. "•••• •••• ABCD"
  String get maskedIdentifier {
    final pair = detectedIdentifier;
    if (pair == null) return 'Unavailable';
    final ident = pair.$2;
    if (ident.length <= 4) return '•••• $ident';
    return '•••• •••• ${ident.substring(ident.length - 4)}';
  }

  Map<String, dynamic> toDiagnosticMap() {
    return {
      'Platform': platform.name.toUpperCase(),
      'Name': name,
      if (model != null) 'Model': model,
      if (modelIdentifier != null) 'Model Identifier': modelIdentifier,
      if (chipFamily != null) 'Family': chipFamily,
      if (manufacturer != null) 'Manufacturer': manufacturer,
      'Hardware Identifier': maskedIdentifier, // Masked to protect privacy in logs
      if (osVersion != null) 'OS Version': osVersion,
      'Mode': mode.label,
      'Connection': connectionType,
      'Status': statusDescription,
      if (compatibilityResult != null) 'Compatibility': compatibilityResult!.statusBadge,
      if (lockdownStatus.showsWarning) 'Lockdown Status': lockdownStatus.name,
      'Detected At': connectedAt.toIso8601String(),
    };
  }
}
