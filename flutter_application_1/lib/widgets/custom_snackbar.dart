import 'package:flutter/material.dart';

class CustomSnackBar {
  static void showSuccess(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.check_circle_outline,
      iconColor: Colors.greenAccent,
      backgroundColor: Colors.green.shade900.withValues(alpha: 0.9),
    );
  }

  static void showError(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.error_outline,
      iconColor: Colors.redAccent,
      backgroundColor: Colors.red.shade900.withValues(alpha: 0.9),
    );
  }

  static void showInfo(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.info_outline,
      iconColor: Colors.amberAccent,
      backgroundColor: const Color(0xFF1E1E1E).withValues(alpha: 0.9),
    );
  }

  /// Variants that take an already-resolved messenger. Capture one *before*
  /// an await and the BuildContext never has to survive the async gap.
  static void showSuccessOn(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message,
          icon: Icons.check_circle_outline,
          iconColor: Colors.greenAccent,
          backgroundColor: Colors.green.shade900.withValues(alpha: 0.9));

  static void showErrorOn(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message,
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
          backgroundColor: Colors.red.shade900.withValues(alpha: 0.9));

  static void _showSnackBar(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    _show(ScaffoldMessenger.of(context), message,
        icon: icon, iconColor: iconColor, backgroundColor: backgroundColor);
  }

  static void _show(
    ScaffoldMessengerState messenger,
    String message, {
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
    );

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
