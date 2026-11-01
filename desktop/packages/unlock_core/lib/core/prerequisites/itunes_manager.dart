import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../device/apple_usbmux_client.dart';
import '../logging/app_logger.dart';
import 'windows_checker_helper.dart';

enum ITunesInstallStatus {
  notChecked,
  checking,
  installed,
  missing,
  downloading,
  validating,
  installRequired,
  installing,
  failed,
}

class ITunesManager extends ChangeNotifier {
  static const String officialInstallerUrl =
      'https://secure-appldnld.apple.com/itunes12/001-80053-20210422-E8A3B28C-A3B2-11EB-BE07-CE1B67FC6302/iTunes64Setup.exe';
  static const String fallbackSupportUrl =
      'https://support.apple.com/HT210384';

  ITunesInstallStatus _status = ITunesInstallStatus.notChecked;
  String _detectedVersion = '';
  String _statusMessage = '';
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _installerPath;
  Timer? _installPollTimer;
  HttpClient? _activeClient;
  bool _isCancelled = false;
  bool _isChecking = false;

  ITunesInstallStatus get status => _status;
  String get detectedVersion => _detectedVersion;
  String get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get installerPath => _installerPath;

  bool get isReady => _status == ITunesInstallStatus.installed;

  /// Checks whether a compatible iTunes / Apple Mobile Device Support installation is present
  Future<bool> checkInstalled() async {
    if (_isChecking) return isReady;
    _isChecking = true;

    _status = ITunesInstallStatus.checking;
    _statusMessage = 'Checking Apple device communication components...';
    notifyListeners();

    try {
      // 1. Direct file check for Apple Mobile Device Service or iTunes executable
      final serviceExe = WindowsCheckerHelper.findFirstExisting([
        r'C:\Program Files\Common Files\Apple\Mobile Device Support\AppleMobileDeviceService.exe',
        r'C:\Program Files (x86)\Common Files\Apple\Mobile Device Support\AppleMobileDeviceService.exe',
        r'C:\Program Files\iTunes\iTunes.exe',
        r'C:\Program Files (x86)\iTunes\iTunes.exe',
      ]);

      if (serviceExe != null) {
        _detectedVersion = 'Apple Mobile Device Support';
        _status = ITunesInstallStatus.installed;
        _statusMessage = 'Apple device communication components verified at: $serviceExe';
        AppLogger().hardware(_statusMessage);
        notifyListeners();
        return true;
      }

      // 2. Check if usbmuxd port 27015 is actively listening
      final isPortActive = await AppleUsbmuxClient.isServiceAvailable();
      if (isPortActive) {
        _detectedVersion = 'Apple Mobile Device Service (Active)';
        _status = ITunesInstallStatus.installed;
        _statusMessage = 'Apple Mobile Device Service is active on local system.';
        AppLogger().hardware(_statusMessage);
        notifyListeners();
        return true;
      }

      // 3. Fast check via cached registry uninstall entries
      final entries = await WindowsCheckerHelper.queryWindowsUninstallEntries('iTunes');
      if (entries.isNotEmpty) {
        final version = entries.first['DisplayVersion'] ?? 'Installed';
        _detectedVersion = version;
        _status = ITunesInstallStatus.installed;
        _statusMessage = 'iTunes detected in Windows records ($version).';
        AppLogger().hardware(_statusMessage);
        notifyListeners();
        return true;
      }

      final appleEntries = await WindowsCheckerHelper.queryWindowsUninstallEntries('Apple Mobile Device Support');
      if (appleEntries.isNotEmpty) {
        final version = appleEntries.first['DisplayVersion'] ?? 'Installed';
        _detectedVersion = version;
        _status = ITunesInstallStatus.installed;
        _statusMessage = 'Apple Mobile Device Support detected ($version).';
        AppLogger().hardware(_statusMessage);
        notifyListeners();
        return true;
      }

      _status = ITunesInstallStatus.missing;
      _statusMessage = '414Unlock needs iTunes to detect and communicate with your iPhone.';
      AppLogger().info(_statusMessage);
      notifyListeners();
      return false;
    } catch (e) {
      _status = ITunesInstallStatus.missing;
      _statusMessage = 'Could not verify iTunes: $e';
      AppLogger().warning(_statusMessage);
      notifyListeners();
      return false;
    } finally {
      _isChecking = false;
    }
  }

  /// Downloads the official Apple iTunes installer directly inside the application
  Future<bool> downloadInstaller({String? targetDirectory}) async {
    // Prevent duplicate concurrent downloads
    if (_status == ITunesInstallStatus.downloading) {
      return false;
    }

    _isCancelled = false;
    _status = ITunesInstallStatus.downloading;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _statusMessage = 'Connecting to Apple servers...';
    notifyListeners();

    AppLogger().info('Starting official iTunes installer download from Apple CDN: $officialInstallerUrl');

    IOSink? sink;
    try {
      final dir = targetDirectory != null
          ? Directory(targetDirectory)
          : await _getDownloadDir();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final destinationFile = File(p.join(dir.path, 'iTunes64Setup.exe'));
      _installerPath = destinationFile.path;

      _activeClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..badCertificateCallback = ((cert, host, port) => false);

      final request = await _activeClient!.getUrl(Uri.parse(officialInstallerUrl));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception(
          'Apple CDN returned status ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      _totalBytes = response.contentLength;
      sink = destinationFile.openWrite();

      await for (final chunk in response) {
        if (_isCancelled) {
          throw Exception('Download cancelled by user.');
        }

        sink.add(chunk);
        _downloadedBytes += chunk.length;
        if (_totalBytes > 0) {
          _downloadProgress = _downloadedBytes / _totalBytes;
        }
        _statusMessage = _totalBytes > 0
            ? 'Downloading iTunes: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${(_downloadProgress * 100).toStringAsFixed(0)}%)'
            : 'Downloading iTunes: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        notifyListeners();
      }

      await sink.flush();
      await sink.close();
      sink = null;
      _activeClient?.close();
      _activeClient = null;

      // Validate the downloaded file
      _status = ITunesInstallStatus.validating;
      _statusMessage = 'Validating downloaded iTunes installer...';
      notifyListeners();

      final isValid = await _validateInstaller(destinationFile);
      if (!isValid) {
        _status = ITunesInstallStatus.failed;
        _statusMessage = 'Downloaded installer failed integrity validation.';
        AppLogger().error(_statusMessage, destinationFile.path);
        notifyListeners();
        return false;
      }

      _status = ITunesInstallStatus.installRequired;
      _statusMessage = 'iTunes installer verified. Administrator approval is required to install.';
      AppLogger().info('iTunes installer verified and ready for execution');
      notifyListeners();
      return true;
    } catch (e) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      _activeClient?.close(force: true);
      _activeClient = null;

      if (_isCancelled) {
        _status = ITunesInstallStatus.missing;
        _statusMessage = 'Download cancelled.';
      } else {
        _status = ITunesInstallStatus.failed;
        _statusMessage = 'Download failed: $e';
        AppLogger().error('iTunes download error', e.toString());
      }
      notifyListeners();
      return false;
    }
  }

  /// Cancels an in-progress download
  void cancelDownload() {
    _isCancelled = true;
    _activeClient?.close(force: true);
    _activeClient = null;
    _status = ITunesInstallStatus.missing;
    _statusMessage = 'Download cancelled.';
    notifyListeners();
  }

  /// Validates the downloaded file (size, PE header)
  Future<bool> _validateInstaller(File file) async {
    if (!file.existsSync()) return false;
    final length = await file.length();
    // iTunes 64-bit installer is ~200 MB; reject if under 50 MB
    if (length < 50 * 1024 * 1024) {
      AppLogger().warning('Installer file is unexpectedly small: $length bytes');
      return false;
    }

    // Check PE header (MZ magic bytes 0x4D, 0x5A)
    final handle = await file.open(mode: FileMode.read);
    final header = await handle.read(2);
    await handle.close();
    if (header.length < 2 || header[0] != 0x4D || header[1] != 0x5A) {
      AppLogger().warning('Installer does not start with executable MZ header');
      return false;
    }

    return true;
  }

  /// Launches the iTunes installer with standard Windows UAC elevation
  Future<bool> startInstallation() async {
    if (_installerPath == null || !File(_installerPath!).existsSync()) {
      _status = ITunesInstallStatus.failed;
      _statusMessage = 'Installer file not found on disk.';
      notifyListeners();
      return false;
    }

    try {
      AppLogger().info('Launching iTunes installer: $_installerPath');
      _status = ITunesInstallStatus.installing;
      _statusMessage = 'Running iTunes setup. Please accept Windows Administrator (UAC) prompt if shown.';
      notifyListeners();

      // Launch installer; Windows will prompt UAC naturally
      await Process.start(
        _installerPath!,
        [],
        mode: ProcessStartMode.detached,
      );

      // Begin background polling for installation completion
      _startPollForInstallation();
      return true;
    } catch (e) {
      _status = ITunesInstallStatus.failed;
      _statusMessage = 'Could not launch installer: $e';
      AppLogger().error('Installer launch failed', e.toString());
      notifyListeners();
      return false;
    }
  }

  void _startPollForInstallation() {
    _installPollTimer?.cancel();
    int attempts = 0;
    _installPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      attempts++;
      final installed = await checkInstalled();
      if (installed) {
        timer.cancel();
        _status = ITunesInstallStatus.installed;
        _statusMessage = 'iTunes installation verified successfully.';
        AppLogger().info(_statusMessage);
        notifyListeners();
      } else if (attempts > 90) { // 6 minutes max
        timer.cancel();
      }
    });
  }

  /// Opens the official Apple fallback download page in default browser
  Future<void> openOfficialDownloadPage() async {
    try {
      final uri = Uri.parse(officialInstallerUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(Uri.parse(fallbackSupportUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AppLogger().error('Failed to open download page', e.toString());
    }
  }

  Future<Directory> _getDownloadDir() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      return Directory(p.join(appSupport.path, 'downloads'));
    } catch (_) {
      final temp = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['TEMP'] ?? '.';
      return Directory(p.join(temp, '414Unlock', 'downloads'));
    }
  }

  @override
  void dispose() {
    _installPollTimer?.cancel();
    _activeClient?.close(force: true);
    super.dispose();
  }
}
