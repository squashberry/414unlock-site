import 'package:flutter/material.dart';

enum AndroidDeviceState {
  disconnected,
  usbConnected,
  normalAndroid,
  normalAndroidLocked,
  setupWizard,
  recovery,
  bootloader,
  fastboot,
  downloadMode,
  unknown,
}

extension AndroidDeviceStateX on AndroidDeviceState {
  String get label {
    switch (this) {
      case AndroidDeviceState.disconnected:
        return 'Disconnected';
      case AndroidDeviceState.usbConnected:
        return 'USB Connected';
      case AndroidDeviceState.normalAndroid:
        return 'Normal Android (Accessible)';
      case AndroidDeviceState.normalAndroidLocked:
        return 'Locked Android';
      case AndroidDeviceState.setupWizard:
        return 'Initial Android Setup';
      case AndroidDeviceState.recovery:
        return 'Recovery Mode';
      case AndroidDeviceState.bootloader:
        return 'Bootloader Mode';
      case AndroidDeviceState.fastboot:
        return 'Fastboot / Bootloader';
      case AndroidDeviceState.downloadMode:
        return 'Download Mode (Odin)';
      case AndroidDeviceState.unknown:
        return 'Assessing Device State...';
    }
  }

  String get userExplanation {
    switch (this) {
      case AndroidDeviceState.disconnected:
        return 'Connect your Android device to this PC using a USB cable.';
      case AndroidDeviceState.usbConnected:
        return 'Device is connected over USB. Assessing low-level protocol access.';
      case AndroidDeviceState.normalAndroid:
        return 'Device is booted normally and accessible with authorized USB debugging.';
      case AndroidDeviceState.normalAndroidLocked:
        return 'The phone is currently protected by the Android lock screen, so normal Android-side interfaces may not be accessible. Supported recovery actions are available below.';
      case AndroidDeviceState.setupWizard:
        return 'The device is waiting at the initial setup screen. Supported recovery options can be performed.';
      case AndroidDeviceState.recovery:
        return 'Recovery interface is detected. Standard device maintenance and recovery operations are available.';
      case AndroidDeviceState.bootloader:
      case AndroidDeviceState.fastboot:
        return 'Device is in Fastboot / Bootloader mode. Protocol commands and low-level diagnostic operations are ready.';
      case AndroidDeviceState.downloadMode:
        return 'Device is in Download Mode. Supported vendor maintenance options are ready.';
      case AndroidDeviceState.unknown:
        return 'Inspecting device hardware endpoints and communication interfaces.';
    }
  }

  Color get badgeColor {
    switch (this) {
      case AndroidDeviceState.disconnected:
        return const Color(0xFF64748B);
      case AndroidDeviceState.normalAndroid:
        return const Color(0xFF22C55E);
      case AndroidDeviceState.setupWizard:
        return const Color(0xFF38BDF8);
      case AndroidDeviceState.normalAndroidLocked:
      case AndroidDeviceState.recovery:
      case AndroidDeviceState.bootloader:
      case AndroidDeviceState.fastboot:
      case AndroidDeviceState.downloadMode:
        return const Color(0xFFF59E0B);
      case AndroidDeviceState.unknown:
      case AndroidDeviceState.usbConnected:
        return const Color(0xFF38BDF8);
    }
  }
}

enum AdbCapability {
  available,
  unauthorized,
  unavailable,
}

extension AdbCapabilityX on AdbCapability {
  String get label {
    switch (this) {
      case AdbCapability.available:
        return 'ADB Available';
      case AdbCapability.unauthorized:
        return 'ADB Unauthorized';
      case AdbCapability.unavailable:
        return 'ADB Unavailable (Normal for some states)';
    }
  }

  Color get color {
    switch (this) {
      case AdbCapability.available:
        return const Color(0xFF22C55E);
      case AdbCapability.unauthorized:
        return const Color(0xFFF59E0B);
      case AdbCapability.unavailable:
        return const Color(0xFF94A3B8);
    }
  }
}

class RecoveryAction {
  final String id;
  final String name;
  final String description;
  final List<AndroidDeviceState> supportedStates;
  final bool isDestructive;
  final bool requiresConfirmation;
  final String? confirmationTitle;
  final String? confirmationMessage;

  const RecoveryAction({
    required this.id,
    required this.name,
    required this.description,
    required this.supportedStates,
    this.isDestructive = false,
    this.requiresConfirmation = false,
    this.confirmationTitle,
    this.confirmationMessage,
  });

  static const List<RecoveryAction> allActions = [
    RecoveryAction(
      id: 'reboot',
      name: 'Reboot Device',
      description: 'Dispatches a safe reboot signal across available USB, ADB, or AT interfaces.',
      supportedStates: [
        AndroidDeviceState.normalAndroid,
        AndroidDeviceState.normalAndroidLocked,
        AndroidDeviceState.setupWizard,
        AndroidDeviceState.recovery,
        AndroidDeviceState.bootloader,
        AndroidDeviceState.fastboot,
        AndroidDeviceState.downloadMode,
        AndroidDeviceState.usbConnected,
      ],
    ),
    RecoveryAction(
      id: 'reboot-recovery',
      name: 'Enter Recovery Mode',
      description: 'Reboots the device into the native Android stock/custom recovery menu.',
      supportedStates: [
        AndroidDeviceState.normalAndroid,
        AndroidDeviceState.setupWizard,
        AndroidDeviceState.fastboot,
      ],
    ),
    RecoveryAction(
      id: 'reboot-bootloader',
      name: 'Enter Bootloader / Fastboot',
      description: 'Transitions the phone into bootloader or fastboot mode.',
      supportedStates: [
        AndroidDeviceState.normalAndroid,
        AndroidDeviceState.setupWizard,
        AndroidDeviceState.recovery,
      ],
    ),
    RecoveryAction(
      id: 'reboot-download',
      name: 'Reboot to Download Mode',
      description: 'Triggers Samsung Download Mode via modem AT protocol (AT+FUS?).',
      supportedStates: [
        AndroidDeviceState.normalAndroid,
        AndroidDeviceState.normalAndroidLocked,
      ],
    ),
    RecoveryAction(
      id: 'factory-reset',
      name: 'Factory Reset (Wipe Data)',
      description: 'Erases all user data stored on the device via Fastboot (-w) or Recovery.',
      supportedStates: [
        AndroidDeviceState.recovery,
        AndroidDeviceState.fastboot,
        AndroidDeviceState.bootloader,
      ],
      isDestructive: true,
      requiresConfirmation: true,
      confirmationTitle: 'Confirm Factory Reset',
      confirmationMessage:
          'This will erase user data stored on the device.\n\nThe operation cannot be undone.\n\nNote: A factory reset restores device storage but does not remove account or security locks.',
    ),
  ];
}
