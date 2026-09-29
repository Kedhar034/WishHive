// The design rules that are easy to break silently.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_theme.dart';
import 'package:flutter_application_1/core/utils/money.dart';
import 'package:flutter_application_1/widgets/hive_card.dart';
import 'package:flutter_application_1/widgets/hive_stack.dart';
import 'package:flutter_application_1/widgets/hive_title.dart';

void main() {
  group('AppTheme.tintFor', () {
    test('is stable for the same id', () {
      expect(AppTheme.tintFor('hive-123'), AppTheme.tintFor('hive-123'));
    });

    test('only ever returns one of the four card tints', () {
      for (var i = 0; i < 200; i++) {
        expect(AppTheme.cardTints, contains(AppTheme.tintFor('hive-$i')));
      }
    });

    test('spreads across all four tints', () {
      final seen = {for (var i = 0; i < 200; i++) AppTheme.tintFor('hive-$i')};
      expect(seen.length, 4);
    });

    test('an empty id still yields a tint', () {
      expect(AppTheme.cardTints, contains(AppTheme.tintFor('')));
    });
  });

  group('formatMoney', () {
    // Indian grouping: lakhs, not thousands.
    test('groups in the Indian style', () {
      expect(formatMoney(139950), '₹1,39,950');
      expect(formatMoney(42500), '₹42,500');
      expect(formatMoney(0), '₹0');
    });

    test('drops the paise', () {
      expect(formatMoney(2499.75), '₹2,500');
    });
  });

  group('HiveTitle', () {
    testWidgets('puts the serif accent on the last word only', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HiveTitle('Your hives')),
      ));

      final rich = tester.widget<Text>(find.byType(Text));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();

      expect(spans.first.text, 'Your ');
      expect(spans.first.style?.fontFamily, isNot(AppTheme.serifFamily));
      expect(spans.last.text, 'hives');
      expect(spans.last.style?.fontFamily, AppTheme.serifFamily);
      expect(spans.last.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('a single word is entirely the accent', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HiveTitle('Hives')),
      ));

      final rich = tester.widget<Text>(find.byType(Text));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.single.text, 'Hives');
      expect(spans.single.style?.fontFamily, AppTheme.serifFamily);
    });
  });

  group('HiveCard', () {
    Future<void> pump(WidgetTester tester, Widget card) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SizedBox(width: 340, child: card)),
      ));
      await tester.pump();
    }

    testWidgets('a row card shows name, count and money', (tester) async {
      await pump(tester, const HiveCard(
        title: 'Gaming Setup',
        items: 13,
        price: 42500,
        imageUrl: '',
        tintSeed: 'h1',
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Gaming Setup'), findsOneWidget);
      expect(find.text('13 wishes'), findsOneWidget);
      expect(find.text('₹42,500'), findsOneWidget);
    });

    testWidgets('a blue card takes white text, a tinted one takes ink',
        (tester) async {
      expect(AppTheme.onColor(AppTheme.brandBlue), Colors.white);
      for (final tint in AppTheme.cardTints) {
        if (tint == AppTheme.brandBlue) continue;
        expect(AppTheme.onColor(tint), AppTheme.ink);
      }
    });

    testWidgets('a picked colour overrides the id-derived tint',
        (tester) async {
      expect(AppTheme.colorFor('butter', 'anything'), AppTheme.tintButter);
      expect(AppTheme.colorFor(null, 'h1'), AppTheme.tintFor('h1'));
      expect(AppTheme.colorFor('', 'h1'), AppTheme.tintFor('h1'));
      expect(AppTheme.colorFor('nonsense', 'h1'), AppTheme.tintFor('h1'));
    });

    // A free pick from the wheel is stored as hex beside the named presets.
    testWidgets('a free colour survives a round trip', (tester) async {
      const chosen = Color(0xFF7ED6A5);
      final key = AppTheme.keyForColor(chosen);

      expect(key, '#7ed6a5');
      expect(AppTheme.colorFor(key, 'h1').toARGB32(), chosen.toARGB32());
    });

    testWidgets('a preset is stored by name, not as hex', (tester) async {
      expect(AppTheme.keyForColor(AppTheme.tintBlush), 'blush');
      expect(AppTheme.keyForColor(AppTheme.brandBlue), 'blue');
    });

    testWidgets('a malformed hex falls back instead of throwing',
        (tester) async {
      expect(AppTheme.parseHex('#12345'), isNull);
      expect(AppTheme.parseHex('#zzzzzz'), isNull);
      expect(AppTheme.colorFor('#zzzzzz', 'h1'), AppTheme.tintFor('h1'));
    });

    testWidgets('one wish is singular', (tester) async {
      await pump(tester, const HiveCard(
        title: 'Books', items: 1, price: 300, imageUrl: '', tintSeed: 'h2'));
      expect(find.text('1 wish'), findsOneWidget);
    });

    // The owner is shown, but never who reserved what.
    testWidgets('a compact card shows only the owner first name',
        (tester) async {
      await pump(tester, const SizedBox(
        height: 176,
        child: HiveCard(
          title: 'Birthday wishes',
          items: 11,
          price: 32400,
          imageUrl: '',
          ownerName: 'Ananya Sharma',
          isCompact: true,
          tintSeed: 'h3',
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.text('Ananya Sharma'), findsNothing);
    });

  });

  group('HiveDeck', () {
    Future<void> pumpDeck(WidgetTester tester, int count,
        void Function(int index, double collapse) record) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: HiveDeck(
              itemCount: count,
              builder: (context, index, collapse) {
                record(index, collapse);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    // The deck lays its slots out against the card height. If these drift
    // apart the cards either gap or overlap by the wrong amount.
    testWidgets('slot geometry matches the card height', (tester) async {
      const deck = HiveDeck(itemCount: 0, builder: _noCard);
      expect(deck.cardHeight, HiveCard.wideHeight);
      expect(deck.slot, lessThan(deck.cardHeight),
          reason: 'cards must overlap, not gap');
    });

    // No pile until a card has actually curled into it, or there would be a
    // permanent empty band under the heading.
    testWidgets('the pile takes no room until a card pins', (tester) async {
      const deck = HiveDeck(itemCount: 5, builder: _noCard);
      expect(deck.pileHeightAt(0), 0);
      expect(deck.pileHeightAt(1), greaterThan(0));
      // And it stops growing once the pile is full.
      expect(deck.pileHeightAt(20), closeTo(deck.pileHeightAt(deck.maxSteps), 0.01));
    });

    // The deck overlaps cards, so anything below the slot height is covered by
    // the next card. The amount has to stay above that line.
    testWidgets('the amount stays inside the visible band', (tester) async {
      const deck = HiveDeck(itemCount: 0, builder: _noCard);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: HiveCard(
                title: 'Birthday Wishlist',
                items: 4,
                price: 31685,
                imageUrl: '',
                tintSeed: 'h1'),
          ),
        ),
      ));
      await tester.pump();

      final card = tester.getRect(find.byType(HiveCard));
      final money = tester.getRect(find.text('₹31,685'));
      expect(money.bottom, lessThanOrEqualTo(card.top + deck.slot));
    });

    // Mid-collapse the two card layouts must not both be on screen: the strip
    // puts its title where the full layout puts its cover, so an overlap reads
    // as a ghost of the card printed over itself.
    testWidgets('only one card layout is visible at any point', (tester) async {
      for (final collapse in [0.0, 0.3, 0.5, 0.7, 1.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              // The deck always gives a card its full height; a shorter box
              // would overflow the full layout and mask what is being tested.
              height: HiveCard.wideHeight,
              width: 400,
              child: HiveCard(
                  title: 'Gaming Setup',
                  items: 3,
                  price: 42500,
                  imageUrl: '',
                  tintSeed: 'h1',
                  collapse: collapse),
            ),
          ),
        ));
        await tester.pump();

        final layers = tester
            .widgetList<Opacity>(find.byType(Opacity))
            .where((o) => o.opacity > 0.02)
            .length;
        expect(layers, lessThanOrEqualTo(1), reason: 'collapse=$collapse');
      }
    });

    testWidgets('every card starts uncollapsed at rest', (tester) async {
      final seen = <int, double>{};
      await pumpDeck(tester, 6, (i, c) => seen[i] = c);

      expect(tester.takeException(), isNull);
      expect(seen[0], 0);
      expect(seen.values.every((c) => c == 0), isTrue);
    });

    // Scrolling one slot must pin exactly one card, not sweep it off screen.
    testWidgets('a card collapses once it passes the top', (tester) async {
      final seen = <int, double>{};
      await pumpDeck(tester, 8, (i, c) => seen[i] = c);

      // One slot exactly, read from the deck so this cannot drift when the
      // geometry is retuned. touchSlopY: 0 maps the drag 1:1 to scroll
      // offset; the default slop would swallow the first 18 logical pixels.
      final slot = tester.widget<HiveDeck>(find.byType(HiveDeck)).slot;
      await tester.drag(find.byType(HiveDeck), Offset(0, -slot),
          touchSlopY: 0);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(seen[0], closeTo(1.0, 0.01), reason: 'first card fully collapsed');
      expect(seen[1], closeTo(0.0, 0.01), reason: 'second card still full');
    });

    testWidgets('an empty deck renders nothing and does not throw',
        (tester) async {
      await pumpDeck(tester, 0, (_, __) {});
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _noCard(BuildContext context, int index, double collapse) =>
    const SizedBox.shrink();
