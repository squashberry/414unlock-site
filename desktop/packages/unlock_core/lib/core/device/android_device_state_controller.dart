import 'dart:async';
import 'package:flutter/foundation.dart';
import 'android_device_state.dart';
import 'device_detection_service.dart';
import 'device_info.dart';
import '../engine/engine_event.dart';
import '../engine/engine_process_manager.dart';
import '../logging/app_logger.dart';

class AndroidDeviceStateController extends ChangeNotifier {
  final DeviceDetectionService _detectionService;
  final EngineProcessManager _processManager;

  AndroidDeviceState _state = AndroidDeviceState.disconnected;
  AdbCapability _adbCapability = AdbCapability.unavailable;
  DeviceInfo? _currentDevice;

  bool _isAssessing = false;
  bool _isOperationRunning = false;
  RecoveryAction? _activeOperation;
  String? _activeProgressMessage;
  EnginePrompt? _activePrompt;
  final List<EngineEvent> _liveEvents = [];

  StreamSubscription<DeviceInfo?>? _deviceSub;
  StreamSubscription<EngineEvent>? _eventSub;

  AndroidDeviceStateController({
    required this._detectionService,
    required this._processManager,
  }) {
    _init();
  }

  AndroidDeviceState get state => _state;
  AdbCapability get adbCapability => _adbCapability;
  DeviceInfo? get currentDevice => _currentDevice;
  bool get isAssessing => _isAssessing;
  bool get isOperationRunning => _isOperationRunning;
  RecoveryAction? get activeOperation => _activeOperation;
  String? get activeProgressMessage => _activeProgressMessage;
  EnginePrompt? get activePrompt => _activePrompt;
  List<EngineEvent> get liveEvents => List.unmodifiable(_liveEvents);

  List<RecoveryAction> get availableActions {
    if (_state == AndroidDeviceState.disconnected) return [];
    return RecoveryAction.allActions
        .where((a) => a.supportedStates.contains(_state))
        .toList();
  }

  void _init() {
    // 1. Subscribe to DeviceDetectionService updates
    _deviceSub = _detectionService.deviceStream.listen(_onUsbDeviceChanged);

    // 2. Subscribe to EngineProcessManager events
    _eventSub = _processManager.eventStream.listen(_onEngineEvent);

    // 3. Initial check
    if (_detectionService.currentDevice != null) {
      _onUsbDeviceChanged(_detectionService.currentDevice);
    }
  }

  void _onUsbDeviceChanged(DeviceInfo? device) {
    if (device == null) {
      _state = AndroidDeviceState.disconnected;
      _adbCapability = AdbCapability.unavailable;
      _currentDevice = null;
      _isOperationRunning = false;
      _activeOperation = null;
      _activePrompt = null;
      _activeProgressMessage = null;
      notifyListeners();
      AppLogger().hardware('Device disconnected; state reset to disconnected');
      return;
    }

    _currentDevice = device;

    // Evidence-based assessment from device info
    _assessFromDeviceInfo(device);
  }

  void _assessFromDeviceInfo(DeviceInfo device) {
    _isAssessing = true;
    notifyListeners();

    // Map DeviceMode from detection service into initial evidence
    switch (device.mode) {
      case DeviceMode.fastboot:
        _state = AndroidDeviceState.fastboot;
        _adbCapability = AdbCapability.unavailable;
        break;
      case DeviceMode.recovery:
        _state = AndroidDeviceState.recovery;
        _adbCapability = AdbCapability.available;
        break;
      case DeviceMode.adb:
        _state = AndroidDeviceState.normalAndroid;
        _adbCapability = AdbCapability.available;
        break;
      case DeviceMode.adbUnauthorized:
        _state = AndroidDeviceState.normalAndroidLocked;
        _adbCapability = AdbCapability.unauthorized;
        break;
      default:
        // Hardware is connected over USB/PnP/MTP, but ADB is unavailable or screen is locked
        _state = AndroidDeviceState.normalAndroidLocked;
        _adbCapability = AdbCapability.unavailable;
        break;
    }

    _isAssessing = false;
    notifyListeners();
    AppLogger().info(
      'Device state classified: ${_state.label} (${_adbCapability.label})',
    );

    // Also trigger nPhoneKIT backend assessment for rich modem/AT/Samsung info
    if (_processManager.isRunning) {
      _processManager.requestDeviceDetection();
    }
  }

  void _onEngineEvent(EngineEvent event) {
    _liveEvents.add(event);
    if (_liveEvents.length > 200) {
      _liveEvents.removeAt(0);
    }

    switch (event.type) {
      case EngineEventType.deviceDetected:
        final devData = event.metadata['device'];
        if (devData is Map<String, dynamic>) {
          _updateFromBackendDevice(devData);
        }
        break;

      case EngineEventType.deviceDisconnected:
        if (_detectionService.currentDevice == null) {
          _state = AndroidDeviceState.disconnected;
          _adbCapability = AdbCapability.unavailable;
          _currentDevice = null;
        }
        break;

      case EngineEventType.prompt:
        _activePrompt = event.prompt;
        break;

      case EngineEventType.progress:
        _activeProgressMessage = event.message;
        break;

      case EngineEventType.operationStarted:
        _isOperationRunning = true;
        _activeProgressMessage = event.message;
        break;

      case EngineEventType.operationCompleted:
        _isOperationRunning = false;
        _activePrompt = null;
        _activeProgressMessage = 'Operation completed.';
        // Re-assess device state after command completion
        Future.delayed(const Duration(milliseconds: 1200), reassessState);
        break;

      case EngineEventType.operationFailed:
      case EngineEventType.cancelled:
        _isOperationRunning = false;
        _activePrompt = null;
        _activeProgressMessage = null;
        break;

      default:
        break;
    }

    notifyListeners();
  }

  void _updateFromBackendDevice(Map<String, dynamic> devData) {
    final stateStr = (devData['state'] ?? '').toString();
    final adbStr = (devData['adbState'] ?? '').toString();

    switch (stateStr) {
      case 'fastboot':
        _state = AndroidDeviceState.fastboot;
        break;
      case 'recovery':
        _state = AndroidDeviceState.recovery;
        break;
      case 'downloadMode':
        _state = AndroidDeviceState.downloadMode;
        break;
      case 'setupWizard':
        _state = AndroidDeviceState.setupWizard;
        break;
      case 'normalAndroid':
        _state = AndroidDeviceState.normalAndroid;
        break;
      case 'normalAndroidLocked':
        _state = AndroidDeviceState.normalAndroidLocked;
        break;
      default:
        break;
    }

    switch (adbStr) {
      case 'available':
        _adbCapability = AdbCapability.available;
        break;
      case 'unauthorized':
        _adbCapability = AdbCapability.unauthorized;
        break;
      default:
        _adbCapability = AdbCapability.unavailable;
        break;
    }

    final devName = devData['name']?.toString();
    if (devName != null && devName.isNotEmpty) {
      _currentDevice = DeviceInfo(
        platform: DevicePlatform.android,
        name: devName,
        model: devData['model']?.toString() ?? _currentDevice?.model,
        manufacturer: devData['manufacturer']?.toString() ?? _currentDevice?.manufacturer,
        serialNumber: devData['serial']?.toString() ?? _currentDevice?.serialNumber,
        osVersion: devData['osVersion']?.toString() ?? _currentDevice?.osVersion,
        statusDescription: devData['statusDescription']?.toString() ?? _currentDevice?.statusDescription ?? 'USB communication available',
      );
    }

    notifyListeners();
  }

  /// Manually triggers a fresh state re-assessment
  Future<void> reassessState() async {
    _isAssessing = true;
    notifyListeners();

    await _detectionService.queryDevices();
    if (_processManager.isRunning) {
      _processManager.requestDeviceDetection();
    }

    _isAssessing = false;
    notifyListeners();
  }

  /// Executes an authorized recovery operation
  Future<void> executeAction(RecoveryAction action) async {
    _activeOperation = action;
    _isOperationRunning = true;
    _activeProgressMessage = 'Initiating ${action.name}...';
    notifyListeners();

    AppLogger().engine('Executing action: ${action.name} (${action.id})');
    _processManager.executeOperation(action.id, targetSerial: _currentDevice?.serialNumber);
  }

  /// Cancels an active operation
  Future<void> cancelOperation() async {
    AppLogger().info('User requested operation cancellation');
    await _processManager.cancel();
    _isOperationRunning = false;
    _activeOperation = null;
    _activePrompt = null;
    _activeProgressMessage = null;
    notifyListeners();
  }

  /// Responds to an interactive engine prompt
  void respondToPrompt(EnginePromptAction action) {
    AppLogger().info('User responded to prompt with action: ${action.label}');
    if (action == EnginePromptAction.cancel) {
      cancelOperation();
    } else if (action == EnginePromptAction.retry) {
      if (_activeOperation != null) {
        executeAction(_activeOperation!);
      } else {
        reassessState();
      }
    } else if (action == EnginePromptAction.reconnect) {
      reassessState();
    }
    _activePrompt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}
