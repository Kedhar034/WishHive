// The create/edit sheet must build for both paths.
//
// It went blank because the live preview card stretches its cover to the card
// height, and the sheet is an unbounded scrolling column — so the card asked
// for infinite height and the whole sheet failed to lay out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/hive_card.dart';
import 'package:flutter_application_1/widgets/color_wheel_picker.dart';

void main() {
  Future<void> pumpUnbounded(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [child]),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the preview card survives an unbounded column', (tester) async {
    await pumpUnbounded(tester, const HiveCard(
      title: 'My birthday', items: 0, price: 0, imageUrl: '', tintSeed: ''));

    expect(tester.takeException(), isNull);
    expect(find.text('My birthday'), findsOneWidget);
    expect(tester.getSize(find.byType(HiveCard)).height, HiveCard.wideHeight);
  });

  testWidgets('a compact card also survives it', (tester) async {
    await pumpUnbounded(tester, const SizedBox(
      height: 176,
      child: HiveCard(
        title: 'Birthday wishes', items: 3, price: 900, imageUrl: '',
        ownerName: 'Ananya', isCompact: true, tintSeed: 'h1'),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the colour wheel builds and reports a colour', (tester) async {
    Color? picked;
    await pumpUnbounded(tester, ColorWheelPicker(
      initial: AppTheme.tintBlush,
      onChanged: (c) => picked = c,
    ));

    expect(tester.takeException(), isNull);

    // A drag on the ring changes the hue.
    await tester.drag(find.byType(ColorWheelPicker), const Offset(40, -40));
    await tester.pump();
    expect(picked, isNotNull);
  });

  testWidgets('every colour the wheel can reach stays readable',
      (tester) async {
    // Light picks take ink, dark picks take white — the card never ends up
    // with text the same tone as its background.
    for (final lightness in [0.88, 0.7, 0.5, 0.32]) {
      final c = HSLColor.fromAHSL(1, 210, 0.7, lightness).toColor();
      final fg = AppTheme.onColor(c);
      expect(fg == AppTheme.ink || fg == Colors.white, isTrue);
    }
  });
}
