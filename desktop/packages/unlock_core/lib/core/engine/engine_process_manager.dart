import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'engine_config.dart';
import 'engine_event.dart';
import 'engine_output_parser.dart';
import '../logging/app_logger.dart';

class EngineProcessManager extends ChangeNotifier {
  final EngineConfig _config;

  Process? _process;
  bool _isRunning = false;
  int? _lastExitCode;
  DateTime? _lastStartupTime;

  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  final List<EngineEvent> _recentEvents = [];

  EngineProcessManager({EngineConfig? config})
      : _config = config ?? EngineConfig();

  bool get isRunning => _isRunning;
  int? get lastExitCode => _lastExitCode;
  DateTime? get lastStartupTime => _lastStartupTime;
  List<EngineEvent> get recentEvents => List.unmodifiable(_recentEvents);
  Stream<EngineEvent> get eventStream => _eventController.stream;

  /// Validates whether the engine and required tools are available
  Future<Map<String, dynamic>> checkHealth() async {
    final adapterPath = _config.resolveAdapterScriptPath();
    final pythonExe = _config.pythonExecutable;

    if (!File(adapterPath).existsSync()) {
      return {
        'ok': false,
        'error': 'Adapter script not found at: $adapterPath',
      };
    }

    try {
      final res = await Process.run(
        pythonExe,
        [adapterPath, '--mode=health'],
      ).timeout(const Duration(seconds: 4));

      if (res.exitCode == 0) {
        final lines = (res.stdout as String).trim().split('\n');
        for (final l in lines) {
          if (l.startsWith('{') && l.endsWith('}')) {
            try {
              return jsonDecode(l);
            } catch (_) {}
          }
        }
        return {'ok': true, 'message': 'Engine verified'};
      } else {
        return {
          'ok': false,
          'error': 'Process exited with code ${res.exitCode}: ${res.stderr}',
        };
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Starts the persistent engine process
  Future<bool> start() async {
    if (_isRunning) return true;

    _lastExitCode = null;
    _lastStartupTime = DateTime.now();

    final adapterPath = _config.resolveAdapterScriptPath();
    final pythonExe = _config.pythonExecutable;
    final modeFlag = _config.mode == EngineMode.mock ? '--mode=mock' : '--mode=stream';

    AppLogger().engine('Starting Android engine backend process ($modeFlag)...');

    try {
      _process = await Process.start(
        pythonExe,
        [adapterPath, modeFlag],
        workingDirectory: _config.engineRoot.isNotEmpty && Directory(_config.engineRoot).existsSync()
            ? _config.engineRoot
            : null,
      );

      _isRunning = true;
      notifyListeners();
      AppLogger().engine('Engine process spawned successfully (PID: ${_process!.pid})');

      // Listen to stdout lines
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final event = EngineOutputParser.parse(line, isStderr: false);
          _recordEvent(event);
        },
        onError: (e) {
          AppLogger().error('Engine stdout stream error', e.toString());
        },
      );

      // Listen to stderr lines
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final event = EngineOutputParser.parse(line, isStderr: true);
          _recordEvent(event);
        },
      );

      // Listen for process exit
      _process!.exitCode.then((code) {
        _isRunning = false;
        _lastExitCode = code;
        _process = null;
        AppLogger().engine('Engine process exited with code $code');
        _recordEvent(
          EngineEvent(
            type: EngineEventType.processExited,
            message: 'Engine process exited with code $code',
            metadata: {'exitCode': code},
          ),
        );
        notifyListeners();
      });

      return true;
    } catch (e) {
      _isRunning = false;
      AppLogger().error('Failed to launch Android engine process', e.toString());
      _recordEvent(
        EngineEvent(
          type: EngineEventType.operationFailed,
          message: 'Process startup error: $e',
        ),
      );
      notifyListeners();
      return false;
    }
  }

  /// Sends a command to the running engine process via stdin
  void sendCommand(String command, {Map<String, dynamic>? extra}) {
    if (_process == null || !_isRunning) {
      AppLogger().warning('Cannot send command; engine process is not running');
      return;
    }

    final payload = {'cmd': command, ...?extra};
    final jsonStr = jsonEncode(payload);
    try {
      _process!.stdin.writeln(jsonStr);
      AppLogger().info('Sent IPC command to engine: $command');
    } catch (e) {
      AppLogger().error('Failed to write to engine stdin', e.toString());
    }
  }

  /// Requests the engine to trigger device state detection
  void requestDeviceDetection() {
    sendCommand('detect');
  }

  /// Dispatches a supported recovery operation to the engine
  void executeOperation(String actionName, {String? targetSerial}) {
    sendCommand('action', extra: {
      'action': actionName,
      'serial': ?targetSerial,
    });
  }

  /// Requests the engine to cancel any running operation
  Future<void> cancel() async {
    if (!_isRunning || _process == null) return;
    AppLogger().info('Requesting engine operation cancellation...');
    sendCommand('cancel');

    // Allow graceful cancellation before terminating
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// Forcefully terminates child process if still alive
  void terminate() {
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigkill);
      } catch (_) {}
      _process = null;
      _isRunning = false;
      notifyListeners();
    }
  }

  void _recordEvent(EngineEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > 500) {
      _recentEvents.removeAt(0);
    }
    _eventController.add(event);

    // Sync with main AppLogger
    if (event.type == EngineEventType.deviceDetected) {
      AppLogger().hardware(event.message);
    } else if (event.type == EngineEventType.operationStarted ||
        event.type == EngineEventType.operationCompleted) {
      AppLogger().engine(event.message);
    } else if (event.type == EngineEventType.warning ||
        event.type == EngineEventType.operationFailed) {
      AppLogger().warning(event.message);
    }
  }

  @override
  void dispose() {
    terminate();
    _eventController.close();
    super.dispose();
  }
}
