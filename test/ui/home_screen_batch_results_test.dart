import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/external_app_checker.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/services/settings_service.dart';
import 'package:autononext/ui/home_screen.dart';
import '../mock_services.dart';
import '../mocks/mock_installer_service.dart';

class _OneAppDatabase extends DatabaseService {
  @override
  Future<List<TrackedApp>> getAllApps() async => [
        TrackedApp(
          id: 1,
          repoOwner: 'ninepointlabs',
          repoName: 'autononext',
          displayName: 'Test App',
          installedVersion: '1.0.0',
          latestVersion: '1.0.1',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  Future<List<TrackedDebPackage>> getAllDebPackages() async => [];

  @override
  Future<void> updateApp(TrackedApp app) async {}

  @override
  Future<Map<String, String>> checkDebPackageUpdates() async => {};
}

/// Every update check fails, so the batch summary has exactly one failure.
class _FailingGitHubService extends GitHubService {
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

late ExternalVersionProvider _originalVersionProvider;
late ExternalDebVersionProvider _originalDebVersionProvider;

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => _OneAppDatabase()),
        Provider<GitHubService>(create: (_) => _FailingGitHubService()),
        Provider<InstallerService>(create: (_) => MockInstallerService()),
        Provider<SettingsService>(create: (_) => MockSettingsService()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

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

  testWidgets('batch update summary names the app that failed', (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test App'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for Updates'));
    // The progress dialog refreshes from a periodic Timer, so `pumpAndSettle`
    // would never return while it is open.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('1 failed')),
      findsOneWidget,
    );
    // A failed result used to carry an empty app name, so the summary could not
    // say which app failed.
    expect(
      find.descendant(of: dialog, matching: find.text('Test App')),
      findsOneWidget,
    );
  });
}
