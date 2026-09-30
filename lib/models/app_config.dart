import 'install_type.dart';
import 'tracked_app.dart';

class AppConfig {
  final String schemaVersion;
  final DateTime exportedAt;
  final String? appName;
  final String? appVersion;
  final List<TrackedAppData> apps;

  AppConfig({
    required this.schemaVersion,
    required this.exportedAt,
    this.appName,
    this.appVersion,
    required this.apps,
  });

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'appName': appName,
      'appVersion': appVersion,
      'apps': apps.map((app) => app.toMap()).toList(),
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      schemaVersion: json['schemaVersion'] as String,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      appName: json['appName'] as String?,
      appVersion: json['appVersion'] as String?,
      apps: (json['apps'] as List?)
              ?.map((app) => TrackedAppData.fromMap(app as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class TrackedAppData {
  final String repoOwner;
  final String repoName;
  final String displayName;
  final String? assetFilterPattern;
  final String? tagPrefix;
  final List<String> architectures;
  final bool includePrerelease;

  // Install state — carried through export/import so a round trip does not
  // silently drop what the user already installed.
  final String? installedVersion;
  final String? latestVersion;
  final InstallType? installType;
  final String? launchCommand;
  final String? packageName;
  final DateTime? lastChecked;
  final DateTime? latestReleaseDate;
  final String? fetchedPackage;

  TrackedAppData({
    required this.repoOwner,
    required this.repoName,
    required this.displayName,
    this.assetFilterPattern,
    this.tagPrefix,
    List<String>? architectures,
    this.includePrerelease = false,
    this.installedVersion,
    this.latestVersion,
    this.installType,
    this.launchCommand,
    this.packageName,
    this.lastChecked,
    this.latestReleaseDate,
    this.fetchedPackage,
  }) : architectures = architectures ?? [];

  Map<String, dynamic> toMap() {
    return {
      'repoOwner': repoOwner,
      'repoName': repoName,
      'displayName': displayName,
      'assetFilterPattern': assetFilterPattern,
      'tagPrefix': tagPrefix,
      'architectures': architectures,
      'includePrerelease': includePrerelease,
      'installedVersion': installedVersion,
      'latestVersion': latestVersion,
      'installType': installType?.name,
      'launchCommand': launchCommand,
      'packageName': packageName,
      'lastChecked': lastChecked?.toIso8601String(),
      'latestReleaseDate': latestReleaseDate?.toIso8601String(),
      'fetchedPackage': fetchedPackage,
    };
  }

  factory TrackedAppData.fromMap(Map<String, dynamic> map) {
    return TrackedAppData(
      repoOwner: map['repoOwner'] as String,
      repoName: map['repoName'] as String,
      displayName: map['displayName'] as String,
      assetFilterPattern: map['assetFilterPattern'] as String?,
      tagPrefix: map['tagPrefix'] as String?,
      architectures: map['architectures'] != null
          ? List<String>.from(map['architectures'] as List)
          : [],
      includePrerelease: map['includePrerelease'] as bool? ?? false,
      installedVersion: map['installedVersion'] as String?,
      latestVersion: map['latestVersion'] as String?,
      installType: InstallType.fromString(map['installType'] as String?),
      launchCommand: map['launchCommand'] as String?,
      packageName: map['packageName'] as String?,
      lastChecked: map['lastChecked'] != null
          ? DateTime.parse(map['lastChecked'] as String)
          : null,
      latestReleaseDate: map['latestReleaseDate'] != null
          ? DateTime.parse(map['latestReleaseDate'] as String)
          : null,
      fetchedPackage: map['fetchedPackage'] as String?,
    );
  }

  TrackedApp toTrackedApp(int id, {DateTime? createdAt}) {
    return TrackedApp(
      id: id,
      repoOwner: repoOwner,
      repoName: repoName,
      displayName: displayName,
      assetFilterPattern: assetFilterPattern,
      tagPrefix: tagPrefix,
      architectures: architectures,
      includePrerelease: includePrerelease,
      installedVersion: installedVersion,
      latestVersion: latestVersion,
      installType: installType,
      launchCommand: launchCommand,
      packageName: packageName,
      lastChecked: lastChecked,
      latestReleaseDate: latestReleaseDate,
      fetchedPackage: fetchedPackage,
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}
