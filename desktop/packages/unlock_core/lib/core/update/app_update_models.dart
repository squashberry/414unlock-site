import 'semantic_version.dart';

/// Models the update policy returned by the 414Unlock update endpoint.
/// Conforms to APP_UPDATE_CONTRACT.md.
class UpdateCheckResult {
  final bool ok;
  final String product;
  final String channel;
  final String platform;
  final String currentVersion;
  final String latestVersion;
  final String minimumVersion;
  final bool updateAvailable;
  final bool updateRequired;
  final bool forceUpdate;
  final String releaseUrl;
  final String releaseNotes;
  final int publishedAt;
  final int checkedAt;
  final String message;

  const UpdateCheckResult({
    required this.ok,
    required this.product,
    required this.channel,
    required this.platform,
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumVersion,
    required this.updateAvailable,
    required this.updateRequired,
    required this.forceUpdate,
    required this.releaseUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.checkedAt,
    required this.message,
  });

  /// Factory constructor to parse JSON response with numeric SemVer re-validation.
  factory UpdateCheckResult.fromJson(
    Map<String, dynamic> json, {
    required String installedVersion,
  }) {
    final ok = json['ok'] == true;
    final product = (json['product'] as String?) ?? '414Unlock';
    final channel = (json['channel'] as String?) ?? 'stable';
    final platform = (json['platform'] as String?) ?? 'windows';
    final currentVerStr = installedVersion.trim();
    final latestVerStr = ((json['latestVersion'] as String?) ?? '0.0.0').trim();
    final minVerStr = ((json['minimumVersion'] as String?) ?? '0.0.0').trim();
    final forceUpdate = json['forceUpdate'] == true;
    final rawReleaseUrl = ((json['releaseUrl'] as String?) ?? '').trim();
    final releaseNotes = ((json['releaseNotes'] as String?) ?? '').trim();
    final publishedAt = (json['publishedAt'] as num?)?.toInt() ?? 0;
    final checkedAt = (json['checkedAt'] as num?)?.toInt() ?? 0;
    final message = (json['message'] as String?) ?? '';

    // Enforce numeric semantic-version comparison (SemVer 2.0)
    final currentSem = SemanticVersion.tryParse(currentVerStr);
    final latestSem = SemanticVersion.tryParse(latestVerStr);
    final minSem = SemanticVersion.tryParse(minVerStr);

    bool computedAvailable = false;
    bool computedRequired = false;

    if (currentSem != null && latestSem != null) {
      computedAvailable = latestSem > currentSem;
      if (computedAvailable) {
        final isBelowMinimum = minSem != null && currentSem < minSem;
        computedRequired = forceUpdate || json['updateRequired'] == true || isBelowMinimum;
      }
    }

    return UpdateCheckResult(
      ok: ok,
      product: product,
      channel: channel,
      platform: platform,
      currentVersion: currentVerStr,
      latestVersion: latestVerStr,
      minimumVersion: minVerStr,
      updateAvailable: computedAvailable,
      updateRequired: computedRequired,
      forceUpdate: forceUpdate,
      releaseUrl: rawReleaseUrl,
      releaseNotes: releaseNotes,
      publishedAt: publishedAt,
      checkedAt: checkedAt,
      message: message,
    );
  }

  /// Whether the release URL is a valid, secure HTTPS URL
  bool get hasValidHttpsUrl {
    if (releaseUrl.isEmpty) return false;
    final uri = Uri.tryParse(releaseUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// True when an update must be performed before using unlock functions
  bool get isMandatory => updateRequired;

  /// True when an update is available but optional
  bool get isOptional => updateAvailable && !updateRequired;
}
