import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:autononext/models/install_type.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/ui/upgrade_flow.dart';

import '../mock_services.dart';
import '../mocks/mock_installer_service.dart';

TrackedApp _app({
  String? installedVersion,
  String? fetchedPackage,
  List<String> architectures = const [],
}) =>
    TrackedApp(
      repoOwner: 'ninepointlabs',
      repoName: 'autononext',
      displayName: 'Test App',
      installedVersion: installedVersion,
      createdAt: DateTime(2026, 1, 1),
      fetchedPackage: fetchedPackage,
      architectures: architectures,
    );

Release _release(List<ReleaseAsset> assets, {String tagName = 'v2.0.0'}) =>
    Release(
      tagName: tagName,
      prerelease: false,
      draft: false,
      assets: assets,
    );

ReleaseAsset _asset(String name) => ReleaseAsset(
      name: name,
      browserDownloadUrl: 'https://example.com/$name',
      contentType: 'application/octet-stream',
      size: 0,
    );

/// Captures the [TrackedApp] persisted by [performUpgrade] so the test can
/// prove the asset actually installed reached the database.
class _RecordingDatabase extends MockDatabaseService {
  final List<TrackedApp> updates = [];

  @override
  Future<void> updateApp(TrackedApp app) async {
    updates.add(app);
  }
}

/// Pumps a minimal tree with the services the flow helpers read from
/// [BuildContext], plus a button that invokes [action].
Future<void> _pumpHarness(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) action,
  MockInstallerService? installer,
  DatabaseService? db,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<InstallerService>.value(
          value: installer ?? MockInstallerService(),
        ),
        Provider<DatabaseService>.value(value: db ?? MockDatabaseService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => action(context),
              child: const Text('run'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('chooseAsset', () {
    testWidgets(
      'returns the sole asset of that type without asking — one candidate is not a choice',
      (tester) async {
        ReleaseAsset? result;
        final release = _release([
          _asset('autononext_1.0.0_amd64.deb'),
          _asset('autononext_1.0.0_x86_64.AppImage'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseAsset(
              context,
              release,
              InstallType.appImage,
              app: _app(),
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.name, 'autononext_1.0.0_x86_64.AppImage');
        expect(find.text('Select AppImage Asset'), findsNothing);
      },
    );

    testWidgets(
      'honours the tapped asset instead of the first listed — upstream issue #5',
      (tester) async {
        ReleaseAsset? result;
        // A GUI and a CLI AppImage: the release ships two assets of the same
        // type, so the old "pick the first one" behaviour was wrong.
        final release = _release([
          _asset('autononext-gui_1.0.0_amd64.AppImage'),
          _asset('autononext-cli_1.0.0_amd64.AppImage'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseAsset(
              context,
              release,
              InstallType.appImage,
              app: _app(architectures: ['amd64']),
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(find.text('Select AppImage Asset'), findsOneWidget);
        expect(find.text('autononext-gui_1.0.0_amd64.AppImage'), findsOneWidget);
        expect(find.text('autononext-cli_1.0.0_amd64.AppImage'), findsOneWidget);
        // Both assets satisfy the tracked architecture, so both are hinted.
        expect(find.text('AMD64'), findsNWidgets(2));

        await tester.tap(find.text('autononext-cli_1.0.0_amd64.AppImage'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.name, 'autononext-cli_1.0.0_amd64.AppImage');
        expect(
          result!.browserDownloadUrl,
          'https://example.com/autononext-cli_1.0.0_amd64.AppImage',
        );
      },
    );

    testWidgets(
      'yields null when dismissed so a cancel is not silently treated as the first asset',
      (tester) async {
        ReleaseAsset? result;
        var completed = false;
        final release = _release([
          _asset('autononext-gui_1.0.0_amd64.AppImage'),
          _asset('autononext-cli_1.0.0_amd64.AppImage'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseAsset(
              context,
              release,
              InstallType.appImage,
              app: _app(),
            );
            completed = true;
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();
        expect(find.text('Select AppImage Asset'), findsOneWidget);

        // Tapping the barrier outside the dialog dismisses it.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(result, isNull);
      },
    );

    testWidgets(
      'returns null without asking when no asset of that type ships — nothing to choose from',
      (tester) async {
        ReleaseAsset? result;
        final release = _release([
          _asset('autononext_1.0.0_amd64.deb'),
          _asset('autononext_1.0.0.src.tar.gz'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseAsset(
              context,
              release,
              InstallType.appImage,
              app: _app(),
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(result, isNull);
        expect(find.byType(SimpleDialog), findsNothing);
        expect(find.text('Select AppImage Asset'), findsNothing);
      },
    );
  });

  group('performUpgrade', () {
    testWidgets(
      'records the asset it installed in fetchedPackage so the row shows what is on disk',
      (tester) async {
        final installer = MockInstallerService();
        final db = _RecordingDatabase();
        const assetName = 'autononext-cli_2.0.0_amd64.AppImage';
        // The row previously showed this stale asset from an earlier check.
        final app = _app(fetchedPackage: 'autononext-gui_1.0.0_amd64.AppImage');

        await _pumpHarness(
          tester,
          installer: installer,
          db: db,
          action: (context) async {
            await performUpgrade(
              context: context,
              app: app,
              release: _release(const []),
              type: InstallType.appImage,
              assetName: assetName,
              downloadUrl: 'https://example.com/$assetName',
              targetPath: '/usr/local/bin/autononext',
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(db.updates, hasLength(1));
        expect(db.updates.single.fetchedPackage, assetName);
        expect(db.updates.single.installedVersion, 'v2.0.0');
        expect(installer.downloadedUrls, ['https://example.com/$assetName']);

        // Drain the SnackBar's auto-dismiss timer.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );
  });
}
