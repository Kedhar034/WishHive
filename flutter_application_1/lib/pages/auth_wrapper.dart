import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'welcome_page.dart';
import 'home_page.dart';
import 'complete_profile_page.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              return const HomePage();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/WishHive.png',
          height: 100,
          width: 100,
        ),
      ),
    );
  }
}
