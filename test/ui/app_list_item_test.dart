import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/ui/widgets/app_list_item.dart';

TrackedApp _app({String? installed, String? latest}) => TrackedApp(
  id: 1,
  repoOwner: 'bitwarden',
  repoName: 'clients',
  displayName: 'Bitwarden client apps',
  installedVersion: installed,
  latestVersion: latest,
  fetchedPackage: 'Bitwarden-2026.9.0-amd64.deb',
  latestReleaseDate: DateTime.utc(2026, 9, 17),
  createdAt: DateTime(2026, 1, 1),
  architectures: const ['amd64'],
);

Future<void> _pump(WidgetTester tester, TrackedApp app) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            AppListItem(
              app: app,
              onTap: () {},
              onUpdate: () {},
              onEdit: () {},
              onDelete: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The rendered text of the line containing [needle].
///
/// These lines are `Text.rich`, whose content lives in spans rather than
/// `Text.data`, so the plain text is what has to be asserted on.
String _lineContaining(WidgetTester tester, String needle) {
  final text = tester.widget<Text>(find.textContaining(needle));
  return text.textSpan?.toPlainText() ?? text.data ?? '';
}

void main() {
  testWidgets('the open-repository icon shares one row with the other actions, so they align', (
    tester,
  ) async {
    await _pump(tester, _app(installed: '2026.8.0', latest: 'desktop-v2026.9.0'));

    // The innermost Row holding the open icon must also hold the action icons;
    // a Row centres its children vertically, which is what makes them line up.
    final row = find
        .ancestor(of: find.byIcon(Icons.open_in_new), matching: find.byType(Row))
        .first;

    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      findsOneWidget,
      reason: 'the open icon must not sit in the title row',
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.edit)),
      findsOneWidget,
    );
  });

  testWidgets('the title is highlighted when an update is available', (tester) async {
    await _pump(tester, _app(installed: '2026.8.0', latest: 'desktop-v2026.9.0'));

    final title = tester.widget<Text>(find.text('Bitwarden client apps'));
    expect(title.style?.color, Colors.orange.shade700);
    expect(find.byIcon(Icons.system_update), findsOneWidget);
  });

  testWidgets('the title is not highlighted when there is no update', (tester) async {
    await _pump(tester, _app(installed: '2026.9.0', latest: 'desktop-v2026.9.0'));

    final title = tester.widget<Text>(find.text('Bitwarden client apps'));
    expect(title.style?.color, isNot(Colors.orange.shade700));
    expect(find.byIcon(Icons.system_update), findsNothing);
  });

  testWidgets('the repository and the asset filename share one line separated by a bar', (
    tester,
  ) async {
    await _pump(tester, _app(installed: '2026.8.0', latest: 'desktop-v2026.9.0'));

    expect(
      _lineContaining(tester, 'bitwarden/clients'),
      'bitwarden/clients  |  Bitwarden-2026.9.0-amd64.deb',
    );
  });

  testWidgets('installed, latest and released share one line separated by bars', (tester) async {
    await _pump(tester, _app(installed: '2026.8.0', latest: 'desktop-v2026.9.0'));

    expect(
      _lineContaining(tester, 'Installed:'),
      'Installed: 2026.8.0  |  Latest: desktop-v2026.9.0  |  Released: 2026-09-17',
    );
  });

  testWidgets('the release date stays attached to the Latest line, not drifting elsewhere', (
    tester,
  ) async {
    await _pump(tester, _app(installed: '2026.8.0', latest: 'desktop-v2026.9.0'));

    // Part of the same Text as the version it describes…
    expect(
      _lineContaining(tester, 'Latest:'),
      contains('Released: 2026-09-17'),
    );
    // …and rendered exactly once, so it has not also drifted to another line.
    expect(find.textContaining('Released:'), findsOneWidget);
  });
}
