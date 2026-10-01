import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/tracked_app.dart';
import '../models/app_config.dart';
import '../models/tracked_deb_package.dart';
import 'external_app_checker.dart';
import 'debug_logger.dart';

class DatabaseService {
  File? _file;
  File? _debFile;

  /// True when the on-disk app database exists but cannot be parsed. While
  /// set, saves are refused so a corrupt file is never silently overwritten.
  bool _appsDbUnreadable = false;
  String? _appsDbBackupPath;

  /// Same as [_appsDbUnreadable] for the deb-package database.
  bool _debDbUnreadable = false;
  String? _debDbBackupPath;

  DatabaseService();

  Future<File> get _dbFile async {
    if (_file != null) return _file!;
    final configDir = await getApplicationSupportDirectory();
    await Directory(configDir.path).create(recursive: true);
    _file = File(join(configDir.path, 'apps.json'));
    return _file!;
  }

  Future<File> get _debDbFile async {
    if (_debFile != null) return _debFile!;
    final configDir = await getApplicationSupportDirectory();
    await Directory(configDir.path).create(recursive: true);
    _debFile = File(join(configDir.path, 'deb_packages.json'));
    return _debFile!;
  }

  /// Reads the app database.
  ///
  /// A missing (or empty) file is a legitimate first run and yields `[]`. A
  /// file that exists but cannot be parsed is backed up and flagged, and every
  /// later save is refused so the damaged data is not destroyed.
  Future<List<TrackedApp>> getAllApps() async {
    final file = await _dbFile;
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => TrackedApp.fromMap(e)).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } catch (e) {
      _appsDbUnreadable = true;
      _appsDbBackupPath = await _backupUnreadableFile(file);
      dlog('DatabaseService',
          'Error reading apps DB: $e. Copy kept at ${_appsDbBackupPath ?? file.path}');
      return [];
    }
  }

  Future<void> _saveApps(List<TrackedApp> apps) async {
    final file = await _dbFile;
    if (_appsDbUnreadable) {
      throw Exception(
        'Refusing to overwrite unreadable apps database (${file.path})'
        '${_appsDbBackupPath != null ? '; a copy is kept at $_appsDbBackupPath' : ''}',
      );
    }
    final jsonList = apps.map((e) => e.toMap()).toList();
    await _writeJsonAtomically(file, jsonEncode(jsonList));
  }

  /// Writes [contents] via a temp file + [File.rename], so an interrupted
  /// write can never leave a truncated database behind.
  Future<void> _writeJsonAtomically(File target, String contents) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(contents);
    try {
      await tmp.rename(target.path);
    } catch (e) {
      try {
        await tmp.delete();
      } catch (_) {
        // Best effort: nothing else to do while already failing.
      }
      rethrow;
    }
  }

  /// Copies an unreadable database aside so a later save cannot destroy it.
  Future<String?> _backupUnreadableFile(File file) async {
    try {
      final backup = File('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      await file.copy(backup.path);
      return backup.path;
    } catch (e) {
      dlog('DatabaseService', 'Failed to back up unreadable database: $e');
      return null;
    }
  }

  Future<int> addApp(
    String repoOwner,
    String repoName,
    String displayName, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String> architectures = const [],
    bool includePrerelease = false,
    String? launchCommand,
    String? packageName,
  }) async {
    final apps = await getAllApps();

    if (apps.any((a) => a.repoOwner == repoOwner && a.repoName == repoName)) {
      throw Exception('App already exists');
    }

    final id = (apps.isEmpty ? 0 : apps.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b)) + 1;

    final newApp = TrackedApp(
      id: id,
      repoOwner: repoOwner,
      repoName: repoName,
      displayName: displayName,
      createdAt: DateTime.now(),
      assetFilterPattern: assetFilterPattern,
      tagPrefix: tagPrefix,
      architectures: architectures,
      includePrerelease: includePrerelease,
      launchCommand: launchCommand,
      packageName: packageName,
    );

    apps.add(newApp);
    await _saveApps(apps);
    return id;
  }

  Future<void> updateApp(TrackedApp app) async {
    final apps = await getAllApps();
    final index = apps.indexWhere((a) => a.id == app.id);

    if (index == -1) {
      throw Exception('App with id ${app.id} not found in database');
    }

    apps[index] = app;
    await _saveApps(apps);
  }

  Future<void> deleteApp(int id) async {
    final apps = await getAllApps();
    apps.removeWhere((a) => a.id == id);
    await _saveApps(apps);
  }

  Future<String> exportConfig() async {
    try {
      final apps = await getAllApps();
      final appData = apps.map((app) => TrackedAppData(
        repoOwner: app.repoOwner,
        repoName: app.repoName,
        displayName: app.displayName,
        assetFilterPattern: app.assetFilterPattern,
        tagPrefix: app.tagPrefix,
        architectures: app.architectures,
        includePrerelease: app.includePrerelease,
        installedVersion: app.installedVersion,
        latestVersion: app.latestVersion,
        installType: app.installType,
        launchCommand: app.launchCommand,
        packageName: app.packageName,
        lastChecked: app.lastChecked,
        latestReleaseDate: app.latestReleaseDate,
        fetchedPackage: app.fetchedPackage,
      )).toList();

      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.now(),
        appName: 'Autononext',
        appVersion: await _resolveAppVersion(),
        apps: appData,
      );

      final configDir = await getApplicationSupportDirectory();
      final exportFile = File('${configDir.path}/autononext-export-${DateTime.now().toIso8601String().split('T').first}.json');
      await exportFile.writeAsString(jsonEncode(config.toJson()));
      
      return exportFile.path;
    } catch (e) {
      throw Exception('Failed to export config: $e');
    }
  }

  /// The running app version, read from the platform package metadata.
  ///
  /// Falls back to [_fallbackAppVersion] when `PackageInfo` is unavailable
  /// (e.g. on a platform without the plugin) so an export never fails or
  /// reports a blank version.
  Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) return info.version;
    } catch (e) {
      dlog('DatabaseService', 'Could not read app version: $e');
    }
    return _fallbackAppVersion;
  }

  /// Last-resort version used when [PackageInfo] cannot be read. Keep in sync
  /// with `version` in pubspec.yaml.
  static const String _fallbackAppVersion = '0.1.0-b4';

  Future<int> importConfig(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final content = await file.readAsString();
      final config = AppConfig.fromJson(jsonDecode(content) as Map<String, dynamic>);

      final existingApps = await getAllApps();
      int importCount = 0;

      for (final appData in config.apps) {
        if (!existingApps.any((a) =>
            a.repoOwner == appData.repoOwner && a.repoName == appData.repoName)) {
          final newApp = appData.toTrackedApp(
            (existingApps.isEmpty ? 0 : existingApps.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b)) + 1 + importCount,
          );
          existingApps.add(newApp);
          importCount++;
        }
      }

      if (importCount > 0) {
        await _saveApps(existingApps);
      }

      return importCount;
    } catch (e) {
      throw Exception('Failed to import config: $e');
    }
  }

  // Deb Package Methods
  Future<List<TrackedDebPackage>> getAllDebPackages() async {
    final file = await _debDbFile;
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => TrackedDebPackage.fromMap(e)).toList();
    } catch (e) {
      _debDbUnreadable = true;
      _debDbBackupPath = await _backupUnreadableFile(file);
      dlog('DatabaseService',
          'Error reading deb packages DB: $e. Copy kept at ${_debDbBackupPath ?? file.path}');
      return [];
    }
  }

  Future<void> _saveDebPackages(List<TrackedDebPackage> packages) async {
    final file = await _debDbFile;
    if (_debDbUnreadable) {
      throw Exception(
        'Refusing to overwrite unreadable deb package database (${file.path})'
        '${_debDbBackupPath != null ? '; a copy is kept at $_debDbBackupPath' : ''}',
      );
    }
    final jsonList = packages.map((e) => e.toMap()).toList();
    await _writeJsonAtomically(file, jsonEncode(jsonList));
  }

  Future<int> addDebPackage({
    required String name,
    required String packageUrl,
    String? displayName,
    bool autoUpdate = false,
    String? launchCommand,
    String? packageName,
  }) async {
    final packages = await getAllDebPackages();

    if (packages.any((p) => p.packageUrl == packageUrl)) {
      throw Exception('Package URL already exists');
    }

    final id = (packages.isEmpty ? 0 : packages.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b)) + 1;

    var newPackage = TrackedDebPackage(
      id: id,
      name: name,
      packageUrl: packageUrl,
      displayName: displayName ?? name,
      createdAt: DateTime.now(),
      autoUpdate: autoUpdate,
      launchCommand: launchCommand,
      packageName: packageName,
    );

    // Best-effort metadata probe so the list can show the real file size and
    // date immediately. `_fetchDebInfo` never throws, and a failed probe must
    // not stop the package from being added.
    final info = await _fetchDebInfo(packageUrl);
    newPackage = newPackage.copyWith(
      fileSize: info.fileSize,
      fileDate: info.fileDate,
    );

    packages.add(newPackage);
    await _saveDebPackages(packages);
    return id;
  }

  Future<void> updateDebPackage(TrackedDebPackage pkg) async {
    final packages = await getAllDebPackages();
    final index = packages.indexWhere((p) => p.id == pkg.id);

    if (index == -1) {
      throw Exception('Package with id ${pkg.id} not found');
    }

    packages[index] = pkg;
    await _saveDebPackages(packages);
  }

  Future<void> deleteDebPackage(int id) async {
    final packages = await getAllDebPackages();
    packages.removeWhere((p) => p.id == id);
    await _saveDebPackages(packages);
  }

  /// Check a single tracked deb package for an available update.
  ///
  /// Returns the newly advertised version when the package's remote version
  /// differs from the version detected on the system, otherwise `null`. The
  /// package is identified by the object passed in (its
  /// [TrackedDebPackage.id]), so two packages that share a [name] can never
  /// collide. Refreshed metadata (latest/installed version, file size, file
  /// date, last-checked timestamp) is persisted. Never throws: a failed probe
  /// is logged and reported as "no update".
  Future<String?> checkDebPackageUpdate(TrackedDebPackage pkg) async {
    try {
      final info = await _fetchDebInfo(pkg.packageUrl);
      final installedVersion = await ExternalAppChecker.getExternalDebVersion(pkg);

      if (info.version == null && installedVersion == null) {
        return null;
      }

      await updateDebPackage(pkg.copyWith(
        latestVersion: info.version ?? pkg.latestVersion,
        installedVersion: installedVersion ?? pkg.installedVersion,
        fileSize: info.fileSize ?? pkg.fileSize,
        fileDate: info.fileDate ?? pkg.fileDate,
        lastChecked: DateTime.now(),
      ));

      // Compare against the version detected just now, not the stale value
      // stored on [pkg]. Use the same normalised comparison as
      // [TrackedDebPackage.hasUpdate] so a `v`-prefix mismatch or a downgrade
      // is not reported as an available update.
      if (info.version != null &&
          installedVersion != null &&
          isNewerVersion(
            normalizeVersion(info.version!),
            normalizeVersion(installedVersion),
          )) {
        return info.version;
      }
      return null;
    } catch (e) {
      dlog('DatabaseService', 'Error checking updates for ${pkg.name}: $e');
      return null;
    }
  }

  /// Check for updates on all tracked deb packages.
  ///
  /// Returns a map of package name to the newly advertised version. Kept for
  /// callers that sweep every package; a single-row action should use
  /// [checkDebPackageUpdate] to avoid the O(n) work and the name-keyed
  /// collision between same-named packages.
  Future<Map<String, String>> checkDebPackageUpdates() async {
    final packages = await getAllDebPackages();
    final updates = <String, String>{};

    for (final pkg in packages) {
      final latestVersion = await checkDebPackageUpdate(pkg);
      if (latestVersion != null) {
        updates[pkg.name] = latestVersion;
      }
    }

    return updates;
  }

  /// Probe a direct deb URL for its advertised version and file metadata.
  ///
  /// Sends a HEAD request (falling back to a 1-byte ranged GET when the host
  /// rejects HEAD) and derives the version from the `Content-Disposition`
  /// filename, the final (redirected) URL or the `Location` header. The real
  /// file size comes from `Content-Length` (or the total in `Content-Range`
  /// for a ranged GET) and the file date from `Last-Modified`. Falls back to
  /// the filename in [url]. Never throws: an update sweep must stay non-fatal
  /// even when a host is unreachable.
  Future<_DebRemoteInfo> _fetchDebInfo(String url) async {
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (e) {
      dlog('DatabaseService', 'Invalid deb package URL "$url": $e');
      return const _DebRemoteInfo();
    }

    final client = http.Client();
    try {
      var response = await client.head(uri).timeout(const Duration(seconds: 15));

      // Hosts that disallow HEAD answer 405/403/501 — retry with a tiny GET.
      if (response.statusCode == 405 ||
          response.statusCode == 403 ||
          response.statusCode == 501) {
        response = await client
            .get(uri, headers: {'Range': 'bytes=0-0'})
            .timeout(const Duration(seconds: 15));
      }

      if (response.statusCode >= 400) {
        dlog('DatabaseService', 'Deb version check for $url returned ${response.statusCode}');
        return _DebRemoteInfo(version: _versionFromUrl(uri));
      }

      final fileSize = _fileSizeFromResponse(response);
      final fileDate = _fileDateFromHeaders(response.headers);

      for (final candidate in <String>[
        _filenameFromContentDisposition(response.headers['content-disposition']),
        _filenameFromUrl(response.request?.url),
        _filenameFromUrl(_tryParse(response.headers['location'])),
      ]) {
        if (candidate.isEmpty) continue;
        final version = TrackedDebPackage.extractVersionFromFilename(candidate);
        if (version != null) {
          return _DebRemoteInfo(
            version: version,
            fileSize: fileSize,
            fileDate: fileDate,
          );
        }
      }

      return _DebRemoteInfo(
        version: _versionFromUrl(uri),
        fileSize: fileSize,
        fileDate: fileDate,
      );
    } catch (e) {
      dlog('DatabaseService', 'Error fetching deb version for $url: $e');
      return _DebRemoteInfo(version: _versionFromUrl(uri));
    } finally {
      client.close();
    }
  }

  /// The full size of the remote file, as a byte-count string.
  ///
  /// A HEAD response carries it in `Content-Length`; a ranged GET only
  /// transfers one byte, so its `Content-Range` (`bytes 0-0/12345`) holds the
  /// total. Returns null when neither header is usable.
  String? _fileSizeFromResponse(http.Response response) {
    final contentRange = response.headers['content-range'];
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash != -1) {
        final total = contentRange.substring(slash + 1).trim();
        if (total.isNotEmpty && total != '*') return total;
      }
    }
    final contentLength = response.headers['content-length'];
    if (contentLength == null || contentLength.isEmpty) return null;
    return contentLength;
  }

  /// Parses the HTTP `Last-Modified` header, or null when absent/invalid.
  DateTime? _fileDateFromHeaders(Map<String, String> headers) {
    final lastModified = headers['last-modified'];
    if (lastModified == null || lastModified.isEmpty) return null;
    try {
      return HttpDate.parse(lastModified);
    } catch (e) {
      dlog('DatabaseService', 'Invalid Last-Modified header "$lastModified": $e');
      return null;
    }
  }

  Uri? _tryParse(String? url) {
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  String _filenameFromUrl(Uri? uri) {
    if (uri == null || uri.pathSegments.isEmpty) return '';
    return uri.pathSegments.last;
  }

  String? _versionFromUrl(Uri? uri) {
    final filename = _filenameFromUrl(uri);
    if (filename.isEmpty) return null;
    return TrackedDebPackage.extractVersionFromFilename(filename);
  }

  /// Pulls the filename out of a `Content-Disposition` header value such as
  /// `attachment; filename="app_1.2.3_amd64.deb"`.
  String _filenameFromContentDisposition(String? header) {
    if (header == null || header.isEmpty) return '';
    for (final part in header.split(';')) {
      final trimmed = part.trim();
      if (!trimmed.toLowerCase().startsWith('filename')) continue;
      final eq = trimmed.indexOf('=');
      if (eq == -1) continue;
      var value = trimmed.substring(eq + 1).trim().replaceAll('"', '').replaceAll("'", '');
      // RFC 5987 encoded form: filename*=UTF-8''app_1.2.3.deb
      final prefix = value.toLowerCase().indexOf("utf-8''");
      if (prefix != -1) value = value.substring(prefix + 7);
      final name = value.split('/').last.split('\\').last.trim();
      if (name.isNotEmpty) return name;
    }
    return '';
  }
}

/// Metadata harvested from a single HTTP probe of a direct deb URL.
class _DebRemoteInfo {
  /// Version parsed from the response, or null when it could not be derived.
  final String? version;

  /// Size of the remote file in bytes (as advertised by the server), or null.
  final String? fileSize;

  /// Value of the `Last-Modified` header, or null when absent/unparseable.
  final DateTime? fileDate;

  const _DebRemoteInfo({this.version, this.fileSize, this.fileDate});
}
