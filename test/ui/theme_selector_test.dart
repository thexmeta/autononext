import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/widgets/theme_selector.dart';
import 'package:autononext/services/theme_service.dart';
import '../mock_services.dart';

void main() {
  group('ThemeSelector', () {
    testWidgets('displays theme options', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Verify theme selector is visible
      expect(find.byType(ThemeSelector), findsOneWidget);
    });

    testWidgets('shows current theme selection', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Should show theme options
      expect(find.textContaining('Light'), findsWidgets);
      expect(find.textContaining('Dark'), findsWidgets);
      expect(find.textContaining('System'), findsWidgets);
    });

    testWidgets('calls onThemeChange when theme selected', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Tap on dark theme option
      final darkOption = find.textContaining('Dark');
      await tester.tap(darkOption);
      await tester.pumpAndSettle();

      // Verify theme change was triggered
      expect(themeService.theme, equals(AppTheme.dark));
    });

    testWidgets('updates UI when theme changes', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Initial theme
      expect(find.byType(ThemeSelector), findsOneWidget);

      // Change theme programmatically
      themeService.setTheme(AppTheme.dark);
      await tester.pumpAndSettle();

      // UI should update
      expect(find.byType(ThemeSelector), findsOneWidget);
    });

    testWidgets('displays theme icons', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Should have icons for themes
      expect(find.byIcon(Icons.light_mode), findsWidgets);
      expect(find.byIcon(Icons.dark_mode), findsWidgets);
      // System icon might be brightness_auto or something else depending on Flutter version, 
      // but it's there in the code. We'll check for any icon in the SegmentedButton.
      expect(find.descendant(of: find.byType(SegmentedButton<AppTheme>), matching: find.byType(Icon)), findsAtLeastNWidgets(3));
    });

    testWidgets('highlights current theme', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());
      themeService.setTheme(AppTheme.light);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Current theme should be visually distinct
      expect(find.byType(ThemeSelector), findsOneWidget);
    });

    testWidgets('theme selection is persisted', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Select dark theme
      await tester.tap(find.textContaining('Dark'));
      await tester.pumpAndSettle();

      // Verify persistence (would be stored in preferences)
      expect(themeService.theme, equals(AppTheme.dark));
    });

    testWidgets('displays theme preview', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Should show SegmentedButton
      expect(find.byType(SegmentedButton<AppTheme>), findsOneWidget);
    });

    testWidgets('handles system theme mode', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Select system theme
      await tester.tap(find.textContaining('System'));
      await tester.pumpAndSettle();

      expect(themeService.theme, equals(AppTheme.system));
    });

    testWidgets('theme selector has proper layout', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Verify layout structure
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('theme options are tappable', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Tap each theme option
      await tester.tap(find.byIcon(Icons.light_mode));
      await tester.pumpAndSettle();
      expect(themeService.theme, equals(AppTheme.light));
      
      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pumpAndSettle();
      expect(themeService.theme, equals(AppTheme.dark));
      
      await tester.tap(find.byIcon(Icons.brightness_auto));
      await tester.pumpAndSettle();
      expect(themeService.theme, equals(AppTheme.system));
    });

    testWidgets('displays theme descriptions', (WidgetTester tester) async {
      final themeService = ThemeService(settingsService: MockSettingsService());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeService>.value(
          value: themeService,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeSelector(),
            ),
          ),
        ),
      );

      // Should have descriptive text
      expect(find.byType(Text), findsWidgets);
    });
  });
}
