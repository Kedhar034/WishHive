import 'dart:async';

import 'package:flutter/material.dart';

import '../splash/wishhive_splash.dart';

/// Plays the launch animation, then hands over to [child].
///
/// The animation is real Flutter — layered artwork moved by transforms — not a
/// video. That matters: a video depends on the device having a working H.264
/// decoder, and when it does not, the splash freezes on its first frame. This
/// draws on the same frame loop as the rest of the app, so it renders on every
/// device, stays sharp at any resolution, and reflows for any screen shape.
///
/// It is still never a gate. If anything goes wrong, or the device asks for
/// reduced motion, the app shows through immediately, and a hard cap lifts it
/// regardless. A splash that can trap someone outside their own app is worse
/// than no splash at all.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  /// Longest the animation may hold the app back, whatever happens. The
  /// timeline itself runs to roughly 3.5s.
  static const Duration _cap = Duration(seconds: 5);

  static const Duration _fade = Duration(milliseconds: 420);

  /// The colour the animation opens on, so there is no flash on either side.
  static const Color background = Color(0xFF050A1C);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _capTimer;
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _finish();
      return;
    }

    _capTimer = Timer(SplashGate._cap, _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _capTimer?.cancel();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _capTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The app is built underneath from the first frame, so it finishes its
        // own startup work while the animation plays and there is no second
        // loading state afterwards.
        widget.child,

        IgnorePointer(
          ignoring: _done,
          child: AnimatedOpacity(
            opacity: _done ? 0 : 1,
            duration: SplashGate._fade,
            curve: Curves.easeOut,
            child: ColoredBox(
              color: SplashGate.background,
              child: _done
                  ? const SizedBox.expand()
                  : WishHiveSplash(onFinished: _finish),
            ),
          ),
        ),
      ],
    );
  }
}
