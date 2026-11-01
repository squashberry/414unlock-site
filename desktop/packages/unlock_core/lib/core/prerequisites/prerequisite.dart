import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../logging/app_logger.dart';

enum PrerequisiteStatus {
  checking,
  installed,
  missing,
  updateRequired,
  unableToVerify,
}

extension PrerequisiteStatusX on PrerequisiteStatus {
  String get label {
    switch (this) {
      case PrerequisiteStatus.checking:
        return 'Checking...';
      case PrerequisiteStatus.installed:
        return 'Installed';
      case PrerequisiteStatus.missing:
        return 'Missing';
      case PrerequisiteStatus.updateRequired:
        return 'Update required';
      case PrerequisiteStatus.unableToVerify:
        return 'Unable to verify';
    }
  }
}

class PrerequisiteCheckResult {
  final PrerequisiteStatus status;
  final String? detectedVersion;
  final String? message;

  const PrerequisiteCheckResult({
    required this.status,
    this.detectedVersion,
    this.message,
  });
}

typedef CheckFunction = Future<PrerequisiteCheckResult> Function();

class Prerequisite extends ChangeNotifier {
  final String id;
  final String displayName;
  final String description;
  final String? requiredVersion;
  final String officialDownloadUrl;
  final CheckFunction _checkFunction;

  PrerequisiteStatus _status;
  String? _detectedVersion;
  String? _statusDetail;

  Prerequisite({
    required this.id,
    required this.displayName,
    required this.description,
    required this.officialDownloadUrl,
    required this._checkFunction,
    this.requiredVersion,
    PrerequisiteStatus initialStatus = PrerequisiteStatus.checking,
  })  : _status = initialStatus;

  PrerequisiteStatus get status => _status;
  String? get detectedVersion => _detectedVersion;
  String? get statusDetail => _statusDetail;

  Future<PrerequisiteCheckResult> check() async {
    _status = PrerequisiteStatus.checking;
    notifyListeners();
    AppLogger().info('Checking prerequisite: $displayName');

    try {
      final result = await _checkFunction();
      _status = result.status;
      _detectedVersion = result.detectedVersion;
      _statusDetail = result.message;
      AppLogger().info(
        'Prerequisite result: $displayName -> ${_status.label}${_detectedVersion != null ? ' (v$_detectedVersion)' : ''}',
      );
      notifyListeners();
      return result;
    } catch (e) {
      AppLogger().error(
        'Prerequisite check failed for $displayName',
        e.toString(),
      );
      _status = PrerequisiteStatus.unableToVerify;
      _statusDetail = 'Check error: $e';
      notifyListeners();
      return PrerequisiteCheckResult(
        status: PrerequisiteStatus.unableToVerify,
        message: e.toString(),
      );
    }
  }

  Future<void> openDownload() async {
    try {
      final uri = Uri.parse(officialDownloadUrl);
      AppLogger().info('Opening official download link for $displayName: $officialDownloadUrl');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        AppLogger().warning('Cannot launch URL: $officialDownloadUrl');
      }
    } catch (e) {
      AppLogger().error('Failed to open download link: $officialDownloadUrl', e.toString());
    }
  }
}
