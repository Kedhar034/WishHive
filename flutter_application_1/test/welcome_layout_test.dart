// Layout guard for the welcome screen.
//
// The panel must never grow past its cap, or the background photo it sits on
// stops being visible. Note that widget tests render with a placeholder font
// whose glyphs are wider than Figtree, so real heights come out slightly
// smaller than these.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/pages/welcome_page.dart';

void main() {
  const sizes = [Size(320, 568), Size(360, 640), Size(411, 780)];

  for (final size in sizes) {
    testWidgets('panel stays within its cap at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: WelcomePage()));
      await tester.pump();

      // Any overflow surfaces here rather than as a silent yellow banner.
      expect(tester.takeException(), isNull);

      final panel = tester.getRect(find.byType(SingleChildScrollView));
      expect(panel.height, lessThanOrEqualTo(size.height * 0.52 + 0.5));
    });
  }

  testWidgets('both sign-in options and the sign-up link are present',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));
    await tester.pump();

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Login with Email'), findsOneWidget);
    expect(find.textContaining('Sign Up', findRichText: true), findsOneWidget);
  });
}
