import 'package:flutter/material.dart';

class CircularLogo extends StatelessWidget {
  final double size;
  final double padding;
  final String logoAsset;
  final bool showShadow;

  const CircularLogo({
    super.key,
    this.size = 80,
    this.padding = 12,
    this.logoAsset = 'assets/images/WishHive.png',
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Image.asset(
        logoAsset,
        fit: BoxFit.contain,
      ),
    );
  }
}
