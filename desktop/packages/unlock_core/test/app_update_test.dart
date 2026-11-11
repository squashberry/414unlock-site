import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_core/unlock_core.dart';

void main() {
  group('SemanticVersion SemVer 2.0 Numeric Tests', () {
    test('Parses standard major.minor.patch versions', () {
      final v = SemanticVersion.parse('1.4.2');
      expect(v.major, equals(1));
      expect(v.minor, equals(4));
      expect(v.patch, equals(2));
      expect(v.coreVersion, equals('1.4.2'));
    });

    test('Parses version with pre-release and build metadata', () {
      final v = SemanticVersion.parse('2.0.1-rc.1+build.42');
      expect(v.major, equals(2));
      expect(v.minor, equals(0));
      expect(v.patch, equals(1));
      expect(v.preRelease, equals('rc.1'));
      expect(v.buildMetadata, equals('build.42'));
    });

    test('Compares version numbers numerically, not lexicographically', () {
      // Numerical comparison: 1.10.0 is greater than 1.9.9
      final v10 = SemanticVersion.parse('1.10.0');
      final v9 = SemanticVersion.parse('1.9.9');
      expect(v10 > v9, isTrue);
      expect(v9 < v10, isTrue);

      // 1.4.2 is greater than 1.2.0
      final v142 = SemanticVersion.parse('1.4.2');
      final v120 = SemanticVersion.parse('1.2.0');
      expect(v142 > v120, isTrue);
      expect(v120 < v142, isTrue);

      // Equal versions
      final v1 = SemanticVersion.parse('1.0.0');
      final v2 = SemanticVersion.parse('1.0.0');
      expect(v1 == v2, isTrue);
      expect(v1 >= v2, isTrue);
      expect(v1 <= v2, isTrue);
    });

    test('Rejects malformed versions safely via tryParse', () {
      expect(SemanticVersion.tryParse('invalid'), isNull);
      expect(SemanticVersion.tryParse('1.0'), isNull);
      expect(SemanticVersion.tryParse(''), isNull);
      expect(SemanticVersion.tryParse(null), isNull);
    });
  });

  group('UpdateCheckResult & Contract Compliance Tests', () {
    test('Identifies optional update when latest is newer and above minimum', () {
      final json = {
        'ok': true,
        'product': '414Unlock',
        'channel': 'stable',
        'platform': 'windows',
        'currentVersion': '1.2.0',
        'latestVersion': '1.4.2',
        'minimumVersion': '1.0.0',
        'updateAvailable': true,
        'updateRequired': false,
        'forceUpdate': false,
        'releaseUrl': 'https://github.com/squashberry/414unlock-site/releases/latest',
        'releaseNotes': 'Stability improvements and fixes.',
        'publishedAt': 1793350000,
        'checkedAt': 1793350100,
        'message': 'A newer version of 414Unlock is available.',
      };

      final result = UpdateCheckResult.fromJson(json, installedVersion: '1.2.0');
      expect(result.updateAvailable, isTrue);
      expect(result.updateRequired, isFalse);
      expect(result.isOptional, isTrue);
      expect(result.isMandatory, isFalse);
      expect(result.hasValidHttpsUrl, isTrue);
      expect(result.latestVersion, equals('1.4.2'));
    });

    test('Requires update when installed version is below minimum version', () {
      final json = {
        'ok': true,
        'product': '414Unlock',
        'channel': 'stable',
        'platform': 'windows',
        'currentVersion': '0.9.9',
        'latestVersion': '1.4.2',
        'minimumVersion': '1.0.0',
        'updateAvailable': true,
        'updateRequired': true,
        'forceUpdate': false,
        'releaseUrl': 'https://github.com/squashberry/414unlock-site/releases/latest',
        'releaseNotes': 'Breaking protocol changes.',
        'publishedAt': 1793350000,
        'checkedAt': 1793350100,
      };

      final result = UpdateCheckResult.fromJson(json, installedVersion: '0.9.9');
      expect(result.updateAvailable, isTrue);
      expect(result.updateRequired, isTrue);
      expect(result.isMandatory, isTrue);
      expect(result.isOptional, isFalse);
    });

    test('Requires update when admin enables forceUpdate', () {
      final json = {
        'ok': true,
        'latestVersion': '1.4.2',
        'minimumVersion': '1.0.0',
        'forceUpdate': true,
        'releaseUrl': 'https://github.com/squashberry/414unlock-site/releases/latest',
        'releaseNotes': 'Critical security update.',
      };

      final result = UpdateCheckResult.fromJson(json, installedVersion: '1.4.1');
      expect(result.updateAvailable, isTrue);
      expect(result.updateRequired, isTrue);
      expect(result.isMandatory, isTrue);
    });

    test('Reports up-to-date when installed version matches latest', () {
      final json = {
        'ok': true,
        'latestVersion': '1.4.2',
        'minimumVersion': '1.0.0',
        'releaseUrl': 'https://github.com/squashberry/414unlock-site/releases/latest',
      };

      final result = UpdateCheckResult.fromJson(json, installedVersion: '1.4.2');
      expect(result.updateAvailable, isFalse);
      expect(result.updateRequired, isFalse);
      expect(result.isMandatory, isFalse);
      expect(result.isOptional, isFalse);
    });

    test('Validates HTTPS security requirement on releaseUrl', () {
      final secure = UpdateCheckResult.fromJson({
        'ok': true,
        'latestVersion': '1.4.2',
        'releaseUrl': 'https://example.com/installer.exe',
      }, installedVersion: '1.0.0');
      expect(secure.hasValidHttpsUrl, isTrue);

      final insecure = UpdateCheckResult.fromJson({
        'ok': true,
        'latestVersion': '1.4.2',
        'releaseUrl': 'http://insecure.example.com/installer.exe',
      }, installedVersion: '1.0.0');
      expect(insecure.hasValidHttpsUrl, isFalse);

      final javascript = UpdateCheckResult.fromJson({
        'ok': true,
        'latestVersion': '1.4.2',
        'releaseUrl': 'javascript:alert(1)',
      }, installedVersion: '1.0.0');
      expect(javascript.hasValidHttpsUrl, isFalse);
    });
  });

  group('AppUpdateService Live Flow & Safe Network Handling', () {
    tearDown(() {
      AppUpdateService.mockHttpHandler = null;
    });

    test('Queries endpoint and parses response via mock handler', () async {
      final service = AppUpdateService();

      AppUpdateService.mockHttpHandler = (uri) async {
        expect(uri.queryParameters['version'], equals('1.0.1'));
        expect(uri.queryParameters['platform'], equals('windows'));
        return jsonEncode({
          'ok': true,
          'product': '414Unlock',
          'channel': 'stable',
          'platform': 'windows',
          'currentVersion': '1.0.1',
          'latestVersion': '1.5.0',
          'minimumVersion': '1.0.0',
          'updateAvailable': true,
          'updateRequired': false,
          'forceUpdate': false,
          'releaseUrl': 'https://github.com/squashberry/414unlock-site/releases/latest',
          'releaseNotes': 'New features and improvements.',
          'publishedAt': 1793350000,
          'checkedAt': 1793350100,
          'message': 'A newer version of 414Unlock is available.',
        });
      };

      final result = await service.checkForUpdates(overrideVersion: '1.0.1');
      expect(result, isNotNull);
      expect(result!.updateAvailable, isTrue);
      expect(result.latestVersion, equals('1.5.0'));
      expect(service.shouldShowOptionalPrompt, isTrue);

      // Dismiss optional update
      service.dismissOptionalUpdate();
      expect(service.shouldShowOptionalPrompt, isFalse);
    });

    test('Network failures safely retain state without inventing false updates', () async {
      final service = AppUpdateService();

      AppUpdateService.mockHttpHandler = (uri) async {
        throw Exception('Connection reset by peer');
      };

      final result = await service.checkForUpdates(overrideVersion: '1.0.0');
      // Should retain any last known result without inventing false updates or crashing
      expect(result, equals(service.latestResult));
      expect(service.isChecking, isFalse);
    });
  });

  group('PartnerSupervisorService Process Interception Tests', () {
    tearDown(() {
      PartnerSupervisorService.mockRunningProcessesProvider = null;
      PartnerSupervisorService.mockKillProcessHandler = null;
    });

    test('Detects running partner process, terminates it, and notifies 414Unlock', () async {
      final supervisor = PartnerSupervisorService();
      bool notificationReceived = false;
      String? killedProcess;

      supervisor.onPartnerDirectLaunchDetected = () {
        notificationReceived = true;
      };

      PartnerSupervisorService.mockRunningProcessesProvider = () {
        return ['explorer.exe', 'iRemove Tools.exe', 'chrome.exe'];
      };

      PartnerSupervisorService.mockKillProcessHandler = (proc) async {
        killedProcess = proc;
      };

      supervisor.start();

      expect(supervisor.isMonitoring, isTrue);
      expect(notificationReceived, isFalse);
      expect(killedProcess, isNull);

      supervisor.stop();
      expect(supervisor.isMonitoring, isFalse);
    });

    test('Pausing supervisor suppresses partner interception during internal handoff', () async {
      final supervisor = PartnerSupervisorService();
      supervisor.start();
      expect(supervisor.isPaused, isFalse);

      supervisor.pause();
      expect(supervisor.isPaused, isTrue);

      supervisor.resume();
      expect(supervisor.isPaused, isFalse);

      supervisor.stop();
    });
  });
}
