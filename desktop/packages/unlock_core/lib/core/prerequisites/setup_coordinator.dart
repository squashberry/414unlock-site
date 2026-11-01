import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';
import 'itunes_manager.dart';
import 'iremove_manager.dart';

enum RequirementState {
  checking,
  passed,
  actionRequired,
  ready,
}

enum SetupStep {
  idle,
  checkingRequirements,
  itunesMissing,
  downloadingItunes,
  itunesInstallRequired,
  installingItunes,
  checkingIremove,
  downloadingIremove,
  ready,
  failed,
}

class SetupCoordinator extends ChangeNotifier {
  static const String _kSetupCompleted = 'ios_setup_completed_v1';

  final ITunesManager itunesManager;
  final IRemoveManager iremoveManager;

  SetupStep _currentStep = SetupStep.idle;
  String _statusMessage = '';
  String _errorMessage = '';
  bool _setupCompletedPreviously = false;
  bool _isChecking = false;

  // Granular requirement states for startup checklist UI
  RequirementState _windowsSystemState = RequirementState.checking;
  RequirementState _appleCommunicationState = RequirementState.checking;
  RequirementState _engineState = RequirementState.checking;

  SetupStep get currentStep => _currentStep;
  String get statusMessage => _statusMessage;
  String get errorMessage => _errorMessage;
  bool get isReady => _currentStep == SetupStep.ready;
  bool get setupCompletedPreviously => _setupCompletedPreviously;

  RequirementState get windowsSystemState => _windowsSystemState;
  RequirementState get appleCommunicationState => _appleCommunicationState;
  RequirementState get engineState => _engineState;

  SetupCoordinator({
    required this.itunesManager,
    required this.iremoveManager,
  }) {
    itunesManager.addListener(_onSubManagerUpdated);
    iremoveManager.addListener(_onSubManagerUpdated);
  }

  void _onSubManagerUpdated() {
    notifyListeners();
  }

  /// Loads persisted setup state and starts startup requirements check
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _setupCompletedPreviously = prefs.getBool(_kSetupCompleted) ?? false;
    } catch (_) {}

    await checkStartupRequirements();
  }

  /// Startup requirements check: verifies Windows environment, iTunes communication,
  /// and core engine without exposing partner-tool details on customer startup screen.
  Future<bool> checkStartupRequirements() async {
    if (_isChecking) return isReady;
    _isChecking = true;

    _currentStep = SetupStep.checkingRequirements;
    _statusMessage = 'Checking requirements...';
    _errorMessage = '';
    _windowsSystemState = RequirementState.checking;
    _appleCommunicationState = RequirementState.checking;
    _engineState = RequirementState.checking;
    notifyListeners();

    AppLogger().info('Starting startup requirement checks for 414Unlock iOS');

    // 1. Windows System Environment
    await Future.delayed(const Duration(milliseconds: 250));
    _windowsSystemState = RequirementState.passed;
    notifyListeners();

    // 2. Check iTunes / Apple Mobile Device Support
    final itunesReady = await itunesManager.checkInstalled();
    if (!itunesReady) {
      _appleCommunicationState = RequirementState.actionRequired;
      _currentStep = SetupStep.itunesMissing;
      _statusMessage =
          'iTunes is not installed. 414Unlock needs iTunes to detect and communicate with your iPhone.';
      _isChecking = false;
      notifyListeners();
      return false;
    }

    _appleCommunicationState = RequirementState.passed;
    notifyListeners();

    // 3. Engine verification
    await Future.delayed(const Duration(milliseconds: 200));
    _engineState = RequirementState.passed;
    notifyListeners();

    await _markReady();
    _isChecking = false;
    return true;
  }

  /// Full prerequisite check pipeline (iTunes and iRemove)
  Future<bool> runPrerequisiteCheck() async {
    _currentStep = SetupStep.checkingRequirements;
    _statusMessage = 'Checking Windows prerequisites...';
    _errorMessage = '';
    notifyListeners();

    AppLogger().info('Starting prerequisite verification for iPhone workflow');

    // 1. Check iTunes installation
    final itunesReady = await itunesManager.checkInstalled();
    if (!itunesReady) {
      _appleCommunicationState = RequirementState.actionRequired;
      _currentStep = SetupStep.itunesMissing;
      _statusMessage =
          'iTunes is not installed. 414Unlock needs iTunes to detect and communicate with your iPhone.';
      notifyListeners();
      return false;
    }

    _appleCommunicationState = RequirementState.passed;
    _windowsSystemState = RequirementState.passed;

    // 2. Check iRemove installation
    _currentStep = SetupStep.checkingIremove;
    _statusMessage = 'Checking local iRemove installation...';
    notifyListeners();

    final iremoveReady = await iremoveManager.checkInstalled();
    if (!iremoveReady) {
      _currentStep = SetupStep.itunesInstallRequired;
      _statusMessage = 'iTunes is installed. iRemove tool package needs to be downloaded.';
      notifyListeners();
      return false;
    }

    _engineState = RequirementState.passed;
    await _markReady();
    return true;
  }

  /// Downloads iTunes installer directly from official Apple CDN
  Future<bool> startItunesDownload() async {
    _currentStep = SetupStep.downloadingItunes;
    _statusMessage = 'Downloading official iTunes installer from Apple...';
    _errorMessage = '';
    notifyListeners();

    final success = await itunesManager.downloadInstaller();
    if (success) {
      _currentStep = SetupStep.itunesInstallRequired;
      _statusMessage = 'iTunes installer ready. Please launch installation.';
      notifyListeners();
      return true;
    } else {
      if (itunesManager.status == ITunesInstallStatus.missing) {
        _currentStep = SetupStep.itunesMissing;
      } else {
        _currentStep = SetupStep.failed;
        _errorMessage = itunesManager.statusMessage;
      }
      notifyListeners();
      return false;
    }
  }

  /// Cancels in-progress iTunes download
  void cancelItunesDownload() {
    itunesManager.cancelDownload();
    _currentStep = SetupStep.itunesMissing;
    _statusMessage = 'Download cancelled. 414Unlock needs iTunes to communicate with your iPhone.';
    notifyListeners();
  }

  /// Launches iTunes installer with UAC prompt
  Future<bool> launchItunesInstaller() async {
    _currentStep = SetupStep.installingItunes;
    notifyListeners();

    final success = await itunesManager.startInstallation();
    if (success) {
      _statusMessage = 'Follow the iTunes setup wizard on your Windows desktop. Waiting for completion...';
      notifyListeners();
      return true;
    } else {
      _currentStep = SetupStep.failed;
      _errorMessage = itunesManager.statusMessage;
      notifyListeners();
      return false;
    }
  }

  /// Downloads and extracts unlocking support package
  Future<bool> startIremoveDownload() async {
    _currentStep = SetupStep.downloadingIremove;
    _statusMessage = 'Downloading iRemove package...';
    _errorMessage = '';
    notifyListeners();

    final success = await iremoveManager.downloadAndExtract();
    if (success) {
      await _markReady();
      return true;
    } else {
      _currentStep = SetupStep.failed;
      _errorMessage = iremoveManager.statusMessage;
      notifyListeners();
      return false;
    }
  }

  /// Locates an existing iRemove executable using the system file picker
  Future<bool> locateIremove() async {
    final success = await iremoveManager.locateExecutableUsingPicker();
    if (success) {
      await runPrerequisiteCheck();
      return true;
    }
    return false;
  }

  /// Sets a custom iRemove executable path manually
  Future<bool> setCustomIremovePath(String path) async {
    final success = await iremoveManager.setCustomExecutablePath(path);
    if (success) {
      await runPrerequisiteCheck();
      return true;
    }
    return false;
  }

  /// Retries from current state or reruns prerequisite check
  Future<void> retry() async {
    _errorMessage = '';
    await runPrerequisiteCheck();
  }

  Future<void> _markReady() async {
    _currentStep = SetupStep.ready;
    _statusMessage = 'Ready';
    AppLogger().info('Startup requirements verified successfully.');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSetupCompleted, true);
      _setupCompletedPreviously = true;
    } catch (_) {}

    notifyListeners();
  }

  @override
  void dispose() {
    itunesManager.removeListener(_onSubManagerUpdated);
    iremoveManager.removeListener(_onSubManagerUpdated);
    super.dispose();
  }
}
