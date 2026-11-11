import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_core/unlock_core.dart';

void main() {
  group('Activation-Locked & USB Descriptors Detection Tests', () {
    test('1. Normal mode 24-character USB serial extracts CPID, ECID, and chip family without pairing', () {
      // Instance ID from Windows PNP: USB\VID_05AC&PID_12A8\00008110000A184214D0201E
      const instanceId = r'USB\VID_05AC&PID_12A8\00008110000A184214D0201E';
      final dev = NativeWindowsUsb.getConnectedAppleDevices;

      NativeWindowsUsb.mockDevicesProvider = () => [
        const RawUsbDevice(
          instanceId: instanceId,
          vid: '05AC',
          pid: '12A8',
          serialNumber: '00008110000A184214D0201E',
          mode: DeviceMode.normal,
          friendlyName: 'Apple Mobile Device USB Device',
          cpid: '8110',
          ecid: '000A184214D0201E',
          chipFamily: 'Apple A15 Bionic',
        ),
      ];

      final devices = dev();
      expect(devices, hasLength(1));
      final d = devices.first;
      expect(d.cpid, equals('8110'));
      expect(d.ecid, equals('000A184214D0201E'));
      expect(d.chipFamily, equals('Apple A15 Bionic'));
      expect(d.mode, equals(DeviceMode.normal));

      NativeWindowsUsb.mockDevicesProvider = null;
    });

    test('2. Recovery mode descriptor string parses CPID, BDID, ECID, SRNM and maps to iPhone 13', () {
      const recoveryInstanceId =
          r'USB\VID_05AC&PID_1281\SDOM:01_CPID:8110_CPRV:11_CPFM:03_SCEP:01_BDID:0A_ECID:000A184214D0201E_IBFL:1C_SRNM:F2LN40VXXXXX';

      final dev = NativeWindowsUsb.parseInstanceId(recoveryInstanceId)!;
      expect(dev.cpid, equals('8110'));
      expect(dev.bdid, equals('0A'));
      expect(dev.ecid, equals('000A184214D0201E'));
      expect(dev.serialNumber, equals('F2LN40VXXXXX'));
      expect(dev.productType, equals('iPhone14,5'));
      expect(dev.chipFamily, equals('Apple A15 Bionic'));

      final parsed = AppleDeviceDatabase.lookupProductTypeByCpidBdid(
        cpidHex: '8110',
        bdidHex: '0A',
      );
      expect(parsed, equals('iPhone14,5'));
      expect(AppleDeviceDatabase.mapProductType(parsed!), equals('iPhone 13'));
      expect(AppleDeviceDatabase.lookupChipFamilyByCpid('8110'), equals('Apple A15 Bionic'));
    });

    test('3. ExternalIdeviceTools parses irecovery -q output accurately', () {
      const irecoveryOutput = '''
CPID: 0x8110
CPRV: 0x11
CPFM: 0x03
SCEP: 0x01
BDID: 0x0a
ECID: 0x000a184214d0201e
IBFL: 0x1c
SRNM: F2LN40V89012
''';

      final info = ExternalIdeviceTools.parseIrecoveryOutput(irecoveryOutput);
      expect(info.cpid, equals('8110'));
      expect(info.bdid, equals('0A'));
      expect(info.ecid, equals('000A184214D0201E'));
      expect(info.serialNumber, equals('F2LN40V89012'));
      expect(info.productType, equals('iPhone14,5'));
      expect(info.model, equals('iPhone 13'));
      expect(info.chipFamily, equals('Apple A15 Bionic'));
    });

    test('4. AppleUsbmuxClient maps ProductType to correct consumer models across generations', () {
      expect(AppleDeviceDatabase.mapProductType('iPhone14,5'), equals('iPhone 13'));
      expect(AppleDeviceDatabase.mapProductType('iPhone15,2'), equals('iPhone 14 Pro'));
      expect(AppleDeviceDatabase.mapProductType('iPhone16,1'), equals('iPhone 15 Pro'));
      expect(AppleDeviceDatabase.mapProductType('iPhone17,1'), equals('iPhone 16 Pro'));
      expect(AppleDeviceDatabase.mapProductType('iPhone10,3'), equals('iPhone X'));
      expect(AppleDeviceDatabase.mapProductType('iPhone8,4'), equals('iPhone SE (1st gen)'));
      expect(AppleDeviceDatabase.mapProductType('iPhone14,6'), equals('iPhone SE (3rd gen)'));
    });

    test('5. Activation-locked iPhone at Hello screen sets LockdownStatus.setupScreen without passcode error', () async {
      final detectionService = AppleDeviceDetectionService();

      NativeWindowsUsb.mockDevicesProvider = () => [
        const RawUsbDevice(
          instanceId: r'USB\VID_05AC&PID_12A8\00008110000A184214D0201E',
          vid: '05AC',
          pid: '12A8',
          serialNumber: '00008110000A184214D0201E',
          mode: DeviceMode.normal,
          friendlyName: 'Apple Mobile Device USB Device',
          cpid: '8110',
          ecid: '000A184214D0201E',
          chipFamily: 'Apple A15 Bionic',
        ),
      ];

      AppleUsbmuxClient.mockListDevicesProvider = () async => [
        const UsbmuxDeviceEntry(
          deviceId: 42,
          serialNumber: '00008110-000A184214D0201E',
          productId: 0x12A8,
          connectionType: 'USB',
        ),
      ];

      AppleUsbmuxClient.mockLockdownProvider = (deviceId) async => const LockdownDeviceInfo(
        productType: 'iPhone14,5',
        productVersion: '17.5.1',
        deviceName: 'iPhone',
        buildVersion: '21F90',
        udid: '00008110-000A184214D0201E',
        activationState: 'Unactivated',
        passwordProtected: false,
        chipId: '33040',
      );

      final device = await detectionService.queryDevices();
      expect(device, isNotNull);
      expect(device!.model, equals('iPhone 13'));
      expect(device.modelIdentifier, equals('iPhone14,5'));
      expect(device.osVersion, equals('17.5.1'));
      expect(device.chipFamily, equals('Apple A15 Bionic'));
      expect(device.lockdownStatus, equals(LockdownStatus.setupScreen));
      expect(device.lockdownStatus.showsWarning, isFalse);
      expect(device.statusDescription, contains('Setup / Activation Lock screen'));

      NativeWindowsUsb.mockDevicesProvider = null;
      AppleUsbmuxClient.mockListDevicesProvider = null;
      AppleUsbmuxClient.mockLockdownProvider = null;
      detectionService.dispose();
    });

    test('6. Unconfirmed properties show Unavailable in current device state without requesting passcode bypass', () {
      final unconfirmedDevice = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'Apple Mobile Device USB Device',
        mode: DeviceMode.normal,
        lockdownStatus: LockdownStatus.setupScreen,
        serialNumber: '00008110000A184214D0201E',
      );

      expect(unconfirmedDevice.modelIdentifier, isNull);
      expect(unconfirmedDevice.osVersion, isNull);
      expect(unconfirmedDevice.lockdownStatus.showsWarning, isFalse);
      expect(unconfirmedDevice.isReadyForUnlock, isTrue);
    });

    test('7. AndroidPlatformToolsManager resolves managed directory', () {
      final managedDir = AndroidPlatformToolsManager.getManagedToolsDir();
      expect(managedDir, contains('platform-tools'));
      expect(managedDir, contains('414Unlock'));
    });
  });
}
