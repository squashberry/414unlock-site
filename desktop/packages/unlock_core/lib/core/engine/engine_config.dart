import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EngineMode {
  development,
  bundled,
  mock,
}

extension EngineModeX on EngineMode {
  String get label {
    switch (this) {
      case EngineMode.development:
        return 'Local Development (Source)';
      case EngineMode.bundled:
        return 'Bundled Executable';
      case EngineMode.mock:
        return 'Mock Harness (Test)';
    }
  }
}

class EngineConfig extends ChangeNotifier {
  static final EngineConfig _instance = EngineConfig._internal();
  factory EngineConfig() => _instance;
  EngineConfig._internal();

  static const _kEngineMode = 'android_engine_mode';
  static const _kEngineRoot = 'android_engine_root';
  static const _kPythonExe = 'android_engine_python_exe';

  EngineMode _mode = EngineMode.development;
  String _engineRoot = r'C:\Users\Squashberry\Downloads\nPhoneKIT-1.6.8';
  String _pythonExecutable = 'py';
  String _customAdapterPath = '';

  EngineMode get mode => _mode;
  String get engineRoot => _engineRoot;
  String get pythonExecutable => _pythonExecutable;
  String get customAdapterPath => _customAdapterPath;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_kEngineMode);
      if (modeStr != null) {
        _mode = EngineMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => EngineMode.development,
        );
      }
      _engineRoot = prefs.getString(_kEngineRoot) ??
          r'C:\Users\Squashberry\Downloads\nPhoneKIT-1.6.8';
      _pythonExecutable = prefs.getString(_kPythonExe) ?? 'py';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMode(EngineMode newMode) async {
    _mode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEngineMode, newMode.name);
    notifyListeners();
  }

  Future<void> setEngineRoot(String path) async {
    _engineRoot = path.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEngineRoot, _engineRoot);
    notifyListeners();
  }

  Future<void> setPythonExecutable(String path) async {
    _pythonExecutable = path.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPythonExe, _pythonExecutable);
    notifyListeners();
  }

  void setCustomAdapterPath(String path) {
    _customAdapterPath = path.trim();
    notifyListeners();
  }

  /// Locates the nPhoneKIT adapter script
  String resolveAdapterScriptPath() {
    if (_customAdapterPath.isNotEmpty && File(_customAdapterPath).existsSync()) {
      return _customAdapterPath;
    }

    // Default location within workspace
    final candidatePaths = [
      r'packages\unlock_core\tooling\nphonekit_adapter.py',
      r'..\..\packages\unlock_core\tooling\nphonekit_adapter.py',
      r'..\packages\unlock_core\tooling\nphonekit_adapter.py',
      r'C:\Users\Squashberry\414unlock\packages\unlock_core\tooling\nphonekit_adapter.py',
    ];

    for (final p in candidatePaths) {
      if (File(p).existsSync()) {
        return File(p).absolute.path;
      }
    }

    return r'C:\Users\Squashberry\414unlock\packages\unlock_core\tooling\nphonekit_adapter.py';
  }
}
