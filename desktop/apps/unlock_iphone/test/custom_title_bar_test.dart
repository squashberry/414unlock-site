import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_iphone/widgets/close_confirmation_dialog.dart';
import 'package:unlock_iphone/widgets/custom_title_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom Title Bar & Close Interception Tests', () {
    testWidgets('CustomTitleBar renders branding and window controls', (WidgetTester tester) async {
      bool closeRequested = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CustomTitleBar(
                  onCloseRequested: () {
                    closeRequested = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Verify titlebar branding
      expect(find.text('414Unlock'), findsOneWidget);
      expect(find.text('— iPhone Device Utility'), findsOneWidget);

      // Verify macOS traffic light window controls
      expect(find.byTooltip('Close 414Unlock'), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Zoom Window'), findsOneWidget);

      // Verify utility toolbar buttons
      expect(find.byTooltip('Help & Support (Online Guide)'), findsOneWidget);
      expect(find.byTooltip('Diagnostics & Logs'), findsOneWidget);
      expect(find.byTooltip('Settings & Appearance'), findsOneWidget);

      // Click close button
      await tester.tap(find.byTooltip('Close 414Unlock'));
      await tester.pumpAndSettle();

      expect(closeRequested, isTrue);
    });

    testWidgets('CloseConfirmationDialog renders (Close) and (Minimize) options',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => CloseConfirmationDialog.show(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog title and message
      expect(find.text('Close 414Unlock?'), findsOneWidget);
      expect(
        find.textContaining('Are you sure you want to close 414Unlock, or would you rather minimize it'),
        findsOneWidget,
      );

      // Verify the two explicit actions: Close and Minimize
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Minimize'), findsOneWidget);

      // Test tapping Minimize
      await tester.tap(find.text('Minimize'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Close 414Unlock?'), findsNothing);
    });

    testWidgets('CloseConfirmationDialog Close button dismisses dialog cleanly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => CloseConfirmationDialog.show(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Test tapping Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Close 414Unlock?'), findsNothing);
    });
  });
}
