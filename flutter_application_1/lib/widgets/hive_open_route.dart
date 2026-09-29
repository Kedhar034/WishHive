import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Opening a hive: the tilted card tips flat toward you, lifts out of the
/// stack and becomes the page.
///
/// The card in the stack sits at 14° with a slight shrink, so the page starts
/// from the same pose and settles to flat on a spring. Closing runs shorter
/// and plainer, because a reverse of an overshoot reads as a wobble.
///
/// Motion values: spring stiffness 260, damping 26; close 380 ms; reduced
/// motion falls back to a plain 200 ms fade.
class HiveOpenRoute<T> extends PageRouteBuilder<T> {
  HiveOpenRoute({
    required WidgetBuilder builder,
    required bool reducedMotion,
  }) : super(
          transitionDuration:
              Duration(milliseconds: reducedMotion ? 200 : 560),
          reverseTransitionDuration:
              Duration(milliseconds: reducedMotion ? 200 : 380),
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            if (reducedMotion) {
              return FadeTransition(opacity: animation, child: child);
            }

            final settle = CurvedAnimation(
              parent: animation,
              curve: const _SpringCurve(stiffness: 260, damping: 26),
              reverseCurve: Curves.easeInCubic,
            );

            // The page is opaque well before it finishes settling, so the
            // spring is felt rather than watched.
            final fade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.45, curve: Curves.easeOut),
            );

            return AnimatedBuilder(
              animation: settle,
              builder: (context, inner) {
                final away = 1 - settle.value;
                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..translateByDouble(0, away * 26, 0, 1)
                  ..rotateX(away * 14 * math.pi / 180)
                  ..scaleByDouble(1 - away * 0.06, 1 - away * 0.06, 1, 1);

                return Transform(
                  transform: transform,
                  alignment: Alignment.bottomCenter,
                  child: inner,
                );
              },
              child: FadeTransition(opacity: fade, child: child),
            );
          },
        );
}

/// A damped spring sampled as a curve, so route transitions can use the same
/// motion values as the rest of the design without a physics simulation.
class _SpringCurve extends Curve {
  final double stiffness;
  final double damping;

  const _SpringCurve({required this.stiffness, required this.damping});

  static const double mass = 1;

  @override
  double transformInternal(double t) {
    final omega = math.sqrt(stiffness / mass);
    final zeta = damping / (2 * math.sqrt(stiffness * mass));

    // Real time the curve stands for. The spring has effectively settled by
    // then, so the tail is flat rather than clipped.
    final time = t * 0.6;

    if (zeta < 1) {
      final omegaD = omega * math.sqrt(1 - zeta * zeta);
      return 1 -
          math.exp(-zeta * omega * time) *
              (math.cos(omegaD * time) +
                  (zeta * omega / omegaD) * math.sin(omegaD * time));
    }
    // Critically damped, and near enough for the overdamped case too.
    return 1 - math.exp(-omega * time) * (1 + omega * time);
  }
}
