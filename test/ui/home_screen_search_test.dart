import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/release.dart';
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

/// Three apps, so a filtered row never sits at the same position as the row it
/// must act on. Repo names deliberately differ from display names so a match on
/// either can be told apart.
class _ThreeAppsDatabase extends DatabaseService {
  @override
  Future<List<TrackedApp>> getAllApps() async => [
    TrackedApp(
      id: 1,
      repoOwner: 'owner',
      repoName: 'alpha-src',
      displayName: 'App Alpha',
      installedVersion: '1.0.0',
      createdAt: DateTime(2026, 1, 1),
    ),
    TrackedApp(
      id: 2,
      repoOwner: 'owner',
      repoName: 'beta-src',
      displayName: 'App Beta',
      installedVersion: '1.0.0',
      createdAt: DateTime(2026, 1, 1),
    ),
    TrackedApp(
      id: 3,
      repoOwner: 'owner',
      repoName: 'gamma-src',
      displayName: 'App Gamma',
      installedVersion: '1.0.0',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  @override
  Future<List<TrackedDebPackage>> getAllDebPackages() async => [];

  @override
  Future<void> updateApp(TrackedApp app) async {}

  @override
  Future<void> deleteApp(int id) async {}

  @override
  Future<void> deleteDebPackage(int id) async {}

  @override
  Future<Map<String, String>> checkDebPackageUpdates() async => {};
}

class _NullGitHubService extends GitHubService {
  /// Every network path is cut here. Overriding only
  /// [getLatestReleaseWithPackageInfo] is not enough: the details sheet calls
  /// [getLatestRelease], which falls through to the real [getReleases] and
  /// leaves its HTTP timeout Timer pending at teardown.
  @override
  Future<List<Release>> getReleases(
    String owner,
    String repo, {
    int? perPage,
  }) async => [];

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

Future<void> _pumpHome(WidgetTester tester, DatabaseService db) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: db),
        Provider<GitHubService>(create: (_) => _NullGitHubService()),
        Provider<InstallerService>(create: (_) => MockInstallerService()),
        Provider<SettingsService>(create: (_) => MockSettingsService()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Types [query] into the search field at the top of the screen.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
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

  testWidgets('narrows the list to matching rows as the user types', (
    tester,
  ) async {
    await _pumpHome(tester, _ThreeAppsDatabase());
    expect(find.text('App Alpha'), findsOneWidget);
    expect(find.text('App Beta'), findsOneWidget);
    expect(find.text('App Gamma'), findsOneWidget);

    await _search(tester, 'gamma');

    expect(find.text('App Gamma'), findsOneWidget);
    expect(find.text('App Alpha'), findsNothing);
    expect(find.text('App Beta'), findsNothing);
  });

  testWidgets('matches the repository name, not only the display name', (
    tester,
  ) async {
    await _pumpHome(tester, _ThreeAppsDatabase());

    // 'beta-src' appears in no display name, so this can only match the repo.
    await _search(tester, 'beta-src');

    expect(find.text('App Beta'), findsOneWidget);
    expect(find.text('App Alpha'), findsNothing);
  });

  testWidgets('restores every row when the search is cleared', (tester) async {
    await _pumpHome(tester, _ThreeAppsDatabase());

    await _search(tester, 'gamma');
    expect(find.text('App Alpha'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('App Alpha'), findsOneWidget);
    expect(find.text('App Beta'), findsOneWidget);
    expect(find.text('App Gamma'), findsOneWidget);
  });

  testWidgets('says so instead of showing an empty list when nothing matches', (
    tester,
  ) async {
    await _pumpHome(tester, _ThreeAppsDatabase());

    await _search(tester, 'nothing-matches-this');

    expect(find.text('No matches for "nothing-matches-this"'), findsOneWidget);
    expect(find.text('App Alpha'), findsNothing);
  });

  testWidgets(
    'opens the filtered row\'s own app, not whichever app sits at that position',
    (tester) async {
      await _pumpHome(tester, _ThreeAppsDatabase());

      // Only App Gamma survives the filter, so it renders at list position 0.
      // Reusing the list index directly would resolve to App Alpha (index 0).
      await _search(tester, 'gamma');
      expect(find.text('App Gamma'), findsOneWidget);
      expect(find.text('App Alpha'), findsNothing);

      await tester.tap(find.text('App Gamma'));
      // The details sheet fetches its latest version on open, so drive it with
      // bounded pumps rather than pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Repo: owner/gamma-src'), findsOneWidget);
      expect(
        find.text('Repo: owner/alpha-src'),
        findsNothing,
        reason: 'the visible row must open its own app, not the entry at index 0',
      );
    },
  );

  testWidgets(
    'selects only the rows the filter shows, so a batch action cannot reach hidden rows',
    (tester) async {
      await _pumpHome(tester, _ThreeAppsDatabase());

      await _search(tester, 'beta');

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      // Two of the three apps are hidden by the filter; selecting them would
      // let "Delete" reach rows the user cannot see.
      expect(find.text('1 of 1 selected'), findsOneWidget);
    },
  );
}
