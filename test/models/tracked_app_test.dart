import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';

void main() {
  TrackedApp app({
    String? installed,
    String? latest,
  }) {
    return TrackedApp(
      repoOwner: 'owner',
      repoName: 'repo',
      displayName: 'App',
      installedVersion: installed,
      latestVersion: latest,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );
  }

  group('TrackedApp', () {
    test('hasUpdate returns true when latest version is newer', () {
      expect(app(installed: '1.0.0', latest: '1.0.1').hasUpdate, isTrue);
    });

    test('hasUpdate returns false when versions are equal', () {
      expect(app(installed: '1.0.0', latest: '1.0.0').hasUpdate, isFalse);
    });

    test('hasUpdate returns false when installed version is newer', () {
      expect(app(installed: '1.0.1', latest: '1.0.0').hasUpdate, isFalse);
    });

    test('hasUpdate handles v-prefix correctly', () {
      expect(app(installed: 'v1.0.0', latest: '1.0.1').hasUpdate, isTrue);
      expect(app(installed: 'v1.0.0', latest: 'v1.0.1').hasUpdate, isTrue);
      expect(app(installed: '1.0.0', latest: 'v1.0.1').hasUpdate, isTrue);
    });

    test('hasUpdate handles uppercase V-prefix', () {
      expect(app(installed: 'V1.0.0', latest: 'V1.0.1').hasUpdate, isTrue);
    });

    test('hasUpdate compares major/minor/patch numerically', () {
      expect(app(installed: '1.0.0', latest: '2.0.0').hasUpdate, isTrue);
      expect(app(installed: '1.0.0', latest: '1.1.0').hasUpdate, isTrue);
      expect(app(installed: '1.0.2', latest: '1.0.10').hasUpdate, isTrue);
    });

    test('hasUpdate returns false if installedVersion is null', () {
      expect(app(installed: null, latest: '1.0.0').hasUpdate, isFalse);
    });

    test('hasUpdate returns false if latestVersion is null', () {
      expect(app(installed: '1.0.0', latest: null).hasUpdate, isFalse);
    });

    test('hasUpdate treats a release as newer than a prerelease', () {
      expect(app(installed: '1.0.0-alpha', latest: '1.0.0').hasUpdate, isTrue);
    });

    test('isInstalled reflects whether installedVersion is set', () {
      expect(app(installed: '1.0.0', latest: '1.0.0').isInstalled, isTrue);
      expect(app(installed: null, latest: '1.0.0').isInstalled, isFalse);
    });

    test('repoUrl is correct', () {
      final tracked = TrackedApp(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'App',
        createdAt: DateTime.now(),
      );

      expect(tracked.repoUrl, 'https://github.com/owner/repo');
    });

    test('hasUpdate is false when a Debian revision is compared against the same upstream version', () {
      expect(app(installed: '2.11.10-1', latest: 'v2.11.10').hasUpdate, isFalse);
    });

    test('REVERSED: hasUpdate is true for an npm release tag because it embeds a real version', () {
      // This previously asserted `false`, which hid a genuine update: the tag
      // `@biomejs/biome@2.5.15` carries the version 2.5.15, so it compares
      // cleanly against the installed 2.5.10 once the npm prefix is stripped.
      // The raw string is still not version-shaped, so the check must run on
      // the normalised value.
      expect(app(installed: '2.5.10', latest: '@biomejs/biome@2.5.15').hasUpdate, isTrue);
      // A latest value with no version in it at all is still rejected.
      expect(app(installed: '2.5.10', latest: 'multiplatform#1').hasUpdate, isFalse);
    });

    test('REGRESSION: hasUpdate stays true for a genuine minor bump', () {
      expect(app(installed: '0.6.0', latest: 'v0.7.3').hasUpdate, isTrue);
    });

    test('REGRESSION: hasUpdate stays true for a genuine patch bump', () {
      expect(app(installed: '0.0.80', latest: '0.0.84').hasUpdate, isTrue);
    });

    test('REGRESSION: hasUpdate is true for a prefixed release tag, so a real update is not hidden', () {
      // Real case: bitwarden/clients publishes per-client tags such as
      // `desktop-v2026.9.0`, so the stored latest carries a `desktop-` prefix.
      // That was rejected as "not a version" AND parsed as 0.0.0, so the row
      // never highlighted even though 2026.9.0 was available.
      expect(app(installed: '2026.8.0', latest: 'desktop-v2026.9.0').hasUpdate, isTrue);
      expect(isNewerVersion('desktop-v2026.9.0', '2026.8.0'), isTrue);
      expect(isNewerVersion('2026.8.0', 'desktop-v2026.9.0'), isFalse);
    });

    test('REGRESSION: hasUpdate is true for a prefixed tag that also carries a prerelease suffix', () {
      // Real case: refactoringhq/tolaria tags releases as
      // `alpha-v2026.9.25-alpha.0006`.
      expect(
        app(installed: '2026.5.2', latest: 'alpha-v2026.9.25-alpha.0006').hasUpdate,
        isTrue,
      );
    });
  });

  group('normalizeVersion', () {
    test('drops an npm specifier prefix so a dist-tag compares as its bare version', () {
      expect(normalizeVersion('@biomejs/biome@2.5.14'), '2.5.14');
      expect(normalizeVersion('biome@2.5.14'), '2.5.14');
    });
  });

  group('looksLikeVersion', () {
    test('accepts real version shapes so genuine upgrades still compare', () {
      expect(looksLikeVersion('1'), isTrue);
      expect(looksLikeVersion('2.5.14'), isTrue);
      expect(looksLikeVersion('v2.11.10'), isTrue);
      expect(looksLikeVersion('2.11.10-1'), isTrue);
    });

    test('accepts a prefixed tag whose version part is dotted', () {
      // `desktop-v2026.9.0` is a version tag with a product prefix, not a label.
      expect(looksLikeVersion('desktop-v2026.9.0'), isTrue);
      expect(looksLikeVersion('cli-v2026.9.0'), isTrue);
      expect(looksLikeVersion('desktop-2026.9.0'), isTrue);
      // …including when it carries a prerelease suffix.
      expect(looksLikeVersion('alpha-v2026.9.25-alpha.0006'), isTrue);
    });

    test('rejects non-version labels so they cannot masquerade as an upgrade', () {
      expect(looksLikeVersion('@biomejs/biome@2.5.14'), isFalse);
      expect(looksLikeVersion('multiplatform#1'), isFalse);
      expect(looksLikeVersion('download_cli.sh'), isFalse);
      expect(looksLikeVersion('latest.json'), isFalse);
      // A prefix alone is not enough: the version part must be dotted, so a
      // bare-number tag with a junk separator still fails.
      expect(looksLikeVersion('release-build'), isFalse);
    });
  });

  group('isNewerVersion Debian revision semantics', () {
    test('treats a lone Debian revision as the same upstream version, not a prerelease', () {
      expect(isNewerVersion('2.11.10', '2.11.10-1'), isFalse);
      expect(isNewerVersion('2.11.10-1', '2.11.10'), isFalse);
    });
  });
}
