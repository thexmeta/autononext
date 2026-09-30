import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/ui/widgets/deb_package_details_sheet.dart';
import '../mock_services.dart';
import '../mocks/mock_installer_service.dart';

TrackedDebPackage _pkg({String? installedVersion}) => TrackedDebPackage(
      name: 'autononext',
      packageUrl: 'https://example.com/autononext_2.0.0_amd64.deb',
      installedVersion: installedVersion,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpSheet(
  WidgetTester tester,
  TrackedDebPackage pkg,
  MockInstallerService installer,
) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<InstallerService>.value(value: installer),
        Provider<DatabaseService>.value(value: MockDatabaseService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => DebPackageDetailsSheet(package: pkg),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('DebPackageDetailsSheet', () {
    testWidgets('names the step in flight instead of showing a bare spinner',
        (tester) async {
      final installer = MockInstallerService()..holdDownload();
      await _pumpSheet(tester, _pkg(), installer);

      await tester.tap(find.text('Install'));
      await tester.pump();

      // Previously only a spinner was rendered, so the user could not tell
      // whether the app was downloading or installing.
      expect(find.textContaining('Downloading'), findsOneWidget);

      installer.releaseDownload();
      await tester.pumpAndSettle();

      expect(installer.downloadCount, 1);
      expect(installer.installCount, 1);
      // The success path closes the sheet, so the row can refresh.
      expect(find.byType(DebPackageDetailsSheet), findsNothing);
      expect(find.text('Installation successful'), findsOneWidget);
    });

    testWidgets('dismisses the sheet after dispatching a launch', (tester) async {
      final installer = MockInstallerService();
      await _pumpSheet(tester, _pkg(installedVersion: '1.0.0'), installer);

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(installer.launchDebCount, 1);
      // Leaving the sheet open made a successful launch look like a no-op.
      expect(find.byType(DebPackageDetailsSheet), findsNothing);
    });

    testWidgets('keeps the sheet open when a launch fails', (tester) async {
      final installer = MockInstallerService()
        ..setShouldFail(true, message: 'no such binary');
      await _pumpSheet(tester, _pkg(installedVersion: '1.0.0'), installer);

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(find.byType(DebPackageDetailsSheet), findsOneWidget);
      expect(find.textContaining('Launch failed'), findsOneWidget);
    });
  });
}
