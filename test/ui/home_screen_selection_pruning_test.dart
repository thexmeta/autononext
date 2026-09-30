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

/// Returns two apps until [shrink] is set, then one — standing in for a list
/// that shrinks while a multi-select is still live.
class _ShrinkingDatabase extends DatabaseService {
  bool shrink = false;

  List<TrackedApp> get _all => [
        TrackedApp(
          id: 1,
          repoOwner: 'ninepointlabs',
          repoName: 'one',
          displayName: 'App One',
          installedVersion: '1.0.0',
          createdAt: DateTime(2026, 1, 1),
        ),
        TrackedApp(
          id: 2,
          repoOwner: 'ninepointlabs',
          repoName: 'two',
          displayName: 'App Two',
          installedVersion: '1.0.0',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  Future<List<TrackedApp>> getAllApps() async =>
      shrink ? _all.sublist(0, 1) : _all;

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

/// Reads the progress dialog's "N of M completed" line.
String _progressLine(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .firstWhere((s) => s.endsWith('completed'), orElse: () => '<none>');

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

  testWidgets('a shrunken list cannot leave a selection pointing past the end',
      (tester) async {
    final db = _ShrinkingDatabase();

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

    expect(find.text('App One'), findsOneWidget);
    expect(find.text('App Two'), findsOneWidget);

    // Enter multi-select and select both rows.
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 selected'), findsOneWidget);

    // The list shrinks; the reload after the batch delete returns one row while
    // index 1 is still in the selection.
    db.shrink = true;
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('App Two'), findsNothing);
    // Indices past the end must be dropped, or the bar claims more items than
    // the list holds.
    expect(find.text('1 of 1 selected'), findsOneWidget);

    // Let the batch-delete SnackBar auto-dismiss — it sits over the action bar
    // and would swallow the tap below.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for Updates'));
    // The progress dialog refreshes from a periodic Timer, so `pumpAndSettle`
    // would never return while it is open.
    await tester.pump();
    await tester.pump();

    // The denominator must match the work actually queued, or the bar can never
    // reach 100%.
    expect(_progressLine(tester), endsWith('of 1 completed'));

    // Let the batch finish so no timers are left pending.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
