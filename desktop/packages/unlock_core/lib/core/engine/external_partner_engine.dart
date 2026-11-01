import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'repair_engine.dart';
import '../config/app_config.dart';
import '../device/device_info.dart';
import '../logging/app_logger.dart';

class ExternalPartnerEngine extends RepairEngine {
  final AppConfig _config;

  EngineState _state = EngineState.idle;
  EngineResult? _lastResult;
  final StreamController<EngineState> _stateController =
      StreamController<EngineState>.broadcast();

  ExternalPartnerEngine({AppConfig? config})
      : _config = config ?? AppConfig();

  @override
  EngineState get state => _state;

  @override
  EngineResult? get lastResult => _lastResult;

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  void _setState(EngineState newState) {
    _state = newState;
    _stateController.add(_state);
    AppLogger().engine('Engine state changed: ${_state.label}');
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    _setState(EngineState.checking);
    // Initialize config if needed
    if (!_config.isPartnerConfigured()) {
      _lastResult = EngineResult.notConfigured();
      _setState(EngineState.ready);
      AppLogger().engine('Engine initialized. Status: Not configured');
    } else {
      _setState(EngineState.ready);
      AppLogger().engine('Engine ready with configured partner tool');
    }
  }

  @override
  Future<EngineResult> executeOperation(DeviceInfo device) async {
    final startTime = DateTime.now();
    _setState(EngineState.running);
    AppLogger().engine(
      'Operation requested for device: ${device.name} (${device.mode.label})',
    );

    // Prompt requirement:
    // "The repair engine interface must initially return: Not configured rather than pretending to perform an operation."
    if (!_config.isPartnerConfigured()) {
      AppLogger().warning('Repair engine execution halted: Not configured');
      _lastResult = EngineResult(
        success: false,
        status: EngineState.failed,
        message: 'Not configured',
        deviceInfo: device,
        startedAt: startTime,
        finishedAt: DateTime.now(),
        isVerified: false,
      );
      _setState(EngineState.failed);
      return _lastResult!;
    }

    _setState(EngineState.handoffRequired);
    _lastResult = EngineResult(
      success: true,
      status: EngineState.handoffRequired,
      message: 'Ready for external partner handoff',
      deviceInfo: device,
      startedAt: startTime,
      finishedAt: null,
      isVerified: false,
    );
    return _lastResult!;
  }

  /// Launches the external partner tool (either executable or URL)
  Future<bool> launchPartnerTool() async {
    final exePath = _config.partnerExecutablePath;
    final partnerUrl = _config.partnerUrl;

    AppLogger().info('Partner handoff initiated');

    // 1. If executable is configured and exists on disk
    if (exePath.isNotEmpty) {
      final file = File(exePath);
      if (file.existsSync()) {
        try {
          AppLogger().info('Launching partner executable: $exePath');
          await Process.start(exePath, [], mode: ProcessStartMode.detached);
          _setState(EngineState.running);
          return true;
        } catch (e) {
          AppLogger().error(
            'Partner application could not be started',
            'Path: $exePath - Error: $e',
          );
          return false;
        }
      } else {
        AppLogger().error(
          'Configured partner executable not found on disk',
          exePath,
        );
        return false;
      }
    }

    // 2. If partner URL is configured
    if (partnerUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(partnerUrl);
        AppLogger().info('Opening partner URL: $partnerUrl');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _setState(EngineState.running);
          return true;
        }
      } catch (e) {
        AppLogger().error('Failed to open partner URL', e.toString());
        return false;
      }
    }

    AppLogger().error(
      'Partner application could not be started',
      'Check the configured partner-tool path in Settings.',
    );
    return false;
  }

  @override
  Future<EngineResult> verifyHandoffCompletion(DeviceInfo? device) async {
    final startTime = DateTime.now();
    _setState(EngineState.checking);
    AppLogger().engine('Checking operation status with integration provider...');

    // Verification check:
    // "Never display Done unless the configured status provider actually reports completion."
    // "If status cannot be verified: Title: Verification Required, Text: The partner application finished, but 414Unlock could not independently verify the final device state."
    
    // Check if partner provided a verified output or if a status token file was produced
    final statusTokenFile = File(
      r'%TEMP%\414unlock_partner_status.json'
          .replaceAllMapped(RegExp(r'%TEMP%'), (_) => Platform.environment['TEMP'] ?? ''),
    );

    bool verified = false;
    String statusMessage = '';

    if (statusTokenFile.existsSync()) {
      try {
        final content = statusTokenFile.readAsStringSync();
        if (content.contains('"status":"completed"') || content.contains('"success":true')) {
          verified = true;
          statusMessage = 'The partner tool reported that the operation completed successfully.';
          // Clean up token file after read
          statusTokenFile.deleteSync();
        }
      } catch (_) {}
    }

    if (verified) {
      _lastResult = EngineResult(
        success: true,
        status: EngineState.completed,
        message: statusMessage,
        deviceInfo: device,
        startedAt: startTime,
        finishedAt: DateTime.now(),
        isVerified: true,
      );
      _setState(EngineState.completed);
      AppLogger().engine('Operation successfully verified by partner provider');
    } else {
      // Honest unverified response as required by specifications
      _lastResult = EngineResult(
        success: false,
        status: EngineState.failed,
        message:
            'The partner application finished, but 414Unlock could not independently verify the final device state.',
        deviceInfo: device,
        startedAt: startTime,
        finishedAt: DateTime.now(),
        isVerified: false,
      );
      _setState(EngineState.failed);
      AppLogger().warning(
        'Verification required: External partner finished without an authenticated completion signal.',
      );
    }

    return _lastResult!;
  }

  @override
  Future<void> cancel() async {
    _setState(EngineState.cancelled);
    AppLogger().info('Operation cancelled by user');
  }

  @override
  void dispose() {
    _stateController.close();
    super.dispose();
  }
}
