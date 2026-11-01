import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unlock_core/core/compatibility/device_compatibility_service.dart';
import 'package:unlock_core/core/device/apple_device_detection_service.dart';
import 'package:unlock_core/core/device/apple_usbmux_client.dart';
import 'package:unlock_core/core/device/device_info.dart';
import 'package:unlock_core/core/device/native_windows_usb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NativeWindowsUsb.mockDevicesProvider = null;
    AppleUsbmuxClient.mockListDevicesProvider = null;
    AppleUsbmuxClient.mockLockdownProvider = null;
  });

  tearDown(() {
    NativeWindowsUsb.mockDevicesProvider = null;
    AppleUsbmuxClient.mockListDevicesProvider = null;
    AppleUsbmuxClient.mockLockdownProvider = null;
  });

  group('DeviceCompatibilityService Tests', () {
    test('1. A12+ iPhone on supported iOS 17.5.1 reports verified support with no-signal notice', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPhone16,1',
        modelName: 'iPhone 15 Pro',
        osVersion: '17.5.1',
      );

      expect(result.status, equals(CompatibilityStatus.verifiedSupported));
      expect(result.chipFamily, equals(ChipFamily.a12Plus));
      expect(result.hasNoCellularSignalLimitation, isTrue);
      expect(result.statusBadge, contains('No Cellular Signal'));

      // Check prominent no-cellular-signal limitation wording
      final limitationText = result.limitations.join(' ');
      expect(limitationText, contains('No-Cellular-Signal Service Limitation'));
      expect(limitationText, contains('Wi-Fi and internet-connected applications'));
      expect(limitationText, contains('Traditional mobile carrier calls, SMS text messages'));
      expect(limitationText, contains('not an equivalent replacement'));

      // Legitimate recovery pathway
      expect(result.officialAppleRecoveryUrl, equals('https://support.apple.com/en-us/108934'));
      expect(result.officialRecoveryOptions.length, equals(3));
      expect(result.officialRecoveryOptions[0], contains('Apple Account'));
      expect(result.officialRecoveryOptions[1], contains('icloud.com/find'));
      expect(result.officialRecoveryOptions[2], contains('proof of purchase'));
    });

    test('2. A12+ iPhone on unconfirmed iOS 18.0 reports firmware outside range', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPhone16,1',
        modelName: 'iPhone 15 Pro',
        osVersion: '18.0',
      );

      expect(result.status, equals(CompatibilityStatus.firmwareOutsideRange));
      expect(result.chipFamily, equals(ChipFamily.a12Plus));
      expect(result.statusBadge, equals('Firmware Outside Vendor Reported Range'));
      expect(result.explanation, contains('outside the vendor\'s currently stated supported range'));
      expect(result.explanation, contains('Compatibility is not confirmed'));
    });

    test('3. Older A7–A11 iPhone (iPhone X) on iOS 16.7 reports legacy family support', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPhone10,6',
        modelName: 'iPhone X',
        osVersion: '16.7.4',
      );

      expect(result.status, equals(CompatibilityStatus.verifiedSupported));
      expect(result.chipFamily, equals(ChipFamily.a7ToA11));
      expect(result.hasNoCellularSignalLimitation, isFalse);
      expect(result.statusBadge, contains('Legacy Family'));
    });

    test('4. Older A7–A11 iPhone with impossible/exceeded iOS 17 reports outside range', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPhone10,6',
        modelName: 'iPhone X',
        osVersion: '17.2',
      );

      expect(result.status, equals(CompatibilityStatus.firmwareOutsideRange));
      expect(result.chipFamily, equals(ChipFamily.a7ToA11));
      expect(result.statusBadge, equals('Firmware Outside Vendor Reported Range'));
    });

    test('5. Missing or unverified firmware reports unconfirmed compatibility', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPhone15,2',
        modelName: 'iPhone 14 Pro',
        osVersion: null,
      );

      expect(result.status, equals(CompatibilityStatus.unconfirmed));
      expect(result.statusBadge, equals('Compatibility Not Confirmed'));
      expect(result.explanation, contains('firmware version is unconfirmed'));
      expect(result.explanation, contains('requires exact firmware verification'));
    });

    test('6. Unrecognized device model reports unconfirmed compatibility without speculation', () {
      final result = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'UnknownModel99,1',
        modelName: 'Generic Device',
        osVersion: '17.0',
      );

      expect(result.status, equals(CompatibilityStatus.unconfirmed));
      expect(result.statusBadge, equals('Compatibility Not Confirmed'));
      expect(result.explanation, contains('could not be verified against published vendor documentation'));
    });

    test('7. Diagnostic Recovery or DFU Mode reports unconfirmed with Apple restore guidance', () {
      final result = DeviceCompatibilityService.evaluate(
        modelName: 'Apple Mobile Device',
        mode: DeviceMode.recovery,
      );

      expect(result.status, equals(CompatibilityStatus.unconfirmed));
      expect(result.statusBadge, contains('Diagnostic Mode'));
      expect(result.limitations.join(' '), contains('Apple iTunes or Finder'));
    });

    test('8. iPad models distinguish between legacy A7+ and modern A12+ architectures', () {
      // iPad Air 2 (A8X)
      final legacyPad = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPad5,3',
        modelName: 'iPad Air 2',
        osVersion: '15.8.2',
      );
      expect(legacyPad.chipFamily, equals(ChipFamily.a7ToA11));

      // iPad Pro 11-inch (M-series / A12+ class)
      final modernPad = DeviceCompatibilityService.evaluate(
        modelIdentifier: 'iPad13,4',
        modelName: 'iPad Pro 11-inch (3rd gen)',
        osVersion: '17.4.1',
      );
      expect(modernPad.chipFamily, equals(ChipFamily.a12Plus));
      expect(modernPad.hasNoCellularSignalLimitation, isTrue);
    });
  });

  group('AppleDeviceDetectionService Lockdown & Device-Aware Detection Tests', () {
    test('9. Detection service queries lockdown and populates model identifier and compatibility', () async {
      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];

      AppleUsbmuxClient.mockListDevicesProvider = () async => [
        const UsbmuxDeviceEntry(
          deviceId: 42,
          serialNumber: '00008130000E70162241001C',
          productId: 0x12A8,
          connectionType: 'USB',
        ),
      ];

      AppleUsbmuxClient.mockLockdownProvider = (deviceId) async {
        expect(deviceId, equals(42));
        return const LockdownDeviceInfo(
          productType: 'iPhone16,1',
          productVersion: '17.5.1',
          deviceName: 'Tester\'s iPhone',
          buildVersion: '21F90',
        );
      };

      final detectionService = AppleDeviceDetectionService();
      final dev = await detectionService.queryDevices();

      expect(dev, isNotNull);
      expect(dev!.name, equals('Tester\'s iPhone'));
      expect(dev.model, equals('iPhone 15 Pro'));
      expect(dev.modelIdentifier, equals('iPhone16,1'));
      expect(dev.osVersion, equals('17.5.1'));
      expect(dev.compatibilityResult, isNotNull);
      expect(dev.compatibilityResult!.status, equals(CompatibilityStatus.verifiedSupported));
      expect(dev.compatibilityResult!.hasNoCellularSignalLimitation, isTrue);

      detectionService.dispose();
    });

    test('10. Lockdown query failure preserves device presence with unconfirmed compatibility', () async {
      final mockDevice = RawUsbDevice(
        instanceId: r'USB\VID_05AC&PID_12A8\00008130000E70162241001C',
        vid: '05AC',
        pid: '12A8',
        serialNumber: '00008130000E70162241001C',
        mode: DeviceMode.normal,
        friendlyName: 'Apple Mobile Device USB Device',
      );

      NativeWindowsUsb.mockDevicesProvider = () => [mockDevice];

      AppleUsbmuxClient.mockListDevicesProvider = () async => [
        const UsbmuxDeviceEntry(
          deviceId: 42,
          serialNumber: '00008130000E70162241001C',
          productId: 0x12A8,
          connectionType: 'USB',
        ),
      ];

      // Lockdown returns null (e.g. screen locked or passcode required)
      AppleUsbmuxClient.mockLockdownProvider = (deviceId) async => null;

      final detectionService = AppleDeviceDetectionService();
      final dev = await detectionService.queryDevices();

      // Device remains connected!
      expect(dev, isNotNull);
      expect(dev!.serialNumber, equals('00008130000E70162241001C'));
      expect(dev.modelIdentifier, isNull);
      expect(dev.osVersion, isNull);
      // Compatibility evaluates safely to unconfirmed without throwing
      expect(dev.compatibilityResult, isNotNull);
      expect(dev.compatibilityResult!.status, equals(CompatibilityStatus.unconfirmed));

      detectionService.dispose();
    });

    test('11. DeviceInfo toDiagnosticMap includes model identifier and compatibility safely', () {
      final dev = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 15 Pro',
        model: 'iPhone 15 Pro',
        modelIdentifier: 'iPhone16,1',
        chipFamily: 'A12+ Modern Family',
        serialNumber: 'C39Z1028N40V',
        osVersion: '17.5.1',
        mode: DeviceMode.normal,
        compatibilityResult: const DeviceCompatibilityResult(
          status: CompatibilityStatus.verifiedSupported,
          statusBadge: 'Vendor Support Available (No Cellular Signal)',
          chipFamily: ChipFamily.a12Plus,
          modelName: 'iPhone 15 Pro',
          modelIdentifier: 'iPhone16,1',
          osVersion: '17.5.1',
          hasNoCellularSignalLimitation: true,
          limitations: [],
          explanation: 'Supported',
          officialRecoveryOptions: [],
        ),
      );

      final map = dev.toDiagnosticMap();
      expect(map['Platform'], equals('IOS'));
      expect(map['Model Identifier'], equals('iPhone16,1'));
      expect(map['Family'], equals('A12+ Modern Family'));
      expect(map['Compatibility'], contains('No Cellular Signal'));
      // Hardware Identifier is masked for privacy
      expect(map['Hardware Identifier'], contains('••••'));
    });
  });
}
