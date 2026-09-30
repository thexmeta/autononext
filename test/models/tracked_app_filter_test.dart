import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';

void main() {
  group('TrackedApp isValidFilterPattern', () {
    test('accepts null or empty', () {
      expect(TrackedApp.isValidFilterPattern(null), isTrue);
      expect(TrackedApp.isValidFilterPattern(''), isTrue);
    });

    test('accepts valid patterns with wildcard', () {
      expect(TrackedApp.isValidFilterPattern('*.deb'), isTrue);
      expect(TrackedApp.isValidFilterPattern('app*.deb'), isTrue);
      expect(TrackedApp.isValidFilterPattern('*.tar.gz'), isTrue);
    });

    test('accepts valid patterns with question mark', () {
      expect(TrackedApp.isValidFilterPattern('app?.deb'), isTrue);
      expect(TrackedApp.isValidFilterPattern('app??.deb'), isTrue);
    });

    test('accepts patterns with file extension', () {
      expect(TrackedApp.isValidFilterPattern('app.deb'), isTrue);
      expect(TrackedApp.isValidFilterPattern('MyApp.tar.gz'), isTrue);
    });

    test('accepts literal filenames', () {
      expect(TrackedApp.isValidFilterPattern('abc'), isTrue);
      expect(TrackedApp.isValidFilterPattern('123'), isTrue);
      expect(TrackedApp.isValidFilterPattern('appimage'), isTrue);
    });

    test('rejects whitespace-only patterns', () {
      expect(TrackedApp.isValidFilterPattern('   '), isFalse);
    });
  });

  group('TrackedApp isValidTagPrefix', () {
    test('accepts null or empty', () {
      expect(TrackedApp.isValidTagPrefix(null), isTrue);
      expect(TrackedApp.isValidTagPrefix(''), isTrue);
    });

    test('accepts alphanumeric prefixes', () {
      expect(TrackedApp.isValidTagPrefix('v'), isTrue);
      expect(TrackedApp.isValidTagPrefix('release'), isTrue);
      expect(TrackedApp.isValidTagPrefix('v1'), isTrue);
      expect(TrackedApp.isValidTagPrefix('app-v1'), isTrue);
    });

    test('accepts hyphens and underscores', () {
      expect(TrackedApp.isValidTagPrefix('app-v1'), isTrue);
      expect(TrackedApp.isValidTagPrefix('release_tag'), isTrue);
      expect(TrackedApp.isValidTagPrefix('my-prefix_test'), isTrue);
    });

    test('rejects special characters', () {
      expect(TrackedApp.isValidTagPrefix('v*'), isFalse);
      expect(TrackedApp.isValidTagPrefix('app@v1'), isFalse);
      expect(TrackedApp.isValidTagPrefix('release!'), isFalse);
      expect(TrackedApp.isValidTagPrefix('test#'), isFalse);
      expect(TrackedApp.isValidTagPrefix('app/v1'), isFalse);
    });
  });

  group('TrackedApp validateFilterSettings', () {
    test('returns null for valid settings', () {
      expect(
        TrackedApp.validateFilterSettings(
          assetFilterPattern: '*.deb',
          tagPrefix: 'v',
        ),
        isNull,
      );
    });

    test('returns null for literal filename pattern', () {
      expect(
        TrackedApp.validateFilterSettings(assetFilterPattern: 'appimage'),
        isNull,
      );
    });

    test('returns error for whitespace-only pattern', () {
      final result = TrackedApp.validateFilterSettings(
        assetFilterPattern: '   ',
      );
      expect(result, isNotNull);
      expect(result, contains('Invalid asset filter pattern'));
    });

    test('returns error for invalid tag prefix', () {
      final result = TrackedApp.validateFilterSettings(
        tagPrefix: 'v*',
      );
      expect(result, isNotNull);
      expect(result, contains('Invalid tag prefix'));
    });
  });

  group('TrackedApp serialization', () {
    test('toMap includes filter fields', () {
      final app = TrackedApp(
        id: 1,
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64', 'arm64'],
        includePrerelease: true,
      );

      final map = app.toMap();
      expect(map['asset_filter_pattern'], equals('*.deb'));
      expect(map['tag_prefix'], equals('v'));
      expect(map['architectures'], equals(['amd64', 'arm64']));
      expect(map['include_prerelease'], isTrue);
    });

    test('fromMap parses filter fields', () {
      final map = {
        'id': 1,
        'repo_owner': 'owner',
        'repo_name': 'repo',
        'display_name': 'Test App',
        'created_at': '2026-01-01T00:00:00Z',
        'asset_filter_pattern': '*.deb',
        'tag_prefix': 'v',
        'architectures': ['amd64', 'arm64'],
        'include_prerelease': true,
      };

      final app = TrackedApp.fromMap(map);
      expect(app.assetFilterPattern, equals('*.deb'));
      expect(app.tagPrefix, equals('v'));
      expect(app.architectures, equals(['amd64', 'arm64']));
      expect(app.includePrerelease, isTrue);
    });

    test('fromMap handles missing filter fields', () {
      final map = {
        'id': 1,
        'repo_owner': 'owner',
        'repo_name': 'repo',
        'display_name': 'Test App',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final app = TrackedApp.fromMap(map);
      expect(app.assetFilterPattern, isNull);
      expect(app.tagPrefix, isNull);
      expect(app.architectures, isEmpty);
      expect(app.includePrerelease, isFalse);
    });

    test('copyWith updates filter fields', () {
      final original = TrackedApp(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      final updated = original.copyWith(
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64'],
        includePrerelease: true,
      );

      expect(updated.assetFilterPattern, equals('*.deb'));
      expect(updated.tagPrefix, equals('v'));
      expect(updated.architectures, equals(['amd64']));
      expect(updated.includePrerelease, isTrue);

      expect(original.assetFilterPattern, isNull);
      expect(original.tagPrefix, isNull);
      expect(original.architectures, isEmpty);
      expect(original.includePrerelease, isFalse);
    });
  });

  group('TrackedApp constructor', () {
    test('initializes architectures to empty list if null', () {
      final app = TrackedApp(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        architectures: null,
      );
      expect(app.architectures, isEmpty);
    });

    test('initializes includePrerelease to false by default', () {
      final app = TrackedApp(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );
      expect(app.includePrerelease, isFalse);
    });
  });
}
