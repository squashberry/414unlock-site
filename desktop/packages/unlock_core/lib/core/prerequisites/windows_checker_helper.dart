import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../logging/app_logger.dart';

class WindowsCheckerHelper {
  static bool _isPowerShellRunning = false;
  static DateTime? _lastPowerShellWarning;

  // Cached registry & shortcut lookups
  static List<Map<String, String>>? _cachedUninstallEntries;
  static DateTime? _cachedUninstallTimestamp;

  static List<String>? _cachedShortcuts;
  static DateTime? _cachedShortcutsTimestamp;

  /// Runs a PowerShell script safely with bounded execution time,
  /// automatic process termination on timeout, and concurrency protection.
  static Future<String?> runPowerShell(
    String script, {
    Duration? timeout,
    int? timeoutSeconds,
  }) async {
    if (!Platform.isWindows) return null;

    final effectiveTimeout = timeout ?? Duration(seconds: timeoutSeconds ?? 4);

    // Prevent concurrent PowerShell instances from dogpiling
    int waitCount = 0;
    while (_isPowerShellRunning && waitCount < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      waitCount++;
    }
    if (_isPowerShellRunning) {
      return null;
    }

    _isPowerShellRunning = true;
    Process? process;

    try {
      process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        runInShell: false,
      );

      final stdoutCompleter = Completer<String>();
      final stderrCompleter = Completer<String>();

      final stdoutLines = <int>[];
      final stderrLines = <int>[];

      final subOut = process.stdout.listen(
        stdoutLines.addAll,
        onDone: () {
          if (!stdoutCompleter.isCompleted) {
            stdoutCompleter.complete(utf8.decode(stdoutLines, allowMalformed: true));
          }
        },
        onError: (_) {
          if (!stdoutCompleter.isCompleted) stdoutCompleter.complete('');
        },
      );

      final subErr = process.stderr.listen(
        stderrLines.addAll,
        onDone: () {
          if (!stderrCompleter.isCompleted) {
            stderrCompleter.complete(utf8.decode(stderrLines, allowMalformed: true));
          }
        },
        onError: (_) {
          if (!stderrCompleter.isCompleted) stderrCompleter.complete('');
        },
      );

      final exitCodeFuture = process.exitCode;

      final exitCode = await exitCodeFuture.timeout(
        effectiveTimeout,
        onTimeout: () {
          // Terminate hung process immediately
          try {
            process?.kill(ProcessSignal.sigkill);
          } catch (_) {}
          throw TimeoutException(
            'PowerShell execution timed out after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );

      await Future.wait([subOut.cancel(), subErr.cancel()]);

      if (exitCode == 0) {
        final outStr = await stdoutCompleter.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => '',
        );
        return outStr.trim();
      } else {
        return null;
      }
    } catch (e) {
      // Rate-limit warning logs (max once every 5 seconds) to avoid diagnostic log spam
      final now = DateTime.now();
      if (_lastPowerShellWarning == null || now.difference(_lastPowerShellWarning!).inSeconds >= 5) {
        _lastPowerShellWarning = now;
        AppLogger().warning('PowerShell check failed', e.toString());
      }
      return null;
    } finally {
      try {
        process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      _isPowerShellRunning = false;
    }
  }

  /// Checks if an executable exists on the Windows PATH
  static Future<String?> findExecutableOnPath(String executableName) async {
    try {
      final result = await Process.run('where.exe', [executableName]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        final valid = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (valid.isNotEmpty && File(valid.trim()).existsSync()) {
          return valid.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Queries Windows uninstall registry for entries matching a display name pattern,
  /// with memory caching to avoid repeated subprocess execution.
  static Future<List<Map<String, String>>> queryWindowsUninstallEntries(
    String namePattern, {
    bool forceRefresh = false,
  }) async {
    if (!Platform.isWindows) return [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedUninstallEntries != null &&
        _cachedUninstallTimestamp != null &&
        now.difference(_cachedUninstallTimestamp!).inMinutes < 5) {
      return _cachedUninstallEntries!;
    }

    try {
      final script = '''
      \$regKeys = @(
        'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
        'HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
        'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
      )
      foreach (\$rk in \$regKeys) {
        Get-ItemProperty \$rk -ErrorAction SilentlyContinue | Where-Object { \$_.DisplayName -like '*$namePattern*' } | ForEach-Object {
          [PSCustomObject]@{
            DisplayName = \$_.DisplayName
            DisplayVersion = \$_.DisplayVersion
            InstallLocation = \$_.InstallLocation
            DisplayIcon = \$_.DisplayIcon
            UninstallString = \$_.UninstallString
          } | ConvertTo-Json -Compress
        }
      }
      ''';
      final out = await runPowerShell(script, timeoutSeconds: 5);
      if (out == null || out.trim().isEmpty) return [];
      final lines = out.split(RegExp(r'[\r\n]+')).where((l) => l.trim().startsWith('{'));
      final list = <Map<String, String>>[];
      for (final l in lines) {
        try {
          final data = jsonDecode(l) as Map<String, dynamic>;
          list.add(data.map((k, v) => MapEntry(k, v?.toString() ?? '')));
        } catch (_) {}
      }

      _cachedUninstallEntries = list;
      _cachedUninstallTimestamp = now;
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Queries Start Menu programs for shortcuts matching name pattern and returns resolved target paths,
  /// with caching to avoid repeated scans.
  static Future<List<String>> queryStartMenuShortcuts(
    String namePattern, {
    bool forceRefresh = false,
  }) async {
    if (!Platform.isWindows) return [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedShortcuts != null &&
        _cachedShortcutsTimestamp != null &&
        now.difference(_cachedShortcutsTimestamp!).inMinutes < 5) {
      return _cachedShortcuts!;
    }

    try {
      final script = '''
      \$sh = New-Object -ComObject WScript.Shell
      \$dirs = @(
        "\$env:ProgramData\\Microsoft\\Windows\\Start Menu\\Programs",
        "\$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs"
      )
      foreach (\$d in \$dirs) {
        if (Test-Path \$d) {
          Get-ChildItem -Path \$d -Filter '*$namePattern*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
              \$target = \$sh.CreateShortcut(\$_.FullName).TargetPath
              if (\$target -and (Test-Path \$target) -and \$target.EndsWith('.exe')) {
                Write-Output \$target
              }
            } catch {}
          }
        }
      }
      ''';
      final out = await runPowerShell(script, timeoutSeconds: 5);
      if (out == null || out.trim().isEmpty) return [];
      final list = out
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.toLowerCase().endsWith('.exe'))
          .toSet()
          .toList();

      _cachedShortcuts = list;
      _cachedShortcutsTimestamp = now;
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Opens the native Windows OpenFileDialog and returns selected file path
  static Future<String?> showWindowsOpenFileDialog({
    String title = 'Locate Executable',
    String filter = 'Executable Files (*.exe)|*.exe|All Files (*.*)|*.*',
    String? initialDirectory,
  }) async {
    if (!Platform.isWindows) return null;
    try {
      final initDir = initialDirectory ?? r'C:\Program Files';
      final script = '''
      [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
      \$f = New-Object System.Windows.Forms.OpenFileDialog
      \$f.Title = "$title"
      \$f.Filter = "$filter"
      if (Test-Path "$initDir") { \$f.InitialDirectory = "$initDir" }
      \$res = \$f.ShowDialog()
      if (\$res -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Output \$f.FileName
      }
      ''';
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-Sta',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      ).timeout(const Duration(minutes: 5));

      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty && File(out).existsSync()) {
          return out;
        }
      }
    } catch (e) {
      AppLogger().warning('OpenFileDialog failed: $e');
    }
    return null;
  }

  /// Queries the product or file version of an executable on Windows
  static Future<String?> getFileVersion(String filePath) async {
    if (!Platform.isWindows) return null;
    try {
      final script = '''
      if (Test-Path "$filePath") {
        \$v = (Get-Item "$filePath").VersionInfo
        if (\$v.ProductVersion) { Write-Output \$v.ProductVersion }
        elseif (\$v.FileVersion) { Write-Output \$v.FileVersion }
      }
      ''';
      final out = await runPowerShell(script, timeoutSeconds: 3);
      if (out != null && out.trim().isNotEmpty) {
        return out.trim();
      }
    } catch (_) {}
    return null;
  }

  /// Checks if any file exists in a list of candidate paths safely
  static String? findFirstExisting(List<String> paths) {
    for (final rawPath in paths) {
      try {
        final expanded = expandEnvironmentVariables(rawPath);
        if (!expanded.contains('*')) {
          if (File(expanded).existsSync() || Directory(expanded).existsSync()) {
            return expanded;
          }
        }
      } catch (_) {
        // Ignore OS syntax or permission errors on candidate paths
      }
    }
    return null;
  }

  /// Expands Windows environment variables like %LOCALAPPDATA%
  static String expandEnvironmentVariables(String path) {
    return path.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
      final varName = match.group(1)!;
      return Platform.environment[varName] ?? '%$varName%';
    });
  }
}
