import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/ui/widgets/app_list_item.dart';
import 'package:autononext/ui/widgets/deb_package_list_item.dart';

TrackedApp _app() => TrackedApp(
      repoOwner: 'ninepointlabs',
      repoName: 'autononext',
      displayName: 'Autononext',
      createdAt: DateTime(2026, 1, 1),
    );

TrackedDebPackage _deb() => TrackedDebPackage(
      name: 'autononext',
      packageUrl: 'https://example.com/autononext_1.0.0_amd64.deb',
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, Widget row) async {
  // The rows render a multi-line subtitle, which overflows the default
  // 800x600 test surface.
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: row)));
}

void main() {
  group('Row inline actions while multi-select is active', () {
    testWidgets('AppListItem hides the open-repository action', (tester) async {
      await _pump(
        tester,
        AppListItem(app: _app(), onTap: () {}, isMultiSelectMode: true),
      );

      // Tapping the row toggles selection in this mode, so a live "open in
      // browser" button would fire the wrong action.
      expect(find.byTooltip('Open repository on GitHub'), findsNothing);
    });

    testWidgets('AppListItem shows the open-repository action outside multi-select',
        (tester) async {
      await _pump(tester, AppListItem(app: _app(), onTap: () {}));

      expect(find.byTooltip('Open repository on GitHub'), findsOneWidget);
    });

    testWidgets('AppListItem shows an unchecked box on unselected rows in multi-select',
        (tester) async {
      await _pump(
        tester,
        AppListItem(
          app: _app(),
          onTap: () {},
          isSelected: false,
          isMultiSelectMode: true,
        ),
      );

      // Without this, unselected rows give no hint that the list is in
      // multi-select mode at all.
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('AppListItem keeps the box checked on selected rows', (tester) async {
      await _pump(
        tester,
        AppListItem(
          app: _app(),
          onTap: () {},
          isSelected: true,
          isMultiSelectMode: true,
        ),
      );

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('DebPackageListItem hides the open-URL action', (tester) async {
      await _pump(
        tester,
        DebPackageListItem(
          package: _deb(),
          onTap: () {},
          isMultiSelectMode: true,
        ),
      );

      expect(find.byTooltip('Open direct download URL'), findsNothing);
    });

    testWidgets('DebPackageListItem shows the open-URL action outside multi-select',
        (tester) async {
      await _pump(tester, DebPackageListItem(package: _deb(), onTap: () {}));

      expect(find.byTooltip('Open direct download URL'), findsOneWidget);
    });
  });
}
