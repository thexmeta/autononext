import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/ui/home_screen.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/settings_service.dart';
import '../mock_services.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/services/external_app_checker.dart';

class MockDatabaseService extends DatabaseService {
  @override
  Future<List<TrackedApp>> getAllApps() async {
    return [
      TrackedApp(
        id: 1,
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Test App',
        installedVersion: '1.0.0',
        latestVersion: '1.0.1',
        createdAt: DateTime.now(),
      ),
    ];
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
    return 1;
  }

  @override
  Future<List<TrackedDebPackage>> getAllDebPackages() async => [];

  @override
  Future<void> updateApp(TrackedApp app) async {}
}

class MockGitHubService extends GitHubService {
  @override
  Future<Map<String, dynamic>?> getLatestReleaseWithPackageInfo(
    String owner,
    String repo, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures = const [],
    bool includePrerelease = false,
  }) async => null;
}
class MockInstallerService extends InstallerService {}

// Captured before each override so the static providers can be restored,
// preventing leakage into other test files.
late ExternalVersionProvider _originalVersionProvider;
late ExternalDebVersionProvider _originalDebVersionProvider;

void main() {
  setUp(() {
    _originalVersionProvider = ExternalAppChecker.versionProvider;
    _originalDebVersionProvider = ExternalAppChecker.debVersionProvider;
    ExternalAppChecker.versionProvider = (_) async => null;
    ExternalAppChecker.debVersionProvider = (_) async => null;
  });

  tearDown(() {
    ExternalAppChecker.versionProvider = _originalVersionProvider;
    ExternalAppChecker.debVersionProvider = _originalDebVersionProvider;
  });

  testWidgets('HomeScreen shows apps', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>(create: (_) => MockDatabaseService()),
          Provider<GitHubService>(create: (_) => MockGitHubService()),
          Provider<InstallerService>(create: (_) => MockInstallerService()),
          Provider<SettingsService>(create: (_) => MockSettingsService()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Initial load
    await tester.pump(); 
    // Wait for future to complete
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Test App'), findsOneWidget);
    expect(find.text('owner/repo'), findsOneWidget);
    expect(find.byIcon(Icons.system_update), findsOneWidget);
  });

  testWidgets('Add App dialog opens', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>(create: (_) => MockDatabaseService()),
          Provider<GitHubService>(create: (_) => MockGitHubService()),
          Provider<InstallerService>(create: (_) => MockInstallerService()),
          Provider<SettingsService>(create: (_) => MockSettingsService()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Add App'), findsOneWidget);
    expect(find.text('GitHub URL'), findsOneWidget);
  });
}
