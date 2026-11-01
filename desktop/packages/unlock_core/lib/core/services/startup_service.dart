import 'dart:io';
import '../logging/app_logger.dart';

/// Manages Windows auto-start on logon into system tray.
class StartupService {
  static const String _registryKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = '414Unlock';

  /// Ensures that 414Unlock is registered in Windows Startup by default,
  /// configured to start minimized in the system tray via `--tray`.
  static Future<bool> ensureAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;

    try {
      final exePath = Platform.resolvedExecutable;
      // Wrap path in quotes and append --tray flag
      final commandValue = '"$exePath" --tray';

      final result = await Process.run('reg.exe', [
        'add',
        _registryKey,
        '/v',
        _valueName,
        '/t',
        'REG_SZ',
        '/d',
        commandValue,
        '/f',
      ]);

      if (result.exitCode == 0) {
        AppLogger().info('Windows auto-start registered: $commandValue');
        return true;
      } else {
        AppLogger().warning('Failed to register auto-start: ${result.stderr}');
        return false;
      }
    } catch (e) {
      AppLogger().warning('Error configuring Windows auto-start: $e');
      return false;
    }
  }

  /// Removes 414Unlock from Windows Startup if user opts out.
  static Future<bool> disableAutoStart() async {
    if (!Platform.isWindows) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;

    try {
      final result = await Process.run('reg.exe', [
        'delete',
        _registryKey,
        '/v',
        _valueName,
        '/f',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      AppLogger().warning('Error disabling Windows auto-start: $e');
      return false;
    }
  }

  /// Checks if 414Unlock auto-start is registered in registry.
  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;

    try {
      final result = await Process.run('reg.exe', [
        'query',
        _registryKey,
        '/v',
        _valueName,
      ]);
      return result.exitCode == 0 && result.stdout.toString().contains(_valueName);
    } catch (_) {
      return false;
    }
  }
}
