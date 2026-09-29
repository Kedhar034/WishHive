import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../widgets/avatar_image.dart'; // Add widget import
import '../widgets/circular_logo.dart';
import 'welcome_page.dart';

class MenuPage extends ConsumerWidget {
  final Function(int) onPageSelected;

  const MenuPage({super.key, required this.onPageSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use watch to ensure this rebuilds when the stream updates
    final user = ref.watch(currentUserStreamProvider).value;
    final requestCount = user?.friendRequestsReceived.length ?? 0;

    final unseenCount = ref.watch(unseenFulfilledCountProvider).value ?? 0;

    // Premium colors updated to match app branding (Amber)
    final menuBgColor = isDark ? const Color(0xFF1A1A1A) : AppTheme.brandBlue;
    final activeItemColor = isDark ? AppTheme.brandBlue : Colors.black.withValues(alpha: 0.15);

    return Drawer(
      backgroundColor: menuBgColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Section and Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        AvatarImage(
                          radius: 28,
                          url: user?.photoUrl,
                          backgroundColor: Colors.white12,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'User',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                user?.username != null ? '@${user!.username}' : 'Member',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close Button (X)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.black54, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              
              // BROWSE SECTION
              _buildSectionHeader("BROWSE"),
              const SizedBox(height: 12),
              _MenuTile(
                index: 0,
                icon: Icons.home_outlined,
                label: "Home",
                isSelected: selectedIndex == 0,
                activeColor: activeItemColor,
                onTap: () {
                  Navigator.of(context).pop();
                  onPageSelected(0);
                },
                badgeCount: unseenCount, // Use fulfillment notifications here
              ),
              _MenuTile(
                index: 1,
                icon: Icons.people_outline,
                label: "Friends",
                isSelected: selectedIndex == 1,
                activeColor: activeItemColor,
                onTap: () {
                  Navigator.of(context).pop();
                  onPageSelected(1);
                },
                badgeCount: requestCount,
              ),
              _MenuTile(
                index: 2,
                icon: Icons.shopping_bag_outlined,
                label: "Marketplace",
                isSelected: selectedIndex == 2,
                activeColor: activeItemColor,
                onTap: () {
                  Navigator.of(context).pop();
                  onPageSelected(2);
                },
              ),
              _MenuTile(
                index: 3,
                icon: Icons.settings_outlined,
                label: "Settings",
                isSelected: selectedIndex == 3,
                activeColor: activeItemColor,
                onTap: () {
                  Navigator.of(context).pop();
                  onPageSelected(3);
                },
              ),

              const SizedBox(height: 24),
              _buildSectionHeader("ACCOUNT"),
              const SizedBox(height: 12),
              _MenuTile(
                index: 99, // Logout isn't a main nav index
                icon: Icons.logout,
                label: "Logout",
                isSelected: false,
                activeColor: activeItemColor,
                onTap: () async {
                  Navigator.of(context).pop();
                  await AuthService().signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const WelcomePage()),
                      (route) => false,
                    );
                  }
                },
              ),

              const Spacer(),
              
              // App Branding at bottom
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  onPageSelected(0); // Redirect to Home
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const CircularLogo(size: 40, showShadow: false),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "WishHive",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          ref.watch(appVersionProvider).when(
                                data: (version) => Text(
                                  "$version • Premium",
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const Text(
                                  "v1.0.0 • Premium",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;
  final Color activeColor;

  const _MenuTile({
    required this.index,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white24 : Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
