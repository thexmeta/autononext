import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/ui/widgets/add_app_dialog.dart';
import 'package:autononext/services/settings_service.dart';
import 'package:autononext/services/github_service.dart';
import '../mock_services.dart';

/// Ceiling for the add-app dialog CONTENT height, measured through `showDialog`
/// so the dialog takes its intrinsic size. Measured height is 541 after
/// compaction (714 before); the ceiling leaves ~10% slack but still fails on a
/// real spacing regression, keeping the form short enough to avoid scrolling.
const _maxAddDialogHeight = 595.0;

Future<Size> _openAndMeasure(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<SettingsService>.value(value: MockSettingsService()),
        Provider<GitHubService>.value(value: MockGitHubService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showDialog(context: context, builder: (_) => const AddAppDialog()),
              child: const Text('open'),
            ),
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
  testWidgets('the add-app form stays compact so it does not need scrolling',
      (tester) async {
    final size = await _openAndMeasure(tester);
    // ignore: avoid_print
    print('ADD APP DIALOG CONTENT: ${size.width} x ${size.height}');
    expect(
      size.height,
      lessThanOrEqualTo(_maxAddDialogHeight),
      reason: 'the form grew; check field spacing, isDense and the text scale',
    );
  });
}
