import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_deb_package.dart';
import 'package:autononext/ui/widgets/edit_deb_package_dialog.dart';

TrackedDebPackage _pkg() => TrackedDebPackage(
      name: 'autononext',
      packageUrl: 'https://example.com/autononext_1.0.0_amd64.deb',
      createdAt: DateTime(2026, 1, 1),
    );

/// Field order in the dialog: 0 = internal name, 1 = display name, 2 = URL.
Finder _nameField() => find.byType(TextField).at(0);
Finder _urlField() => find.byType(TextField).at(2);

/// Holds the value the dialog pops, which is only available after it closes.
class _Harness {
  TrackedDebPackage? result;
}

Future<_Harness> _openDialog(WidgetTester tester) async {
  final harness = _Harness();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              harness.result = await showDialog<TrackedDebPackage>(
                context: context,
                builder: (_) => EditDebPackageDialog(package: _pkg()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

/// Taps Save and lets the SnackBar animation start.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('EditDebPackageDialog validation', () {
    testWidgets('refuses a blank internal name', (tester) async {
      final harness = await _openDialog(tester);

      await tester.enterText(_nameField(), '   ');
      await _tapSave(tester);

      // A blank package id would create an entry that cannot be identified,
      // launched or uninstalled.
      expect(find.text('Edit Deb Package'), findsOneWidget);
      expect(harness.result, isNull);
      expect(find.text('Internal name is required'), findsOneWidget);
    });

    testWidgets('refuses a package URL that is not http(s)', (tester) async {
      final harness = await _openDialog(tester);

      await tester.enterText(_urlField(), 'not a url');
      await _tapSave(tester);

      // `downloadFile` would otherwise be handed a string with no scheme.
      expect(find.text('Edit Deb Package'), findsOneWidget);
      expect(harness.result, isNull);
      expect(find.text('A valid http(s) package URL is required'), findsOneWidget);
    });

    testWidgets('saves trimmed values', (tester) async {
      final harness = await _openDialog(tester);

      await tester.enterText(_nameField(), '  autononext  ');
      await tester.enterText(_urlField(), '  https://example.com/autononext_2.0.0_amd64.deb  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.result, isNotNull);
      expect(harness.result!.name, 'autononext');
      expect(harness.result!.packageUrl, 'https://example.com/autononext_2.0.0_amd64.deb');
    });

    testWidgets('clears the display name when it is blanked out', (tester) async {
      final harness = await _openDialog(tester);

      await tester.enterText(find.byType(TextField).at(1), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.result, isNotNull);
      expect(harness.result!.displayName, isNull);
    });
  });
}
