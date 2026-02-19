import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import '../providers/providers.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_selection_sheet.dart';
import '../widgets/avatar_image.dart';
import 'welcome_page.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../services/share_logger.dart'; // Import ShareLogger

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-out failed: $e')),
        );
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
           
           final url = await ImageStorageService.compressAndUploadImage(file, user.uid);
           await FirestoreService().updateUser(user.copyWith(photoUrl: url));
           
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Profile picture updated!')),
             );
           }
         } catch(e) {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Failed to update profile: $e')),
             );
           }
         }
        },
        onAvatarSelected: (url) async {
          try {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Updating profile picture...')),
             );
             await FirestoreService().updateUser(user.copyWith(photoUrl: url));
              if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Profile picture updated!')),
             );
           }
          } catch (e) {
             if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Failed to update profile: $e')),
             );
           }
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
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download link copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://example.com/privacy'); // Placeholder
    if (!await launchUrl(url)) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Privacy Policy')),
        );
      }
    }
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

                      try {
                        // Double check before submit if needed, or trust the debounce state
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Updating username...')),
                        );
                        
                        await FirestoreService().updateUser(user.copyWith(
                          username: newUsername.toLowerCase(),
                          displayName: newUsername, // Sync display name with username
                        ));
                        
                        if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Username updated successfully!')),
                          );
                        }
                      } catch (e) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update: $e')),
                          );
                        }
                      }
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

  void _showLogs() async {
    final logs = await ShareLogger.readLogs();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Logs'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(logs),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ShareLogger.clearLogs();
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
               Clipboard.setData(ClipboardData(text: logs));
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Copied to clipboard')),
               );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider); 
    final theme = Theme.of(context);

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. User Info Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      AvatarImage(
                        radius: 35,
                        url: user.photoUrl,
                        backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
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
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[500],
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
                const SizedBox(height: 32),

                // 2. Preferences
                Text(
                  'Preferences',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Language
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(AppLocalizations.of(context)!.language),
                  subtitle: Text(_getLanguageName(ref.watch(localeProvider).languageCode)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey[50],
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

                const SizedBox(height: 32),
                 Text(
                  'About & Support',
                   style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Privacy Policy
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey[50],
                  onTap: _launchPrivacyPolicy,
                ),
                const SizedBox(height: 8),

                // Share App
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share Beehive'),
                  subtitle: const Text('Invite friends to join'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey[50],
                  onTap: _shareApp,
                ),

                const SizedBox(height: 32),
                
                // Debug Section
                Text(
                  'Debug',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('View Share Logs'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey[50],
                  onTap: _showLogs,
                ),

                const SizedBox(height: 40),

                 // Logout
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.red,
                       elevation: 0,
                    ),
                    label: const Text('Log Out'),
                  ),
                ),
                
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Version 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
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
  }
}
