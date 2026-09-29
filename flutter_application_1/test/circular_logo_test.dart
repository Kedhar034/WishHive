// The logo must stay circular regardless of what its parent imposes.
//
// The auth pages lay it out inside a Column with CrossAxisAlignment.stretch,
// which forced it to full width and cropped the square artwork into an ellipse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/circular_logo.dart';

void main() {
  Future<Size> logoSize(WidgetTester tester, Widget parent) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: parent)));
    await tester.pump();
    return tester.getSize(find.byType(ClipOval));
  }

  testWidgets('stays square inside a stretching Column', (tester) async {
    final size = await logoSize(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [CircularLogo(size: 100)],
      ),
    );
    expect(size, const Size(100, 100));
  });

  testWidgets('stays square inside a full-width SizedBox', (tester) async {
    final size = await logoSize(
      tester,
      const SizedBox(width: double.infinity, child: CircularLogo(size: 64)),
    );
    expect(size, const Size(64, 64));
  });

  testWidgets('stays square in a Row, where nothing stretches it',
      (tester) async {
    final size = await logoSize(
      tester,
      const Row(children: [CircularLogo(size: 42)]),
    );
    expect(size, const Size(42, 42));
  });
}
