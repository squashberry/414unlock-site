import 'dart:io';
import 'prerequisite.dart';
import 'windows_checker_helper.dart';

class AndroidPrerequisites {
  static List<Prerequisite> getPrerequisites() {
    return [
      Prerequisite(
        id: 'android_usb_driver',
        displayName: 'Android OEM / WinUSB Driver',
        description:
            'Windows device driver enabling low-level USB endpoints and ADB/Fastboot composite interfaces for Android hardware.',
        officialDownloadUrl:
            'https://developer.android.com/studio/run/win-usb',
        checkFunction: () async {
          // Check DriverStore for Android / WinUSB drivers
          final driverStore = await WindowsCheckerHelper.runPowerShell(
            'Get-ChildItem -Path "C:\\Windows\\System32\\DriverStore\\FileRepository\\*android*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name',
          );

          if (driverStore != null && driverStore.isNotEmpty) {
            return PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: driverStore.split('_').first,
              message: 'Android USB driver is registered in the Windows DriverStore.',
            );
          }

          // Check for WinUSB system driver which powers generic Android devices
          final winusbFile = WindowsCheckerHelper.findFirstExisting([
            r'C:\Windows\System32\drivers\winusb.sys',
          ]);

          if (winusbFile != null) {
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'WinUSB.sys',
              message: 'Windows WinUSB subsystem available for Android device communication.',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message: 'Android OEM USB Driver not detected. Install the Google or OEM USB driver.',
          );
        },
      ),
      Prerequisite(
        id: 'android_adb',
        displayName: 'Android Debug Bridge (ADB)',
        description:
            'Official command-line utility used to query legitimate device states and facilitate authorized communication.',
        officialDownloadUrl:
            'https://developer.android.com/tools/releases/platform-tools',
        checkFunction: () async {
          // Check PATH
          final pathAdb = await WindowsCheckerHelper.findExecutableOnPath('adb.exe');
          String? adbExe = pathAdb;

          adbExe ??= WindowsCheckerHelper.findFirstExisting([
              r'%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe',
              r'C:\Android\platform-tools\adb.exe',
              r'C:\platform-tools\adb.exe',
              r'%USERPROFILE%\platform-tools\adb.exe',
            ]);

          if (adbExe != null) {
            try {
              final result = await Process.run(adbExe, ['version']).timeout(
                const Duration(seconds: 3),
              );
              if (result.exitCode == 0) {
                final match = RegExp(r'Android Debug Bridge version ([\d\.]+)').firstMatch(
                  result.stdout as String,
                );
                final version = match != null ? match.group(1) : 'Detected';
                return PrerequisiteCheckResult(
                  status: PrerequisiteStatus.installed,
                  detectedVersion: version,
                  message: 'ADB platform tool verified at: $adbExe',
                );
              }
            } catch (_) {}
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'Installed',
              message: 'ADB executable located.',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message:
                'ADB not found on PATH or in Android SDK platform-tools. Download official Android Platform Tools.',
          );
        },
      ),
      Prerequisite(
        id: 'android_fastboot',
        displayName: 'Android Fastboot Utility',
        description:
            'Protocol tool required for device communication when connected in legitimate bootloader or fastboot repair state.',
        officialDownloadUrl:
            'https://developer.android.com/tools/releases/platform-tools',
        checkFunction: () async {
          final pathFastboot = await WindowsCheckerHelper.findExecutableOnPath('fastboot.exe');
          String? fastbootExe = pathFastboot;

          fastbootExe ??= WindowsCheckerHelper.findFirstExisting([
              r'%LOCALAPPDATA%\Android\Sdk\platform-tools\fastboot.exe',
              r'C:\Android\platform-tools\fastboot.exe',
              r'C:\platform-tools\fastboot.exe',
              r'%USERPROFILE%\platform-tools\fastboot.exe',
            ]);

          if (fastbootExe != null) {
            try {
              final result = await Process.run(fastbootExe, ['--version']).timeout(
                const Duration(seconds: 3),
              );
              if (result.exitCode == 0) {
                final match = RegExp(r'fastboot version ([\d\.]+)').firstMatch(
                  result.stdout as String,
                );
                final version = match != null ? match.group(1) : 'Detected';
                return PrerequisiteCheckResult(
                  status: PrerequisiteStatus.installed,
                  detectedVersion: version,
                  message: 'Fastboot verified at: $fastbootExe',
                );
              }
            } catch (_) {}
            return const PrerequisiteCheckResult(
              status: PrerequisiteStatus.installed,
              detectedVersion: 'Installed',
              message: 'Fastboot executable located.',
            );
          }

          return const PrerequisiteCheckResult(
            status: PrerequisiteStatus.missing,
            message:
                'Fastboot utility not found. Bundled in the official Android SDK platform-tools package.',
          );
        },
      ),
    ];
  }
}
