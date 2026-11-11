import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../logging/app_logger.dart';
import 'app_update_models.dart';
import 'semantic_version.dart';

/// Service managing update checks and policies for 414Unlock Windows Desktop.
/// Conforms to APP_UPDATE_CONTRACT.md.
class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  /// Live endpoint specified in APP_UPDATE_CONTRACT.md
  static const String defaultEndpoint =
      'https://414unlock-auth-api.414unlock.workers.dev/api/app/update';

  /// Authoritative packaged application version.
  /// Must match pubspec.yaml version (1.0.1+2) and Runner.rc.
  static const String currentAppVersion = '1.0.1';

  Timer? _periodicTimer;
  UpdateCheckResult? _latestResult;
  bool _isChecking = false;
  bool _optionalUpdateDismissed = false;

  /// Test injection hook for mocking HTTP responses in unit tests.
  @visibleForTesting
  static Future<String> Function(Uri uri)? mockHttpHandler;

  UpdateCheckResult? get latestResult => _latestResult;
  bool get isChecking => _isChecking;
  bool get optionalUpdateDismissed => _optionalUpdateDismissed;

  /// Whether the non-blocking optional update prompt should be shown.
  bool get shouldShowOptionalPrompt =>
      _latestResult != null &&
      _latestResult!.isOptional &&
      !_optionalUpdateDismissed;

  /// Whether the blocking mandatory update screen should be enforced.
  bool get shouldShowMandatoryScreen =>
      _latestResult != null && _latestResult!.isMandatory;

  /// Dismiss the optional update notification for the current session.
  void dismissOptionalUpdate() {
    _optionalUpdateDismissed = true;
    notifyListeners();
  }

  /// Start periodic checks (startup check + recurring check every 60 minutes).
  void startPeriodicChecks({Duration interval = const Duration(minutes: 60)}) {
    _periodicTimer?.cancel();

    // Check immediately on startup
    checkForUpdates();

    // Recurring check every interval
    _periodicTimer = Timer.periodic(interval, (_) {
      checkForUpdates();
    });
  }

  /// Stop periodic update checking.
  void stopPeriodicChecks() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Check the live update endpoint for updates.
  /// Uses semantic version comparison.
  /// Safely handles network errors without falsely claiming an update.
  Future<UpdateCheckResult?> checkForUpdates({
    String? overrideVersion,
    String? endpointUrl,
  }) async {
    if (_isChecking) return _latestResult;
    _isChecking = true;
    notifyListeners();

    final versionToCheck = (overrideVersion ?? currentAppVersion).trim();
    final baseUrl = endpointUrl ?? defaultEndpoint;

    try {
      // Validate that the version string is a valid SemVer
      final sem = SemanticVersion.tryParse(versionToCheck);
      final validVersionParam = sem != null ? sem.coreVersion : versionToCheck;

      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          'version': validVersionParam,
          'platform': 'windows',
        },
      );

      String responseBody;

      if (mockHttpHandler != null) {
        responseBody = await mockHttpHandler!(uri);
      } else {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.getUrl(uri);
          request.headers.set('Cache-Control', 'no-store');
          request.headers.set('Accept', 'application/json');
          request.headers.set('User-Agent', '414Unlock-Desktop/$versionToCheck (Windows)');

          final response = await request.close().timeout(const Duration(seconds: 12));
          if (response.statusCode != HttpStatus.ok) {
            AppLogger().warning(
              'Update check received HTTP ${response.statusCode} from update endpoint',
            );
            return _latestResult;
          }

          responseBody = await response.transform(utf8.decoder).join();
        } finally {
          client.close();
        }
      }

      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        AppLogger().warning('Update check returned non-object JSON payload');
        return _latestResult;
      }

      if (decoded['ok'] != true) {
        AppLogger().warning(
          'Update check returned failure response: ${decoded['error'] ?? decoded['message']}',
        );
        return _latestResult;
      }

      final result = UpdateCheckResult.fromJson(
        decoded,
        installedVersion: versionToCheck,
      );

      _latestResult = result;

      if (result.updateAvailable) {
        AppLogger().info(
          'Update available: v${result.latestVersion} (Mandatory: ${result.isMandatory})',
          'Release URL: ${result.releaseUrl}',
        );
      } else {
        AppLogger().info('414Unlock is up to date (Version $versionToCheck)');
      }

      return result;
    } catch (e) {
      // Safe diagnostic logging: do NOT invent an update or announce false update
      AppLogger().warning('Update check could not complete (safe network fallback): $e');
      return _latestResult;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
}
