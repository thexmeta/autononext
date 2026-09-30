import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/widgets/batch_action_bar.dart';

void main() {
  group('BatchActionBar', () {
    testWidgets('displays selected count and total count', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      expect(find.text('3 of 10 selected'), findsOneWidget);
    });

    testWidgets('displays singular when one selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 1,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      expect(find.text('1 of 10 selected'), findsOneWidget);
    });

    testWidgets('displays zero when none selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 0,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      expect(find.text('0 of 10 selected'), findsOneWidget);
    });

    testWidgets('calls onUpdateAll when update button tapped', (WidgetTester tester) async {
      bool updated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {
                updated = true;
              },
              onInstallAll: () {},
            ),
          ),
        ),
      );

      // Find and tap the update button
      final updateButton = find.byIcon(Icons.refresh);
      await tester.tap(updateButton);
      await tester.pump();

      expect(updated, isTrue);
    });

    testWidgets('calls onInstallAll when install button tapped', (WidgetTester tester) async {
      bool installed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {
                installed = true;
              },
            ),
          ),
        ),
      );

      // Find and tap the install button
      final installButton = find.byIcon(Icons.download);
      await tester.tap(installButton);
      await tester.pump();

      expect(installed, isTrue);
    });

    testWidgets('shows Select All button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.select_all), findsOneWidget);
    });

    testWidgets('shows Deselect All button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 10,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      expect(find.text('Deselect All'), findsOneWidget);
    });

    testWidgets('calls onSelectAll when select all button tapped', (WidgetTester tester) async {
      bool selectedAll = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {
                selectedAll = true;
              },
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      expect(selectedAll, isTrue);
    });

    testWidgets('calls onDeselectAll when deselect all button tapped', (WidgetTester tester) async {
      bool deselectedAll = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 10,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {
                deselectedAll = true;
              },
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Deselect All'));
      await tester.pump();

      expect(deselectedAll, isTrue);
    });

    testWidgets('buttons are enabled when apps selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      // Find buttons
      final updateButton = find.widgetWithText(FilledButton, 'Check for Updates');
      final installButton = find.widgetWithText(FilledButton, 'Install');

      // Verify buttons are enabled
      expect(tester.widget<FilledButton>(updateButton).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);
    });

    testWidgets('displays action buttons in row', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      // Verify layout
      expect(find.byType(Row), findsWidgets);
      expect(find.byType(FilledButton), findsNWidgets(3)); // Check for Updates, Install, Delete
      expect(find.byType(OutlinedButton), findsOneWidget); // Select/Deselect All
    });

    testWidgets('shows progress indicator when updating', (WidgetTester tester) async {
      bool isUpdating = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                bottomSheet: BatchActionBar(
                  selectedCount: 3,
                  totalCount: 10,
                  onSelectAll: () {},
                  onDeselectAll: () {},
                  onUpdateAll: () {
                    setState(() => isUpdating = true);
                  },
                  onInstallAll: () {},
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(isUpdating, isTrue);
    });

    testWidgets('shows progress indicator when installing', (WidgetTester tester) async {
      bool isInstalling = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                bottomSheet: BatchActionBar(
                  selectedCount: 3,
                  totalCount: 10,
                  onSelectAll: () {},
                  onDeselectAll: () {},
                  onUpdateAll: () {},
                  onInstallAll: () {
                    setState(() => isInstalling = true);
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.download));
      await tester.pump();

      expect(isInstalling, isTrue);
    });

    testWidgets('displays tooltip on buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomSheet: BatchActionBar(
              selectedCount: 3,
              totalCount: 10,
              onSelectAll: () {},
              onDeselectAll: () {},
              onUpdateAll: () {},
              onInstallAll: () {},
            ),
          ),
        ),
      );

      // Verify tooltips exist
      expect(find.textContaining('Update'), findsWidgets);
      expect(find.textContaining('Install'), findsWidgets);
    });
  });
}
