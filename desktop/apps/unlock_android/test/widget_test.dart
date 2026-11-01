import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_android/main.dart';

void main() {
  testWidgets('414Unlock Android app initializes and displays startup animation',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const UnlockAndroidApp());

    // Initially displays 414 logo
    expect(find.text('414'), findsOneWidget);
    expect(find.text('unlock'), findsOneWidget);
    expect(find.text('ANDROID DEVICE UTILITY'), findsOneWidget);

    // Advance time past the splash animation
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 600));

    // After animation, displays the Prerequisite Check screen
    expect(find.text("Let's check your PC"), findsOneWidget);
    expect(find.text('414'), findsOneWidget);
    expect(find.text('Android Device Utility'), findsOneWidget);

    // Pump past the async timeout timer to drain pending timers
    await tester.pump(const Duration(seconds: 5));
  });
}
