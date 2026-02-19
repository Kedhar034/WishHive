import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';

import '../models/hive_model.dart';
import '../providers/providers.dart';
import '../widgets/hive_card.dart';
import '../core/constants/app_constants.dart';
import 'product_detail_page.dart';
import 'create_hive_sheet.dart';
import 'create_wish_sheet.dart';
import 'create_wish_sheet.dart';
import 'welcome_page.dart';
import 'contacts_page.dart';
import 'friend_feed_page.dart';
import 'hidden_hives_page.dart';
import 'marketplace_page.dart';
import 'settings_page.dart';
import '../services/metadata_service.dart';
import '../services/share_logger.dart'; // Import ShareLogger
import '../widgets/shimmer_loading.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // Optimistic hiding state for friend slider moved to provider
  int _currentNavIndex = 0;
  late StreamSubscription _intentDataStreamSubscription;
  bool _isHandlingShare = false;
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _initShareIntent();
    // Show skeletons briefly on first load for smooth transition
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isInitialLoad = false);
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  void _initShareIntent() {
    // For sharing or opening urls/text coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && mounted) {
        _handleSharedFiles(value);
      }
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });

    // For sharing or opening urls/text coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && mounted) {
        _handleSharedFiles(value);
      }
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (_isHandlingShare) return;
    _isHandlingShare = true;

    String? foundUrl;
    String? foundImage;
    String? foundText;

    // URL regex: In Dart raw strings (r'...'), backslash is NOT doubled.
    // Single \ is the regex escape character in raw strings.
    final urlRegExp = RegExp(
      r'https?://(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&/=]*)',
      caseSensitive: false,
    );

    // Debug: Log all shared content to help diagnose share issues
    try {
       await ShareLogger.log('--- NEW SHARE RECEIVED ---');
       for (int i = 0; i < files.length; i++) {
         final logMsg = 'SharedFile[$i]: type=${files[i].type.value}, path="${files[i].path}", mimeType=${files[i].mimeType}, message=${files[i].message}';
         debugPrint(logMsg);
         await ShareLogger.log(logMsg);
       }
    } catch (e) {
      debugPrint("Logging error: $e");
    }

    // Iterate through all shared content to find best URL and Text
    for (final file in files) {
      final content = file.path;
      final message = file.message ?? '';
      
      if (file.type == SharedMediaType.url) {
        // Direct URL sharing (some apps like Blinkit use this type)
        foundUrl ??= content;
      } else if (file.type == SharedMediaType.text || file.type == SharedMediaType.file) {
        // Text sharing — URL might be embedded inside the text
        if (foundText == null || content.length > (foundText?.length ?? 0)) {
          foundText = content;
        }
        
        // Try extract URL from the text/content
        if (foundUrl == null) {
          final matches = urlRegExp.allMatches(content);
          for (final match in matches) {
            final val = match.group(0);
            if (val != null) {
               foundUrl = val;
               break; 
            }
          }
        }
      } else if (file.type == SharedMediaType.image) {
        foundImage ??= content; // Keep first image
      }
      
      // 2024 Fix: Some apps (like Blinkit) might send an 'image' type but put the URL in the message 
      // OR they might send a 'path' that is actually just text/url but labeled as image? (unlikely but possible)
      // Check EVERYTHING for a URL if we haven't found one yet.
      
      // Check Path for URL even if type is not text
      if (foundUrl == null && content.isNotEmpty) {
         final matchesContent = urlRegExp.allMatches(content);
         for (final match in matchesContent) {
            final val = match.group(0);
            if (val != null) {
               foundUrl = val;
               break;
            }
         }
      }

      // Check Message for URL
      if (foundUrl == null && message.isNotEmpty) {
         final matchesMessage = urlRegExp.allMatches(message);
         for (final match in matchesMessage) {
            final val = match.group(0);
            if (val != null) {
               foundUrl = val;
               break;
            }
         }
         // If no URL found but we have message text, use it as description/title fallback
         if (foundText == null && message.length > 5) {
            foundText = message;
         }
      }
    }

    // Fallback: Check if the text itself contains a URL if regex didn't catch it inside loop
    if (foundUrl == null && foundText != null) {
         final matches = urlRegExp.allMatches(foundText);
         for (final match in matches) {
            final val = match.group(0);
            if (val != null) {
                foundUrl = val;
                break;
            }
         }
    }

    // Special case for Amazon Short Links if they don't resolve well with Regex (sometimes they are just text)
    // But regex should catch amzn.in/d/...

    String? initialTitle;
    String? initialImage = foundImage; // Use shared image by default
    String? finalUrl = foundUrl;
    
    await ShareLogger.log('Processing Share: URL=$finalUrl, Image=$initialImage, Text=$foundText');

    if (finalUrl != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fetching product details...')),
        );
      }

      final metadata = await MetadataService.extract(finalUrl);
      if (metadata != null) {
        initialTitle = metadata.title;
        if (metadata.imageUrl?.isNotEmpty ?? false) {
          initialImage = metadata.imageUrl;
        }
      }
    } else {
        // No URL found. Use text as title if available.
        initialTitle = foundText;
    }

    if (mounted) {
      _isHandlingShare = false;
      
      showMaterialModalBottomSheet(
        context: context,
        expand: false,
        builder: (context) => CreateWishSheet(
          initialLink: finalUrl,
          initialTitle: initialTitle,
          initialImageUrl: initialImage,
        ),
      );
    } else {
      _isHandlingShare = false;
    }
  }

  Future<void> _signOut() async {
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

  void _showCreateHiveSheet() {
    showMaterialModalBottomSheet(
      context: context,
      expand: false,
      builder: (context) => const CreateHiveSheet(),
    );
  }

  void _showCreateWishSheet() {
    showMaterialModalBottomSheet(
      context: context,
      expand: false,
      builder: (context) => const CreateWishSheet(),
    );
  }

  void _editHive(HiveModel hive) {
    showMaterialModalBottomSheet(
      context: context,
      expand: false,
      builder: (context) => CreateHiveSheet(hiveToEdit: hive),
    );
  }

  void _showHideHiveDialog(HiveModel hive) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hide Hive?'),
        content: Text(
            'Do you want to hide "${hive.title}" from your feed?\nYou can undo this action immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // Optimistic Update: Hide immediately from slider
                ref.read(temporarilyHiddenHivesProvider.notifier).add(hive.id);

                // Hide in backend
                await ref.read(firestoreServiceProvider).hideHive(hive.id);
                
                // Do NOT invalidate immediately to avoid jitter
                // ref.invalidate(friendFeedProvider); 

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hidden "${hive.title}"'),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () async {
                           ref.read(temporarilyHiddenHivesProvider.notifier).remove(hive.id);
                           await ref.read(firestoreServiceProvider).unhideHive(hive.id);
                           ref.invalidate(friendFeedProvider);
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                // Revert if failed
                ref.read(temporarilyHiddenHivesProvider.notifier).remove(hive.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to hide: $e')),
                  );
                }
              }
            },
            child: const Text('Hide', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openHiveDetail(HiveModel hive, {String? heroTag}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductDetailPage(
          hiveId: hive.id,
          title: hive.title,
          imageUrl: hive.imageUrl,
          ownerId: hive.ownerId,
          ownerDisplayName: hive.ownerDisplayName,
          heroTag: heroTag,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(uploadServiceProvider);
    final uid = ref.watch(uidProvider);
    
    final hiveListAsync = ref.watch(hiveListProvider);
    final theme = Theme.of(context);

    // Pre-extract home content to keep build clean
    Widget _buildHomeContent(AsyncValue<QuerySnapshot> hiveList, ThemeData theme) {
      // Show skeletons during initial load for smooth transition from login
      if (_isInitialLoad) {
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const _FriendFeedSkeleton(),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: _HiveCardSkeleton(),
                ),
                childCount: 4,
              ),
            ),
          ],
        );
      }

      final friendHivesAsync = ref.watch(friendFeedProvider);
      final notificationCountsAsync = ref.watch(unseenWishesByHiveProvider);
      final notificationCounts = notificationCountsAsync.value ?? {};

      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Friend Hives Section (Horizontal Slider)
          friendHivesAsync.when(
            data: (allHives) {
              final hives = allHives.where((h) => !temporarilyHidden.contains(h.id)).toList();
              if (hives.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                      child: Text(
                        'From Your Friends',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 220, // Height for the horizontal cards
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        scrollDirection: Axis.horizontal,
                        itemCount: hives.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final hive = hives[index];
                          // Note: Friends hives don't usually show *YOUR* notifications, 
                          // unless you are fulfilling them? 
                          // Logic: unseenWishesByHiveProvider tracks 'ownerSeen: false'.
                          // Only the owner sees these. So for friend hives, count is likely 0 unless you own it.
                          // But just in case you own a hive that appears in friends list (weird edge case), strict ID match works.
                          
                          return SizedBox(
                            width: 160, // Fixed width for horizontal items
                            child: GestureDetector(
                              onTap: () => _openHiveDetail(hive, heroTag: 'friend-hive-${hive.id}'),
                              onLongPress: () => _showHideHiveDialog(hive),
                              child: HiveCard(
                                heroTag: 'friend-hive-${hive.id}',
                                title: hive.title,
                                items: hive.itemCount,
                                price: hive.totalCost,
                                imageUrl: hive.imageUrl.isNotEmpty
                                    ? hive.imageUrl
                                    : AppConstants.fallbackImage,
                                ownerName: hive.ownerDisplayName,
                                isCompact: true, // Use compact mode for slider
                                // notificationCount: notificationCounts[hive.id] ?? 0, // usually 0 for friends hvie
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'My Hives',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
            loading: () => const _FriendFeedSkeleton(),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // 2. My Hives Grid (Vertical)
          hiveList.when(
            data: (snapshot) {
              final hiveDocs = snapshot.docs;
              if (hiveDocs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hive_outlined,
                          size: 80,
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hives yet',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to create your first hive!',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = hiveDocs[index];
                      final hive = HiveModel.fromFirestore(doc);
                      final notifCount = notificationCounts[hive.id] ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GestureDetector(
                          onTap: () => _openHiveDetail(hive, heroTag: 'hive-${hive.id}'),
                          onLongPress: () => _editHive(hive),
                          child: HiveCard(
                            heroTag: 'hive-${hive.id}',
                            title: hive.title,
                            items: hive.itemCount,
                            price: hive.totalCost,
                            imageUrl: hive.imageUrl.isNotEmpty
                                ? hive.imageUrl
                                : AppConstants.fallbackImage,
                            notificationCount: notifCount,
                          ),
                        ),
                      );
                    },
                    childCount: hiveDocs.length,
                  ),
                ),
              );
            },
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: _HiveCardSkeleton(),
                  );
                },
                childCount: 4,
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Error loading hives: $e', textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // ─── Header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/WishHive.png',
                        height: 40,
                        width: 40,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      // TODO: Implement sort/filter menu
                    },
                    icon: const Icon(Icons.sort_rounded, size: 28), // Three dashes style
                    tooltip: 'Sort & Filter',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 28, color: Colors.black87),
                    tooltip: 'More Options',
                    onSelected: (value) {
                      if (value == 'hidden_hives') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HiddenHivesPage()),
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'hidden_hives',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off_outlined, color: Colors.grey),
                              SizedBox(width: 8),
                              Text('Hidden Hives'),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
            ),

            // ─── Main Content ───────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _currentNavIndex,
                children: [
                   _buildHomeContent(hiveListAsync, theme),
                   const ContactsPage(),
                   const MarketplacePage(),
                   const SettingsPage(),
                ],
              ),
            ),
          ],
        ),
      ),

      // ─── Speed Dial FAB ─────────────────────────────────────────
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        overlayOpacity: 0.5,
        spacing: 16,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.star_outline),
            label: 'Create a Wish',
            backgroundColor: theme.colorScheme.secondary,
            onTap: _showCreateWishSheet,
          ),
          SpeedDialChild(
            child: const Icon(Icons.hive_outlined),
            label: 'Create a Hive',
            backgroundColor: theme.colorScheme.primary,
            onTap: _showCreateHiveSheet,
          ),
        ],
      ),

      // ─── Bottom Nav ─────────────────────────────────────────────
      bottomNavigationBar: CurvedNavigationBar(
        index: _currentNavIndex,
        backgroundColor: Colors.transparent,
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
        buttonBackgroundColor: theme.colorScheme.primary,
        animationDuration: const Duration(milliseconds: 300),
        onTap: (index) {
          setState(() => _currentNavIndex = index);
        },
        items: [
          // Badge for unseen fulfilled wishes
          Consumer(
            builder: (context, ref, child) {
              final unseenCount = ref.watch(unseenFulfilledCountProvider).value ?? 0;
              
              if (unseenCount == 0) {
                return const Icon(Icons.home, size: 28);
              }

              return Badge(
                label: Text('$unseenCount'),
                backgroundColor: Colors.red,
                textColor: Colors.white,
                child: const Icon(Icons.home, size: 28),
              );
            },
          ),
          
          // Badge for Friend Requests
          Consumer(
            builder: (context, ref, child) {
              final user = ref.watch(currentUserStreamProvider).value;
              final requestCount = user?.friendRequestsReceived.length ?? 0;
              
              if (requestCount == 0) {
                return const Icon(Icons.people, size: 28);
              }

              return Badge(
                label: Text('$requestCount'),
                backgroundColor: Colors.red,
                textColor: Colors.white,
                child: const Icon(Icons.people, size: 28),
              );
            },
          ),
          
          const Icon(Icons.shopping_bag_outlined, size: 28),
          const Icon(Icons.settings_outlined, size: 28),
        ],
      ),
    );
  }
}

class _FriendFeedSkeleton extends StatelessWidget {
  const _FriendFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
            child: ShimmerLoading(
              child: Container(
                height: 20, 
                width: 150, 
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => const SizedBox(
                width: 160,
                child: _HiveCardSkeleton(), // Reusing the existing vertical skeleton but constrained by width
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HiveCardSkeleton extends StatelessWidget {
  const _HiveCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      clipBehavior: Clip.antiAlias, // Ensure content doesn't bleed out
      child: ShimmerLoading(
        child: Column(
          
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white, // Color doesn't matter much due to shimmer
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
              ),
            ),
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 20, width: 150, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 14, width: 100, color: Colors.white),
                    const Spacer(),
                    Row(
                      children: [
                        Container(height: 14, width: 60, color: Colors.white),
                        const Spacer(),
                        Container(height: 14, width: 40, color: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
