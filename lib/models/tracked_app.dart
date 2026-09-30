import 'install_type.dart';

class TrackedApp {
  final int? id;
  final String repoOwner;
  final String repoName;
  final String displayName;
  final String? installedVersion;
  final String? latestVersion;
  final InstallType? installType;
  final String? launchCommand;
  final String? packageName;
  final DateTime? lastChecked;
  final DateTime createdAt;
  final DateTime? latestReleaseDate;
  final String? fetchedPackage;

  // Advanced filtering fields
  final String? assetFilterPattern;
  final String? tagPrefix;
  final List<String> architectures;
  final bool includePrerelease;

  TrackedApp({
    this.id,
    required this.repoOwner,
    required this.repoName,
    required this.displayName,
    this.installedVersion,
    this.latestVersion,
    this.installType,
    this.launchCommand,
    this.packageName,
    this.lastChecked,
    required this.createdAt,
    this.latestReleaseDate,
    this.fetchedPackage,
    this.assetFilterPattern,
    this.tagPrefix,
    List<String>? architectures,
    this.includePrerelease = false,
  }) : architectures = architectures ?? [];

  String get repoUrl => 'https://github.com/$repoOwner/$repoName';

  bool get hasUpdate {
    if (installedVersion == null || latestVersion == null) return false;
    final installed = normalizeVersion(installedVersion!);
    final latest = normalizeVersion(latestVersion!);
    // Shape-check the NORMALISED value. An npm specifier such as
    // `@biomejs/biome@2.5.15` carries a real version after its final `@`, so
    // testing the raw string hid a genuine update; a value that is still not
    // version-shaped after normalising (e.g. `multiplatform#1`) is rejected.
    if (!looksLikeVersion(latest)) return false;
    if (installed == latest) return false;
    return isNewerVersion(latest, installed);
  }

  bool get isInstalled => installedVersion != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repo_owner': repoOwner,
      'repo_name': repoName,
      'display_name': displayName,
      'installed_version': installedVersion,
      'latest_version': latestVersion,
      'install_type': installType?.name,
      'launch_command': launchCommand,
      'package_name': packageName,
      'last_checked': lastChecked?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'latest_release_date': latestReleaseDate?.toIso8601String(),
      'fetched_package': fetchedPackage,
      'asset_filter_pattern': assetFilterPattern,
      'tag_prefix': tagPrefix,
      'architectures': architectures,
      'include_prerelease': includePrerelease,
    };
  }

  factory TrackedApp.fromMap(Map<String, dynamic> map) {
    // Values may arrive from JSON/SQLite as non-String types, so coerce
    // instead of casting.
    final installedVersion = map['installed_version']?.toString();
    final latestVersion = map['latest_version']?.toString();

    return TrackedApp(
      id: map['id'] as int?,
      repoOwner: map['repo_owner'] as String,
      repoName: map['repo_name'] as String,
      displayName: map['display_name'] as String,
      installedVersion: (installedVersion?.trim().isEmpty ?? true) ? null : installedVersion,
      latestVersion: (latestVersion?.trim().isEmpty ?? true) ? null : latestVersion,
      installType: InstallType.fromString(map['install_type'] as String?),
      launchCommand: map['launch_command'] as String?,
      packageName: map['package_name'] as String?,
      lastChecked: map['last_checked'] != null ? DateTime.parse(map['last_checked'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      latestReleaseDate: map['latest_release_date'] != null ? DateTime.parse(map['latest_release_date'] as String) : null,
      fetchedPackage: map['fetched_package'] as String?,
      assetFilterPattern: map['asset_filter_pattern'] as String?,
      tagPrefix: map['tag_prefix'] as String?,
      architectures: map['architectures'] != null
          ? List<String>.from(map['architectures'] as List)
          : [],
      includePrerelease: map['include_prerelease'] as bool? ?? false,
    );
  }

  static const _sentinel = Object();

  TrackedApp copyWith({
    Object? id = _sentinel,
    String? repoOwner,
    String? repoName,
    String? displayName,
    Object? installedVersion = _sentinel,
    Object? latestVersion = _sentinel,
    Object? installType = _sentinel,
    Object? launchCommand = _sentinel,
    Object? packageName = _sentinel,
    Object? lastChecked = _sentinel,
    DateTime? createdAt,
    Object? latestReleaseDate = _sentinel,
    Object? fetchedPackage = _sentinel,
    Object? assetFilterPattern = _sentinel,
    Object? tagPrefix = _sentinel,
    List<String>? architectures,
    bool? includePrerelease,
  }) {
    return TrackedApp(
      id: identical(id, _sentinel) ? this.id : id as int?,
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      displayName: displayName ?? this.displayName,
      installedVersion: identical(installedVersion, _sentinel)
          ? this.installedVersion
          : installedVersion as String?,
      latestVersion: identical(latestVersion, _sentinel)
          ? this.latestVersion
          : latestVersion as String?,
      installType: identical(installType, _sentinel)
          ? this.installType
          : installType as InstallType?,
      launchCommand: identical(launchCommand, _sentinel)
          ? this.launchCommand
          : launchCommand as String?,
      packageName: identical(packageName, _sentinel)
          ? this.packageName
          : packageName as String?,
      lastChecked: identical(lastChecked, _sentinel)
          ? this.lastChecked
          : lastChecked as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      latestReleaseDate: identical(latestReleaseDate, _sentinel)
          ? this.latestReleaseDate
          : latestReleaseDate as DateTime?,
      fetchedPackage: identical(fetchedPackage, _sentinel)
          ? this.fetchedPackage
          : fetchedPackage as String?,
      assetFilterPattern: identical(assetFilterPattern, _sentinel)
          ? this.assetFilterPattern
          : assetFilterPattern as String?,
      tagPrefix: identical(tagPrefix, _sentinel)
          ? this.tagPrefix
          : tagPrefix as String?,
      architectures: architectures ?? this.architectures,
      includePrerelease: includePrerelease ?? this.includePrerelease,
    );
  }

  /// Validates the asset filter pattern (glob pattern)
  static bool isValidFilterPattern(String? pattern) {
    if (pattern == null || pattern.isEmpty) return true;
    // Wildcards, extensions and plain literal filenames are all valid
    // glob patterns, so only whitespace-only input is rejected.
    return pattern.trim().isNotEmpty;
  }

  /// Validates the tag prefix
  static bool isValidTagPrefix(String? prefix) {
    if (prefix == null || prefix.isEmpty) return true;
    // Tag prefix should not contain special characters
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(prefix);
  }

  /// Validates all filter settings
  static String? validateFilterSettings({
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures,
  }) {
    if (assetFilterPattern != null && 
        assetFilterPattern.isNotEmpty && 
        !isValidFilterPattern(assetFilterPattern)) {
      return 'Invalid asset filter pattern. Use wildcards like * or ?';
    }
    
    if (tagPrefix != null && !isValidTagPrefix(tagPrefix)) {
      return 'Invalid tag prefix. Use only alphanumeric characters, hyphens, and underscores.';
    }

    return null;
  }
}

/// Strips an npm package specifier prefix (`@scope/name@` or `name@`), a
/// leading `v`/`V`, trims and lowercases [version] so that
/// `@biomejs/biome@2.5.14`, `V1.0.0` and `1.0.0` all reduce to their bare
/// version.
String normalizeVersion(String version) {
  var v = version.trim();
  // npm dist-tags are published as `@scope/name@<version>` (or
  // `name@<version>`); only the part after the final `@` is the version.
  final at = v.lastIndexOf('@');
  if (at != -1) {
    v = v.substring(at + 1);
  }
  if (v.startsWith('v') || v.startsWith('V')) {
    v = v.substring(1);
  }
  return v.toLowerCase();
}

/// Returns `true` when [s] is shaped like a version number rather than an
/// arbitrary label.
///
/// Accepts `1`, `2.5.14`, `v2.11.10`, `2.11.10-1`, and a prefixed release tag
/// whose version part is dotted (`desktop-v2026.9.0`). Rejects npm specifiers
/// (`@biomejs/biome@2.5.14`), junk tags (`multiplatform#1`) and filenames
/// (`download_cli.sh`, `latest.json`) so a non-version latest value can never be
/// mistaken for an upgrade.
bool looksLikeVersion(String s) {
  final trimmed = s.trim();
  if (!RegExp(r'\d').hasMatch(trimmed)) return false;
  if (RegExp(r'^[vV]?\d+(\.\d+)*(-.+)?$').hasMatch(trimmed)) return true;
  // A product prefix in front of the version, e.g. Bitwarden's per-client tags
  // `desktop-v2026.9.0` / `cli-v2026.9.0`, optionally followed by a prerelease
  // suffix as in tolaria's `alpha-v2026.9.25-alpha.0006`. The prefix is only
  // accepted when the version part is DOTTED, so a bare-number tag such as
  // `multiplatform#1` still fails — `#` is not part of a product prefix.
  return RegExp(r'^[A-Za-z][\w.-]*[-_]v?\d+(\.\d+)+(-.+)?$').hasMatch(trimmed);
}

/// Returns `true` when [newVersion] is strictly newer than [oldVersion].
///
/// Shared by [TrackedApp.hasUpdate] and [TrackedDebPackage.hasUpdate].
bool isNewerVersion(String newVersion, String oldVersion) {
  final newParts = _parseVersion(newVersion);
  final oldParts = _parseVersion(oldVersion);

  for (var i = 0; i < 3; i++) {
    if (newParts[i] > oldParts[i]) return true;
    if (newParts[i] < oldParts[i]) return false;
  }

  // Debian revisions (`1.0.0-1` vs `1.0.0-2`) only decide the comparison when
  // both sides carry one. A numeric revision on exactly ONE side means the two
  // strings are the same upstream version (`2.11.10-1` is a packaging revision
  // of `2.11.10`), so neither is newer. This must run before the prerelease
  // logic, where a lone `-1` would otherwise look like a prerelease.
  final newRevision = _parseRevision(newVersion);
  final oldRevision = _parseRevision(oldVersion);

  if ((newRevision == null) != (oldRevision == null)) return false;

  if (newRevision != null && oldRevision != null) {
    if (newRevision > oldRevision) return true;
    if (newRevision < oldRevision) return false;
  }

  // If major.minor.patch are equal, check if one is a prerelease.
  // A release version (no dash) is newer than a prerelease (has dash).
  final newIsPrerelease = newVersion.contains('-');
  final oldIsPrerelease = oldVersion.contains('-');

  if (!newIsPrerelease && oldIsPrerelease) return true;
  if (newIsPrerelease && !oldIsPrerelease) return false;

  // If both are prereleases, compare the suffixes chunk by chunk so that
  // `rc10` sorts after `rc9` instead of ordering lexicographically.
  return _comparePrerelease(
        _prereleaseSuffix(newVersion),
        _prereleaseSuffix(oldVersion),
      ) >
      0;
}

/// Parses the numeric `major.minor.patch` part of [version].
List<int> _parseVersion(String version) {
  // The version core is the first dotted numeric run. Splitting at the first
  // `-` instead used to truncate inside a product prefix: `desktop-v2026.9.0`
  // has its dash at index 7, so the "numeric part" came out as `desktop`, every
  // digit was stripped, and the version parsed as [0, 0, 0] — older than
  // everything, so a real update was never reported.
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(version);
  final parts = (match?.group(0) ?? '0')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts.sublist(0, 3);
}

/// Returns the Debian revision of [version] (the leading digits after the
/// first `-`), or `null` when there is no numeric revision.
int? _parseRevision(String version) {
  final dash = version.indexOf('-');
  if (dash == -1) return null;
  final match = RegExp(r'^\d+').firstMatch(version.substring(dash + 1));
  return match == null ? null : int.tryParse(match.group(0)!);
}

String _prereleaseSuffix(String version) {
  final dash = version.indexOf('-');
  return dash == -1 ? '' : version.substring(dash + 1);
}

/// Compares two prerelease suffixes, ordering digit runs numerically
/// (`rc9 < rc10`).
int _comparePrerelease(String a, String b) {
  final aChunks = _naturalChunks(a);
  final bChunks = _naturalChunks(b);

  for (var i = 0; i < aChunks.length && i < bChunks.length; i++) {
    final aNum = int.tryParse(aChunks[i]);
    final bNum = int.tryParse(bChunks[i]);
    if (aNum != null && bNum != null) {
      if (aNum != bNum) return aNum.compareTo(bNum);
    } else {
      final cmp = aChunks[i].compareTo(bChunks[i]);
      if (cmp != 0) return cmp;
    }
  }
  return aChunks.length.compareTo(bChunks.length);
}

/// Splits [value] into alternating digit / non-digit runs.
List<String> _naturalChunks(String value) {
  return RegExp(r'\d+|\D+').allMatches(value).map((m) => m.group(0)!).toList();
}
