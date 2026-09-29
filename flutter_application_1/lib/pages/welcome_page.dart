import 'dart:ui';

import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'login_page.dart';
import 'signup_page.dart';
import '../services/auth_service.dart';
import 'auth_wrapper.dart';
import '../widgets/circular_logo.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final authService = AuthService();
      final user = await authService.signInWithGoogle();
      if (user != null) {
        if (!context.mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign-In failed: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Softened against the scaffold's warm white. Image's own opacity is
          // used rather than an Opacity widget so this costs no save layer.
          Image.asset(
            'assets/images/welcome_bg.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            opacity: const AlwaysStoppedAnimation(0.85),
          ),

          // Keeps the status bar icons legible over the sky in the photo.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: media.padding.top + 48,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Colors.transparent],
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: _FrostedPanel(
              bottomInset: media.padding.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CircularLogo(size: 42, showShadow: false),
                      const SizedBox(width: 12),
                      // "Wish" plain, "Hive" in the serif italic accent — the
                      // same treatment the rest of the design language uses
                      // for the second word of a title.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: AppConstants.appName.substring(0, 4),
                                  style:
                                      const TextStyle(fontWeight: FontWeight.w300),
                                ),
                                TextSpan(
                                  text: AppConstants.appName.substring(4),
                                  style: const TextStyle(
                                    fontFamily: 'InstrumentSerif',
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 34,
                              height: 1.1,
                              letterSpacing: -1.2,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    AppConstants.appTagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),

                  _AuthButton(
                    text: 'Sign in with Google',
                    leading: const _GoogleMark(),
                    onTap: () => _signInWithGoogle(context),
                    backgroundColor: AppTheme.primaryAmber,
                    textColor: Colors.white,
                  ),
                  const SizedBox(height: 10),

                  _AuthButton(
                    text: 'Login with Email',
                    leading: const Icon(Icons.mail_outline_rounded,
                        size: 19, color: AppTheme.textPrimary),
                    onTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginPage()));
                    },
                    backgroundColor: Colors.transparent,
                    textColor: AppTheme.textPrimary,
                    isOutlined: true,
                    borderColor: AppTheme.textPrimary.withValues(alpha: 0.16),
                  ),
                  const SizedBox(height: 14),

                  GestureDetector(
                    onTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SignupPage()));
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: "Don't have an account? "),
                          TextSpan(
                            text: 'Sign Up',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textSecondary,
                      ),
                    ),
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

/// The translucent sheet the photo shows through. Capped at 52% of the screen
/// so the image always keeps the top of the frame, and scrollable underneath
/// that cap so short devices never overflow.
class _FrostedPanel extends StatelessWidget {
  final Widget child;
  final double bottomInset;

  const _FrostedPanel({required this.child, required this.bottomInset});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.52,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite.withValues(alpha: 0.86),
            border: const Border(
              top: BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(26, 24, 26, 18 + bottomInset),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The Google wordmark's "G" on a white disc, which reads as a real provider
/// button where the stock Icons.g_mobiledata glyph did not.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontFamily: 'Figtree',
          fontSize: 14,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryAmber,
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String text;
  final Widget leading;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color textColor;
  final bool isOutlined;
  final Color? borderColor;

  const _AuthButton({
    required this.text,
    required this.leading,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
    this.isOutlined = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          overlayColor: isOutlined
              ? AppTheme.primaryAmber.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.2),
          splashFactory: InkRipple.splashFactory,
          elevation: isOutlined ? 0 : 2,
          shadowColor:
              isOutlined ? null : AppTheme.primaryAmber.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: isOutlined
                ? BorderSide(color: borderColor ?? textColor, width: 1.2)
                : BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(double.infinity, 50),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
