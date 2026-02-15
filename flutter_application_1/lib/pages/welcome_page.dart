import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/theme/app_theme.dart';
import '../core/constants/app_constants.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'home_page.dart';
import 'auth_wrapper.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _isGoogleLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
      final googleUser = await googleSignIn.authenticate();

      final credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        // Create/Update user in Firestore
        await FirestoreService().updateUser(UserModel(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'User',
          photoUrl: user.photoURL,
        ));
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 280,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xFFFFF8E1),
                    Color(0xFFFFE0B2),
                    Color(0xFFF5A623),
                  ],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // Logo
                  Container(
                    width: 100, // Increased size slightly for better visibility
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(
                      'assets/images/WishHive.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Tagline
                  Text(
                    AppConstants.appTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Organize your wishes, track your dreams.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Sign in buttons
                  _AuthButton(
                    text: 'Sign up with Email',
                    icon: Icons.email_outlined,
                    onTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SignupPage()));
                    },
                  ),
                  const SizedBox(height: 14),
                  _AuthButton(
                    text: 'Login with Email',
                    icon: Icons.login,
                    onTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginPage()));
                    },
                  ),
                  const SizedBox(height: 14),
                  _AuthButton(
                    text: 'Sign in with Google',
                    icon: Icons.g_mobiledata,
                    onTap: _isGoogleLoading ? null : _signInWithGoogle,
                    isLoading: _isGoogleLoading,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const _AuthButton({
    required this.text,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              color: Colors.black.withValues(alpha: 0.06),
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Icon(icon, size: 22, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
