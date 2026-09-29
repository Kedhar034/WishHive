import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart'; // Add Google Fonts import
import '../providers/providers.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_selection_sheet.dart';
import '../widgets/avatar_image.dart';
import '../widgets/custom_snackbar.dart';
import 'welcome_page.dart';
import 'privacy_policy_page.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../core/theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  
  String _getLanguageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'fr': return 'Français';
      case 'hi': return 'हिन्दी';
      case 'te': return 'తెలుగు';
      default: return 'English';
    }
  }

  Widget _buildLanguageOption(BuildContext context, WidgetRef ref, String name, String code) {
    return SimpleDialogOption(
      onPressed: () {
        ref.read(localeProvider.notifier).setLocale(Locale(code));
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(name),
      ),
    );
  }

  void _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, 'Sign-out failed: $e');
      }
    }
  }
  
  void _editProfile(UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImageSelectionSheet(
        onImageSelected: (file) async {
         if (file == null) return;
         try {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Updating profile picture...')),
           );
           
            // Optimistic UI for camera image
            final futureUrl = ImageStorageService.compressAndUploadImage(file, user.uid);
            
            if (mounted) {
              Navigator.pop(context);
              CustomSnackBar.showInfo(context, 'Updating profile picture...');
            }
            
            final messenger = ScaffoldMessenger.of(context);
            futureUrl.then((url) {
              return FirestoreService().updateUser(user.copyWith(photoUrl: url));
            }).then((_) {
              CustomSnackBar.showSuccessOn(messenger, 'Profile picture updated successfully!');
            }).catchError((e) {
              debugPrint('Failed to update profile: $e');
              CustomSnackBar.showErrorOn(messenger, 'Failed to update profile picture.');
            });
         } catch(e) {
           debugPrint('Failed to process image: $e');
           if (mounted) CustomSnackBar.showError(context, 'An error occurred. Please try again.');
         }
        },
        onAvatarSelected: (url) {
          try {
             // Optimistic UI for avatar
             if (mounted) {
               Navigator.pop(context);
               CustomSnackBar.showInfo(context, 'Updating profile picture...');
             }
             final messenger = ScaffoldMessenger.of(context);
             FirestoreService().updateUser(user.copyWith(photoUrl: url)).then((_) {
               CustomSnackBar.showSuccessOn(messenger, 'Profile picture updated successfully!');
             }).catchError((e) {
               debugPrint('Failed to update profile avatar: $e');
               CustomSnackBar.showErrorOn(messenger, 'Failed to update profile picture.');
             });
          } catch (e) {
             debugPrint('Failed to update profile: $e');
             if (mounted) CustomSnackBar.showError(context, 'An error occurred. Please try again.');
          }
        },
      ),
    );
  }

  void _shareApp() {
    // Using Clipboard for simplicity as share_plus might not be added
    // If share_plus is available, we would use Share.share(...)
    // For now, let's copy the link.
    const appLink = "https://beehive.app/download"; // Placeholder
    Clipboard.setData(const ClipboardData(text: "Check out Beehive! Organize your wishes and share with friends: $appLink"));
    
    CustomSnackBar.showSuccess(context, 'Download link copied to clipboard!');
  }

  void _launchPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  void _showChangeUsernameDialog(UserModel user) {
    if (!mounted) return;
    
    final usernameController = TextEditingController(text: user.username);
    String? errorText;
    bool isChecking = false;
    bool isAvailable = true; // Assume current is "available" since they own it
    Timer? debounce;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            
            void checkAvailability(String val) {
                if (debounce?.isActive ?? false) debounce!.cancel();
                
                if (val.trim() == user.username) {
                   setState(() {
                     isChecking = false;
                     isAvailable = true;
                     errorText = null;
                   });
                   return;
                }

                if (val.trim().length < 3) {
                   setState(() {
                     isChecking = false;
                     isAvailable = false;
                     errorText = 'Must be at least 3 characters';
                   });
                   return;
                }

                setState(() {
                  isChecking = true;
                  errorText = null;
                });

                debounce = Timer(const Duration(milliseconds: 500), () async {
                   final available = await FirestoreService().isUsernameAvailable(val);
                   if (context.mounted) {
                      setState(() {
                        isChecking = false;
                        isAvailable = available;
                        if (!available) {
                          errorText = 'Username taken';
                        }
                      });
                   }
                });
            }

            return AlertDialog(
              title: const Text('Change Username'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose a unique username.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.alternate_email),
                      errorText: errorText,
                      suffixIcon: isChecking 
                          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                          : (isAvailable && usernameController.text.trim() != user.username && errorText == null)
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                    ),
                    onChanged: (val) => checkAvailability(val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: (isAvailable && !isChecking && errorText == null && usernameController.text.trim().isNotEmpty) 
                  ? () async {
                      debounce?.cancel();
                      final newUsername = usernameController.text.trim();
                      if (newUsername == user.username) {
                        Navigator.pop(context);
                        return;
                      }

                        Navigator.pop(context);
                        CustomSnackBar.showInfo(context, 'Updating username...');

                        final service = FirestoreService();
                        // Claim first — the availability check above is advisory
                        // and someone may have taken the name since.
                        final messenger = ScaffoldMessenger.of(context);
                        service
                            .claimUsername(newUsername)
                            .then((claimed) {
                          if (!claimed) {
                            CustomSnackBar.showErrorOn(
                                messenger, 'That username was just taken.');
                            return null;
                          }
                          return service.updateUser(user.copyWith(
                            username: newUsername.toLowerCase(),
                            displayName: newUsername,
                          )).then((_) {
                            CustomSnackBar.showSuccessOn(
                                messenger, 'Username updated successfully!');
                          });
                        }).catchError((e) {
                          debugPrint('Failed to update username: $e');
                          CustomSnackBar.showErrorOn(
                              messenger, 'Failed to update username.');
                        });
                  }  
                  : null, 
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider); 
    final theme = Theme.of(context);

    // Elegant subtle color for list items
    final tileColor = theme.colorScheme.surfaceContainerLow;
    // Distinct richer color for the profile card
    final profileCardColor = theme.colorScheme.primary.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: myUserAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text('User not signed in'));
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Added bottom padding for navbar
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, // Make children stretch fill width
              children: [
                // 1. User Info Card (Distinct)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: profileCardColor, 
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      AvatarImage(
                        radius: 35,
                        url: user.photoUrl,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.username != null && user.username!.isNotEmpty
                                  ? user.username![0].toUpperCase() + user.username!.substring(1)
                                  : user.displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${user.username ?? "Set username"}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit Profile Picture',
                            onPressed: () => _editProfile(user),
                          ),
                          IconButton(
                            icon: const Icon(Icons.alternate_email),
                            tooltip: 'Change Username',
                            onPressed: () => _showChangeUsernameDialog(user),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Language
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(AppLocalizations.of(context)!.language),
                  subtitle: Text(_getLanguageName(ref.watch(localeProvider).languageCode)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: tileColor,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: Text(AppLocalizations.of(context)!.language),
                        children: [
                          _buildLanguageOption(context, ref, 'English', 'en'),
                          _buildLanguageOption(context, ref, 'Français', 'fr'),
                          _buildLanguageOption(context, ref, 'हिन्दी', 'hi'),
                          _buildLanguageOption(context, ref, 'తెలుగు', 'te'),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Privacy Policy
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(AppLocalizations.of(context)!.privacyPolicy),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: tileColor,
                  onTap: _launchPrivacyPolicy,
                ),
                const SizedBox(height: 8),

                // Share App
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share WishHive'),
                  subtitle: Text(AppLocalizations.of(context)!.friends),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: tileColor,
                  onTap: _shareApp,
                ),
                const SizedBox(height: 8),
                
                // Appearance Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tileColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.brightness_medium_outlined, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('App Theme',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Consumer(
                        builder: (context, ref, _) {
                          final current = ref.watch(themeModeProvider);
                          return Row(
                            children: [
                              _themeChip(context, ref, Icons.light_mode_outlined, 'Light', ThemeMode.light, current),
                              const SizedBox(width: 8),
                              _themeChip(context, ref, Icons.dark_mode_outlined, 'Dark', ThemeMode.dark, current),
                              const SizedBox(width: 8),
                              _themeChip(context, ref, Icons.phone_android, 'System', ThemeMode.system, current),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 48),

                 // Logout
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.red[50],
                      foregroundColor: Colors.red[theme.brightness == Brightness.dark ? 300 : 700],
                       elevation: 0,
                    ),
                    label: Text(AppLocalizations.of(context)!.logout),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Version Info
                Center(
                  child: Text(
                    'Version 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading profile: $e')),
      ),
    );
  } // end build()

  Widget _themeChip(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    String label,
    ThemeMode mode,
    ThemeMode current,
  ) {
    final isSelected = current == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(themeModeProvider.notifier).setTheme(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryAmber : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryAmber : theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
