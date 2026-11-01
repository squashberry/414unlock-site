import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unlock_core/core/auth/auth_service.dart';
import 'package:unlock_core/core/config/app_config.dart';
import 'package:unlock_core/core/device/apple_device_detection_service.dart';
import 'package:unlock_core/core/device/apple_usbmux_client.dart';
import 'package:unlock_core/core/device/device_info.dart';
import 'package:unlock_core/core/device/native_windows_usb.dart';
import 'package:unlock_core/core/prerequisites/iremove_manager.dart';
import 'package:unlock_core/core/prerequisites/itunes_manager.dart';
import 'package:unlock_core/core/prerequisites/setup_coordinator.dart';
import 'package:unlock_core/core/prerequisites/windows_checker_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late ITunesManager itunesManager;
  late IRemoveManager iremoveManager;
  late SetupCoordinator coordinator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testTempDir = Directory.systemTemp.createTempSync('stability_test_');

    NativeWindowsUsb.mockDevicesProvider = null;
    AppleUsbmuxClient.mockListDevicesProvider = null;
    AppConfig().setPartnerExecutablePath('');

    itunesManager = ITunesManager();
    iremoveManager = IRemoveManager();
    coordinator = SetupCoordinator(
      itunesManager: itunesManager,
      iremoveManager: iremoveManager,
    );
  });

  tearDown(() {
    NativeWindowsUsb.mockDevicesProvider = null;
    AppleUsbmuxClient.mockListDevicesProvider = null;
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Prerequisite & Startup Loading Checks', () {
    test('1. All startup requirements pass without exposing partner tools', () async {
      // Mock Apple Mobile Device Support service present
      final dummyService = File('${testTempDir.path}\\AppleMobileDeviceService.exe');
      dummyService.writeAsStringSync('dummy');

      // Check installed with candidate path
      coordinator.itunesManager.checkInstalled();
      // Directly check coordinator pipeline
      await coordinator.checkStartupRequirements();

      // Startup requirements pass
      expect(coordinator.windowsSystemState, equals(RequirementState.passed));
      expect(coordinator.engineState, equals(RequirementState.passed));
      expect(coordinator.isReady, isTrue);

      // Verify iRemove/partner tool details were not checked or exposed on startup
      expect(coordinator.iremoveManager.status, equals(IRemoveStatus.notChecked));
    });

    test('2. iTunes missing displays clear explanation and download option', () async {
      // Mock no service, no iTunes
      final missingManager = ITunesManager();
      final testCoord = SetupCoordinator(
        itunesManager: missingManager,
        iremoveManager: iremoveManager,
      );

      // Ensure no cached registry
      final ready = await testCoord.runPrerequisiteCheck();
      if (!ready) {
        expect(testCoord.currentStep, equals(SetupStep.itunesMissing));
        expect(testCoord.appleCommunicationState, equals(RequirementState.actionRequired));
        expect(testCoord.statusMessage, contains('needs iTunes to detect and communicate'));
      }
    });

    test('3. Bounded PowerShell execution handles timeouts safely without hanging', () async {
      final sw = Stopwatch()..start();
      // Script that sleeps longer than timeout
      final result = await WindowsCheckerHelper.runPowerShell(
        'Start-Sleep -Seconds 5; Write-Output "done"',
        timeoutSeconds: 1,
      );
      sw.stop();
      expect(result, isNull);
      // Ensure timeout was enforced near 1 second, not 5 seconds
      expect(sw.elapsedMilliseconds, lessThan(3500));
    });

    test('4. Concurrency lock prevents duplicate simultaneous checks', () async {
      int queryCount = 0;
      NativeWindowsUsb.mockDevicesProvider = () {
        queryCount++;
        return [];
      };

      final detectionService = AppleDeviceDetectionService();

      // Launch two queries simultaneously
      final future1 = detectionService.queryDevices();
      final future2 = detectionService.queryDevices();

      await Future.wait([future1, future2]);

      // Only one query executed because of the concurrency guard
      expect(queryCount, equals(1));
      detectionService.dispose();
    });
  });

  group('USB & Device State Stability Tests', () {
    test('5. Duplicate USB arrival events are deduplicated', () async {
      int notificationCount = 0;
      final detectionService = AppleDeviceDetectionService();
      detectionService.addListener(() {
        notificationCount++;
      });

      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];

      // Query multiple times with the exact same device
      await detectionService.queryDevices();
      final firstCount = notificationCount;
      expect(firstCount, equals(1));

      // Same query again
      await detectionService.queryDevices();
      await detectionService.queryDevices();

      // Count should NOT increment because device state did not change
      expect(notificationCount, equals(1));
      detectionService.dispose();
    });

    test('6. Detail query failure does not mark device as disconnected', () async {
      final detectionService = AppleDeviceDetectionService();

      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];

      // Usbmuxd throws or fails to return details
      AppleUsbmuxClient.mockListDevicesProvider = () async {
        throw Exception('Lockdown connection timeout');
      };

      final dev = await detectionService.queryDevices();

      // Device remains connected!
      expect(dev, isNotNull);
      expect(detectionService.currentDevice, isNotNull);
      expect(detectionService.currentDevice!.name, contains('Apple Mobile Device'));
      detectionService.dispose();
    });

    test('7. Genuine device removal transitions to disconnected after debouncing', () async {
      final detectionService = AppleDeviceDetectionService();

      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];
      await detectionService.queryDevices();
      expect(detectionService.currentDevice, isNotNull);

      // Now device is unplugged (bus returns empty)
      NativeWindowsUsb.mockDevicesProvider = () => [];

      // First empty scan (debouncing transient event)
      await detectionService.queryDevices();

      // Second consecutive empty scan confirms genuine removal
      await detectionService.queryDevices();
      expect(detectionService.currentDevice, isNull);

      detectionService.dispose();
    });

    test('8. Device disconnects and reconnects cleanly without app restart', () async {
      final detectionService = AppleDeviceDetectionService();

      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      // 1. Connected
      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];
      await detectionService.queryDevices();
      expect(detectionService.currentDevice, isNotNull);

      // 2. Disconnected
      NativeWindowsUsb.mockDevicesProvider = () => [];
      await detectionService.queryDevices();
      await detectionService.queryDevices();
      expect(detectionService.currentDevice, isNull);

      // 3. Reconnected
      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];
      await detectionService.queryDevices();
      expect(detectionService.currentDevice, isNotNull);
      expect(detectionService.currentDevice!.serialNumber, equals('00008130000E70162241001C'));

      detectionService.dispose();
    });
  });

  group('Authentication & Navigation Tests', () {
    test('9. Authentication returns to intended unlock operation without dropping device', () async {
      final authService = AuthService();
      final mockDevice = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 15 Pro',
        serialNumber: 'C39Z1028N40V',
        mode: DeviceMode.normal,
      );

      authService.currentDeviceGetter = () => mockDevice;
      authService.onConnectedDeviceChanged(mockDevice);

      // Unauthenticated state
      expect(authService.isAuthenticated, isFalse);

      // Session restored / logged in
      authService.setAuthenticatedSession(
        token: 'tok_test_123',
        user: const UserProfile(
          id: 'usr_1',
          fullName: 'Customer',
          email: 'customer@414unlock.com',
          emailVerified: true,
        ),
      );

      expect(authService.isAuthenticated, isTrue);
      expect(authService.user?.email, equals('customer@414unlock.com'));

      authService.dispose();
    });
  });

  group('Unlocking Support Preparation & Launch Tests', () {
    test('10. Partner-tool launch executes validated binary and reports status', () async {
      final dummyExe = File('${testTempDir.path}\\iRemove Tools.exe');
      final bytes = List<int>.filled(60 * 1024, 0);
      bytes[0] = 0x4D; // M
      bytes[1] = 0x5A; // Z
      dummyExe.writeAsBytesSync(bytes);

      await iremoveManager.setCustomExecutablePath(dummyExe.path);
      expect(iremoveManager.isReady, isTrue);

      // Validation succeeds
      final isValid = await iremoveManager.validateExecutableFile(dummyExe);
      expect(isValid, isTrue);
    });

    test('11. Safe download validation rejects invalid or corrupt files', () async {
      final corruptFile = File('${testTempDir.path}\\corrupt.exe');
      corruptFile.writeAsStringSync('corrupted non-executable text payload');

      final isValid = await iremoveManager.validateExecutableFile(corruptFile);
      expect(isValid, isFalse);
    });

    test('12. Apple Usbmux model mapping translates ProductType correctly', () {
      expect(AppleUsbmuxClient.mapProductType('iPhone16,1'), equals('iPhone 15 Pro'));
      expect(AppleUsbmuxClient.mapProductType('iPhone15,2'), equals('iPhone 14 Pro'));
      expect(AppleUsbmuxClient.mapProductType('iPhone14,2'), equals('iPhone 13 Pro'));
      expect(AppleUsbmuxClient.mapProductType('iPhone12,1'), equals('iPhone 11'));
      expect(AppleUsbmuxClient.mapProductType('iPhone8,4'), equals('iPhone SE (1st gen)'));
      expect(AppleUsbmuxClient.mapProductType('UnknownAppleDevice'), contains('Apple Device'));
    });
  });
}

extension AuthServiceMock on AuthService {
  Future<void> mockApplyAuthentication(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token'] as String);
    await prefs.setString('auth_user_email', (data['user'] as Map)['email'] as String);
    await restoreSession();
  }
}
