import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_deb_package.dart';

/// These tests pin down [TrackedDebPackage.hasUpdate] version-ordering
/// semantics. They deliberately encode *why* each case matters (numeric vs
/// lexicographic ordering, `v` prefixes, Debian revisions) so a regression in
/// the shared comparison logic fails loudly instead of silently.
void main() {
  TrackedDebPackage pkg({String? installed, String? latest}) {
    return TrackedDebPackage(
      name: 'app',
      packageUrl: 'https://example.com/app.deb',
      installedVersion: installed,
      latestVersion: latest,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );
  }

  group('TrackedDebPackage.hasUpdate', () {
    test('detects 1.9 -> 1.10 as newer (numeric, not lexicographic)', () {
      // Lexicographic string compare would rank "1.10" < "1.9", so this is the
      // canonical multi-digit regression case.
      expect(pkg(installed: '1.9', latest: '1.10').hasUpdate, isTrue);
    });

    test('is false for 1.10 -> 1.9 (installed version is newer)', () {
      expect(pkg(installed: '1.10', latest: '1.9').hasUpdate, isFalse);
    });

    test('ignores a leading v so v1.0.0 is not newer than 1.0.0', () {
      expect(pkg(installed: '1.0.0', latest: 'v1.0.0').hasUpdate, isFalse);
      expect(pkg(installed: 'v1.0.0', latest: '1.0.0').hasUpdate, isFalse);
    });

    test('detects a Debian revision bump (1.0.0-1 -> 1.0.0-2)', () {
      expect(pkg(installed: '1.0.0-1', latest: '1.0.0-2').hasUpdate, isTrue);
    });

    test('is false for a Debian revision downgrade (1.0.0-2 -> 1.0.0-1)', () {
      expect(pkg(installed: '1.0.0-2', latest: '1.0.0-1').hasUpdate, isFalse);
    });

    test('returns false when versions are equal', () {
      expect(pkg(installed: '1.0.0', latest: '1.0.0').hasUpdate, isFalse);
    });

    test('returns false when installedVersion or latestVersion is null', () {
      expect(pkg(installed: null, latest: '1.0.0').hasUpdate, isFalse);
      expect(pkg(installed: '1.0.0', latest: null).hasUpdate, isFalse);
    });

    test('treats a release as newer than its prerelease', () {
      expect(pkg(installed: '1.0.0-alpha', latest: '1.0.0').hasUpdate, isTrue);
      expect(pkg(installed: '1.0.0', latest: '1.0.0-alpha').hasUpdate, isFalse);
    });
  });
}
