import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_iphone/main.dart';

void main() {
  testWidgets('414Unlock iPhone app initializes and displays loading-only prerequisite screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UnlockIPhoneApp());

    // Initially displays 414 logo and wordmark
    expect(find.text('414'), findsWidgets);
    expect(find.text('unlock'), findsOneWidget);
    expect(find.text('IPHONE DEVICE UTILITY'), findsOneWidget);

    // Advance time past the splash animation
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 600));

    // Displays the minimal loading-only requirement screen
    expect(find.text('Loading 414Unlock engine'), findsOneWidget);
    expect(find.text('Checking requirements'), findsOneWidget);
    expect(find.text('Windows System Environment'), findsOneWidget);
    expect(find.text('Apple Device Communication'), findsOneWidget);
    expect(find.text('414Unlock Engine'), findsOneWidget);

    // Verify partner-tool details are NOT shown on startup screen
    expect(find.text('iRemove for Windows'), findsNothing);
    expect(find.text('iRemove Tools'), findsNothing);

    // Pump past timers to cleanly drain test harness
    await tester.pump(const Duration(seconds: 2));
  });
}
