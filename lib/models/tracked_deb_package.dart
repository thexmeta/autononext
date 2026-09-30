import 'tracked_app.dart';

/// Represents a tracked Debian package from a direct URL
/// Used for tracking packages that are not from GitHub releases
class TrackedDebPackage {
  final int? id;
  final String name;
  final String packageUrl;
  final String? displayName;
  final String? installedVersion;
  final String? latestVersion;
  final String? fileSize;
  final DateTime? fileDate;
  final DateTime? lastChecked;
  final DateTime createdAt;
  final String? checksum;
  final bool autoUpdate;
  final String? packageName;
  final String? launchCommand;

  TrackedDebPackage({
    this.id,
    required this.name,
    required this.packageUrl,
    this.displayName,
    this.installedVersion,
    this.latestVersion,
    this.fileSize,
    this.fileDate,
    this.lastChecked,
    required this.createdAt,
    this.checksum,
    this.autoUpdate = false,
    this.packageName,
    this.launchCommand,
  });

  /// Extract version from filename (e.g., "app_1.2.3_amd64.deb" -> "1.2.3")
  static String? extractVersionFromFilename(String filename) {
    final match = RegExp(r'[_-]([0-9]+(?:\.[0-9]+)*(?:-[a-zA-Z0-9]+)?)').firstMatch(filename);
    return match?.group(1);
  }

  /// Get filename from URL
  String get filename {
    try {
      final uri = Uri.parse(packageUrl);
      final path = uri.path;
      return path.split('/').last;
    } catch (_) {
      return '';
    }
  }

  /// Check if package has update available
  bool get hasUpdate {
    if (installedVersion == null || latestVersion == null) return false;
    final installed = normalizeVersion(installedVersion!);
    final latest = normalizeVersion(latestVersion!);
    if (installed == latest) return false;
    return isNewerVersion(latest, installed);
  }

  /// Get display name or fallback to filename
  String get effectiveDisplayName => displayName ?? name;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'package_url': packageUrl,
      'display_name': displayName,
      'installed_version': installedVersion,
      'latest_version': latestVersion,
      'file_size': fileSize,
      'file_date': fileDate?.toIso8601String(),
      'last_checked': lastChecked?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'checksum': checksum,
      'auto_update': autoUpdate,
      'package_name': packageName,
      'launch_command': launchCommand,
    };
  }

  factory TrackedDebPackage.fromMap(Map<String, dynamic> map) {
    return TrackedDebPackage(
      id: map['id'] as int?,
      name: map['name'] as String,
      packageUrl: map['package_url'] as String,
      displayName: map['display_name'] as String?,
      installedVersion: map['installed_version'] as String?,
      latestVersion: map['latest_version'] as String?,
      fileSize: map['file_size'] as String?,
      fileDate: map['file_date'] != null
          ? (map['file_date'] is DateTime
              ? map['file_date']
              : DateTime.parse(map['file_date'] as String))
          : null,
      lastChecked: map['last_checked'] != null
          ? (map['last_checked'] is DateTime
              ? map['last_checked']
              : DateTime.parse(map['last_checked'] as String))
          : null,
      createdAt: map['created_at'] is DateTime
          ? map['created_at']
          : DateTime.parse(map['created_at'] as String),
      checksum: map['checksum'] as String?,
      autoUpdate: map['auto_update'] as bool? ?? false,
      packageName: map['package_name'] as String?,
      launchCommand: map['launch_command'] as String?,
    );
  }

  /// Sentinel used by [copyWith] to distinguish "not supplied" from
  /// "explicitly set to null".
  static const _sentinel = Object();

  TrackedDebPackage copyWith({
    Object? id = _sentinel,
    String? name,
    String? packageUrl,
    Object? displayName = _sentinel,
    Object? installedVersion = _sentinel,
    Object? latestVersion = _sentinel,
    Object? fileSize = _sentinel,
    Object? fileDate = _sentinel,
    Object? lastChecked = _sentinel,
    DateTime? createdAt,
    Object? checksum = _sentinel,
    bool? autoUpdate,
    Object? packageName = _sentinel,
    Object? launchCommand = _sentinel,
  }) {
    return TrackedDebPackage(
      id: identical(id, _sentinel) ? this.id : id as int?,
      name: name ?? this.name,
      packageUrl: packageUrl ?? this.packageUrl,
      displayName: identical(displayName, _sentinel)
          ? this.displayName
          : displayName as String?,
      installedVersion: identical(installedVersion, _sentinel)
          ? this.installedVersion
          : installedVersion as String?,
      latestVersion: identical(latestVersion, _sentinel)
          ? this.latestVersion
          : latestVersion as String?,
      fileSize: identical(fileSize, _sentinel)
          ? this.fileSize
          : fileSize as String?,
      fileDate: identical(fileDate, _sentinel)
          ? this.fileDate
          : fileDate as DateTime?,
      lastChecked: identical(lastChecked, _sentinel)
          ? this.lastChecked
          : lastChecked as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      checksum: identical(checksum, _sentinel)
          ? this.checksum
          : checksum as String?,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      packageName: identical(packageName, _sentinel)
          ? this.packageName
          : packageName as String?,
      launchCommand: identical(launchCommand, _sentinel)
          ? this.launchCommand
          : launchCommand as String?,
    );
  }
}
