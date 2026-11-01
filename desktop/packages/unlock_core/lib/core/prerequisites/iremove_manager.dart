import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../device/device_info.dart';
import '../logging/app_logger.dart';
import 'windows_checker_helper.dart';

enum IRemoveStatus {
  notChecked,
  checking,
  installed,
  missing,
  invalidExecutable,
  downloading,
  extracting,
  validating,
  failed,
}

class IRemoveManager extends ChangeNotifier {
  static const String downloadEndpoint =
      'https://iremove.tools/download-software-a12-win';
  static const String officialWebsiteUrl =
      'https://iremove.tools';

  // Persistence keys
  static const String kSavedExePath = 'iremove_saved_exe_path_v2';
  static const String kSavedVersion = 'iremove_saved_version_v2';
  static const String kSavedSource = 'iremove_saved_source_v2';
  static const String kSavedSignatureVerified = 'iremove_saved_sig_verified_v2';
  static const String kSavedPublisherInfo = 'iremove_saved_publisher_v2';
  static const String kSavedTimestamp = 'iremove_saved_timestamp_v2';

  IRemoveStatus _status = IRemoveStatus.notChecked;
  String _statusMessage = '';
  double _downloadProgress = 0.0;
  double _extractionProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;

  String? _executablePath;
  String? _detectedVersion;
  String? _detectionSource;
  bool _isCustomLocation = false;
  String? _publisherInfo;
  bool _isSignatureVerified = false;
  DateTime? _lastVerifiedAt;

  // Test overrides for deterministic unit testing
  Future<List<Map<String, String>>> Function()? registryQueryOverride;
  Future<List<String>> Function()? startMenuQueryOverride;
  Future<String?> Function()? filePickerOverride;
  Future<bool> Function(File)? executableValidatorOverride;
  Directory Function()? installDirectoryOverride;
  List<String> Function()? candidateDirectoriesOverride;
  List<String> Function()? userDirectoriesOverride;

  IRemoveStatus get status => _status;
  String get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;
  double get extractionProgress => _extractionProgress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get executablePath => _executablePath;
  String? get detectedVersion => _detectedVersion;
  String? get detectionSource => _detectionSource;
  bool get isCustomLocation => _isCustomLocation;
  String? get publisherInfo => _publisherInfo;
  bool get isSignatureVerified => _isSignatureVerified;
  DateTime? get lastVerifiedAt => _lastVerifiedAt;

  bool get isReady =>
      _status == IRemoveStatus.installed &&
      _executablePath != null &&
      File(_executablePath!).existsSync();

  /// Returns the dedicated versioned directory under %LOCALAPPDATA%\414Unlock\iremove\v1
  Directory getInstallDirectory() {
    if (installDirectoryOverride != null) {
      return installDirectoryOverride!();
    }
    final localAppData = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        r'C:\Users\Default\AppData\Local';
    return Directory(p.join(localAppData, '414Unlock', 'iremove', 'v1'));
  }

  /// Validates that a file is a usable Windows executable
  Future<bool> validateExecutableFile(File file) async {
    if (executableValidatorOverride != null) {
      return await executableValidatorOverride!(file);
    }

    try {
      if (!file.existsSync()) return false;
      if (!FileSystemEntity.isFileSync(file.path)) return false;
      if (!file.path.toLowerCase().endsWith('.exe')) return false;

      final len = file.lengthSync();
      // Minimum executable threshold (50 KB)
      if (len < 50 * 1024) return false;

      // Check PE executable magic bytes: 0x4D, 0x5A ('MZ')
      final handle = await file.open(mode: FileMode.read);
      final magic = await handle.read(2);
      await handle.close();

      if (magic.length < 2 || magic[0] != 0x4D || magic[1] != 0x5A) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Multi-stage detection: checks saved path, registry, shortcuts, known dirs, cache, and bounded user folders.
  /// Never downloads automatically if not found.
  Future<bool> checkInstalled({bool forceRescan = false}) async {
    _status = IRemoveStatus.checking;
    _statusMessage = 'Checking for existing iRemove installation...';
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // -------------------------------------------------------------
      // Stage 1: Previously saved executable path in SharedPreferences
      // -------------------------------------------------------------
      if (!forceRescan) {
        final savedPath = prefs.getString(kSavedExePath);
        if (savedPath != null && savedPath.trim().isNotEmpty) {
          final savedFile = File(savedPath.trim());
          if (await validateExecutableFile(savedFile)) {
            _executablePath = savedFile.path;
            _detectedVersion = prefs.getString(kSavedVersion);
            _detectionSource = prefs.getString(kSavedSource) ?? 'Saved Configuration';
            _isSignatureVerified = prefs.getBool(kSavedSignatureVerified) ?? false;
            _publisherInfo = prefs.getString(kSavedPublisherInfo);
            final timeMs = prefs.getInt(kSavedTimestamp);
            _lastVerifiedAt = timeMs != null ? DateTime.fromMillisecondsSinceEpoch(timeMs) : DateTime.now();
            _isCustomLocation = _detectionSource == 'Custom Location' ||
                !p.isWithin(getInstallDirectory().path, _executablePath!);

            _status = IRemoveStatus.installed;
            _statusMessage = 'iRemove ready (${p.basename(_executablePath!)})';
            await AppConfig().setPartnerExecutablePath(_executablePath!);
            AppLogger().info(
              'Restored valid saved iRemove executable: $_executablePath (Source: $_detectionSource, Version: $_detectedVersion)',
            );
            notifyListeners();
            return true;
          } else {
            AppLogger().warning('Previously saved iRemove executable is missing or invalid: $savedPath');
            await clearSavedConfiguration();
          }
        }

        // Check AppConfig partner path as secondary fallback
        final appConfigPath = AppConfig().partnerExecutablePath;
        if (appConfigPath.isNotEmpty && appConfigPath.toLowerCase().contains('iremove')) {
          final acFile = File(appConfigPath);
          if (await validateExecutableFile(acFile)) {
            await _onExecutableDiscovered(
              acFile,
              source: 'Application Configuration',
              version: null,
            );
            return true;
          }
        }
      }

      // -------------------------------------------------------------
      // Stage 2: Windows Uninstall Registry
      // -------------------------------------------------------------
      final registryEntries = registryQueryOverride != null
          ? await registryQueryOverride!()
          : await WindowsCheckerHelper.queryWindowsUninstallEntries('iremove');

      for (final entry in registryEntries) {
        final installLoc = entry['InstallLocation'];
        final displayIcon = entry['DisplayIcon'];
        final displayName = entry['DisplayName'] ?? 'iRemove Tools';
        final displayVersion = entry['DisplayVersion'];

        if (installLoc != null && installLoc.trim().isNotEmpty) {
          final dir = Directory(installLoc.trim());
          if (dir.existsSync()) {
            final exe = await _findExecutableInDirectory(dir);
            if (exe != null && await validateExecutableFile(exe)) {
              await _onExecutableDiscovered(
                exe,
                source: 'Windows Registry ($displayName)',
                version: displayVersion,
              );
              return true;
            }
          }
        }

        if (displayIcon != null && displayIcon.trim().isNotEmpty) {
          final iconPath = displayIcon.split(',')[0].trim();
          if (iconPath.toLowerCase().endsWith('.exe')) {
            final exe = File(iconPath);
            if (await validateExecutableFile(exe)) {
              await _onExecutableDiscovered(
                exe,
                source: 'Windows Registry ($displayName)',
                version: displayVersion,
              );
              return true;
            }
          }
        }
      }

      // -------------------------------------------------------------
      // Stage 3: Start Menu Shortcuts
      // -------------------------------------------------------------
      final shortcutTargets = startMenuQueryOverride != null
          ? await startMenuQueryOverride!()
          : await WindowsCheckerHelper.queryStartMenuShortcuts('iremove');

      for (final targetPath in shortcutTargets) {
        final exe = File(targetPath);
        if (await validateExecutableFile(exe)) {
          final ver = await WindowsCheckerHelper.getFileVersion(exe.path);
          await _onExecutableDiscovered(
            exe,
            source: 'Start Menu Shortcut',
            version: ver,
          );
          return true;
        }
      }

      // -------------------------------------------------------------
      // Stage 4: Known Standard Installation Locations
      // -------------------------------------------------------------
      final candidateDirs = candidateDirectoriesOverride != null
          ? candidateDirectoriesOverride!()
          : _getStandardCandidateDirectories();

      for (final rawDir in candidateDirs) {
        final dir = Directory(WindowsCheckerHelper.expandEnvironmentVariables(rawDir));
        if (dir.existsSync()) {
          final exe = await _findExecutableInDirectory(dir);
          if (exe != null && await validateExecutableFile(exe)) {
            final ver = await WindowsCheckerHelper.getFileVersion(exe.path);
            await _onExecutableDiscovered(
              exe,
              source: 'Standard Installation Directory',
              version: ver,
            );
            return true;
          }
        }
      }

      // -------------------------------------------------------------
      // Stage 5: Existing 414Unlock Download/Extraction Cache
      // -------------------------------------------------------------
      final cacheDir = getInstallDirectory();
      if (cacheDir.existsSync()) {
        final exe = await _findExecutableInDirectory(cacheDir);
        if (exe != null && await validateExecutableFile(exe)) {
          final ver = await WindowsCheckerHelper.getFileVersion(exe.path);
          await _onExecutableDiscovered(
            exe,
            source: '414Unlock Application Cache',
            version: ver,
          );
          return true;
        }
      }

      // -------------------------------------------------------------
      // Stage 6: Bounded Search in User Directories (Desktop, Downloads)
      // -------------------------------------------------------------
      final boundedUserDirs = userDirectoriesOverride != null
          ? userDirectoriesOverride!()
          : _getBoundedUserDirectories();
      for (final rawDir in boundedUserDirs) {
        final dir = Directory(WindowsCheckerHelper.expandEnvironmentVariables(rawDir));
        if (dir.existsSync()) {
          final exe = await _findExecutableInDirectory(dir, maxDepth: 1);
          if (exe != null && await validateExecutableFile(exe)) {
            final ver = await WindowsCheckerHelper.getFileVersion(exe.path);
            await _onExecutableDiscovered(
              exe,
              source: 'User Directory (${p.basename(dir.path)})',
              version: ver,
            );
            return true;
          }
        }
      }

      // If all automatic stages fail: DO NOT download automatically!
      _status = IRemoveStatus.missing;
      _statusMessage = 'iRemove was not detected in standard locations or registry.';
      _executablePath = null;
      notifyListeners();
      return false;
    } catch (e) {
      _status = IRemoveStatus.missing;
      _statusMessage = 'Error during iRemove detection: $e';
      AppLogger().warning(_statusMessage);
      notifyListeners();
      return false;
    }
  }

  /// Sets and validates an executable path explicitly chosen by the user
  Future<bool> setCustomExecutablePath(String rawPath) async {
    _status = IRemoveStatus.checking;
    _statusMessage = 'Validating selected executable...';
    notifyListeners();

    final expanded = WindowsCheckerHelper.expandEnvironmentVariables(rawPath.trim());
    final file = File(expanded);

    if (!await validateExecutableFile(file)) {
      _status = IRemoveStatus.invalidExecutable;
      _statusMessage = 'Selected file is not a valid iRemove executable.';
      AppLogger().warning('Rejected invalid iRemove custom executable: $expanded');
      notifyListeners();
      return false;
    }

    final ver = await WindowsCheckerHelper.getFileVersion(file.path);
    await _onExecutableDiscovered(
      file,
      source: 'Custom Location',
      version: ver,
      isCustom: true,
    );
    return true;
  }

  /// Opens the Windows file picker for the user to select an existing executable
  Future<bool> locateExecutableUsingPicker() async {
    try {
      final selectedPath = filePickerOverride != null
          ? await filePickerOverride!()
          : await WindowsCheckerHelper.showWindowsOpenFileDialog(
              title: 'Locate iRemove Executable',
              filter: 'Executable Files (*.exe)|*.exe|All Files (*.*)|*.*',
              initialDirectory: r'C:\Program Files',
            );

      if (selectedPath != null && selectedPath.trim().isNotEmpty) {
        return await setCustomExecutablePath(selectedPath);
      }
      return false;
    } catch (e) {
      AppLogger().warning('Failed to open file picker: $e');
      return false;
    }
  }

  /// Saves discovered executable metadata and updates active state
  Future<void> _onExecutableDiscovered(
    File exe, {
    required String source,
    String? version,
    bool isCustom = false,
  }) async {
    _executablePath = exe.path;
    _detectedVersion = version;
    _detectionSource = source;
    _isCustomLocation = isCustom || !p.isWithin(getInstallDirectory().path, exe.path);
    _lastVerifiedAt = DateTime.now();

    await _verifyPublisherInfo(exe);

    _status = IRemoveStatus.installed;
    _statusMessage = 'iRemove ready (${p.basename(exe.path)})';

    await _persistConfiguration(
      exe.path,
      version: version,
      source: source,
      isVerified: _isSignatureVerified,
      publisher: _publisherInfo,
    );

    await AppConfig().setPartnerExecutablePath(exe.path);

    AppLogger().info(
      'iRemove verified and ready: ${exe.path} (Source: $source, Version: ${version ?? "unknown"}, Signed: $_isSignatureVerified)',
    );
    notifyListeners();
  }

  /// Persists confirmed configuration to SharedPreferences
  Future<void> _persistConfiguration(
    String path, {
    String? version,
    String? source,
    bool isVerified = false,
    String? publisher,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSavedExePath, path);
      if (version != null && version.isNotEmpty) {
        await prefs.setString(kSavedVersion, version);
      } else {
        await prefs.remove(kSavedVersion);
      }
      if (source != null && source.isNotEmpty) {
        await prefs.setString(kSavedSource, source);
      }
      await prefs.setBool(kSavedSignatureVerified, isVerified);
      if (publisher != null && publisher.isNotEmpty) {
        await prefs.setString(kSavedPublisherInfo, publisher);
      }
      await prefs.setInt(kSavedTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger().warning('Could not persist iRemove configuration: $e');
    }
  }

  /// Clears saved executable configuration
  Future<void> clearSavedConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kSavedExePath);
      await prefs.remove(kSavedVersion);
      await prefs.remove(kSavedSource);
      await prefs.remove(kSavedSignatureVerified);
      await prefs.remove(kSavedPublisherInfo);
      await prefs.remove(kSavedTimestamp);
    } catch (_) {}
  }

  /// Downloads package from official endpoint.
  /// Never wipes existing working files if download fails.
  Future<bool> downloadAndExtract() async {
    _status = IRemoveStatus.downloading;
    _downloadProgress = 0.0;
    _extractionProgress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _statusMessage = 'Connecting to iRemove download service...';
    notifyListeners();

    AppLogger().info('Initiating explicit iRemove download from: $downloadEndpoint');

    HttpClient? client;
    try {
      final installDir = getInstallDirectory();
      if (!installDir.existsSync()) {
        installDir.createSync(recursive: true);
      }

      final tempDir = Directory(p.join(installDir.parent.path, 'temp'));
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20)
        ..badCertificateCallback = ((cert, host, port) => false);

      Uri currentUri = Uri.parse(downloadEndpoint);
      HttpClientResponse? response;
      int redirectCount = 0;

      while (redirectCount < 8) {
        final request = await client.getUrl(currentUri);
        request.followRedirects = false;
        response = await request.close();

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw Exception('Redirect with missing Location header');
          }
          currentUri = currentUri.resolve(location);
          redirectCount++;
          AppLogger().info('Following download redirect ($redirectCount) -> $currentUri');
        } else {
          break;
        }
      }

      if (response == null || response.statusCode != HttpStatus.ok) {
        throw Exception(
          'Download server returned ${response?.statusCode}: ${response?.reasonPhrase}',
        );
      }

      final contentType = response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      _totalBytes = response.contentLength;

      if (contentType.toLowerCase().contains('text/html')) {
        throw Exception(
          'Server returned an HTML page instead of the expected installer package. Please use the official download page.',
        );
      }

      final tempFile = File(p.join(tempDir.path, 'download_${DateTime.now().millisecondsSinceEpoch}.tmp'));
      final sink = tempFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        _downloadedBytes += chunk.length;
        if (_totalBytes > 0) {
          _downloadProgress = _downloadedBytes / _totalBytes;
        }
        _statusMessage = _totalBytes > 0
            ? 'Downloading iRemove: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${(_downloadProgress * 100).toStringAsFixed(0)}%)'
            : 'Downloading iRemove: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        notifyListeners();
      }

      await sink.flush();
      await sink.close();
      client.close();
      client = null;

      // Validate downloaded payload
      final handle = await tempFile.open(mode: FileMode.read);
      final magic = await handle.read(4);
      await handle.close();

      if (magic.length < 2) {
        throw Exception('Downloaded file is empty or incomplete.');
      }

      final isZip = magic.length >= 4 &&
          magic[0] == 0x50 &&
          magic[1] == 0x4B &&
          magic[2] == 0x03 &&
          magic[3] == 0x04;
      final isExe = magic[0] == 0x4D && magic[1] == 0x5A; // MZ

      if (!isZip && !isExe) {
        throw Exception(
          'Unrecognized file signature. Neither a valid ZIP archive nor Windows PE binary.',
        );
      }

      if (isZip) {
        _status = IRemoveStatus.extracting;
        _statusMessage = 'Extracting iRemove package...';
        notifyListeners();

        final bytes = await tempFile.readAsBytes();
        await _safeExtractZip(bytes, installDir);
      } else {
        _status = IRemoveStatus.validating;
        _statusMessage = 'Configuring executable package...';
        notifyListeners();

        final targetExe = File(p.join(installDir.path, 'iRemove Tools.exe'));
        if (targetExe.existsSync()) {
          try {
            targetExe.deleteSync();
          } catch (_) {}
        }
        await tempFile.copy(targetExe.path);
      }

      try {
        tempFile.deleteSync();
      } catch (_) {}

      final discoveredExe = await _findExecutableInDirectory(installDir);
      if (discoveredExe == null || !discoveredExe.existsSync()) {
        throw Exception('Extraction completed, but no executable file was discovered in $installDir');
      }

      final ver = await WindowsCheckerHelper.getFileVersion(discoveredExe.path);
      await _onExecutableDiscovered(
        discoveredExe,
        source: 'Downloaded Package (414Unlock Cache)',
        version: ver,
      );
      return true;
    } catch (e) {
      client?.close(force: true);
      _status = IRemoveStatus.failed;
      _statusMessage = 'iRemove download failed: $e';
      AppLogger().error('iRemove setup error', e.toString());
      notifyListeners();
      return false;
    }
  }

  /// Safely extracts ZIP archive rejecting directory traversal entries
  Future<void> _safeExtractZip(Uint8List zipBytes, Directory destinationDir) async {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final canonicalDest = destinationDir.resolveSymbolicLinksSync();

    int extracted = 0;
    final total = archive.files.length;

    for (final file in archive.files) {
      final normalized = p.normalize(file.name);
      if (normalized.startsWith('..') ||
          p.isAbsolute(normalized) ||
          normalized.contains(':') ||
          normalized.contains(r'..\') ||
          normalized.contains('../')) {
        AppLogger().warning('Blocked zip entry with path traversal: ${file.name}');
        continue;
      }

      final outPath = p.join(canonicalDest, normalized);
      if (!p.isWithin(canonicalDest, outPath)) {
        AppLogger().warning('Blocked zip entry escaping root directory: ${file.name}');
        continue;
      }

      if (file.isFile) {
        final outFile = File(outPath);
        final parentDir = outFile.parent;
        if (!parentDir.existsSync()) {
          parentDir.createSync(recursive: true);
        }
        final dynamic raw = file.content;
        if (raw is List<int>) {
          await outFile.writeAsBytes(raw, flush: true);
        } else if (raw != null) {
          await outFile.writeAsBytes((raw as dynamic).toUint8List() as List<int>, flush: true);
        }
      } else {
        Directory(outPath).createSync(recursive: true);
      }

      extracted++;
      _extractionProgress = total > 0 ? extracted / total : 1.0;
      _statusMessage = 'Extracting: $extracted / $total files (${(_extractionProgress * 100).toStringAsFixed(0)}%)';
      notifyListeners();
    }
  }

  /// Discovers the actual executable within the directory up to maxDepth
  Future<File?> _findExecutableInDirectory(Directory dir, {int maxDepth = 2}) async {
    if (!dir.existsSync()) return null;

    final candidates = <File>[];
    try {
      final entities = dir.listSync(recursive: maxDepth > 1);
      for (final item in entities) {
        if (item is File && item.path.toLowerCase().endsWith('.exe')) {
          candidates.add(item);
        }
      }
    } catch (_) {}

    if (candidates.isEmpty) return null;

    // Preference 1: Contains 'iremove' in filename
    for (final c in candidates) {
      final base = p.basename(c.path).toLowerCase();
      if (base.contains('iremove')) {
        return c;
      }
    }

    // Preference 2: Parent folder contains 'iremove'
    for (final c in candidates) {
      if (c.parent.path.toLowerCase().contains('iremove')) {
        return c;
      }
    }

    return candidates.first;
  }

  /// Verifies file signature / publisher information
  Future<void> _verifyPublisherInfo(File exeFile) async {
    if (!Platform.isWindows) {
      _isSignatureVerified = true;
      _publisherInfo = 'Signature verification simulated (Non-Windows)';
      return;
    }

    try {
      final output = await WindowsCheckerHelper.runPowerShell(
        r'''
        $sig = Get-AuthenticodeSignature "''' + exeFile.path + r'''"
        "$($sig.Status)|$($sig.SignerCertificate.Subject)"
        ''',
        timeoutSeconds: 4,
      );

      if (output != null && output.contains('|')) {
        final parts = output.trim().split('|');
        final status = parts[0].trim();
        final subject = parts.length > 1 ? parts[1].trim() : '';

        if (status == 'Valid' && subject.isNotEmpty) {
          _isSignatureVerified = true;
          _publisherInfo = 'Verified Authenticode signature ($subject)';
        } else {
          _isSignatureVerified = false;
          _publisherInfo = 'Publisher signature status: $status';
        }
      } else {
        _isSignatureVerified = false;
        _publisherInfo = 'No publisher signature record found';
      }
    } catch (_) {
      _isSignatureVerified = false;
      _publisherInfo = 'Signature verification unavailable';
    }
  }

  Process? _activeProcess;
  int? _activePid;

  /// Launches the confirmed, validated iRemove executable
  Future<bool> launchTool([DeviceInfo? device]) async {
    if (_executablePath == null || !File(_executablePath!).existsSync()) {
      _status = IRemoveStatus.failed;
      _statusMessage = 'iRemove executable not found on disk at configured path.';
      notifyListeners();
      return false;
    }

    try {
      final exeFile = File(_executablePath!);
      AppLogger().info('Launching validated iRemove tool: ${exeFile.path}');

      final process = await Process.start(
        exeFile.path,
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: exeFile.parent.path,
      );
      _activeProcess = process;
      _activePid = process.pid;

      AppLogger().engine('iRemove process launched successfully (PID: ${process.pid})');
      return true;
    } catch (e) {
      _statusMessage = 'Failed to launch iRemove: $e';
      AppLogger().error('Failed to launch iRemove tool', e.toString());
      notifyListeners();
      return false;
    }
  }

  /// Closes and terminates the running partner tool when the operation finishes or is cancelled.
  Future<void> terminateTool() async {
    try {
      if (_activeProcess != null) {
        _activeProcess!.kill();
        _activeProcess = null;
      }
      if (_activePid != null && Platform.isWindows) {
        try {
          await Process.run('taskkill', ['/F', '/PID', '$_activePid'], runInShell: true);
        } catch (_) {}
        _activePid = null;
      }
      if (Platform.isWindows && _executablePath != null) {
        final exeName = p.basename(_executablePath!);
        try {
          await Process.run('taskkill', ['/F', '/IM', exeName], runInShell: true);
        } catch (_) {}
      }
      AppLogger().info('Cleaned up and terminated partner tool processes');
    } catch (e) {
      AppLogger().info('Tool termination note: $e');
    }
  }

  /// Opens the official iRemove download page in default browser
  Future<void> openDownloadPage() async {
    try {
      final uri = Uri.parse(officialWebsiteUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AppLogger().error('Failed to open iRemove download page', e.toString());
    }
  }

  List<String> _getStandardCandidateDirectories() {
    return [
      r'C:\Program Files\iRemoveTools',
      r'C:\Program Files (x86)\iRemoveTools',
      r'C:\Program Files\iRemove',
      r'C:\Program Files (x86)\iRemove',
      r'%APPDATA%\iRemoveTools',
      r'%LOCALAPPDATA%\iRemoveTools',
    ];
  }

  List<String> _getBoundedUserDirectories() {
    return [
      r'%USERPROFILE%\Desktop',
      r'%USERPROFILE%\Downloads',
    ];
  }
}
