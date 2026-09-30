import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/ui/widgets/edit_app_dialog.dart';
import 'package:autononext/ui/widgets/edit_deb_package_dialog.dart';

/// Ceilings for the dialog CONTENT height, measured through `showDialog` so the
/// dialog takes its intrinsic size. Measured values are 692 (app) and 308 (deb);
/// the ceilings leave a little slack but still fail on a real regression.
const _maxAppDialogHeight = 780.0;
const _maxDebDialogHeight = 330.0;

Future<Size> _openAndMeasure(
  WidgetTester tester,
  Widget Function(BuildContext) builder,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(context: context, builder: builder),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // The AlertDialog's own render box resolves to the whole viewport, so the
  // content Column — the thing that actually grows — is what gets measured.
  final column = find
      .descendant(of: find.byType(AlertDialog), matching: find.byType(Column))
      .first;
  return tester.getSize(column);
}

void main() {
  testWidgets('the edit-app form stays compact so it needs less scrolling', (tester) async {
    final app = TrackedApp(
      id: 1,
      repoOwner: 'bitwarden',
      repoName: 'clients',
      displayName: 'Bitwarden client apps',
      installedVersion: '2026.8.0',
      latestVersion: 'desktop-v2026.9.0',
      launchCommand: 'bitwarden',
      packageName: 'bitwarden',
      assetFilterPattern: '*amd64.deb',
      tagPrefix: 'desktop',
      architectures: const ['amd64'],
      createdAt: DateTime(2026, 1, 1),
    );

    final size = await _openAndMeasure(tester, (_) => EditAppDialog(app: app));
    // ignore: avoid_print
    print('EDIT APP DIALOG CONTENT: ${size.width} x ${size.height}');
    expect(
      size.height,
      lessThanOrEqualTo(_maxAppDialogHeight),
      reason: 'the form grew; check field spacing, isDense and the text scale',
    );
  });

  testWidgets('the edit-deb form stays compact, matching the app form', (tester) async {
    final pkg = TrackedDebPackage(
      id: 1,
      name: 'sniffnet',
      packageUrl: 'https://example.test/sniffnet_1.5.0_amd64.deb',
      displayName: 'Sniffnet network monitor',
      installedVersion: '1.4.0',
      latestVersion: '1.5.0',
      createdAt: DateTime(2026, 1, 1),
    );

    final size = await _openAndMeasure(
      tester,
      (_) => EditDebPackageDialog(package: pkg),
    );
    // ignore: avoid_print
    print('EDIT DEB DIALOG CONTENT: ${size.width} x ${size.height}');
    expect(size.height, lessThanOrEqualTo(_maxDebDialogHeight));
  });
}
