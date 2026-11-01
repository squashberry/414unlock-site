import 'dart:convert';
import 'engine_event.dart';

class EngineOutputNormalizer {
  static final RegExp _ansiRegex = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');

  static String normalize(String input) {
    var s = input.replaceAll(_ansiRegex, '');
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return s.trim();
  }
}

class EngineOutputParser {
  /// Parses a raw line of engine stdout/stderr into a structured EngineEvent
  static EngineEvent parse(String rawLine, {bool isStderr = false}) {
    final cleaned = EngineOutputNormalizer.normalize(rawLine);
    if (cleaned.isEmpty) {
      return EngineEvent(
        type: isStderr ? EngineEventType.stderr : EngineEventType.stdout,
        message: '',
        raw: rawLine,
      );
    }

    // 1. Try parsing JSON structured output
    if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
      try {
        final Map<String, dynamic> data = jsonDecode(cleaned);
        final eventStr = (data['event'] ?? '').toString();
        final message = (data['message'] ?? '').toString();
        final double? progress = data['progress'] is num ? (data['progress'] as num).toDouble() : null;

        EngineEventType type;
        switch (eventStr) {
          case 'startup':
            type = EngineEventType.startup;
            break;
          case 'device_searching':
            type = EngineEventType.deviceSearching;
            break;
          case 'device_detected':
            type = EngineEventType.deviceDetected;
            break;
          case 'device_disconnected':
            type = EngineEventType.deviceDisconnected;
            break;
          case 'progress':
            type = EngineEventType.progress;
            break;
          case 'prompt':
            type = EngineEventType.prompt;
            break;
          case 'operation_started':
            type = EngineEventType.operationStarted;
            break;
          case 'operation_completed':
            type = EngineEventType.operationCompleted;
            break;
          case 'operation_failed':
            type = EngineEventType.operationFailed;
            break;
          case 'cancelled':
            type = EngineEventType.cancelled;
            break;
          case 'error':
            type = EngineEventType.warning;
            break;
          case 'process_exited':
            type = EngineEventType.processExited;
            break;
          default:
            type = EngineEventType.information;
        }

        EnginePrompt? prompt;
        if (data.containsKey('prompt') && data['prompt'] is Map<String, dynamic>) {
          prompt = EnginePrompt.fromJson(data['prompt']);
        }

        return EngineEvent(
          type: type,
          message: message.isNotEmpty ? message : cleaned,
          raw: rawLine,
          progress: progress,
          metadata: data,
          prompt: prompt,
        );
      } catch (_) {
        // Fall through to plain text parsing
      }
    }

    // 2. Conservative Plain-Text Parsing
    if (isStderr) {
      return EngineEvent(
        type: EngineEventType.stderr,
        message: cleaned,
        raw: rawLine,
      );
    }

    final lower = cleaned.toLowerCase();

    if (lower.contains('device detected') || lower.contains('usb detected') || lower.contains('adb ready')) {
      return EngineEvent(
        type: EngineEventType.deviceDetected,
        message: cleaned,
        raw: rawLine,
      );
    }

    if (lower.contains('waiting for device') || lower.contains('scanning') || lower.contains('searching')) {
      return EngineEvent(
        type: EngineEventType.deviceSearching,
        message: cleaned,
        raw: rawLine,
      );
    }

    if (lower.contains('error') || lower.contains('failed') || lower.contains('exception')) {
      return EngineEvent(
        type: EngineEventType.warning,
        message: cleaned,
        raw: rawLine,
      );
    }

    if (lower.contains('rebooting') || lower.contains('initiating') || lower.contains('starting')) {
      return EngineEvent(
        type: EngineEventType.operationStarted,
        message: cleaned,
        raw: rawLine,
      );
    }

    if (lower.contains('completed') || lower.contains('succeeded')) {
      return EngineEvent(
        type: EngineEventType.operationCompleted,
        message: cleaned,
        raw: rawLine,
      );
    }

    // Default conservative classification: raw information
    return EngineEvent(
      type: EngineEventType.information,
      message: cleaned,
      raw: rawLine,
    );
  }
}
