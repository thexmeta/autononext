import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/app_config.dart';
import 'package:autononext/models/install_type.dart';

void main() {
  group('TrackedAppData', () {
    test('constructor initializes with defaults', () {
      final data = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
      );

      expect(data.repoOwner, equals('owner'));
      expect(data.repoName, equals('repo'));
      expect(data.displayName, equals('Test App'));
      expect(data.assetFilterPattern, isNull);
      expect(data.tagPrefix, isNull);
      expect(data.architectures, isEmpty);
      expect(data.includePrerelease, isFalse);
    });

    test('constructor accepts optional fields', () {
      final data = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64', 'arm64'],
        includePrerelease: true,
      );

      expect(data.assetFilterPattern, equals('*.deb'));
      expect(data.tagPrefix, equals('v'));
      expect(data.architectures, equals(['amd64', 'arm64']));
      expect(data.includePrerelease, isTrue);
    });

    test('toMap serializes correctly', () {
      final data = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64'],
        includePrerelease: true,
      );

      final map = data.toMap();
      expect(map['repoOwner'], equals('owner'));
      expect(map['repoName'], equals('repo'));
      expect(map['displayName'], equals('Test App'));
      expect(map['assetFilterPattern'], equals('*.deb'));
      expect(map['tagPrefix'], equals('v'));
      expect(map['architectures'], equals(['amd64']));
      expect(map['includePrerelease'], isTrue);
    });

    test('fromMap deserializes correctly', () {
      final map = {
        'repoOwner': 'owner',
        'repoName': 'repo',
        'displayName': 'Test App',
        'assetFilterPattern': '*.deb',
        'tagPrefix': 'v',
        'architectures': ['amd64', 'arm64'],
        'includePrerelease': true,
      };

      final data = TrackedAppData.fromMap(map);
      expect(data.repoOwner, equals('owner'));
      expect(data.repoName, equals('repo'));
      expect(data.displayName, equals('Test App'));
      expect(data.assetFilterPattern, equals('*.deb'));
      expect(data.tagPrefix, equals('v'));
      expect(data.architectures, equals(['amd64', 'arm64']));
      expect(data.includePrerelease, isTrue);
    });

    test('fromMap handles missing optional fields', () {
      final map = {
        'repoOwner': 'owner',
        'repoName': 'repo',
        'displayName': 'Test App',
      };

      final data = TrackedAppData.fromMap(map);
      expect(data.assetFilterPattern, isNull);
      expect(data.tagPrefix, isNull);
      expect(data.architectures, isEmpty);
      expect(data.includePrerelease, isFalse);
    });

    test('toTrackedApp creates TrackedApp with correct fields', () {
      final lastChecked = DateTime.parse('2026-02-03T04:05:06Z');
      final latestReleaseDate = DateTime.parse('2026-02-01T00:00:00Z');
      final data = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64'],
        includePrerelease: true,
        installedVersion: '1.2.3',
        latestVersion: '1.3.0',
        installType: InstallType.deb,
        launchCommand: '/usr/bin/testapp',
        packageName: 'test-app',
        lastChecked: lastChecked,
        latestReleaseDate: latestReleaseDate,
        fetchedPackage: 'testapp_1.3.0_amd64.deb',
      );

      final app = data.toTrackedApp(1);
      expect(app.id, equals(1));
      expect(app.repoOwner, equals('owner'));
      expect(app.repoName, equals('repo'));
      expect(app.displayName, equals('Test App'));
      expect(app.assetFilterPattern, equals('*.deb'));
      expect(app.tagPrefix, equals('v'));
      expect(app.architectures, equals(['amd64']));
      expect(app.includePrerelease, isTrue);
      // Install state must survive the export/import round trip.
      expect(app.installedVersion, equals('1.2.3'));
      expect(app.latestVersion, equals('1.3.0'));
      expect(app.installType, equals(InstallType.deb));
      expect(app.launchCommand, equals('/usr/bin/testapp'));
      expect(app.packageName, equals('test-app'));
      expect(app.lastChecked, equals(lastChecked));
      expect(app.latestReleaseDate, equals(latestReleaseDate));
      expect(app.fetchedPackage, equals('testapp_1.3.0_amd64.deb'));
    });

    test('toTrackedApp uses provided createdAt', () {
      final data = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
      );

      final createdAt = DateTime.parse('2026-01-01T00:00:00Z');
      final app = data.toTrackedApp(1, createdAt: createdAt);
      expect(app.createdAt, equals(createdAt));
    });

    test('round-trip serialization', () {
      final lastChecked = DateTime.parse('2026-02-03T04:05:06Z');
      final latestReleaseDate = DateTime.parse('2026-02-01T00:00:00Z');
      final original = TrackedAppData(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        assetFilterPattern: '*.deb',
        tagPrefix: 'v',
        architectures: ['amd64', 'arm64'],
        includePrerelease: true,
        installedVersion: '1.2.3',
        latestVersion: '1.3.0',
        installType: InstallType.appImage,
        launchCommand: 'testapp',
        packageName: 'test-app',
        lastChecked: lastChecked,
        latestReleaseDate: latestReleaseDate,
        fetchedPackage: 'testapp_1.3.0_amd64.deb',
      );

      final map = original.toMap();
      final deserialized = TrackedAppData.fromMap(map);

      expect(deserialized.repoOwner, equals(original.repoOwner));
      expect(deserialized.repoName, equals(original.repoName));
      expect(deserialized.displayName, equals(original.displayName));
      expect(deserialized.assetFilterPattern, equals(original.assetFilterPattern));
      expect(deserialized.tagPrefix, equals(original.tagPrefix));
      expect(deserialized.architectures, equals(original.architectures));
      expect(deserialized.includePrerelease, equals(original.includePrerelease));
      expect(deserialized.installedVersion, equals('1.2.3'));
      expect(deserialized.latestVersion, equals('1.3.0'));
      expect(deserialized.installType, equals(InstallType.appImage));
      expect(deserialized.launchCommand, equals('testapp'));
      expect(deserialized.packageName, equals('test-app'));
      expect(deserialized.lastChecked, equals(lastChecked));
      expect(deserialized.latestReleaseDate, equals(latestReleaseDate));
      expect(deserialized.fetchedPackage, equals('testapp_1.3.0_amd64.deb'));
    });
  });

  group('AppConfig', () {
    test('constructor initializes correctly', () {
      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.parse('2026-01-01T00:00:00Z'),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: [],
      );

      expect(config.schemaVersion, equals('1.0'));
      expect(config.exportedAt, equals(DateTime.parse('2026-01-01T00:00:00Z')));
      expect(config.appName, equals('Autononext'));
      expect(config.appVersion, equals('0.3.4'));
      expect(config.apps, isEmpty);
    });

    test('toJson serializes correctly', () {
      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.parse('2026-01-01T00:00:00Z'),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: [
          TrackedAppData(
            repoOwner: 'owner',
            repoName: 'repo',
            displayName: 'Test App',
          ),
        ],
      );

      final json = config.toJson();
      expect(json['schemaVersion'], equals('1.0'));
      expect(json['exportedAt'], equals('2026-01-01T00:00:00.000Z'));
      expect(json['appName'], equals('Autononext'));
      expect(json['appVersion'], equals('0.3.4'));
      expect(json['apps'], isA<List>());
      expect(json['apps'].length, equals(1));
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'schemaVersion': '1.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'appName': 'Autononext',
        'appVersion': '0.3.4',
        'apps': [
          {
            'repoOwner': 'owner',
            'repoName': 'repo',
            'displayName': 'Test App',
          },
        ],
      };

      final config = AppConfig.fromJson(json);
      expect(config.schemaVersion, equals('1.0'));
      expect(config.exportedAt, equals(DateTime.parse('2026-01-01T00:00:00.000Z')));
      expect(config.appName, equals('Autononext'));
      expect(config.appVersion, equals('0.3.4'));
      expect(config.apps.length, equals(1));
      expect(config.apps.first.repoOwner, equals('owner'));
      expect(config.apps.first.repoName, equals('repo'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'schemaVersion': '1.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'apps': [],
      };

      final config = AppConfig.fromJson(json);
      expect(config.schemaVersion, equals('1.0'));
      expect(config.appName, isNull);
      expect(config.appVersion, isNull);
      expect(config.apps, isEmpty);
    });

    test('round-trip serialization', () {
      final lastChecked = DateTime.parse('2026-02-03T04:05:06Z');
      final original = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.parse('2026-01-01T00:00:00Z'),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: [
          TrackedAppData(
            repoOwner: 'owner',
            repoName: 'repo',
            displayName: 'Test App',
            assetFilterPattern: '*.deb',
            tagPrefix: 'v',
            architectures: ['amd64'],
            includePrerelease: true,
            installedVersion: '1.2.3',
            latestVersion: '1.3.0',
            installType: InstallType.deb,
            launchCommand: '/usr/bin/testapp',
            packageName: 'test-app',
            lastChecked: lastChecked,
            latestReleaseDate: DateTime.parse('2026-02-01T00:00:00Z'),
            fetchedPackage: 'testapp_1.3.0_amd64.deb',
          ),
        ],
      );

      final json = original.toJson();
      final deserialized = AppConfig.fromJson(json);

      expect(deserialized.schemaVersion, equals(original.schemaVersion));
      expect(deserialized.exportedAt, equals(original.exportedAt));
      expect(deserialized.appName, equals(original.appName));
      expect(deserialized.appVersion, equals(original.appVersion));
      expect(deserialized.apps.length, equals(original.apps.length));
      expect(deserialized.apps.first.repoOwner, equals(original.apps.first.repoOwner));
      expect(deserialized.apps.first.displayName, equals(original.apps.first.displayName));
      // Install state must survive the config-level round trip.
      expect(deserialized.apps.first.installedVersion, equals('1.2.3'));
      expect(deserialized.apps.first.latestVersion, equals('1.3.0'));
      expect(deserialized.apps.first.installType, equals(InstallType.deb));
      expect(deserialized.apps.first.launchCommand, equals('/usr/bin/testapp'));
      expect(deserialized.apps.first.packageName, equals('test-app'));
      expect(deserialized.apps.first.lastChecked, equals(lastChecked));
      expect(
        deserialized.apps.first.latestReleaseDate,
        equals(DateTime.parse('2026-02-01T00:00:00Z')),
      );
      expect(
        deserialized.apps.first.fetchedPackage,
        equals('testapp_1.3.0_amd64.deb'),
      );
    });
  });

  group('AppConfig export/import scenarios', () {
    test('empty config exports correctly', () {
      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.now(),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: [],
      );

      final json = config.toJson();
      expect(json['apps'], isA<List>());
      expect(json['apps'].isEmpty, isTrue);
    });

    test('config with multiple apps', () {
      final apps = List.generate(
        5,
        (index) => TrackedAppData(
          repoOwner: 'owner$index',
          repoName: 'repo$index',
          displayName: 'App $index',
        ),
      );

      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.now(),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: apps,
      );

      final json = config.toJson();
      expect(json['apps'].length, equals(5));

      final deserialized = AppConfig.fromJson(json);
      expect(deserialized.apps.length, equals(5));
    });

    test('config preserves filter settings', () {
      final config = AppConfig(
        schemaVersion: '1.0',
        exportedAt: DateTime.now(),
        appName: 'Autononext',
        appVersion: '0.3.4',
        apps: [
          TrackedAppData(
            repoOwner: 'owner',
            repoName: 'repo',
            displayName: 'Test App',
            assetFilterPattern: '*.deb',
            tagPrefix: 'v',
            architectures: ['amd64', 'arm64'],
            includePrerelease: true,
          ),
        ],
      );

      final json = config.toJson();
      final deserialized = AppConfig.fromJson(json);

      expect(deserialized.apps.first.assetFilterPattern, equals('*.deb'));
      expect(deserialized.apps.first.tagPrefix, equals('v'));
      expect(deserialized.apps.first.architectures, equals(['amd64', 'arm64']));
      expect(deserialized.apps.first.includePrerelease, isTrue);
    });
  });
}
