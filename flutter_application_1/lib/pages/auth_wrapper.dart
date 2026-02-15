import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
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
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, stack) => Scaffold(body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, stack) => Scaffold(body: Center(child: Text('Auth Error: $e'))),
    );
  }
}
