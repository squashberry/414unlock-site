/// Semantic version representation with numeric component comparison.
/// Strictly conforms to SemVer 2.0 (major.minor.patch).
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final String? buildMetadata;

  const SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease,
    this.buildMetadata,
  });

  /// Parses a semantic version string (e.g., '1.4.2', '1.0.0+1', '2.0.0-beta').
  /// Throws [FormatException] if the version string does not contain valid numeric components.
  factory SemanticVersion.parse(String versionString) {
    final cleaned = versionString.trim();
    if (cleaned.isEmpty) {
      throw const FormatException('Version string cannot be empty');
    }

    // Split build metadata (+...)
    String core = cleaned;
    String? buildMeta;
    final plusIndex = core.indexOf('+');
    if (plusIndex != -1) {
      buildMeta = core.substring(plusIndex + 1);
      core = core.substring(0, plusIndex);
    }

    // Split pre-release (-...)
    String? pre;
    final dashIndex = core.indexOf('-');
    if (dashIndex != -1) {
      pre = core.substring(dashIndex + 1);
      core = core.substring(0, dashIndex);
    }

    final parts = core.split('.');
    if (parts.length < 3) {
      throw FormatException(
        'Invalid semantic version: "$versionString". Expected major.minor.patch',
      );
    }

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);

    if (major == null || minor == null || patch == null) {
      throw FormatException(
        'Invalid semantic version: "$versionString". Components must be numeric integers.',
      );
    }

    return SemanticVersion(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: pre,
      buildMetadata: buildMeta,
    );
  }

  /// Safe parser that returns null instead of throwing on invalid strings.
  static SemanticVersion? tryParse(String? versionString) {
    if (versionString == null) return null;
    try {
      return SemanticVersion.parse(versionString);
    } catch (_) {
      return null;
    }
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Pre-release versions have lower precedence than normal releases (SemVer spec)
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease != null) {
      return preRelease!.compareTo(other.preRelease!);
    }

    return 0;
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;
  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          preRelease == other.preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) buffer.write('-$preRelease');
    if (buildMetadata != null) buffer.write('+$buildMetadata');
    return buffer.toString();
  }

  /// Returns canonical major.minor.patch representation
  String get coreVersion => '$major.$minor.$patch';
}
