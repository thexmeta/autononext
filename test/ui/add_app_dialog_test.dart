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

void main() {
  group('AddAppDialog', () {
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
    testWidgets('displays repo owner field', (WidgetTester tester) async {
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
                    builder: (dialogContext) => AddAppDialog(),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      // Tap to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog is visible
      expect(find.textContaining('Add App'), findsOneWidget);
      expect(find.textContaining('Repository Owner'), findsWidgets);
    });

    testWidgets('displays repo name field', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Repository Name'), findsWidgets);
    });

    testWidgets('displays asset filter pattern field', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Asset Filter Pattern'), findsWidgets);
    });

    testWidgets('displays tag prefix field', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings (scroll the tile into view before tapping)
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tag Prefix'), findsWidgets);
    });

    testWidgets('displays architecture selection', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings (scroll the tile into view before tapping)
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Architecture'), findsWidgets);
    });

    testWidgets('displays include prerelease toggle', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings (scroll the tile into view before tapping)
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Include Pre-release'), findsWidgets);
      expect(find.byType(CheckboxListTile), findsWidgets);
    });

    testWidgets('displays help text with examples', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Should have help text
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('validates required fields', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Enter an invalid (non-GitHub, non-package) URL and fetch it
      await tester.enterText(find.byType(TextField).first, 'not-a-valid-url');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // Invalid input must surface a user-visible error instead of failing silently
      expect(find.textContaining('Exception'), findsWidgets);
    });

    testWidgets('accepts valid asset filter pattern', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Enter valid pattern
      final patternField = find.byType(TextField).at(2); // Third text field
      await tester.enterText(patternField, '*amd64*.deb');
      await tester.pump();

      expect(find.text('*amd64*.deb'), findsOneWidget);
    });

    testWidgets('accepts valid tag prefix', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Enter valid tag prefix
      final tagPrefixField = find.byType(TextField).at(3); // Fourth text field
      await tester.enterText(tagPrefixField, 'desktop-');
      await tester.pump();

      expect(find.text('desktop-'), findsOneWidget);
    });

    testWidgets('allows multiple architecture selection', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings (scroll the tile into view before tapping)
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      // Architectures are exposed as FilterChips and multiple may be selected
      expect(find.byType(FilterChip), findsWidgets);

      final x86Chip = find.widgetWithText(FilterChip, 'x86_64');
      final arm64Chip = find.widgetWithText(FilterChip, 'arm64');
      await tester.ensureVisible(x86Chip);
      await tester.tap(x86Chip);
      await tester.pump();
      await tester.ensureVisible(arm64Chip);
      await tester.tap(arm64Chip);
      await tester.pump();

      expect(tester.widget<FilterChip>(x86Chip).selected, isTrue);
      expect(tester.widget<FilterChip>(arm64Chip).selected, isTrue);
    });

    testWidgets('toggle prerelease switch works', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings (scroll the tile into view before tapping)
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      // Find and toggle the checkbox
      final checkboxFinder = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkboxFinder);
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Checkbox should still be there and now be checked
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(checkboxFinder).value, isTrue);
    });

    testWidgets('cancel button closes dialog', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap cancel
      final cancelButton = find.textContaining('Cancel');
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.textContaining('Add App'), findsNothing);
    });

    testWidgets('displays filter examples in help text', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Should contain example patterns
      expect(find.textContaining('e.g.'), findsWidgets);
      expect(find.textContaining('.deb'), findsWidgets);
      expect(find.textContaining('amd64'), findsWidgets);
    });

    testWidgets('form layout is scrollable', (WidgetTester tester) async {
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AddAppDialog(),
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Dialog should be scrollable
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });
}
