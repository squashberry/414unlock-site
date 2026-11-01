import 'dart:io';
import '../device/apple_usbmux_client.dart';
import 'prerequisite.dart';
import 'windows_checker_helper.dart';

class ApplePrerequisites {
  static List<Prerequisite> getPrerequisites() {
    return [
      Prerequisite(
        id: 'apple_software',
        displayName: 'Apple Devices / iTunes Software',
        description:
            'Official Apple management software required for USB pairing and communication protocols with iOS hardware.',
        officialDownloadUrl:
            'https://secure-appldnld.apple.com/itunes12/001-80053-20210422-E8A3B28C-A3B2-11EB-BE07-CE1B67FC6302/iTunes64Setup.exe',
        checkFunction: () async {
          // 1. Direct file check for iTunes
          final itunesPath = WindowsCheckerHelper.findFirstExisting([
            r'C:\Program Files\iTunes\iTunes.exe',
            r'C:\Program Files (x86)\iTunes\iTunes.exe',
            r'%LOCALAPPDATA%\Microsoft\WindowsApps\AppleDevices.exe',
          ]);

          if (itunesPath != null) {
            return PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'iTunes (Win32)',
              message: 'iTunes installation verified at: $itunesPath',
            );
          }

          // 2. Fast check via cached registry uninstall records
          final entries = await WindowsCheckerHelper.queryWindowsUninstallEntries('iTunes');
          if (entries.isNotEmpty) {
            final version = entries.first['DisplayVersion'] ?? 'Installed';
            return PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: version,
              message: 'iTunes records detected in Windows ($version).',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message: 'iTunes was not detected. iTunes is required for Apple device communication.',
          );
        },
      ),
      Prerequisite(
        id: 'apple_mobile_device_support',
        displayName: 'Apple Mobile Device Support Service',
        description:
            'Background daemon and drivers managing USB connectivity and handshake sessions with Apple hardware.',
        officialDownloadUrl:
            'https://support.apple.com/en-us/HT210384',
        checkFunction: () async {
          // 1. Direct file check for Apple Mobile Device Service
          final serviceExe = WindowsCheckerHelper.findFirstExisting([
            r'C:\Program Files\Common Files\Apple\Mobile Device Support\AppleMobileDeviceService.exe',
            r'C:\Program Files (x86)\Common Files\Apple\Mobile Device Support\AppleMobileDeviceService.exe',
          ]);

          if (serviceExe != null) {
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'Active Service',
              message: 'Apple Mobile Device Support service files located.',
            );
          }

          // 2. Check if usbmuxd is actively listening on port 27015
          final isListening = await AppleUsbmuxClient.isServiceAvailable();
          if (isListening) {
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'usbmuxd (Active)',
              message: 'Apple Mobile Device Service is actively running on system port 27015.',
            );
          }

          // 3. Fast check via cached registry uninstall records
          final entries = await WindowsCheckerHelper.queryWindowsUninstallEntries('Apple Mobile Device Support');
          if (entries.isNotEmpty) {
            final version = entries.first['DisplayVersion'] ?? 'Installed';
            return PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: version,
              message: 'Apple Mobile Device Support found in Windows records ($version).',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message: 'Apple Mobile Device Support is not installed.',
          );
        },
      ),
      Prerequisite(
        id: 'apple_usb_driver',
        displayName: 'Apple Mobile Device USB Driver',
        description:
            'Windows kernel driver (usbaapl64.sys) enabling low-level USB transfer protocols with iOS devices.',
        officialDownloadUrl:
            'https://support.apple.com/en-us/102575',
        checkFunction: () async {
          final driverFile = WindowsCheckerHelper.findFirstExisting([
            r'C:\Windows\System32\drivers\usbaapl64.sys',
            r'C:\Windows\System32\drivers\usbaapl.sys',
            r'C:\Program Files\Common Files\Apple\Mobile Device Support\Drivers\usbaapl64.inf',
          ]);

          if (driverFile != null) {
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'usbaapl64',
              message: 'Apple USB driver binaries verified in system driver storage.',
            );
          }

          // Check if system driver file exists directly
          if (File(r'C:\Windows\System32\drivers\usbaapl64.sys').existsSync()) {
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'usbaapl64',
              message: 'Apple USB driver active in system drivers.',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message: 'Apple USB driver not found. Install iTunes to register it.',
          );
        },
      ),
    ];
  }
}
