import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/ui/widgets/add_app_dialog.dart';
import 'package:provider/provider.dart';
import 'package:autononext/services/settings_service.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/external_app_checker.dart';
import '../mock_services.dart';

// Captured before each override so the static providers can be restored,
// preventing leakage into other test files.
late ExternalVersionProvider _originalVersionProvider;
late ExternalDebVersionProvider _originalDebVersionProvider;

/// Returns the current text of the field carrying [label], or null when no
/// such field is rendered.
String? _fieldText(WidgetTester tester, String label) {
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    if (field.decoration?.labelText == label) return field.controller?.text;
  }
  return null;
}

/// Types [url] into the dialog's URL box and taps Fetch.
Future<void> _fetch(WidgetTester tester, String url) async {
  await tester.enterText(find.byType(TextField).first, url);
  await tester.tap(find.byTooltip('Fetch details'));
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<SettingsService>.value(value: MockSettingsService()),
        Provider<GitHubService>.value(value: MockGitHubService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => AddAppDialog(),
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Show Dialog'));
  await tester.pumpAndSettle();
}

void main() {
  group('AddAppDialog URL mode detection', () {
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

    testWidgets(
        'a github.com release-asset .deb URL is tracked as a repository, not as a pinned file',
        (tester) async {
      await _pumpDialog(tester);

      await _fetch(
        tester,
        'https://github.com/ninepointlabs/autononext/releases/download/v1.0.0/autononext_1.0.0_amd64.deb',
      );

      // Repository mode is the only mode that can follow new releases; a
      // version-pinned asset URL would report "up to date" forever.
      expect(_fieldText(tester, 'Repository Owner'), 'ninepointlabs');
      expect(_fieldText(tester, 'Repository Name'), 'autononext');
      expect(_fieldText(tester, 'Package URL'), isNull);
    });

    testWidgets(
        'a non-GitHub .deb URL stays a direct package and only loses its trailing extension',
        (tester) async {
      await _pumpDialog(tester);

      await _fetch(tester, 'https://example.com/dl/my.deb-tool_1.0.0_amd64.deb');

      expect(
        _fieldText(tester, 'Package URL'),
        'https://example.com/dl/my.deb-tool_1.0.0_amd64.deb',
      );
      // `replaceAll('.deb', '')` also stripped the ".deb" inside the name,
      // producing "my-tool_1.0.0_amd64".
      expect(_fieldText(tester, 'Display Name'), 'my.deb-tool_1.0.0_amd64');
    });
  });
}
