import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Pull-to-refresh used across the app, so the gesture and the spinner look the
/// same everywhere.
///
/// Most screens are already live — Firestore pushes changes as they happen —
/// so this is a manual fallback and a way to show the user that something
/// refreshed, rather than the primary update mechanism.
class AppRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  /// Extra top inset when the list sits under a transparent app bar.
  final double displacement;

  const AppRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        // A short floor so the spinner is actually seen. Without it a cached
        // response returns instantly and the gesture looks like it did nothing.
        await Future.wait([
          onRefresh(),
          Future<void>.delayed(const Duration(milliseconds: 550)),
        ]);
      },
      displacement: displacement,
      strokeWidth: 2.6,
      color: AppTheme.brandBlue,
      backgroundColor: theme.cardColor,
      child: child,
    );
  }
}
