import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/release.dart';
import '../utils/glob_pattern.dart';
import 'debug_logger.dart';
import 'settings_service.dart';

class GitHubService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _fallbackUserAgent = 'Autononext';

  /// Resolved lazily from [PackageInfo]; falls back to [_fallbackUserAgent]
  /// when the plugin is unavailable (e.g. in unit tests).
  static String _userAgent = _fallbackUserAgent;
  static bool _userAgentResolved = false;

  static Future<String> _resolveUserAgent() async {
    if (_userAgentResolved) return _userAgent;
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 2));
      final version = info.version.trim();
      _userAgent = version.isEmpty ? _fallbackUserAgent : 'Autononext/$version';
      _userAgentResolved = true;
    } catch (_) {
      // Keep the fallback for this call and try again next time.
    }
    return _userAgent;
  }

  final SettingsService? _settingsService;
  
  GitHubService({SettingsService? settingsService}) : _settingsService = settingsService;

  Future<String?> _getGithubToken() async {
    if (_settingsService != null) {
      return await _settingsService!.getGithubToken();
    }
    return null;
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'User-Agent': await _resolveUserAgent(),
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    final token = await _getGithubToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Release?> getLatestRelease(
    String owner,
    String repo, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures,
    bool includePrerelease = false,
  }) async {
    final releases = await getReleases(owner, repo);

    final filteredReleases = releases.where((release) {
      if (!includePrerelease && release.prerelease) {
        return false;
      }
      if (tagPrefix != null && tagPrefix.trim().isNotEmpty) {
        final searchPrefix = tagPrefix.trim().toLowerCase();
        final lowerTag = release.tagName.toLowerCase();
        if (!lowerTag.startsWith(searchPrefix)) {
          return false;
        }
      }
      return true;
    }).toList();

    for (var release in filteredReleases) {
      final filteredAssets = filterAssets(
        release,
        assetFilterPattern: assetFilterPattern,
        architectures: architectures,
      );

      if (filteredAssets.isNotEmpty) {
        return release.copyWith(assets: filteredAssets);
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> getLatestReleaseWithPackageInfo(
    String owner,
    String repo, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures,
    bool includePrerelease = false,
  }) async {
    final release = await getLatestRelease(
      owner,
      repo,
      assetFilterPattern: assetFilterPattern,
      tagPrefix: tagPrefix,
      architectures: architectures,
      includePrerelease: includePrerelease,
    );

    if (release == null) return null;

    // Find the best matching asset
    ReleaseAsset? bestAsset;
    for (var asset in release.assets) {
      if (architectures != null && architectures.isNotEmpty) {
        for (var arch in architectures) {
          if (matchesArchitecture(asset.name, arch)) {
            bestAsset = asset;
            break;
          }
        }
      } else {
        bestAsset = asset;
        break;
      }
      if (bestAsset != null) break;
    }

    if (bestAsset == null && release.assets.isNotEmpty) {
      bestAsset = release.assets.first;
    }

    return {
      'release': release,
      'packageName': bestAsset?.name,
      'downloadUrl': bestAsset?.browserDownloadUrl,
      'releaseDate': release.publishedAt?.toIso8601String(),
    };
  }

  Future<List<Release>> getReleases(String owner, String repo, {int? perPage}) async {
    final releasesPerPage = perPage ?? await _getReleasesPerPage();
    final url = Uri.parse(
      '$_baseUrl/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}'
      '/releases?per_page=$releasesPerPage',
    );
    final response = await http.get(
      url,
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      try {
        return parseReleases(response.body);
      } catch (e) {
        // A GitHub HTML error page or truncated body must not surface as a
        // raw FormatException.
        throw Exception('Failed to load releases: ${response.statusCode} (malformed response: $e)');
      }
    } else {
      throw Exception('Failed to load releases: ${response.statusCode}');
    }
  }

  /// Parses a GitHub releases response body into [Release] objects.
  ///
  /// Malformed *entries* — a non-object element, or one whose fields are the
  /// wrong type — are skipped and logged rather than aborting the whole list.
  /// A body that is not a JSON array still throws a [FormatException] so the
  /// caller can surface a genuinely malformed response.
  static List<Release> parseReleases(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Expected a JSON list of releases');
    }

    final releases = <Release>[];
    for (final entry in decoded) {
      try {
        if (entry is! Map) {
          throw FormatException('Unexpected release entry: ${entry.runtimeType}');
        }
        releases.add(Release.fromJson(Map<String, dynamic>.from(entry)));
      } catch (e) {
        dlog('GitHubService', 'Skipping malformed release entry: $e');
      }
    }
    return releases;
  }

  Future<int> _getReleasesPerPage() async {
    if (_settingsService != null) {
      return await _settingsService!.getEffectiveReleasesPerPage();
    }
    return 100; // Default
  }

  Future<Map<String, dynamic>> getRepository(String owner, String repo) async {
    final url = Uri.parse(
      '$_baseUrl/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}',
    );
    final response = await http.get(
      url,
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Failed to load repository: ${response.statusCode} (malformed response: $e)');
      }
    } else {
      throw Exception('Failed to load repository: ${response.statusCode}');
    }
  }

  List<ReleaseAsset> filterAssets(
    Release release, {
    String? assetFilterPattern,
    List<String>? architectures,
  }) {
    final assets = release.assets;

    return assets.where((asset) {
      final name = asset.name;

      if (assetFilterPattern != null && assetFilterPattern.isNotEmpty) {
        if (!matchesGlobPattern(name, assetFilterPattern)) {
          return false;
        }
      }

      if (architectures != null && architectures.isNotEmpty) {
        final hasMatchingArch = architectures.any((arch) =>
          matchesArchitecture(name, arch)
        );
        if (!hasMatchingArch) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}
