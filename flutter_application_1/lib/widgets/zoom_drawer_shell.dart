import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import '../pages/menu_page.dart';
import '../pages/home_page.dart';
import '../providers/providers.dart';

class ZoomDrawerShell extends ConsumerStatefulWidget {
  const ZoomDrawerShell({super.key});

  @override
  ConsumerState<ZoomDrawerShell> createState() => _ZoomDrawerShellState();
}

class _ZoomDrawerShellState extends ConsumerState<ZoomDrawerShell> {
  final ZoomDrawerController _drawerController = ZoomDrawerController();

  @override
  Widget build(BuildContext context) {
    return ZoomDrawer(
      controller: _drawerController,
      menuScreen: MenuPage(
        onPageSelected: (index) {
          ref.read(navigationProvider.notifier).setIndex(index);
          _drawerController.close?.call();
        },
      ),
      mainScreen: const HomePage(),
      borderRadius: 24.0,
      showShadow: true,
      angle: -12.0,
      drawerShadowsBackgroundColor: Colors.grey.withValues(alpha: 0.2),
      slideWidth: MediaQuery.of(context).size.width * 0.65,
      isRtl: true, // Opened from right as requested
      clipMainScreen: true,
      mainScreenScale: 0.1, // Perspective effect
      mainScreenTapClose: true, // Tap to close as requested
      menuBackgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF1A1A1A) 
          : const Color(0xFFFFB300),
    );
  }
}
