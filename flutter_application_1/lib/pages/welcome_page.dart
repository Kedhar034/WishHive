import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'login_page.dart';
import 'signup_page.dart';
import '../services/auth_service.dart';
import 'auth_wrapper.dart';
import '../widgets/circular_logo.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/video.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..initialize().then((_) {
        _controller.setLooping(true);
        _controller.setVolume(0.0); // Mute the video
        _controller.play();
        setState(() {
          _isInitialized = true;
        });
      }).catchError((error) {
        debugPrint("Video initialization failed: $error");
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Stack(
        children: [
          // 1. Video Background
          if (_isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          else
            Container(
              color: AppTheme.primaryAmber.withValues(alpha: 0.1),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryAmber),
              ),
            ),

          // 2. Dark Overlay for readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.2), // Subtle dark to make white card pop? 
                  // Or maybe warm? "Match our app appearance" -> Amber theme.
                  // Let's use a subtle dark overlay to ensure the video isn't too distracting
                  // but keep the bottom card BRIGHT (White).
                  Colors.black.withValues(alpha: 0.6),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // 3. Content - Bottom Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), // Reduced padding
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite.withValues(alpha: 0.95), // 95% Opacity
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ... (content remains same, focusing on button style next)

// ... skipping to button style update in next replacement or if I can do it here ...
// Wait, I cannot efficiently do two far-apart edits in one replace_file_content unless I use multi_replace.
// I will use multi_replace_file_content.
                  // Logo
                  const CircularLogo(size: 80, padding: 12),
                  const SizedBox(height: 5), // Reduced spacing
                  
                  // App Name
                  Text(
                    AppConstants.appName,
                    style: AppTheme.lightTheme.textTheme.headlineLarge?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5), // Reduced spacing

                  // Tagline
                  Text(
                    AppConstants.appTagline,
                    textAlign: TextAlign.center,
                    style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24), // Reduced spacing

                  // Google Sign In (Primary - Amber)
                  _AuthButton(
                    text: 'Sign In with Google',
                    icon: Icons.g_mobiledata, // Fallback icon
                    onTap: () async {
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
                    },
                    backgroundColor: AppTheme.primaryAmber,
                    textColor: Colors.white,
                    iconColor: Colors.white,
                  ),

                  const SizedBox(height: 16),

                  // Email Login (Secondary - Outline)
                  _AuthButton(
                    text: 'Login with Email',
                    icon: Icons.email_outlined,
                    onTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginPage()));
                    },
                    backgroundColor: Colors.transparent,
                    textColor: AppTheme.primaryDark,
                    iconColor: AppTheme.primaryDark,
                    isOutlined: true,
                    borderColor: AppTheme.primaryAmber,
                  ),
                  
                  const SizedBox(height: 20), // Reduced
                  
                  // Footer Text
                  Column(
                    children: [
                      Text(
                        "Don't have an account?",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 2), // Reduced
                      GestureDetector(
                        onTap: () {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SignupPage()));
                        },
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            color: AppTheme.primaryDark, 
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
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
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final bool isOutlined;
  final Color? borderColor;

  const _AuthButton({
    // super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    this.isOutlined = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          // Explicit splash for better visibility & aesthetics
          overlayColor: isOutlined 
              ? AppTheme.primaryAmber.withValues(alpha: 0.1) // Warm splash for transparent buttons
              : Colors.white.withValues(alpha: 0.2),         // Bright splash for filled buttons
          splashFactory: InkRipple.splashFactory, // Smoother ripple
          elevation: isOutlined ? 0 : 4,
          shadowColor: isOutlined ? null : AppTheme.primaryAmber.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: isOutlined 
                ? BorderSide(color: borderColor ?? textColor, width: 2) 
                : BorderSide.none,
          ),
          // Ensure minSize for touch targets
          minimumSize: const Size(double.infinity, 56),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
