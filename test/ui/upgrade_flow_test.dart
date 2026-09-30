import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:autononext/models/install_type.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/install_location.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/ui/upgrade_flow.dart';

import '../mock_services.dart';
import '../mocks/mock_installer_service.dart';

TrackedApp _app({
  String? installedVersion,
  String? launchCommand,
}) =>
    TrackedApp(
      repoOwner: 'ninepointlabs',
      repoName: 'autononext',
      displayName: 'Test App',
      installedVersion: installedVersion,
      launchCommand: launchCommand,
      createdAt: DateTime(2026, 1, 1),
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
      browserDownloadUrl: 'http://example.com/$name',
      contentType: 'application/octet-stream',
      size: 0,
    );

/// Captures the [TrackedApp] persisted by [performUpgrade] so the test can
/// prove the DB write happened with the upgraded fields.
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
  group('pickInstallType', () {
    testWidgets(
      'returns the chosen type so the caller knows what to install',
      (tester) async {
        InstallType? result;
        final release = _release([
          _asset('app_1.0.0_amd64.deb'),
          _asset('app_1.0.0_amd64.AppImage'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await pickInstallType(context, release);
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(find.text('DEB'), findsOneWidget);
        expect(find.text('AppImage'), findsOneWidget);

        await tester.tap(find.text('DEB'));
        await tester.pumpAndSettle();

        expect(result, InstallType.deb);
      },
    );

    testWidgets(
      'returns null when dismissed so the caller aborts instead of guessing',
      (tester) async {
        InstallType? result = InstallType.deb;
        var completed = false;
        final release = _release([
          _asset('app_1.0.0_amd64.deb'),
          _asset('app_1.0.0_amd64.AppImage'),
        ]);

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await pickInstallType(context, release);
            completed = true;
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();
        expect(find.text('DEB'), findsOneWidget);

        // Tapping the barrier outside the dialog dismisses it.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(result, isNull);
      },
    );
  });

  group('chooseInstallTarget', () {
    testWidgets(
      'returns the only candidate without asking — one location is unambiguous',
      (tester) async {
        String? result;
        const candidates = [
          InstallLocation(
            path: '/usr/local/bin/app',
            source: 'PATH',
            writable: true,
            ownedByPackage: false,
          ),
        ];

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseInstallTarget(
              context,
              _app(),
              candidatesOverride: candidates,
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(result, '/usr/local/bin/app');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SimpleDialog), findsNothing);
      },
    );

    testWidgets(
      'lists every candidate when several exist so the user picks the right one',
      (tester) async {
        String? result;
        const candidates = [
          InstallLocation(
            path: '/usr/bin/app',
            source: 'PATH',
            writable: false,
            ownedByPackage: true,
          ),
          InstallLocation(
            path: '/home/u/.local/bin/app',
            source: 'well-known',
            writable: true,
            ownedByPackage: false,
          ),
        ];

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseInstallTarget(
              context,
              _app(),
              candidatesOverride: candidates,
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(find.text('/usr/bin/app'), findsOneWidget);
        expect(find.text('/home/u/.local/bin/app'), findsOneWidget);
        // The package-managed note steers the user away from the risky target.
        expect(find.textContaining('package-managed'), findsOneWidget);

        await tester.tap(find.text('/home/u/.local/bin/app'));
        await tester.pumpAndSettle();

        expect(result, '/home/u/.local/bin/app');
      },
    );

    testWidgets(
      'warns before a package-managed overwrite and returns null when declined',
      (tester) async {
        String? result;
        const candidates = [
          InstallLocation(
            path: '/usr/bin/app',
            source: 'PATH',
            writable: false,
            ownedByPackage: true,
          ),
        ];

        await _pumpHarness(
          tester,
          action: (context) async {
            result = await chooseInstallTarget(
              context,
              _app(),
              candidatesOverride: candidates,
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('managed by your system package manager'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(result, isNull);
      },
    );
  });

  group('performUpgrade', () {
    testWidgets(
      'persists the new version and only then reports success',
      (tester) async {
        final installer = MockInstallerService();
        final db = _RecordingDatabase();
        final app = _app();
        final release = _release(const []);

        await _pumpHarness(
          tester,
          installer: installer,
          db: db,
          action: (context) async {
            await performUpgrade(
              context: context,
              app: app,
              release: release,
              type: InstallType.binary,
              assetName: 'app',
              downloadUrl: 'http://example.com/app',
              targetPath: '/usr/local/bin/app',
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(installer.downloadCount, 1);
        expect(installer.installCount, 1);
        expect(db.updates, hasLength(1));
        expect(db.updates.single.installedVersion, 'v2.0.0');
        expect(db.updates.single.installType, InstallType.binary);
        expect(db.updates.single.launchCommand, isNotNull);

        expect(find.text('Upgraded Test App to v2.0.0'), findsOneWidget);

        // Drain the SnackBar's auto-dismiss timer.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'never claims success when the install throws — failure is reported instead',
      (tester) async {
        final installer = MockInstallerService()
          ..setShouldFail(true, message: 'disk full');
        final db = _RecordingDatabase();
        final app = _app();
        final release = _release(const []);

        var succeeded = true;
        await _pumpHarness(
          tester,
          installer: installer,
          db: db,
          action: (context) async {
            succeeded = await performUpgrade(
              context: context,
              app: app,
              release: release,
              type: InstallType.binary,
              assetName: 'app',
              downloadUrl: 'http://example.com/app',
              targetPath: '/usr/local/bin/app',
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(succeeded, isFalse);
        expect(db.updates, isEmpty);
        expect(find.textContaining('Upgrade failed'), findsOneWidget);
        expect(find.textContaining('Upgraded '), findsNothing);

        // The error snackbar is persistent now, so dismiss it explicitly;
        // otherwise its Timer outlives the widget tree.
        await tester.tap(find.text('Dismiss'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'refuses to persist a release that is not newer so an upgrade cannot downgrade',
      (tester) async {
        final installer = MockInstallerService();
        final db = _RecordingDatabase();
        final app = _app(installedVersion: 'v2.0.0');
        final release = _release(const [], tagName: 'v1.0.0');

        var succeeded = true;
        await _pumpHarness(
          tester,
          installer: installer,
          db: db,
          action: (context) async {
            succeeded = await performUpgrade(
              context: context,
              app: app,
              release: release,
              type: InstallType.binary,
              assetName: 'app',
              downloadUrl: 'http://example.com/app',
              targetPath: '/usr/local/bin/app',
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(succeeded, isFalse);
        expect(db.updates, isEmpty);
        // The download must not even start for a downgrade.
        expect(installer.downloadCount, 0);
        expect(find.textContaining('is not newer'), findsOneWidget);

        // The warning snackbar is persistent now, so dismiss it explicitly;
        // otherwise its Timer outlives the widget tree.
        await tester.tap(find.text('Dismiss'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'keeps a stored launch command when the install reports none',
      (tester) async {
        final installer = MockInstallerService()
          ..setInstallResult(
            'app',
            (launchCommand: null, packageName: 'pkgname'),
          );
        final db = _RecordingDatabase();
        final app = _app(launchCommand: '/opt/old/tool');

        await _pumpHarness(
          tester,
          installer: installer,
          db: db,
          action: (context) async {
            await performUpgrade(
              context: context,
              app: app,
              release: _release(const []),
              type: InstallType.deb,
              assetName: 'app',
              downloadUrl: 'http://example.com/app',
              targetPath: '/usr/local/bin/app',
            );
          },
        );

        await tester.tap(find.text('run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(db.updates, hasLength(1));
        expect(db.updates.single.launchCommand, '/opt/old/tool');

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );
  });
}
