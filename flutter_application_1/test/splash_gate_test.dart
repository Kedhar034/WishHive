// The splash must never be able to trap someone outside their own app.
//
// The animation is real Flutter rather than a video, so there is no decoder to
// fail — but it still has to lift on its own, respect reduced motion, and stop
// intercepting touches once it is gone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/pages/splash_gate.dart';
import 'package:flutter_application_1/splash/wishhive_splash.dart';

void main() {
  const app = Text('app', textDirection: TextDirection.ltr);

  double overlayOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('the app is built underneath from the first frame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashGate(child: app)));
    await tester.pump();

    // Present in the tree immediately, so startup work overlaps the animation
    // and there is no second loading state when the splash lifts.
    expect(find.text('app'), findsOneWidget);
    expect(overlayOpacity(tester), 1, reason: 'splash should cover at first');
  });

  testWidgets('the animation lifts on its own', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashGate(child: app)));
    await tester.pump();

    // Part way through, it is still covering.
    await tester.pump(const Duration(seconds: 1));
    expect(overlayOpacity(tester), 1);

    // The timeline runs to roughly 3.5s, and a cap catches anything longer.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(overlayOpacity(tester), 0, reason: 'splash should have lifted');
  });

  testWidgets('reduced motion skips it entirely', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: SplashGate(child: app)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(overlayOpacity(tester), 0);
  });

  testWidgets('it stops swallowing taps once it lifts', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: SplashGate(
        child: Center(
          child: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('tap me'),
          ),
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('tap me'));
    expect(taps, 1);
  });

  // The splash lifting is not on its own proof the artwork moved: the cap in
  // SplashGate would lift it either way. This drives the animation widget
  // directly, so onFinished can only fire if its timeline actually advanced.
  testWidgets('the animation timeline runs to completion', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WishHiveSplash(
          holdAfter: const Duration(milliseconds: 100),
          onFinished: () => finished = true,
        ),
      ),
    ));

    await tester.pump();
    expect(finished, isFalse, reason: 'should not finish on the first frame');

    await tester.pump(const Duration(seconds: 1));
    expect(finished, isFalse, reason: 'timeline is longer than a second');

    // The documented timeline is about 3.0s plus the hold.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(finished, isTrue, reason: 'timeline should have completed');
  });
}
