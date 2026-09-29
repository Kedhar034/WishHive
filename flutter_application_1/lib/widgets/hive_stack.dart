import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A sticky stacked-card deck that curves away at the top.
///
/// Cards scroll normally until they reach the top of the deck, where each one
/// pins instead of leaving: it collapses to a title strip and leans back onto
/// a cylinder, so the pile above the reading area reads as a wheel receding
/// into the screen rather than as a flat list of headers. The next card slides
/// over the one collapsing, and a fresh card rises into view from the bottom.
///
/// Each pinned card sits one [anglePerCard] step further around a cylinder of
/// radius [wheelRadius]. Its offset is the chord of that arc, which is why the
/// strips bunch closer together the further back they go instead of marching
/// up at a constant spacing — the same foreshortening a real wheel gives.
///
/// The scroll offset drives everything. Layout stays a plain fixed-extent list
/// — one [slot] per card — and every card is moved into place with a
/// transform, so nothing ever changes height underneath the drag.
class HiveDeck extends StatefulWidget {
  final int itemCount;

  /// Builds one card. [collapse] runs 0 for a full card to 1 for one fully
  /// collapsed into the pile at the top.
  final Widget Function(BuildContext context, int index, double collapse)
      builder;

  /// Scroll distance from one card to the next.
  final double slot;

  /// Height of a card before it starts collapsing.
  final double cardHeight;

  /// Height of a fully collapsed card.
  final double stripHeight;

  /// Radius of the cylinder the pinned cards curve around. Larger is flatter.
  final double wheelRadius;

  /// How far around that cylinder each card steps as it pins, in degrees.
  final double anglePerCard;

  /// How many strips stay visible before the oldest fade out behind the rest.
  final int maxStrips;

  const HiveDeck({
    super.key,
    required this.itemCount,
    required this.builder,
    this.slot = 116,
    this.cardHeight = 156,
    this.stripHeight = 46,
    this.wheelRadius = 96,
    this.anglePerCard = 13,
    this.maxStrips = 4,
  });

  /// How much narrower each card gets per step around the wheel.
  static const double _shrinkPerStep = 0.055;

  /// Without this the rotation reads as a vertical squash, not a lean.
  static const double _perspective = 0.0016;

  /// The furthest a card travels up the arc before the pile stops growing.
  double get maxSteps => maxStrips + 1;

  /// Height the pile occupies once `steps` cards have curled into it. The deck
  /// pushes everything down by this much, so the pile takes up no room at all
  /// until a card has actually pinned — reserving it up front would leave a
  /// permanent gap under the heading.
  double pileHeightAt(double steps) =>
      wheelRadius * math.sin(math.min(steps, maxSteps) * anglePerCard * math.pi / 180);

  @override
  State<HiveDeck> createState() => _HiveDeckState();
}

class _HiveDeckState extends State<HiveDeck> {
  final ScrollController _controller = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    setState(() => _offset = _controller.offset);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      // Pinned strips are drawn far above their own slot, so those slots have
      // to stay built or the pile would blink out as it scrolls away.
      cacheExtent: widget.slot * (widget.maxStrips + 2),
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(bottom: widget.cardHeight),
      itemCount: widget.itemCount,
      itemExtent: widget.slot,
      itemBuilder: (context, index) {
        // How far this card has travelled past the top of the deck, in slots.
        // Zero or less means it is still scrolling normally.
        final page = _offset / widget.slot;
        final rel = page - index;

        // The pile grows as cards curl into it, and everything else is pushed
        // down to make room, so there is no gap before the first one pins.
        final pile = widget.pileHeightAt(math.max(page, 0));

        if (rel <= 0) {
          return Transform.translate(
            offset: Offset(0, pile),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: widget.cardHeight,
              child: SizedBox(
                height: widget.cardHeight,
                child: widget.builder(context, index, 0),
              ),
            ),
          );
        }

        final collapse = rel.clamp(0.0, 1.0);
        final height = widget.cardHeight +
            (widget.stripHeight - widget.cardHeight) * collapse;

        // How far around the wheel this card has turned. Capped so the oldest
        // strips settle instead of folding through themselves.
        final steps = math.min(rel, widget.maxSteps);
        final angle = steps * widget.anglePerCard * math.pi / 180;

        // Where the slot puts it, versus where the wheel wants it: measured
        // down from the top of the pile rather than from the viewport, so the
        // strips stay put as the pile below them grows.
        final naturalTop = -rel * widget.slot;
        final wheelTop = pile - widget.pileHeightAt(rel);

        final scale = 1 - steps * HiveDeck._shrinkPerStep;
        final fade = (1 - (rel - widget.maxStrips)).clamp(0.0, 1.0);

        final transform = Matrix4.identity()
          ..setEntry(3, 2, HiveDeck._perspective)
          ..translateByDouble(0, wheelTop - naturalTop, 0, 1)
          ..rotateX(angle)
          ..scaleByDouble(scale, scale, 1, 1);

        return Transform(
          transform: transform,
          // The card hangs from where it pinned and leans back from there, so
          // its top edge stays put on the arc and the body foreshortens away
          // below it. Hinging on the bottom edge instead drags the top down
          // as the lean deepens, which inverts the order of the pile.
          alignment: Alignment.topCenter,
          child: Opacity(
            opacity: fade,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: widget.cardHeight,
              child: SizedBox(
                height: height,
                child: widget.builder(context, index, collapse),
              ),
            ),
          ),
        );
      },
    );
  }
}
