import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';

import '../services/startup_service.dart';

class AppConfig extends ChangeNotifier {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  static const _kPartnerExePath = 'partner_exe_path';
  static const _kPartnerUrl = 'partner_url';
  static const _kStartWithWindows = 'start_with_windows';
  static const _kMinimizeToTray = 'minimize_to_tray';
  static const _kAutoCheckPrereqs = 'auto_check_prereqs';
  static const _kAutoDetectUsb = 'auto_detect_usb';
  static const _kThemeMode = 'app_theme_mode';

  String _partnerExecutablePath = '';
  String _partnerUrl = '';
  bool _startWithWindows = true; // Auto launch on startup always on by default
  bool _minimizeToTray = true;
  bool _autoCheckPrerequisites = true;
  bool _autoDetectUsb = true;
  String _themeMode = 'light'; // Default to clean white theme as requested

  String get partnerExecutablePath => _partnerExecutablePath;
  String get partnerUrl => _partnerUrl;
  bool get startWithWindows => _startWithWindows;
  bool get minimizeToTray => _minimizeToTray;
  bool get autoCheckPrerequisites => _autoCheckPrerequisites;
  bool get autoDetectUsb => _autoDetectUsb;
  String get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == 'dark';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _partnerExecutablePath = prefs.getString(_kPartnerExePath) ?? '';
      _partnerUrl = prefs.getString(_kPartnerUrl) ?? '';
      _startWithWindows = prefs.getBool(_kStartWithWindows) ?? true;
      _minimizeToTray = prefs.getBool(_kMinimizeToTray) ?? true;
      _autoCheckPrerequisites = prefs.getBool(_kAutoCheckPrereqs) ?? true;
      _autoDetectUsb = prefs.getBool(_kAutoDetectUsb) ?? true;
      _themeMode = prefs.getString(_kThemeMode) ?? 'light';

      if (_startWithWindows) {
        await StartupService.ensureAutoStartEnabled();
      }
      notifyListeners();
    } catch (e) {
      AppLogger().error('Failed to load application config', e.toString());
    }
  }

  Future<void> setPartnerExecutablePath(String path) async {
    _partnerExecutablePath = path.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPartnerExePath, _partnerExecutablePath);
    AppLogger().info('Partner executable path configured', _partnerExecutablePath);
    notifyListeners();
  }

  Future<void> setPartnerUrl(String url) async {
    _partnerUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPartnerUrl, _partnerUrl);
    AppLogger().info('Partner URL configured', _partnerUrl);
    notifyListeners();
  }

  Future<void> setStartWithWindows(bool value) async {
    _startWithWindows = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStartWithWindows, value);
    if (value) {
      await StartupService.ensureAutoStartEnabled();
    } else {
      await StartupService.disableAutoStart();
    }
    AppLogger().info('Setting "Start with Windows" updated: $value');
    notifyListeners();
  }

  Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMinimizeToTray, value);
    AppLogger().info('Setting "Minimize to tray" updated: $value');
    notifyListeners();
  }

  Future<void> setAutoCheckPrerequisites(bool value) async {
    _autoCheckPrerequisites = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoCheckPrereqs, value);
    notifyListeners();
  }

  Future<void> setAutoDetectUsb(bool value) async {
    _autoDetectUsb = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDetectUsb, value);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = (mode == 'dark') ? 'dark' : 'light';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _themeMode);
    AppLogger().info('Setting "Theme mode" updated: $_themeMode');
    notifyListeners();
  }

  bool isPartnerConfigured() {
    if (_partnerExecutablePath.isNotEmpty) {
      final file = File(_partnerExecutablePath);
      return file.existsSync();
    }
    return _partnerUrl.isNotEmpty;
  }
}
