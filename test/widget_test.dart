// Basic widget test for Be@Mandaluyong.
//
// Verifies the app starts on the welcome screen with Log in / Create account.

import 'package:flutter_test/flutter_test.dart';

import 'package:be_mandaluyong/main.dart';

void main() {
  testWidgets('App starts on the welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BeMandaluyongApp());

    // App title and the two entry points are visible.
    expect(find.text('Be@Mandaluyong'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);

    // Tapping "Log in" opens the login screen.
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
