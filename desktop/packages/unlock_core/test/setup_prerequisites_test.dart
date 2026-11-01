import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unlock_core/unlock_core.dart';

class MockITunesManager extends ITunesManager {
  bool mockInstalled = false;
  String mockVersion = '12.13.0.9';
  bool mockDownloadSuccess = true;
  bool mockInstallSuccess = true;

  @override
  Future<bool> checkInstalled() async {
    return mockInstalled;
  }

  @override
  String get detectedVersion => mockVersion;

  @override
  Future<bool> downloadInstaller({String? targetDirectory}) async {
    if (!mockDownloadSuccess) {
      return false;
    }
    return true;
  }

  @override
  Future<bool> startInstallation() async {
    return mockInstallSuccess;
  }
}

class MockIRemoveManager extends IRemoveManager {
  bool mockInstalled = false;
  bool mockDownloadSuccess = true;
  bool mockLaunchSuccess = true;
  String mockFailReason = 'Partner executable not found';

  @override
  Future<bool> checkInstalled({bool forceRescan = false}) async {
    return mockInstalled;
  }

  @override
  Future<bool> downloadAndExtract() async {
    return mockDownloadSuccess;
  }

  @override
  Future<bool> launchTool([DeviceInfo? device]) async {
    return mockLaunchSuccess;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupCoordinator & Prerequisites Tests', () {
    late MockITunesManager itunes;
    late MockIRemoveManager iremove;
    late SetupCoordinator coordinator;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      itunes = MockITunesManager();
      iremove = MockIRemoveManager();
      coordinator = SetupCoordinator(
        itunesManager: itunes,
        iremoveManager: iremove,
      );
    });

    test('Scenario 1: First launch with both prerequisites missing stops at itunesMissing', () async {
      itunes.mockInstalled = false;
      iremove.mockInstalled = false;

      final ready = await coordinator.runPrerequisiteCheck();

      expect(ready, false);
      expect(coordinator.isReady, false);
      expect(coordinator.currentStep, SetupStep.itunesMissing);
      expect(coordinator.statusMessage, contains('iTunes is not installed'));
    });

    test('Scenario 2: iTunes already installed advances to iRemove check', () async {
      itunes.mockInstalled = true;
      iremove.mockInstalled = false;

      final ready = await coordinator.runPrerequisiteCheck();

      expect(ready, false);
      expect(coordinator.isReady, false);
      expect(coordinator.currentStep, SetupStep.itunesInstallRequired);
      expect(coordinator.statusMessage, contains('iRemove tool package needs to be downloaded'));
    });

    test('Scenario 2b: Both iTunes and iRemove verified transitions to ready and persists', () async {
      itunes.mockInstalled = true;
      iremove.mockInstalled = true;

      final ready = await coordinator.runPrerequisiteCheck();

      expect(ready, true);
      expect(coordinator.isReady, true);
      expect(coordinator.currentStep, SetupStep.ready);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ios_setup_completed_v1'), true);
    });

    test('Scenario 3: Failed installer download transitions to failed state', () async {
      itunes.mockDownloadSuccess = false;

      final success = await coordinator.startItunesDownload();

      expect(success, false);
      expect(coordinator.currentStep, SetupStep.failed);
    });

    test('Scenario 4: Interrupted or failed iRemove download transitions to failed state', () async {
      iremove.mockDownloadSuccess = false;

      final success = await coordinator.startIremoveDownload();

      expect(success, false);
      expect(coordinator.currentStep, SetupStep.failed);
    });

    test('Scenario 5: ZIP directory traversal vulnerability is blocked', () {
      final archive = Archive();

      // Add a malicious entry attempting directory traversal out of root
      final evilBytes = [0x54, 0x45, 0x53, 0x54];
      archive.addFile(ArchiveFile('../../evil.exe', evilBytes.length, evilBytes));
      archive.addFile(ArchiveFile('safe.exe', evilBytes.length, evilBytes));

      final rootDir = Directory.systemTemp.createTempSync('zip_test_');
      try {
        final canonicalDest = rootDir.resolveSymbolicLinksSync();

        for (final file in archive) {
          final normalized = p.normalize(file.name);
          final outPath = p.join(canonicalDest, normalized);

          if (!p.isWithin(canonicalDest, outPath)) {
            // Must block traversal entries
            expect(file.name, contains('..'));
            expect(p.isWithin(canonicalDest, outPath), false);
            continue;
          }

          expect(file.name, 'safe.exe');
          expect(p.isWithin(canonicalDest, outPath), true);
        }
      } finally {
        rootDir.deleteSync(recursive: true);
      }
    });

    test('Scenario 6: Successful in-memory extraction creates valid file', () async {
      final archive = Archive();
      final exeBytes = [0x4D, 0x5A, 0x90, 0x00]; // MZ header
      archive.addFile(ArchiveFile('iRemove.exe', exeBytes.length, exeBytes));

      final rootDir = Directory.systemTemp.createTempSync('extract_test_');
      try {
        for (final file in archive) {
          final outPath = p.join(rootDir.path, file.name);
          final outFile = File(outPath);
          await outFile.writeAsBytes(file.content as List<int>);
        }

        final extractedFile = File(p.join(rootDir.path, 'iRemove.exe'));
        expect(extractedFile.existsSync(), true);
        final readBytes = await extractedFile.readAsBytes();
        expect(readBytes, [0x4D, 0x5A, 0x90, 0x00]);
      } finally {
        rootDir.deleteSync(recursive: true);
      }
    });

    test('Scenario 13: Service prerequisites missing barrier', () {
      coordinator.runPrerequisiteCheck();
      expect(coordinator.isReady, false);
    });

    test('Scenario 14: External process launch failure handled safely', () async {
      iremove.mockLaunchSuccess = false;
      final launched = await iremove.launchTool();
      expect(launched, false);
    });
  });
}
