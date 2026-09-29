import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/share_link_service.dart';
import '../services/share_link_flow.dart';
import 'welcome_page.dart';
import 'complete_profile_page.dart';
import 'home_page.dart';
import '../widgets/circular_logo.dart';

import '../services/update_service.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  StreamSubscription<String>? _shareLinkSub;

  @override
  void initState() {
    super.initState();
    _checkUpdates();
    _initShareLinks();
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

  Future<void> _initShareLinks() async {
    await ShareLinkService.instance.init();
    _shareLinkSub = ShareLinkService.instance.onShareLink.listen((shareId) {
      if (mounted) openSharedHive(context, ref, shareId);
    });
  }

  @override
  void dispose() {
    _shareLinkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          ShareLinkService.instance.signedIn = false;
          return const WelcomePage();
        }

        // A link that arrived while signed out is held until now.
        ShareLinkService.instance.onSignedIn();
        
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: const Center(
        child: CircularLogo(size: 120),
      ),
    );
  }
}
