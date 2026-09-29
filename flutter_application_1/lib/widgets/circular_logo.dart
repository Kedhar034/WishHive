import 'package:flutter/material.dart';

class CircularLogo extends StatelessWidget {
  final double size;
  final String logoAsset;
  final bool showShadow;

  const CircularLogo({
    super.key,
    this.size = 80,
    this.logoAsset = 'assets/images/wishhive_logo.png',
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    // A stretching parent (a Column with CrossAxisAlignment.stretch, say) would
    // otherwise force the box to full width and crop the logo into an ellipse.
    // The factors keep this Align sized to the logo wherever it can be, and
    // hand the child loose constraints where it cannot.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipOval(
          child: Image.asset(
            logoAsset,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
