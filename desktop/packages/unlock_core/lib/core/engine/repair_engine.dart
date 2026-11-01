import 'dart:async';
import 'package:flutter/foundation.dart';
import '../device/device_info.dart';

enum EngineState {
  idle,
  checking,
  ready,
  waitingForDevice,
  running,
  handoffRequired,
  completed,
  failed,
  cancelled,
}

extension EngineStateX on EngineState {
  String get label {
    switch (this) {
      case EngineState.idle:
        return 'Idle';
      case EngineState.checking:
        return 'Checking';
      case EngineState.ready:
        return 'Ready';
      case EngineState.waitingForDevice:
        return 'Waiting for Device';
      case EngineState.running:
        return 'Running';
      case EngineState.handoffRequired:
        return 'Partner Handoff Required';
      case EngineState.completed:
        return 'Completed';
      case EngineState.failed:
        return 'Failed';
      case EngineState.cancelled:
        return 'Cancelled';
    }
  }
}

class EngineResult {
  final bool success;
  final EngineState status;
  final String message;
  final DeviceInfo? deviceInfo;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool isVerified;
  final Map<String, dynamic>? extraData;

  const EngineResult({
    required this.success,
    required this.status,
    required this.message,
    this.deviceInfo,
    required this.startedAt,
    this.finishedAt,
    this.isVerified = false,
    this.extraData,
  });

  factory EngineResult.notConfigured({DeviceInfo? deviceInfo}) {
    return EngineResult(
      success: false,
      status: EngineState.failed,
      message: 'Not configured',
      deviceInfo: deviceInfo,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      isVerified: false,
    );
  }
}

abstract class RepairEngine extends ChangeNotifier {
  EngineState get state;
  EngineResult? get lastResult;
  Stream<EngineState> get stateStream;

  Future<void> initialize();
  Future<EngineResult> executeOperation(DeviceInfo device);
  Future<EngineResult> verifyHandoffCompletion(DeviceInfo? device);
  Future<void> cancel();
}
