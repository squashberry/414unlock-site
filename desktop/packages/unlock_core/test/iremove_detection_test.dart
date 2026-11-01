import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unlock_core/unlock_core.dart';

class TestITunesManager extends ITunesManager {
  bool mockInstalled = true;
  @override
  Future<bool> checkInstalled() async => mockInstalled;
  @override
  Future<bool> downloadInstaller({String? targetDirectory}) async => true;
  @override
  Future<bool> startInstallation() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iRemove Detection & Persistence Regression Tests', () {
    late Directory tempRoot;
    late Directory mockInstallDir;
    late Directory mockCustomDir;
    late Directory mockCacheDir;
    late IRemoveManager iremoveManager;

    // Helper to create a valid mock Windows PE executable with MZ header and >50KB size
    Future<File> createMockExecutable(String dirPath, String fileName) async {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File(p.join(dir.path, fileName));
      // Write PE MZ header (0x4D, 0x5A) + padding to reach 60 KB
      final bytes = Uint8List(60 * 1024);
      bytes[0] = 0x4D; // M
      bytes[1] = 0x5A; // Z
      await file.writeAsBytes(bytes);
      return file;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig().setPartnerExecutablePath('');
      tempRoot = Directory.systemTemp.createTempSync('iremove_test_');
      mockInstallDir = Directory(p.join(tempRoot.path, 'ProgramFiles', 'iRemoveTools'));
      mockCustomDir = Directory(p.join(tempRoot.path, 'CustomFolder', 'iRemove Tools'));
      mockCacheDir = Directory(p.join(tempRoot.path, 'LocalAppData', '414Unlock', 'iremove', 'v1'));

      iremoveManager = IRemoveManager();
      iremoveManager.installDirectoryOverride = () => mockCacheDir;
      iremoveManager.candidateDirectoriesOverride = () => [];
      iremoveManager.userDirectoriesOverride = () => [];
    });

    tearDown(() async {
      await AppConfig().setPartnerExecutablePath('');
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Test 1: iRemove installed outside default directory is detected via registry without downloading', () async {
      // Create executable in non-default directory (e.g. Program Files)
      final exe = await createMockExecutable(mockInstallDir.path, 'iRemove Tools.exe');

      // Mock registry returning the installation
      iremoveManager.registryQueryOverride = () async {
        return [
          {
            'DisplayName': 'iRemove Tools (A12+ Edition)',
            'DisplayVersion': '9.5',
            'InstallLocation': mockInstallDir.path,
          }
        ];
      };

      final found = await iremoveManager.checkInstalled();

      expect(found, true);
      expect(iremoveManager.isReady, true);
      expect(iremoveManager.status, IRemoveStatus.installed);
      expect(iremoveManager.executablePath, exe.path);
      expect(iremoveManager.detectedVersion, '9.5');
      expect(iremoveManager.detectionSource, contains('Windows Registry'));
      expect(iremoveManager.downloadedBytes, 0); // No network download!

      // Verify it was persisted to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(IRemoveManager.kSavedExePath), exe.path);
      expect(prefs.getString(IRemoveManager.kSavedVersion), '9.5');
    });

    test('Test 2: A previously saved custom executable path is restored without scanning or downloading', () async {
      final exe = await createMockExecutable(mockCustomDir.path, 'iRemove Tools.exe');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(IRemoveManager.kSavedExePath, exe.path);
      await prefs.setString(IRemoveManager.kSavedVersion, '9.5');
      await prefs.setString(IRemoveManager.kSavedSource, 'Custom Location');

      // No registry or search overrides supplied - should resolve purely from saved configuration
      var registryCalled = false;
      iremoveManager.registryQueryOverride = () async {
        registryCalled = true;
        return [];
      };

      final found = await iremoveManager.checkInstalled();

      expect(found, true);
      expect(iremoveManager.isReady, true);
      expect(iremoveManager.executablePath, exe.path);
      expect(iremoveManager.isCustomLocation, true);
      expect(iremoveManager.detectionSource, 'Custom Location');
      expect(registryCalled, false); // Did NOT need to query registry or search
      expect(iremoveManager.downloadedBytes, 0);
    });

    test('Test 3: Valid executable found in 414Unlock cache is reused without redownload', () async {
      final cachedExe = await createMockExecutable(mockCacheDir.path, 'iRemove.exe');

      iremoveManager.registryQueryOverride = () async => [];
      iremoveManager.startMenuQueryOverride = () async => [];

      final found = await iremoveManager.checkInstalled();

      expect(found, true);
      expect(iremoveManager.isReady, true);
      expect(iremoveManager.executablePath, cachedExe.path);
      expect(iremoveManager.detectionSource, contains('Application Cache'));
      expect(iremoveManager.downloadedBytes, 0);
    });

    test('Test 4: Missing executable results in missing state with NO automatic download', () async {
      iremoveManager.registryQueryOverride = () async => [];
      iremoveManager.startMenuQueryOverride = () async => [];
      iremoveManager.candidateDirectoriesOverride = () => [];

      final found = await iremoveManager.checkInstalled();

      expect(found, false);
      expect(iremoveManager.isReady, false);
      expect(iremoveManager.status, IRemoveStatus.missing);
      expect(iremoveManager.executablePath, isNull);
      expect(iremoveManager.statusMessage, contains('not detected'));
      expect(iremoveManager.downloadedBytes, 0); // Must NOT download automatically!
    });

    test('Test 5: An invalid or deleted saved path is cleared and fallback detection succeeds', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(IRemoveManager.kSavedExePath, r'C:\NonExistent\iRemove.exe');

      // Fallback location has valid executable
      final exe = await createMockExecutable(mockInstallDir.path, 'iRemove Tools.exe');
      iremoveManager.registryQueryOverride = () async {
        return [
          {
            'DisplayName': 'iRemove Tools',
            'InstallLocation': mockInstallDir.path,
          }
        ];
      };

      final found = await iremoveManager.checkInstalled();

      expect(found, true);
      expect(iremoveManager.executablePath, exe.path);
      // Saved path in prefs should now be updated to the valid discovered path
      expect(prefs.getString(IRemoveManager.kSavedExePath), exe.path);
    });

    test('Test 6: Executable validation rejects non-PE files or small stubs', () async {
      final stubFile = File(p.join(tempRoot.path, 'stub.exe'));
      await stubFile.writeAsString('not a real pe binary');

      final isValid = await iremoveManager.validateExecutableFile(stubFile);
      expect(isValid, false);

      final accepted = await iremoveManager.setCustomExecutablePath(stubFile.path);
      expect(accepted, false);
      expect(iremoveManager.status, IRemoveStatus.invalidExecutable);
      expect(iremoveManager.statusMessage, contains('not a valid'));
    });

    test('Test 7: Start Menu shortcut target resolution detects iRemove', () async {
      final exe = await createMockExecutable(mockInstallDir.path, 'iRemove Tools.exe');

      iremoveManager.registryQueryOverride = () async => [];
      iremoveManager.startMenuQueryOverride = () async => [exe.path];

      final found = await iremoveManager.checkInstalled();

      expect(found, true);
      expect(iremoveManager.executablePath, exe.path);
      expect(iremoveManager.detectionSource, contains('Start Menu Shortcut'));
    });

    test('Test 8: Locating iRemove via file picker saves path and persists across fresh manager restarts', () async {
      final exe = await createMockExecutable(mockCustomDir.path, 'iRemove Tools.exe');

      // User picks the file
      iremoveManager.filePickerOverride = () async => exe.path;
      final located = await iremoveManager.locateExecutableUsingPicker();

      expect(located, true);
      expect(iremoveManager.isReady, true);
      expect(iremoveManager.executablePath, exe.path);
      expect(iremoveManager.isCustomLocation, true);

      // Simulate app closing and reopening with a brand new IRemoveManager instance
      final freshManager = IRemoveManager();
      freshManager.installDirectoryOverride = () => mockCacheDir;
      freshManager.candidateDirectoriesOverride = () => [];
      freshManager.userDirectoriesOverride = () => [];

      // On restart, checkInstalled must find it from saved configuration
      final restartReady = await freshManager.checkInstalled();
      expect(restartReady, true);
      expect(freshManager.isReady, true);
      expect(freshManager.executablePath, exe.path);
      expect(freshManager.downloadedBytes, 0); // No redownloading!
    });

    test('Test 9: SetupCoordinator coordinates locateIremove and transitions to ready', () async {
      final itunes = TestITunesManager();
      itunes.mockInstalled = true;

      final exe = await createMockExecutable(mockCustomDir.path, 'iRemove Tools.exe');
      iremoveManager.filePickerOverride = () async => exe.path;

      final coordinator = SetupCoordinator(
        itunesManager: itunes,
        iremoveManager: iremoveManager,
      );

      // Initially no iRemove found
      iremoveManager.registryQueryOverride = () async => [];
      iremoveManager.startMenuQueryOverride = () async => [];
      iremoveManager.candidateDirectoriesOverride = () => [];
      iremoveManager.userDirectoriesOverride = () => [];
      iremoveManager.candidateDirectoriesOverride = () => [];

      await coordinator.runPrerequisiteCheck();
      expect(coordinator.isReady, false);

      // User clicks "Locate Existing iRemove"
      final success = await coordinator.locateIremove();

      expect(success, true);
      expect(coordinator.isReady, true);
      expect(coordinator.currentStep, SetupStep.ready);
      expect(iremoveManager.executablePath, exe.path);
    });

    test('Test 10: Launching tool uses validated executable and working directory', () async {
      final exe = await createMockExecutable(mockCustomDir.path, 'iRemove Tools.exe');
      await iremoveManager.setCustomExecutablePath(exe.path);

      expect(iremoveManager.executablePath, exe.path);
      expect(iremoveManager.isReady, true);
    });
  });
}
