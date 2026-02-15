import 'dart:io';
import 'package:flutter/material.dart';

class AvatarImage extends StatelessWidget {
  final String? url;
  final double radius;
  final Color? backgroundColor;

  const AvatarImage({
    super.key,
    this.url,
    this.radius = 20,
    this.backgroundColor,
  });

  ImageProvider? _getImageProvider() {
    if (url == null || url!.isEmpty) return null;
    
    if (url!.startsWith('http')) {
      return NetworkImage(url!);
    } else if (url!.startsWith('assets/')) {
      return AssetImage(url!);
    } else {
      return FileImage(File(url!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey[200],
      backgroundImage: _getImageProvider(),
      child: (url == null || url!.isEmpty)
          ? Icon(Icons.person, size: radius, color: Colors.grey[400])
          : null,
    );
  }
}
