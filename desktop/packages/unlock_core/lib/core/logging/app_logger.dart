import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum LogLevel {
  info,
  warning,
  error,
  hardware,
  engine,
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;

  LogEntry({
    DateTime? timestamp,
    required this.level,
    required this.message,
    this.details,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formattedTime => DateFormat('HH:mm:ss').format(timestamp);

  String get formattedFullTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);

  @override
  String toString() {
    final lvl = level.name.toUpperCase().padRight(8);
    final detailStr = details != null ? ' - $details' : '';
    return '$formattedTime  [$lvl] $message$detailStr';
  }
}

/// Central application logger providing timestamped, safe logging.
/// Never stores or outputs credentials, passcodes, or tokens.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final List<LogEntry> _entries = [];
  final StreamController<LogEntry> _entryController =
      StreamController<LogEntry>.broadcast();

  List<LogEntry> get entries => List.unmodifiable(_entries);
  Stream<LogEntry> get onEntry => _entryController.stream;

  void info(String message, [String? details]) {
    _log(LogLevel.info, message, details);
  }

  void warning(String message, [String? details]) {
    _log(LogLevel.warning, message, details);
  }

  void error(String message, [String? details]) {
    _log(LogLevel.error, message, details);
  }

  void hardware(String message, [String? details]) {
    _log(LogLevel.hardware, message, details);
  }

  void engine(String message, [String? details]) {
    _log(LogLevel.engine, message, details);
  }

  void _log(LogLevel level, String rawMessage, String? rawDetails) {
    // Redact any accidental sensitive parameters
    final message = _sanitize(rawMessage);
    final details = rawDetails != null ? _sanitize(rawDetails) : null;

    final entry = LogEntry(
      level: level,
      message: message,
      details: details,
    );

    _entries.add(entry);
    if (_entries.length > 2000) {
      _entries.removeAt(0);
    }

    _entryController.add(entry);

    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  String _sanitize(String input) {
    // Ensure tokens, passcodes, keys, passwords are redacted if present
    var sanitized = input;
    final sensitivePatterns = [
      RegExp(r'(token[:=]\s*)[^\s]+', caseSensitive: false),
      RegExp(r'(password[:=]\s*)[^\s]+', caseSensitive: false),
      RegExp(r'(pin[:=]\s*)\d+', caseSensitive: false),
      RegExp(r'(key[:=]\s*)[^\s]+', caseSensitive: false),
      RegExp(r'(passcode[:=]\s*)\d+', caseSensitive: false),
    ];
    for (final pattern in sensitivePatterns) {
      sanitized = sanitized.replaceAllMapped(
        pattern,
        (m) => '${m.group(1)}[REDACTED]',
      );
    }
    return sanitized;
  }

  String exportDiagnostics() {
    final buffer = StringBuffer();
    buffer.writeln('=== 414Unlock Diagnostic Export ===');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('Total Log Entries: ${_entries.length}');
    buffer.writeln('--------------------------------------------------');
    for (final entry in _entries) {
      buffer.writeln(
          '${entry.formattedFullTime} [${entry.level.name.toUpperCase()}] ${entry.message}');
      if (entry.details != null && entry.details!.isNotEmpty) {
        buffer.writeln('   Details: ${entry.details}');
      }
    }
    buffer.writeln('=== End of Diagnostics ===');
    return buffer.toString();
  }

  void clear() {
    _entries.clear();
  }
}
