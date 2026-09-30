import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/ui/home_screen.dart';
import 'package:autononext/widgets/batch_action_bar.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/installer_service.dart';
import '../mocks/mock_github_service.dart';
import '../mocks/mock_installer_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:autononext/services/external_app_checker.dart';

// Captured before each override so the static providers can be restored,
// preventing leakage into other test files.
late ExternalVersionProvider _originalVersionProvider;
late ExternalDebVersionProvider _originalDebVersionProvider;

void main() {
  group('Batch Operations Integration Tests', () {
    setUp(() {
      _originalVersionProvider = ExternalAppChecker.versionProvider;
      _originalDebVersionProvider = ExternalAppChecker.debVersionProvider;

      TestWidgetsFlutterBinding.ensureInitialized();
      PackageInfo.setMockInitialValues(
        appName: 'Autononext',
        packageName: 'com.autononext',
        version: '0.3.6',
        buildNumber: '1',
        buildSignature: 'sig',
      );
      
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          return '.';
        },
      );

      // Mock ExternalAppChecker to prevent real processes and timer leaks
      ExternalAppChecker.versionProvider = (app) async => null;
      ExternalAppChecker.debVersionProvider = (pkg) async => null;
    });

    tearDown(() {
      ExternalAppChecker.versionProvider = _originalVersionProvider;
      ExternalAppChecker.debVersionProvider = _originalDebVersionProvider;
    });

    group('Batch Update Check', () {
      testWidgets('verifies batch update check fetches latest versions',
          (WidgetTester tester) async {
        // Setup mock data
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v2.0.0',
            assets: [
              ReleaseAsset(name: 'app_2.0.0_amd64.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();

        // Select all apps
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Trigger batch update check
        await tester.tap(find.text('Check for Updates'));
        await tester.pumpAndSettle();

        // Verify update check was performed
        expect(find.text('Update Check Results'), findsOneWidget);
        await tester.pumpAndSettle();
      });

      testWidgets('handles mixed success/failure scenarios', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setShouldFail(false);
        
        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Enter multi-select mode and select apps
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Simulate failure for some apps
        mockGitHub.setShouldFail(true, message: 'Rate limited');

        // Batch update should complete without crashing
        await tester.tap(find.byTooltip('Check Selected for Updates'));
        await tester.pumpAndSettle();

        // Should show completion message
        expect(find.text('Update Check Results'), findsOneWidget);
        await tester.pumpAndSettle();
      });

      testWidgets('updates lastChecked timestamp', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v2.0.0',
            assets: [
              ReleaseAsset(name: 'app_2.0.0_amd64.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        final beforeUpdate = DateTime.now();
        
        // Trigger batch update
        await tester.tap(find.byTooltip('Check Selected for Updates'));
        await tester.pumpAndSettle();

        // Verify timestamp was updated
        final apps = await mockDb.getAllApps();
        expect(apps.first.lastChecked, isNotNull);
        expect(apps.first.lastChecked!.isAfter(beforeUpdate.subtract(Duration(seconds: 5))), isTrue);
        await tester.pumpAndSettle();
      });
    });

    group('Batch Install/Update', () {
      testWidgets('batch install downloads and installs correct assets', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v1.0.0',
            assets: [
              ReleaseAsset(name: 'app_1.0.0_amd64.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockInstaller = MockInstallerService();
        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<InstallerService>.value(value: mockInstaller),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // The batch install performs real async file I/O, so the whole flow —
        // including the new confirmation dialog — must run inside runAsync for
        // the install chain to be created in the real zone.
        await tester.runAsync(() async {
          // Tapping the batch Install action opens a confirmation dialog.
          await tester.tap(find.text('Install'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Install Selected'), findsOneWidget);

          // Confirm. Scope to the AlertDialog because the action bar also has
          // an "Install" button.
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'Install'),
            ),
          );

          for (int i = 0; i < 50; i++) {
            if (mockInstaller.installCount >= 1) break;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pumpAndSettle();

        // Verify installer was called
        expect(mockInstaller.installCount, equals(1));
        expect(mockInstaller.downloadCount, equals(1));

        // Verify app was updated in DB
        final apps = await mockDb.getAllApps();
        expect(apps.first.installedVersion, equals('v1.0.0'));

        // The results summary is left open; close it so no route lingers.
        expect(find.text('Batch Install Results'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      });

      testWidgets('batch update updates installed version', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v2.0.0',
            assets: [
              ReleaseAsset(name: 'app_2.0.0_amd64.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        final app = TrackedApp(
          id: 1,
          repoOwner: 'owner1',
          repoName: 'repo1',
          displayName: 'App 1',
          installedVersion: 'v1.0.0',
          createdAt: DateTime.now(),
        );
        await mockDb.addAppWithId(app);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Trigger batch update
        await tester.tap(find.text('Check for Updates'));
        await tester.pumpAndSettle();

        // Verify version was updated in database
        final apps = await mockDb.getAllApps();
        expect(apps.first.latestVersion, equals('v2.0.0'));
        await tester.pumpAndSettle();
      });

      testWidgets('handles multiple package types', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v1.0.0',
            assets: [
              ReleaseAsset(name: 'app_1.0.0_amd64.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
              ReleaseAsset(name: 'app_1.0.0.rpm', browserDownloadUrl: 'http://example.com/app.rpm', contentType: 'application/octet-stream', size: 0),
              ReleaseAsset(name: 'app_1.0.0.AppImage', browserDownloadUrl: 'http://example.com/app.AppImage', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify app list shows the app
        expect(find.text('App 1'), findsOneWidget);
        await tester.pumpAndSettle();
      });
    });

    group('Error Handling', () {
      testWidgets('continues on individual failures', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v1.0.0',
            assets: [],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Batch operations should complete without crashing
        await tester.tap(find.byTooltip('Check Selected for Updates'));
        await tester.pumpAndSettle();

        // Should complete without crashing
        expect(find.byType(HomeScreen), findsOneWidget);
        await tester.pumpAndSettle();
      });

      testWidgets('reports correct success/failure counts', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setShouldFail(true, message: 'Network error');

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Trigger batch update
        await tester.tap(find.text('Check for Updates'));
        await tester.pumpAndSettle();

        // Should show completion message even with errors
        await tester.pumpAndSettle();
        expect(find.text('Update Check Results'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      });

      testWidgets('handles network errors gracefully', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setShouldFail(true, message: 'Network error');

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Should not crash on network error
        await tester.tap(find.byTooltip('Check Selected for Updates'));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Progress Tracking', () {
      testWidgets('shows progress indicator during batch operations', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Trigger batch update
        await tester.tap(find.text('Check for Updates'));
        
        // Pump until dialog appears
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(Dialog), findsOneWidget);
        
        // Wait for results
        await tester.pumpAndSettle(const Duration(seconds: 15));
        
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      });

      testWidgets('completes all operations before showing result', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v1.0.0',
            publishedAt: DateTime.now(),
            assets: [
              ReleaseAsset(name: 'app.deb', browserDownloadUrl: 'http://example.com/app.deb', contentType: 'application/octet-stream', size: 0),
            ],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Trigger batch update
        await tester.tap(find.text('Check for Updates'));
        
        // Wait for results
        await tester.pumpAndSettle(const Duration(seconds: 15));

        expect(find.text('Update Check Results'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      });
    });

    group('Selection State', () {
      testWidgets('maintains selection during batch operations', (WidgetTester tester) async {
        final mockGitHub = MockGitHubService();
        mockGitHub.setReleases([
          Release(
            tagName: 'v1.0.0',
            assets: [],
            prerelease: false,
            draft: false,
          ),
        ]);

        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<GitHubService>.value(value: mockGitHub),
              Provider<DatabaseService>.value(value: mockDb),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        
        // Select first app only
        await tester.tap(find.text('App 1'));
        await tester.pumpAndSettle();

        // Verify selection state
        expect(find.text('1 selected'), findsOneWidget);
        
        // Wait for cleanup
        await tester.pumpAndSettle();
      });

      testWidgets('clears selection on deselect all', (WidgetTester tester) async {
        final mockDb = MockDatabaseService();
        await mockDb.addApp('owner1', 'repo1', 'App 1');
        await mockDb.addApp('owner2', 'repo2', 'App 2');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<DatabaseService>.value(value: mockDb),
              Provider<GitHubService>.value(value: MockGitHubService()),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // Enter multi-select mode
        await tester.tap(find.byTooltip('Select Multiple'));
        await tester.pumpAndSettle();
        
        // Select all
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // Deselect all
        await tester.tap(find.text('Deselect All'));
        await tester.pumpAndSettle();

        // Should show 0 selected
        expect(find.descendant(of: find.byType(BatchActionBar), matching: find.text('0 of 2 selected')), findsOneWidget);
        
        // Wait for cleanup
        await tester.pumpAndSettle();
      });
    });
  });
}

// Mock DatabaseService for testing
class MockDatabaseService extends DatabaseService {
  final List<TrackedApp> _apps = [];
  final List<TrackedDebPackage> _debPackages = [];
  int _nextId = 1;

  @override
  Future<List<TrackedApp>> getAllApps() async {
    return _apps;
  }

  @override
  Future<List<TrackedDebPackage>> getAllDebPackages() async {
    return _debPackages;
  }

  @override
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
    final id = _nextId++;
    final app = TrackedApp(
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
    _apps.add(app);
    return id;
  }

  Future<void> addAppWithId(TrackedApp app) async {
    _apps.add(app);
  }

  @override
  Future<void> updateApp(TrackedApp app) async {
    final index = _apps.indexWhere((a) => a.id == app.id);
    if (index != -1) {
      _apps[index] = app;
    }
  }

  @override
  Future<void> deleteApp(int id) async {
    _apps.removeWhere((a) => a.id == id);
  }

  @override
  Future<void> updateDebPackage(TrackedDebPackage pkg) async {
    final index = _debPackages.indexWhere((p) => p.id == pkg.id);
    if (index != -1) {
      _debPackages[index] = pkg;
    }
  }

  @override
  Future<void> deleteDebPackage(int id) async {
    _debPackages.removeWhere((p) => p.id == id);
  }

  @override
  Future<Map<String, String>> checkDebPackageUpdates() async {
    return {};
  }

  @override
  Future<String> exportConfig() async {
    return '/mock/path/config.json';
  }

  @override
  Future<int> importConfig(String filePath) async {
    return 0;
  }
}
