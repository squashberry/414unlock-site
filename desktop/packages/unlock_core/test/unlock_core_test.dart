import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_core/unlock_core.dart';

void main() {
  group('AppLogger Tests', () {
    test('Logs are timestamped and formatted correctly', () {
      final logger = AppLogger();
      logger.clear();
      logger.info('Application started');
      expect(logger.entries.length, 1);
      expect(logger.entries.first.message, 'Application started');
      expect(logger.entries.first.level, LogLevel.info);
      expect(logger.entries.first.formattedTime, isNotEmpty);
    });

    test('Sensitive credentials and passcodes are redacted in logs', () {
      final logger = AppLogger();
      logger.clear();
      logger.info('Checking pin: 123456 and token: secretTokenValue');
      expect(logger.entries.first.message, contains('[REDACTED]'));
      expect(logger.entries.first.message, isNot(contains('123456')));
      expect(logger.entries.first.message, isNot(contains('secretTokenValue')));
    });
  });

  group('PrerequisiteService Tests', () {
    test('Detects installed and missing states properly', () async {
      final prereq1 = Prerequisite(
        id: 'test_1',
        displayName: 'Test Dep 1',
        description: 'First test dependency',
        officialDownloadUrl: 'https://example.com/1',
        checkFunction: () async => const PrerequisiteCheckResult(
          status: PrerequisiteStatus.installed,
          detectedVersion: '1.0.0',
        ),
      );

      final prereq2 = Prerequisite(
        id: 'test_2',
        displayName: 'Test Dep 2',
        description: 'Second test dependency',
        officialDownloadUrl: 'https://example.com/2',
        checkFunction: () async => const PrerequisiteCheckResult(
          status: PrerequisiteStatus.missing,
        ),
      );

      final service = PrerequisiteService(prerequisites: [prereq1, prereq2]);
      expect(service.allPassed, false);

      await service.checkAll();
      expect(prereq1.status, PrerequisiteStatus.installed);
      expect(prereq2.status, PrerequisiteStatus.missing);
      expect(service.allPassed, false);
      expect(service.installedCount, 1);
    });
  });

  group('RepairEngine Tests', () {
    test('ExternalPartnerEngine initially returns Not Configured result', () async {
      final engine = ExternalPartnerEngine();
      await engine.initialize();

      final device = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 15 Pro',
        statusDescription: 'USB communication available',
      );

      final result = await engine.executeOperation(device);
      expect(result.success, false);
      expect(result.message, 'Not configured');
      expect(engine.state, EngineState.failed);
    });

    test('verifyHandoffCompletion returns Verification Required when unverified', () async {
      final engine = ExternalPartnerEngine();
      final result = await engine.verifyHandoffCompletion(null);
      expect(result.success, false);
      expect(result.isVerified, false);
      expect(
        result.message,
        'The partner application finished, but 414Unlock could not independently verify the final device state.',
      );
    });
  });

  group('DeviceInfo Tests', () {
    test('Produces accurate diagnostic mapping', () {
      final device = DeviceInfo(
        platform: DevicePlatform.android,
        name: 'Pixel 8',
        model: 'Pixel 8',
        manufacturer: 'Google',
        serialNumber: 'TEST12345',
        mode: DeviceMode.adb,
        statusDescription: 'USB communication available via ADB',
      );

      final diag = device.toDiagnosticMap();
      expect(diag['Platform'], 'ANDROID');
      expect(diag['Name'], 'Pixel 8');
      expect(diag['Manufacturer'], 'Google');
      expect(diag['Hardware Identifier'], '•••• •••• 2345');
      expect(diag['Mode'], 'ADB Authorized');
    });
  });
}
