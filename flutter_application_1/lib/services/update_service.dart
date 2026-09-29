import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../widgets/circular_logo.dart';
import '../widgets/hive_title.dart';

enum UpdateStatus { noUpdate, softUpdate, forceUpdate }

class UpdateService {
  static const String _storeUrl =
      'https://play.google.com/store/apps/details?id=com.wishhive.app';

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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.rHive)),
          elevation: 0,
          backgroundColor: theme.colorScheme.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: CircularLogo(size: 64, showShadow: false)),
                const SizedBox(height: 20),

                Center(
                  child: HiveTitle(
                    force ? 'Update required' : 'Update available',
                    size: 28,
                    align: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  force
                      ? 'This version is no longer supported. Update to keep '
                          'using WishHive.'
                      : 'A newer version is ready, with the latest fixes and '
                          'improvements.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final uri = Uri.parse(_storeUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text('Update now'),
                  ),
                ),

                // A forced update has no way out, by design: the dialog is the
                // only thing standing between an unsupported client and data
                // it can no longer read correctly.
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Not now'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
