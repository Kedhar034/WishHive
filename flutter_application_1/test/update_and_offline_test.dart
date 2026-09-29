// Two things users see when something is wrong: the update prompt and the
// offline bar. Both were carrying the old brand or did not exist.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_theme.dart';
import 'package:flutter_application_1/services/update_service.dart';
import 'package:flutter_application_1/widgets/offline_banner.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, {required bool force}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => UpdateService.showUpdateDialog(context, force: force),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  group('update dialog', () {
    testWidgets('a soft update can be dismissed', (tester) async {
      await openDialog(tester, force: false);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Update available', findRichText: true),
          findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsNothing);
    });

    // A forced update must have no way past it, including the back gesture.
    testWidgets('a forced update offers no way out', (tester) async {
      await openDialog(tester, force: true);

      expect(find.textContaining('Update required', findRichText: true),
          findsOneWidget);
      expect(find.text('Not now'), findsNothing);

      await tester.tapAt(const Offset(10, 10)); // outside the dialog
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsOneWidget,
          reason: 'barrier must not dismiss a forced update');
    });
  });

  group('offline banner', () {
    testWidgets('stays out of the way when connectivity is unknown',
        (tester) async {
      // No platform channel under test, so the plugin errors — which must be
      // treated as online rather than falsely reporting offline.
      await tester.pumpWidget(const MaterialApp(
        home: OfflineBanner(
          child: Scaffold(body: Center(child: Text('app'))),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('app'), findsOneWidget);

      final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
      expect(slide.offset, const Offset(0, 1), reason: 'bar should be hidden');
    });

    testWidgets('never blocks taps on the app beneath', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: OfflineBanner(
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('tap me'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('tap me'));
      expect(taps, 1);
    });
  });
}
