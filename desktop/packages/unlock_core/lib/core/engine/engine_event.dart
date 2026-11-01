import 'package:intl/intl.dart';

enum EngineEventType {
  startup,
  stdout,
  stderr,
  deviceSearching,
  deviceDetected,
  deviceDisconnected,
  information,
  warning,
  prompt,
  progress,
  operationStarted,
  operationCompleted,
  operationFailed,
  cancelled,
  processExited,
}

enum EnginePromptAction {
  continueAction,
  retry,
  cancel,
  reconnect,
  openHelp,
}

extension EnginePromptActionX on EnginePromptAction {
  String get label {
    switch (this) {
      case EnginePromptAction.continueAction:
        return 'Continue';
      case EnginePromptAction.retry:
        return 'Retry';
      case EnginePromptAction.cancel:
        return 'Cancel';
      case EnginePromptAction.reconnect:
        return 'Reconnect USB';
      case EnginePromptAction.openHelp:
        return 'Help';
    }
  }
}

class EnginePrompt {
  final String message;
  final String? type;
  final List<EnginePromptAction> allowedActions;

  const EnginePrompt({
    required this.message,
    this.type,
    this.allowedActions = const [EnginePromptAction.retry, EnginePromptAction.cancel],
  });

  factory EnginePrompt.fromJson(Map<String, dynamic> json) {
    final actionsList = (json['actions'] as List<dynamic>?) ?? ['retry', 'cancel'];
    final actions = actionsList.map((a) {
      final s = a.toString().toLowerCase();
      if (s.contains('continue')) return EnginePromptAction.continueAction;
      if (s.contains('retry')) return EnginePromptAction.retry;
      if (s.contains('reconnect')) return EnginePromptAction.reconnect;
      if (s.contains('help')) return EnginePromptAction.openHelp;
      return EnginePromptAction.cancel;
    }).toList();

    return EnginePrompt(
      message: json['message']?.toString() ?? 'Action required',
      type: json['type']?.toString(),
      allowedActions: actions,
    );
  }
}

class EngineEvent {
  final EngineEventType type;
  final String message;
  final String? raw;
  final double? progress;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final EnginePrompt? prompt;

  EngineEvent({
    required this.type,
    required this.message,
    this.raw,
    this.progress,
    DateTime? timestamp,
    this.metadata = const {},
    this.prompt,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formattedTime => DateFormat('HH:mm:ss').format(timestamp);

  @override
  String toString() => '$formattedTime [${type.name.toUpperCase()}] $message';
}
