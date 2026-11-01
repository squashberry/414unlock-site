import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_info.dart';

abstract class DeviceDetectionService extends ChangeNotifier {
  DeviceInfo? get currentDevice;
  bool get isConnected => currentDevice != null;
  bool get isMonitoring;
  Stream<DeviceInfo?> get deviceStream;

  void startMonitoring();
  void stopMonitoring();
  Future<DeviceInfo?> queryDevices();
}
