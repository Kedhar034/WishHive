import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A screen title where exactly one word carries the serif italic accent.
///
/// The accent is always the last word — "Your *hives*", "Friends' *hives*",
/// "New *hive*" — and is never used anywhere else, or it stops reading as an
/// accent at all.
class HiveTitle extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final TextAlign align;

  const HiveTitle(
    this.text, {
    super.key,
    this.size = 34,
    this.color,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).textTheme.headlineLarge?.color ?? AppTheme.ink;
    final cut = text.trimRight().lastIndexOf(' ');
    final lead = cut == -1 ? '' : text.substring(0, cut + 1);
    final accent = cut == -1 ? text : text.substring(cut + 1);

    return Text.rich(
      TextSpan(
        children: [
          if (lead.isNotEmpty) TextSpan(text: lead),
          TextSpan(text: accent, style: AppTheme.serif(size: size, color: tone)),
        ],
      ),
      textAlign: align,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w300,
        height: 1.1,
        letterSpacing: size >= 40 ? -1.8 : -1.2,
        color: tone,
      ),
    );
  }
}
