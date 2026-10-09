import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A small pill offering to fetch what the free scraper could not read.
///
/// It pulses a few times when it first appears so it is noticed, then stays
/// still — a control that keeps moving reads as an ad. While loading it says
/// how long to expect, because a silent wait of fifteen seconds feels broken.
class FetchDetailsChip extends StatefulWidget {
  final String label;
  final String? hint;
  final bool loading;
  final String loadingLabel;
  final VoidCallback? onTap;
  final IconData icon;

  const FetchDetailsChip({
    super.key,
    required this.label,
    this.hint,
    this.loading = false,
    this.loadingLabel = 'Fetching details… this can take up to 20 seconds',
    this.onTap,
    this.icon = Icons.auto_awesome,
  });

  @override
  State<FetchDetailsChip> createState() => _FetchDetailsChipState();
}

class _FetchDetailsChipState extends State<FetchDetailsChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _playPulse();
  }

  Future<void> _playPulse() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    for (var i = 0; i < 3 && mounted; i++) {
      await _pulse.forward(from: 0);
      if (!mounted) return;
      await _pulse.reverse();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.brandBlue;

    final pill = AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_pulse.value);
        return Transform.scale(
          scale: 1 + 0.05 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35 * t),
                  blurRadius: 14 * t,
                  spreadRadius: 1.5 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: color.withValues(alpha: 0.10),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.loading ? null : widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.loading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                else
                  Icon(widget.icon, size: 16, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.loading ? widget.loadingLabel : widget.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: widget.loading ? widget.loadingLabel : widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          pill,
          if (widget.hint != null && !widget.loading)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                widget.hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
