import '../device/device_info.dart';

enum ChipFamily {
  a7ToA11,
  a12Plus,
  unconfirmed,
}

extension ChipFamilyX on ChipFamily {
  String get label {
    switch (this) {
      case ChipFamily.a7ToA11:
        return 'Older A7–A11 Family';
      case ChipFamily.a12Plus:
        return 'A12+ Modern Family';
      case ChipFamily.unconfirmed:
        return 'Unconfirmed Architecture';
    }
  }
}

enum CompatibilityStatus {
  verifiedSupported,
  firmwareOutsideRange,
  unconfirmed,
  unsupported,
}

extension CompatibilityStatusX on CompatibilityStatus {
  String get label {
    switch (this) {
      case CompatibilityStatus.verifiedSupported:
        return 'Vendor Stated Support Available';
      case CompatibilityStatus.firmwareOutsideRange:
        return 'Firmware Outside Vendor Reported Range';
      case CompatibilityStatus.unconfirmed:
        return 'Compatibility Not Confirmed';
      case CompatibilityStatus.unsupported:
        return 'Unsupported Hardware';
    }
  }
}

class DeviceCompatibilityResult {
  final CompatibilityStatus status;
  final String statusBadge;
  final ChipFamily chipFamily;
  final String modelName;
  final String? modelIdentifier;
  final String? osVersion;
  final bool hasNoCellularSignalLimitation;
  final List<String> limitations;
  final String explanation;
  final String officialAppleRecoveryUrl;
  final List<String> officialRecoveryOptions;

  const DeviceCompatibilityResult({
    required this.status,
    required this.statusBadge,
    required this.chipFamily,
    required this.modelName,
    this.modelIdentifier,
    this.osVersion,
    required this.hasNoCellularSignalLimitation,
    required this.limitations,
    required this.explanation,
    this.officialAppleRecoveryUrl = 'https://support.apple.com/en-us/108934',
    required this.officialRecoveryOptions,
  });

  bool get isConfirmed => status == CompatibilityStatus.verifiedSupported;
}

class DeviceCompatibilityService {
  static const String appleSupportGuideUrl =
      'https://support.apple.com/en-us/108934';

  static const List<String> standardAppleRecoveryOptions = [
    'Sign in with the Apple Account originally associated with this device.',
    'Ask the previous owner to remove the device from their account at icloud.com/find.',
    'Contact Apple Support and submit an Activation Lock support request with valid proof of purchase.',
  ];

  /// Set of ProductType model identifiers belonging to the A7–A11 legacy family (iPhone 5s through iPhone X)
  static const Set<String> _a7ToA11Identifiers = {
    // iPhone 5s
    'iPhone6,1', 'iPhone6,2',
    // iPhone 6 / 6 Plus
    'iPhone7,1', 'iPhone7,2',
    // iPhone 6s / 6s Plus / SE 1st gen
    'iPhone8,1', 'iPhone8,2', 'iPhone8,4',
    // iPhone 7 / 7 Plus
    'iPhone9,1', 'iPhone9,2', 'iPhone9,3', 'iPhone9,4',
    // iPhone 8 / 8 Plus
    'iPhone10,1', 'iPhone10,2', 'iPhone10,4', 'iPhone10,5',
    // iPhone X
    'iPhone10,3', 'iPhone10,6',
    // Legacy iPads (A7–A10X)
    'iPad4,1', 'iPad4,2', 'iPad4,3', 'iPad4,4', 'iPad4,5', 'iPad4,6',
    'iPad4,7', 'iPad4,8', 'iPad4,9', 'iPad5,1', 'iPad5,2', 'iPad5,3',
    'iPad5,4', 'iPad6,3', 'iPad6,4', 'iPad6,7', 'iPad6,8', 'iPad6,11',
    'iPad6,12', 'iPad7,1', 'iPad7,2', 'iPad7,3', 'iPad7,4', 'iPad7,5',
    'iPad7,6', 'iPad7,11', 'iPad7,12',
  };

  /// Set of ProductType model identifiers belonging to the A12+ modern family (iPhone XR/XS through iPhone 16 generation)
  static const Set<String> _a12PlusIdentifiers = {
    // iPhone XS, XS Max, XR
    'iPhone11,2', 'iPhone11,4', 'iPhone11,6', 'iPhone11,8',
    // iPhone 11 series & SE 2nd gen
    'iPhone12,1', 'iPhone12,3', 'iPhone12,5', 'iPhone12,8',
    // iPhone 12 series
    'iPhone13,1', 'iPhone13,2', 'iPhone13,3', 'iPhone13,4',
    // iPhone 13 series & SE 3rd gen
    'iPhone14,2', 'iPhone14,3', 'iPhone14,4', 'iPhone14,5', 'iPhone14,6',
    // iPhone 14 series
    'iPhone14,7', 'iPhone14,8', 'iPhone15,2', 'iPhone15,3',
    // iPhone 15 series
    'iPhone15,4', 'iPhone15,5', 'iPhone16,1', 'iPhone16,2',
    // iPhone 16 series
    'iPhone17,1', 'iPhone17,2', 'iPhone17,3', 'iPhone17,4',
    // Modern iPads (A12, A14, A15, M-series)
    'iPad8,1', 'iPad8,2', 'iPad8,3', 'iPad8,4', 'iPad8,5', 'iPad8,6',
    'iPad8,7', 'iPad8,8', 'iPad8,9', 'iPad8,10', 'iPad8,11', 'iPad8,12',
    'iPad11,1', 'iPad11,2', 'iPad11,3', 'iPad11,4', 'iPad11,6', 'iPad11,7',
    'iPad12,1', 'iPad12,2', 'iPad13,1', 'iPad13,2', 'iPad13,4', 'iPad13,5',
    'iPad13,6', 'iPad13,7', 'iPad13,8', 'iPad13,9', 'iPad13,10', 'iPad13,11',
    'iPad13,16', 'iPad13,17', 'iPad13,18', 'iPad13,19', 'iPad14,1', 'iPad14,2',
    'iPad14,3', 'iPad14,4', 'iPad14,5', 'iPad14,6', 'iPad14,8', 'iPad14,9',
    'iPad14,10', 'iPad14,11', 'iPad16,1', 'iPad16,2', 'iPad16,3', 'iPad16,4',
    'iPad16,5', 'iPad16,6',
  };

  /// Evaluates an Apple device's model and firmware against published vendor compatibility data
  static DeviceCompatibilityResult evaluate({
    String? modelIdentifier,
    String? modelName,
    String? osVersion,
    DeviceMode mode = DeviceMode.normal,
  }) {
    final cleanId = modelIdentifier?.trim() ?? '';
    final cleanName = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : (cleanId.isNotEmpty ? cleanId : 'Apple Device');
    final cleanOs = osVersion?.trim() ?? '';

    // If device is in Recovery or DFU mode, full firmware cannot be verified via normal lockdown
    if (mode == DeviceMode.recovery || mode == DeviceMode.dfu) {
      return DeviceCompatibilityResult(
        status: CompatibilityStatus.unconfirmed,
        statusBadge: 'Diagnostic Mode · Unconfirmed',
        chipFamily: _determineChipFamily(cleanId, cleanName),
        modelName: cleanName,
        modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
        osVersion: cleanOs.isNotEmpty ? cleanOs : null,
        hasNoCellularSignalLimitation: false,
        limitations: [
          'Device is in ${mode.label}. Exact firmware version cannot be verified through standard communication.',
          'Restore or recovery operations should be performed using Apple iTunes or Finder.',
        ],
        explanation:
            'The device is in ${mode.label}. Firmware and hardware state cannot be confirmed until the device boots into standard operating mode.',
        officialRecoveryOptions: standardAppleRecoveryOptions,
      );
    }

    final chipFamily = _determineChipFamily(cleanId, cleanName);

    // If neither model identifier nor family can be confirmed
    if (chipFamily == ChipFamily.unconfirmed) {
      return DeviceCompatibilityResult(
        status: CompatibilityStatus.unconfirmed,
        statusBadge: 'Compatibility Not Confirmed',
        chipFamily: ChipFamily.unconfirmed,
        modelName: cleanName,
        modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
        osVersion: cleanOs.isNotEmpty ? cleanOs : null,
        hasNoCellularSignalLimitation: false,
        limitations: [
          'Hardware model identifier could not be verified against vendor documentation.',
          'Support cannot be confirmed for unrecognized device models.',
        ],
        explanation:
            'The device model could not be verified against published vendor documentation. Compatibility is unconfirmed.',
        officialRecoveryOptions: standardAppleRecoveryOptions,
      );
    }

    // If OS version is missing or unverified
    if (cleanOs.isEmpty) {
      return DeviceCompatibilityResult(
        status: CompatibilityStatus.unconfirmed,
        statusBadge: 'Compatibility Not Confirmed',
        chipFamily: chipFamily,
        modelName: cleanName,
        modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
        osVersion: null,
        hasNoCellularSignalLimitation: chipFamily == ChipFamily.a12Plus,
        limitations: [
          'Installed iOS version was not reported by the device.',
          'Vendor compatibility is strictly firmware-dependent. Without verified firmware, support cannot be confirmed.',
        ],
        explanation:
            'The installed firmware version is unconfirmed. Compatibility reported by the software vendor requires exact firmware verification.',
        officialRecoveryOptions: standardAppleRecoveryOptions,
      );
    }

    final parsedVersion = _parseVersion(cleanOs);

    // Evaluation for A12+ Modern Family (iPhone XR / XS through iPhone 16 series)
    if (chipFamily == ChipFamily.a12Plus) {
      // Vendor states support for A12+ on iOS 17.0 through 17.5.1 / 17.6 beta
      final isSupportedA12Firmware = _isA12SupportedFirmware(parsedVersion);

      if (isSupportedA12Firmware) {
        return DeviceCompatibilityResult(
          status: CompatibilityStatus.verifiedSupported,
          statusBadge: 'Vendor Support Available (No Cellular Signal)',
          chipFamily: ChipFamily.a12Plus,
          modelName: cleanName,
          modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
          osVersion: cleanOs,
          hasNoCellularSignalLimitation: true,
          limitations: [
            'No-Cellular-Signal Service Limitation: The software vendor states that this service potentially leaves the device without normal cellular calling and SMS capabilities.',
            'Wi-Fi and internet-connected applications (App Store, Safari, FaceTime over Wi-Fi) may remain usable.',
            'Traditional mobile carrier calls, SMS text messages, and cellular data will not work as expected.',
            'Internet-based communication is not an equivalent replacement for an ordinary, carrier-connected iPhone.',
            'Firmware locked: Updating or restoring iOS after service may re-lock the device.',
          ],
          explanation:
              'The model ($cleanName) and firmware (iOS $cleanOs) are within the vendor\'s published supported range. A no-cellular-signal limitation applies.',
          officialRecoveryOptions: standardAppleRecoveryOptions,
        );
      } else {
        return DeviceCompatibilityResult(
          status: CompatibilityStatus.firmwareOutsideRange,
          statusBadge: 'Firmware Outside Vendor Reported Range',
          chipFamily: ChipFamily.a12Plus,
          modelName: cleanName,
          modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
          osVersion: cleanOs,
          hasNoCellularSignalLimitation: true,
          limitations: [
            'Detected firmware (iOS $cleanOs) is outside the vendor\'s reported compatible range (iOS 17.0 – 17.5.1 for A12+).',
            'Unconfirmed or newer firmware updates (e.g. iOS 18 branches) are not confirmed to be supported by the vendor.',
            'Do not attempt unauthorized downgrade or modified firmware installations.',
          ],
          explanation:
              'The detected firmware (iOS $cleanOs) on this $cleanName is outside the vendor\'s currently stated supported range. Compatibility is not confirmed.',
          officialRecoveryOptions: standardAppleRecoveryOptions,
        );
      }
    }

    // Evaluation for A7–A11 Older Family (iPhone 5s through iPhone X)
    if (chipFamily == ChipFamily.a7ToA11) {
      final isSupportedA7Firmware = _isA7SupportedFirmware(parsedVersion, cleanId);

      if (isSupportedA7Firmware) {
        return DeviceCompatibilityResult(
          status: CompatibilityStatus.verifiedSupported,
          statusBadge: 'Vendor Stated Support Available (Legacy Family)',
          chipFamily: ChipFamily.a7ToA11,
          modelName: cleanName,
          modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
          osVersion: cleanOs,
          hasNoCellularSignalLimitation: false,
          limitations: [
            'Legacy A7–A11 family: service availability depends on exact hardware revision and supported firmware branch.',
            'Devices running unlisted or newer firmware updates are not confirmed by the vendor.',
          ],
          explanation:
              'This device ($cleanName, iOS $cleanOs) is reported as supported by the vendor for the older A7–A11 hardware family.',
          officialRecoveryOptions: standardAppleRecoveryOptions,
        );
      } else {
        return DeviceCompatibilityResult(
          status: CompatibilityStatus.firmwareOutsideRange,
          statusBadge: 'Firmware Outside Vendor Reported Range',
          chipFamily: ChipFamily.a7ToA11,
          modelName: cleanName,
          modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
          osVersion: cleanOs,
          hasNoCellularSignalLimitation: false,
          limitations: [
            'Detected firmware (iOS $cleanOs) is outside the vendor\'s reported range for this older device family.',
            'Firmware support differs per model and cannot be assumed.',
          ],
          explanation:
              'The detected firmware (iOS $cleanOs) on this $cleanName is outside the vendor\'s stated coverage range. Compatibility is not confirmed.',
          officialRecoveryOptions: standardAppleRecoveryOptions,
        );
      }
    }

    return DeviceCompatibilityResult(
      status: CompatibilityStatus.unconfirmed,
      statusBadge: 'Compatibility Not Confirmed',
      chipFamily: ChipFamily.unconfirmed,
      modelName: cleanName,
      modelIdentifier: cleanId.isNotEmpty ? cleanId : null,
      osVersion: cleanOs.isNotEmpty ? cleanOs : null,
      hasNoCellularSignalLimitation: false,
      limitations: [
        'Device configuration could not be verified against vendor documentation.',
      ],
      explanation: 'Compatibility is not confirmed for this device.',
      officialRecoveryOptions: standardAppleRecoveryOptions,
    );
  }

  static ChipFamily _determineChipFamily(String identifier, String modelName) {
    if (identifier.isNotEmpty) {
      if (_a12PlusIdentifiers.contains(identifier)) {
        return ChipFamily.a12Plus;
      }
      if (_a7ToA11Identifiers.contains(identifier)) {
        return ChipFamily.a7ToA11;
      }
    }

    // Fallback: check model name if identifier is not available
    final lowerName = modelName.toLowerCase();
    if (lowerName.contains('iphone 16') ||
        lowerName.contains('iphone 15') ||
        lowerName.contains('iphone 14') ||
        lowerName.contains('iphone 13') ||
        lowerName.contains('iphone 12') ||
        lowerName.contains('iphone 11') ||
        lowerName.contains('iphone xr') ||
        lowerName.contains('iphone xs') ||
        lowerName.contains('se (2nd gen)') ||
        lowerName.contains('se (3rd gen)')) {
      return ChipFamily.a12Plus;
    }

    if (lowerName.contains('iphone x') ||
        lowerName.contains('iphone 8') ||
        lowerName.contains('iphone 7') ||
        lowerName.contains('iphone 6s') ||
        lowerName.contains('iphone 6') ||
        lowerName.contains('iphone 5s') ||
        lowerName.contains('se (1st gen)')) {
      return ChipFamily.a7ToA11;
    }

    return ChipFamily.unconfirmed;
  }

  static List<int> _parseVersion(String versionString) {
    try {
      final cleaned = versionString.replaceAll(RegExp(r'[^0-9.]'), '');
      final parts = cleaned.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      while (parts.length < 3) {
        parts.add(0);
      }
      return parts;
    } catch (_) {
      return [0, 0, 0];
    }
  }

  /// Checks if version falls within iOS 17.0 to 17.6 beta
  static bool _isA12SupportedFirmware(List<int> v) {
    final major = v.isNotEmpty ? v[0] : 0;
    final minor = v.length > 1 ? v[1] : 0;
    final patch = v.length > 2 ? v[2] : 0;

    // A12+ reported range: iOS 17.0 up to 17.5.1 / 17.6 beta
    if (major == 17) {
      if (minor < 5) return true;
      if (minor == 5 && patch <= 1) return true;
      if (minor == 6) return true; // 17.6 beta
      return false;
    }
    return false;
  }

  /// Checks if version falls within older A7–A11 supported firmware bounds
  static bool _isA7SupportedFirmware(List<int> v, String identifier) {
    final major = v.isNotEmpty ? v[0] : 0;

    // iPhone X / iPhone 8 supported up to iOS 16.7.x
    if (identifier.startsWith('iPhone10,')) {
      return major <= 16;
    }
    // iPhone 7 supported up to iOS 15.8.x
    if (identifier.startsWith('iPhone9,')) {
      return major <= 15;
    }
    // iPhone 6s / SE 1st gen supported up to iOS 15.8.x
    if (identifier.startsWith('iPhone8,')) {
      return major <= 15;
    }
    // iPhone 6 / 5s supported up to iOS 12.5.x
    if (identifier.startsWith('iPhone7,') || identifier.startsWith('iPhone6,')) {
      return major <= 12;
    }
    // Generic fallback for older devices: major <= 16
    return major >= 12 && major <= 16;
  }
}
