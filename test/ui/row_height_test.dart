import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/ui/widgets/app_list_item.dart';
import 'package:autononext/ui/widgets/deb_package_list_item.dart';

/// A fully populated row is the worst case: every optional metadata line is
/// present, so it is the height that decides how many entries fit on screen.
/// Measured heights are 95 (app) and 103 (deb); the ceiling leaves a little
/// slack but still fails on a real regression.
const _maxRowHeight = 110.0;

Future<void> _pumpRow(WidgetTester tester, Widget row, {double width = 1200}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ListView(children: [row]))),
  );
  await tester.pump();
}

void main() {
  testWidgets('an app row stays compact so more entries fit on screen', (
    tester,
  ) async {
    final app = TrackedApp(
      id: 1,
      repoOwner: 'bitwarden',
      repoName: 'clients',
      displayName:
          'Bitwarden client apps (web, browser extension, desktop, and cli).',
      installedVersion: '2026.8.0',
      latestVersion: 'desktop-v2026.9.0',
      launchCommand: 'bitwarden',
      fetchedPackage: 'Bitwarden-2026.9.0-amd64.deb',
      latestReleaseDate: DateTime.utc(2026, 9, 3),
      createdAt: DateTime(2026, 1, 1),
      architectures: const ['amd64'],
    );

    await _pumpRow(
      tester,
      AppListItem(
        app: app,
        onTap: () {},
        onUpdate: () {},
        onEdit: () {},
        onDelete: () {},
      ),
    );

    final height = tester.getSize(find.byType(AppListItem)).height;
    // ignore: avoid_print
    print('APP ROW HEIGHT: $height');
    expect(
      height,
      lessThanOrEqualTo(_maxRowHeight),
      reason: 'the row grew; check paddings and the default IconButton hit box',
    );
  });

  testWidgets('an app row does not overflow on a narrow window', (tester) async {
    // The trailing row carries five icon buttons plus the architecture chip, so
    // a narrow window is where it would start clipping.
    final app = TrackedApp(
      id: 1,
      repoOwner: 'bitwarden',
      repoName: 'clients',
      displayName:
          'Bitwarden client apps (web, browser extension, desktop, and cli).',
      installedVersion: '2026.8.0',
      latestVersion: 'desktop-v2026.9.0',
      fetchedPackage: 'Bitwarden-2026.9.0-amd64.deb',
      latestReleaseDate: DateTime.utc(2026, 9, 3),
      createdAt: DateTime(2026, 1, 1),
      architectures: const ['amd64'],
    );

    await _pumpRow(
      tester,
      AppListItem(
        app: app,
        onTap: () {},
        onUpdate: () {},
        onEdit: () {},
        onDelete: () {},
      ),
      width: 640,
    );

    // A RenderFlex overflow would have thrown by now.
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('a deb package row stays compact, matching the app rows', (
    tester,
  ) async {
    final pkg = TrackedDebPackage(
      id: 1,
      name: 'sniffnet',
      packageUrl: 'https://example.test/sniffnet_1.5.0_amd64.deb',
      displayName: 'Sniffnet network monitor',
      installedVersion: '1.4.0',
      latestVersion: '1.5.0',
      fileSize: '11.8 MB',
      fileDate: DateTime.utc(2026, 9, 3),
      createdAt: DateTime(2026, 1, 1),
    );

    await _pumpRow(
      tester,
      DebPackageListItem(
        package: pkg,
        onTap: () {},
        onUpdate: () {},
        onEdit: () {},
        onDelete: () {},
      ),
    );

    final height = tester.getSize(find.byType(DebPackageListItem)).height;
    // ignore: avoid_print
    print('DEB ROW HEIGHT: $height');
    expect(height, lessThanOrEqualTo(_maxRowHeight));
  });
}
