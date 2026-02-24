import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateStatus { noUpdate, softUpdate, forceUpdate }

class UpdateService {
  static final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  static Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _remoteConfig.setDefaults(<String, dynamic>{
        'min_version': '1.0.0',
        'latest_version': '1.0.0',
      });
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('Remote Config failed to initialize: $e');
    }
  }

  static Future<UpdateStatus> checkUpdateStatus() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final minVersion = _remoteConfig.getString('min_version');
      final latestVersion = _remoteConfig.getString('latest_version');

      if (_isLowerVersion(currentVersion, minVersion)) {
        return UpdateStatus.forceUpdate;
      } else if (_isLowerVersion(currentVersion, latestVersion)) {
        return UpdateStatus.softUpdate;
      }
    } catch (e) {
      debugPrint('Failed to check update status: $e');
    }
    return UpdateStatus.noUpdate;
  }

  static bool _isLowerVersion(String current, String target) {
    try {
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> targetParts = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        int c = i < currentParts.length ? currentParts[i] : 0;
        int t = i < targetParts.length ? targetParts[i] : 0;
        if (c < t) return true;
        if (c > t) return false;
      }
    } catch (e) {
      debugPrint('Error comparing versions: $e');
    }
    return false;
  }

  static void showUpdateDialog(BuildContext context, {bool force = false}) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 0,
          backgroundColor: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand Illustration
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/images/logo_amber.png',
                    width: 64,
                    height: 64,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.update_rounded,
                      size: 64,
                      color: Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                Text(
                  force ? 'New Beehive Awaits!' : 'Better Version Ready',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Friendly Reason
                Text(
                  force 
                      ? 'To keep your experience sweet and secure, we\'ve released a critical update. Please update the app to continue your journey!'
                      : 'We\'ve added some new buzz! Update now to enjoy the latest features, improvements, and bug fixes.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Primary Action
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      const url = 'https://play.google.com/store/apps/details?id=com.wishhive.app';
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Update Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Secondary Action (only for non-force)
                if (!force) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Maybe Later',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
