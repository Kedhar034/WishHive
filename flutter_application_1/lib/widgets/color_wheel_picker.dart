import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A hue ring with a shade slider, for choosing a hive card colour.
///
/// Hue comes from the angle around the ring and shade from the slider, which
/// runs from a pale tint at one end to a deep tone at the other. Card text
/// picks itself from the background luminance, so both ends stay readable;
/// the slider stops short of black and white, where nothing would.
class ColorWheelPicker extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  final double size;

  const ColorWheelPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.size = 180,
  });

  /// Ring thickness as a fraction of the radius.
  static const double _ringFraction = 0.28;

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late double _hue;
  late double _shade;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.initial);
    _hue = hsl.hue;
    // Recover the slider position from the lightness the colour came in with.
    _shade = ((_lightest - hsl.lightness) / (_lightest - _darkest)).clamp(0.0, 1.0);
  }

  /// The pale end of the slider, matching the four preset tints.
  static const double _lightest = 0.88;

  /// The deep end. Stops above black so text still has somewhere to go.
  static const double _darkest = 0.30;

  /// Lightness and saturation move together, so the pale end stays a soft tint
  /// and the deep end stays a rich colour rather than a muddy grey.
  Color get _color => HSLColor.fromAHSL(
        1,
        _hue,
        0.50 + _shade * 0.32,
        _lightest - _shade * (_lightest - _darkest),
      ).toColor();

  void _emit() => widget.onChanged(_color);

  void _handleRing(Offset local) {
    final centre = Offset(widget.size / 2, widget.size / 2);
    final v = local - centre;
    if (v.distance < 1) return;
    // atan2 measures from the positive x axis; shift so 0° sits at the top.
    final degrees = (math.atan2(v.dy, v.dx) * 180 / math.pi + 90) % 360;
    setState(() => _hue = degrees);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: GestureDetector(
              onPanDown: (d) => _handleRing(d.localPosition),
              onPanUpdate: (d) => _handleRing(d.localPosition),
              child: CustomPaint(
                painter: _RingPainter(hue: _hue, swatch: _color),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Light', style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbColor: _color,
                  activeTrackColor: _color,
                  inactiveTrackColor: _color.withValues(alpha: 0.25),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: _shade,
                  onChanged: (v) {
                    setState(() => _shade = v);
                    _emit();
                  },
                ),
              ),
            ),
            Text('Deep', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double hue;
  final Color swatch;

  const _RingPainter({required this.hue, required this.swatch});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;
    final thickness = radius * ColorWheelPicker._ringFraction;
    final ringRadius = radius - thickness / 2;

    // A sweep of the full hue circle, started at the top to match the angle
    // the drag handler reports.
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: [
          for (var i = 0; i <= 360; i += 15)
            HSLColor.fromAHSL(1, i.toDouble() % 360, 0.7, 0.62).toColor(),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: ringRadius));

    canvas.drawCircle(centre, ringRadius, sweep);

    // The chosen colour, previewed in the middle.
    canvas.drawCircle(
      centre,
      radius - thickness - 10,
      Paint()..color = swatch,
    );

    // The handle.
    final angle = (hue - 90) * math.pi / 180;
    final handle = centre + Offset(math.cos(angle), math.sin(angle)) * ringRadius;
    canvas.drawCircle(handle, thickness / 2 + 2,
        Paint()..color = Colors.white);
    canvas.drawCircle(handle, thickness / 2 - 2, Paint()..color = swatch);
    canvas.drawCircle(
      handle,
      thickness / 2 + 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppTheme.ink.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hue != hue || old.swatch != swatch;
}
