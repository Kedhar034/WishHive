import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../core/constants/app_constants.dart';
import 'welcome_page.dart';
import 'complete_profile_page.dart';
import '../widgets/zoom_drawer_shell.dart';
import '../widgets/circular_logo.dart';

import '../services/update_service.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    await UpdateService.initialize();
    final status = await UpdateService.checkUpdateStatus();
    
    if (status == UpdateStatus.forceUpdate) {
      if (mounted) UpdateService.showUpdateDialog(context, force: true);
    } else if (status == UpdateStatus.softUpdate) {
      if (mounted) UpdateService.showUpdateDialog(context, force: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          return const WelcomePage();
        }
        
        // User is logged in, check Firestore profile
        final userProfileAsync = ref.watch(currentUserStreamProvider);
        
        return userProfileAsync.when(
          data: (userModel) {
            // Check if profile is complete (has username)
            if (userModel != null && userModel.username != null && userModel.username!.isNotEmpty) {
              return const ZoomDrawerShell();
            }
            
            // If userModel is null or missing username, go to completion
            return CompleteProfilePage(firebaseUser: user);
          },
          loading: () => const _SplashScreen(),
          error: (e, stack) => Scaffold(body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () => const _SplashScreen(),
      error: (e, stack) => Scaffold(body: Center(child: Text('Auth Error: $e'))),
    );
  }
}

/// Simple splash — just the logo, no text or spinner.
/// TODO: Replace with custom animation later.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: const Center(
        child: CircularLogo(size: 120, padding: 20),
      ),
    );
  }
}
