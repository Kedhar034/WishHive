import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A slim bar that appears when the device drops off the network.
///
/// Firestore keeps an offline cache, so the app still shows the hives and
/// wishes it already had — this only tells you that what you are looking at is
/// saved rather than live. It never blocks anything.
///
/// Note this reports the *network interface*, not reachability: joined to Wi-Fi
/// with no working internet still counts as connected. It is a hint, which is
/// why nothing depends on it.
class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  Future<void> _watch() async {
    final connectivity = Connectivity();
    try {
      _apply(await connectivity.checkConnectivity());
    } catch (_) {
      // An unavailable platform channel must not make the app look offline.
    }
    // A stream error here would otherwise go unhandled and take down the
    // zone. An unknown connectivity state is treated as online, because
    // wrongly claiming to be offline is the worse failure.
    _sub = connectivity.onConnectivityChanged.listen(
      _apply,
      onError: (Object e) => debugPrint('OfflineBanner: $e'),
    );
  }

  void _apply(List<ConnectivityResult> results) {
    final offline = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (offline != _offline && mounted) setState(() => _offline = offline);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedSlide(
              offset: _offline ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _offline ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: AppTheme.ink,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'You are offline — showing saved hives',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
