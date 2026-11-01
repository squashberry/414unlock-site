import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// Lightweight supervisor service that detects when a user attempts to launch
/// the partner application directly while 414Unlock is docked in the system tray.
/// Terminates the rogue partner process and restores 414Unlock to the foreground.
class PartnerSupervisorService {
  static final PartnerSupervisorService _instance =
      PartnerSupervisorService._internal();
  factory PartnerSupervisorService() => _instance;
  PartnerSupervisorService._internal();

  Timer? _monitorTimer;
  bool _isMonitoring = false;
  bool _isPaused = false;
  bool _isScanning = false;

  /// Callback invoked when direct partner application launch is detected and killed.
  VoidCallback? onPartnerDirectLaunchDetected;

  /// Test injection hook for unit tests.
  @visibleForTesting
  static List<String> Function()? mockRunningProcessesProvider;

  @visibleForTesting
  static Future<void> Function(String processName)? mockKillProcessHandler;

  bool get isMonitoring => _isMonitoring;
  bool get isPaused => _isPaused;

  /// Temporarily pause supervision (e.g., when 414Unlock itself launches the partner tool).
  void pause() {
    _isPaused = true;
  }

  /// Resume supervision after 414Unlock finishes its partner operation.
  void resume() {
    _isPaused = false;
  }

  /// Start background monitoring. Lightweight scan every 2.5 seconds.
  void start() {
    if (_isMonitoring) return;
    if (!Platform.isWindows && mockRunningProcessesProvider == null) return;
    if (Platform.environment.containsKey('FLUTTER_TEST') &&
        mockRunningProcessesProvider == null) {
      return;
    }

    _isMonitoring = true;
    _isPaused = false;

    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _checkProcesses();
    });
  }

  /// Stop background monitoring.
  void stop() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// Targets to watch for direct launch.
  Set<String> _getTargetProcessNames() {
    final targets = <String>{
      'iremove tools.exe',
      'iremove.exe',
      'iremovetools.exe',
    };

    final customPath = AppConfig().partnerExecutablePath;
    if (customPath.isNotEmpty) {
      targets.add(p.basename(customPath).toLowerCase());
    }

    return targets;
  }

  Future<void> _checkProcesses() async {
    if (!_isMonitoring || _isPaused || _isScanning) return;
    _isScanning = true;

    try {
      final targets = _getTargetProcessNames();
      final detected = <String>[];

      if (mockRunningProcessesProvider != null) {
        final current = mockRunningProcessesProvider!();
        for (final proc in current) {
          if (targets.contains(proc.toLowerCase())) {
            detected.add(proc);
          }
        }
      } else if (Platform.isWindows) {
        // Query matching iRemove processes via tasklist with CSV output
        final result = await Process.run('tasklist.exe', [
          '/FI',
          'IMAGENAME eq iRemove*',
          '/FO',
          'CSV',
          '/NH',
        ]);

        if (result.exitCode == 0) {
          final stdout = result.stdout.toString();
          for (final line in stdout.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('INFO:')) continue;
            // CSV first column is "Image Name"
            final match = RegExp(r'^"([^"]+)"').firstMatch(trimmed);
            if (match != null) {
              final imgName = match.group(1)!;
              if (targets.contains(imgName.toLowerCase())) {
                detected.add(imgName);
              }
            }
          }
        }

        // Also check custom partner executable if configured
        final customPath = AppConfig().partnerExecutablePath;
        if (customPath.isNotEmpty) {
          final customName = p.basename(customPath);
          if (!customName.toLowerCase().startsWith('iremove')) {
            final customResult = await Process.run('tasklist.exe', [
              '/FI',
              'IMAGENAME eq $customName',
              '/FO',
              'CSV',
              '/NH',
            ]);
            if (customResult.exitCode == 0 &&
                customResult.stdout.toString().contains(customName)) {
              detected.add(customName);
            }
          }
        }
      }

      for (final procName in detected) {
        // Kill the directly opened partner application immediately
        AppLogger().warning(
          'Detected unauthorized direct execution of partner tool "$procName". Terminating and restoring 414Unlock...',
        );

        if (mockKillProcessHandler != null) {
          await mockKillProcessHandler!(procName);
        } else if (Platform.isWindows) {
          await Process.run('taskkill.exe', ['/F', '/T', '/IM', procName]);
        }

        // Signal 414Unlock to surface and focus
        onPartnerDirectLaunchDetected?.call();
      }
    } catch (e) {
      // Non-fatal scan error
    } finally {
      _isScanning = false;
    }
  }
}
