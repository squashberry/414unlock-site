import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../logging/app_logger.dart';
import '../prerequisites/windows_checker_helper.dart';

class AndroidPlatformToolsManager {
  AndroidPlatformToolsManager._();

  static const String officialZipUrl =
      'https://dl.google.com/android/repository/platform-tools-latest-windows.zip';

  static String? _cachedAdbPath;
  static String? _cachedFastbootPath;
  static bool _isDownloading = false;

  /// Test injection hook for mocking download
  static Future<bool> Function()? mockDownloadHandler;

  static String getManagedToolsDir() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ??
        (Platform.environment['USERPROFILE'] != null
            ? '${Platform.environment['USERPROFILE']}\\AppData\\Local'
            : 'C:\\414Unlock');
    return '$localAppData\\414Unlock\\platform-tools';
  }

  static Future<String?> findAdb() async {
    if (_cachedAdbPath != null && File(_cachedAdbPath!).existsSync()) {
      return _cachedAdbPath;
    }

    final pathAdb = await WindowsCheckerHelper.findExecutableOnPath('adb.exe');
    if (pathAdb != null) {
      _cachedAdbPath = pathAdb;
      return pathAdb;
    }

    final managedAdb = '${getManagedToolsDir()}\\platform-tools\\adb.exe';
    if (File(managedAdb).existsSync()) {
      _cachedAdbPath = managedAdb;
      return managedAdb;
    }

    final managedDirectAdb = '${getManagedToolsDir()}\\adb.exe';
    if (File(managedDirectAdb).existsSync()) {
      _cachedAdbPath = managedDirectAdb;
      return managedDirectAdb;
    }

    final existing = WindowsCheckerHelper.findFirstExisting([
      r'%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe',
      r'C:\Android\platform-tools\adb.exe',
      r'C:\platform-tools\adb.exe',
      r'%USERPROFILE%\platform-tools\adb.exe',
    ]);

    if (existing != null) {
      _cachedAdbPath = existing;
      return existing;
    }

    return null;
  }

  static Future<String?> findFastboot() async {
    if (_cachedFastbootPath != null && File(_cachedFastbootPath!).existsSync()) {
      return _cachedFastbootPath;
    }

    final pathFb = await WindowsCheckerHelper.findExecutableOnPath('fastboot.exe');
    if (pathFb != null) {
      _cachedFastbootPath = pathFb;
      return pathFb;
    }

    final managedFb = '${getManagedToolsDir()}\\platform-tools\\fastboot.exe';
    if (File(managedFb).existsSync()) {
      _cachedFastbootPath = managedFb;
      return managedFb;
    }

    final managedDirectFb = '${getManagedToolsDir()}\\fastboot.exe';
    if (File(managedDirectFb).existsSync()) {
      _cachedFastbootPath = managedDirectFb;
      return managedDirectFb;
    }

    final existing = WindowsCheckerHelper.findFirstExisting([
      r'%LOCALAPPDATA%\Android\Sdk\platform-tools\fastboot.exe',
      r'C:\Android\platform-tools\fastboot.exe',
      r'C:\platform-tools\fastboot.exe',
      r'%USERPROFILE%\platform-tools\fastboot.exe',
    ]);

    if (existing != null) {
      _cachedFastbootPath = existing;
      return existing;
    }

    return null;
  }

  /// Automatically downloads official Android platform-tools from Google if missing.
  static Future<bool> ensurePlatformToolsDownloaded({
    void Function(double progress)? onProgress,
  }) async {
    if (mockDownloadHandler != null) {
      return await mockDownloadHandler!();
    }

    final existingAdb = await findAdb();
    if (existingAdb != null) {
      return true;
    }

    if (_isDownloading) return false;
    _isDownloading = true;

    try {
      AppLogger().info('Downloading official Android platform-tools from Google...');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final req = await client.getUrl(Uri.parse(officialZipUrl));
      final resp = await req.close();

      if (resp.statusCode != 200) {
        AppLogger().warning('Failed to download Android platform tools: HTTP ${resp.statusCode}');
        client.close();
        return false;
      }

      final contentLength = resp.contentLength;
      final bytesBuilder = BytesBuilder();
      int received = 0;

      await for (final chunk in resp) {
        bytesBuilder.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      }
      client.close();

      final zipBytes = bytesBuilder.toBytes();
      AppLogger().info('Downloaded ${zipBytes.length} bytes of platform-tools. Extracting...');

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final targetDir = Directory(getManagedToolsDir());
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      for (final file in archive) {
        final filename = file.name;
        final outPath = '${targetDir.path}\\$filename';
        if (file.isFile) {
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      AppLogger().info('Successfully installed Android platform-tools to ${targetDir.path}');
      _cachedAdbPath = null;
      _cachedFastbootPath = null;

      final verifiedAdb = await findAdb();
      return verifiedAdb != null;
    } catch (e) {
      AppLogger().warning('Could not auto-download Android platform tools: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }
}
