// LIVE sweep — NOT part of the test suite (it lives outside `test/`).
// Run explicitly:  flutter test tool/asset_sweep_test.dart
//
// For every app the app itself considers updatable, print the asset it would
// actually install and flag anything that is not a plausible Linux binary.
// This answers the reviewer's claim that a SHA256SUMS/LICENCE asset can be
// selected over the real binary when no architecture match disambiguates.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/installer_service.dart';

// Dart's RegExp has no `(?i)` inline flag — passing it throws
// "FormatException: Invalid group", so case-insensitivity must be a parameter.
final _doc = RegExp(
  r'(license|licence|readme|changelog|sha256|sha512|checksum|\.txt$|\.json$|\.sig$|\.asc$)',
  caseSensitive: false,
);
final _foreignOs = RegExp(
  r'(darwin|macos|osx|win32|win64|windows|mingw|\.exe$|\.msi$|\.dmg$|\.pkg$)',
  caseSensitive: false,
);

void main() {
  test('every updatable app selects an installable Linux asset', () async {
    final home = Platform.environment['HOME']!;
    final raw = File(
      '$home/.local/share/com.autononext/apps.json',
    ).readAsStringSync();
    final apps = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(TrackedApp.fromMap)
        .where((a) => a.hasUpdate)
        .toList();

    final gh = GitHubService();
    final installer = InstallerService();
    var docAssets = 0;
    var foreignAssets = 0;
    var uninstallable = 0;

    for (final a in apps) {
      final label = '${a.repoOwner}/${a.repoName}';
      try {
        final info = await gh.getLatestReleaseWithPackageInfo(
          a.repoOwner,
          a.repoName,
          assetFilterPattern: a.assetFilterPattern,
          tagPrefix: a.tagPrefix,
          architectures: a.architectures,
          includePrerelease: a.includePrerelease,
        );
        final tag = (info?['release'] as dynamic)?.tagName;
        final asset = info?['packageName'] as String?;
        final type = asset == null ? null : installer.identifyAssetType(asset);
        final isDoc = asset != null && _doc.hasMatch(asset);
        final isForeign = asset != null && _foreignOs.hasMatch(asset);
        if (isDoc) docAssets++;
        if (isForeign) foreignAssets++;
        if (type == null) uninstallable++;
        // ignore: avoid_print
        print(
          'SWEEP $label tag=$tag asset=$asset type=${type?.name}'
          '${isDoc ? '  <<DOC-ASSET' : ''}'
          '${isForeign ? '  <<FOREIGN-OS' : ''}'
          '${type == null ? '  <<NOT-INSTALLABLE' : ''}',
        );
      } catch (e) {
        // ignore: avoid_print
        print('SWEEP $label ERROR $e');
      }
    }

    // ignore: avoid_print
    print(
      'SWEEP total=${apps.length} docAssets=$docAssets '
      'foreignAssets=$foreignAssets uninstallable=$uninstallable',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
