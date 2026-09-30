import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/models/release.dart';
import '../mocks/mock_github_service.dart';

void main() {
  group('GitHubService filterAssets', () {
    late GitHubService service;

    setUp(() {
      service = GitHubService();
    });

    Release createRelease({
      String tagName = 'v1.0.0',
      List<ReleaseAsset>? assets,
      bool prerelease = false,
    }) {
      return Release(
        tagName: tagName,
        name: 'Test Release',
        body: null,
        publishedAt: DateTime.now(),
        prerelease: prerelease,
        draft: false,
        assets: assets ?? [],
      );
    }

    ReleaseAsset createAsset({
      required String name,
      String contentType = 'application/octet-stream',
      int size = 1000,
    }) {
      return ReleaseAsset(
        name: name,
        browserDownloadUrl: 'https://example.com/$name',
        contentType: contentType,
        size: size,
      );
    }

    test('returns all assets when no filters', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-arm64.deb'),
        createAsset(name: 'app.tar.gz'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(release);

      expect(result.length, equals(3));
    });

    test('filters by asset pattern', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-arm64.deb'),
        createAsset(name: 'app.tar.gz'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(release, assetFilterPattern: '*.deb');

      expect(result.length, equals(2));
      expect(result.every((a) => a.name.endsWith('.deb')), isTrue);
    });

    test('filters by architecture', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-arm64.deb'),
        createAsset(name: 'app-armhf.deb'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(release, architectures: ['amd64']);

      expect(result.length, equals(1));
      expect(result.first.name, contains('amd64'));
    });

    test('filters by multiple architectures', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-arm64.deb'),
        createAsset(name: 'app-armhf.deb'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(
        release,
        architectures: ['amd64', 'arm64'],
      );

      expect(result.length, equals(2));
    });

    test('filters by both pattern and architecture', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-amd64.tar.gz'),
        createAsset(name: 'app-arm64.deb'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(
        release,
        assetFilterPattern: '*.deb',
        architectures: ['amd64'],
      );

      expect(result.length, equals(1));
      expect(result.first.name, equals('app-amd64.deb'));
    });

    test('returns empty list when no matches', () {
      final assets = [
        createAsset(name: 'app-amd64.deb'),
        createAsset(name: 'app-arm64.deb'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(
        release,
        assetFilterPattern: '*.rpm',
      );

      expect(result, isEmpty);
    });

    test('handles cross-architecture detection', () {
      final assets = [
        createAsset(name: 'app-x86_64.deb'),
        createAsset(name: 'app-x64.deb'),
        createAsset(name: 'app-64-bit.deb'),
      ];
      final release = createRelease(assets: assets);

      final result = service.filterAssets(
        release,
        architectures: ['amd64'],
      );

      expect(result.length, equals(3));
    });

    test('handles empty asset list', () {
      final release = createRelease(assets: []);

      final result = service.filterAssets(release);

      expect(result, isEmpty);
    });
  });

  group('GitHubService getLatestRelease with filters', () {
    test('filters releases by tag prefix', () async {
      final mockGitHub = MockGitHubService();
      mockGitHub.setReleases([
        Release(tagName: 'v1.0.0', assets: [ReleaseAsset(name: 'a.deb', browserDownloadUrl: '', contentType: '', size: 0)], prerelease: false, draft: false),
        Release(tagName: 'app-2.0.0', assets: [ReleaseAsset(name: 'b.deb', browserDownloadUrl: '', contentType: '', size: 0)], prerelease: false, draft: false),
      ]);

      // Match 'app' prefix
      var result = await mockGitHub.getLatestRelease('o', 'r', tagPrefix: 'app');
      expect(result?.tagName, equals('app-2.0.0'));

      // Match 'v' prefix
      result = await mockGitHub.getLatestRelease('o', 'r', tagPrefix: 'v');
      expect(result?.tagName, equals('v1.0.0'));
      
      // Case insensitive match
      result = await mockGitHub.getLatestRelease('o', 'r', tagPrefix: 'APP');
      expect(result?.tagName, equals('app-2.0.0'));
    });

    test('handles prerelease filtering', () async {
      final mockGitHub = MockGitHubService();
      mockGitHub.setReleases([
        Release(tagName: 'v2.0.0-beta', assets: [ReleaseAsset(name: 'a.deb', browserDownloadUrl: '', contentType: '', size: 0)], prerelease: true, draft: false),
        Release(tagName: 'v1.0.0', assets: [ReleaseAsset(name: 'b.deb', browserDownloadUrl: '', contentType: '', size: 0)], prerelease: false, draft: false),
      ]);

      // Should exclude prerelease by default
      var result = await mockGitHub.getLatestRelease('o', 'r', includePrerelease: false);
      expect(result?.tagName, equals('v1.0.0'));

      // Should include prerelease when requested
      result = await mockGitHub.getLatestRelease('o', 'r', includePrerelease: true);
      expect(result?.tagName, equals('v2.0.0-beta'));
    });
  });

  group('GitHubService parseReleases', () {
    test('skips non-object and wrong-typed entries but keeps valid ones', () {
      final body = jsonEncode([
        {
          'tag_name': 'v1.0.0',
          'name': 'Good Release',
          'prerelease': false,
          'draft': false,
          'assets': <Map<String, dynamic>>[],
        },
        'not-an-object',
        null,
        {
          // Wrong type: tag_name must be a String, not a number.
          'tag_name': 12345,
          'prerelease': false,
          'draft': false,
          'assets': <Map<String, dynamic>>[],
        },
      ]);

      final releases = GitHubService.parseReleases(body);

      expect(releases.length, equals(1));
      expect(releases.single.tagName, equals('v1.0.0'));
    });

    test('still throws when the response body is not a JSON list', () {
      expect(
        () => GitHubService.parseReleases('<html>GitHub error</html>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
