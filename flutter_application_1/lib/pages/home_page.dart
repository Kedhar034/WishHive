import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';

import '../models/hive_model.dart';
import '../providers/providers.dart';
import '../widgets/hive_card.dart';
import '../core/constants/app_constants.dart';
import 'product_detail_page.dart';
import 'create_hive_sheet.dart';
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
import '../l10n/app_localizations.dart';
import '../services/review_service.dart';
import '../widgets/circular_logo.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with SingleTickerProviderStateMixin {
  // Optimistic hiding state for friend slider moved to provider
  int _currentNavIndex = 0;
  late StreamSubscription _intentDataStreamSubscription;
  bool _isHandlingShare = false;
  bool _isInitialLoad = true;
  late TabController _tabController; // Declared TabController

  // Tutorial Keys
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _hivesListKey = GlobalKey(); // To be assigned to the Hive List Sliver
  final GlobalKey _hiddenHivesKey = GlobalKey(); // To be assigned to the Hidden Hives Icon
  final GlobalKey _contactsTabKey = GlobalKey(); // To be assigned to the Contacts Tab
  final GlobalKey _marketplaceTabKey = GlobalKey(); // To be assigned to the Marketplace Tab

  @override
  void initState() {
    super.initState();
    _initShareIntent();
    // Show skeletons briefly on first load for smooth transition
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isInitialLoad = false);
    });
    
    // Check for tutorial after frame build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowTutorial();
    });

    // Check if we should request an in-app review
    ReviewService.maybeRequestReview();
  }

  Future<void> _checkAndShowTutorial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenTutorial = prefs.getBool('has_seen_tutorial_${user.uid}') ?? false;

    if (!hasSeenTutorial) {
      // Delay slightly to ensure UI is ready
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _showTutorial();
      });
    }
  }

  void _showTutorial() {
    late TutorialCoachMark tutorialCoachMark;
    
    List<TargetFocus> targets = [];

    // Target 1: Create Hive (FAB)
    targets.add(
      TargetFocus(
        identify: "create_hive",
        keyTarget: _fabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Create a Hive",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20.0,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 10.0),
                    child: Text(
                      "Start by creating a new Hive (Wishlist) or a Wish. Tap the + button to get started.",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Target 2: Hidden Hives Icon
    targets.add(
      TargetFocus(
        identify: "hidden_hives",
        keyTarget: _hiddenHivesKey,
        alignSkip: Alignment.bottomLeft,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end, // Align text to the right side if icon is on right
                children: const [
                  Text(
                    "Hidden Hives",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20.0,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 10.0),
                    child: Text(
                      "If you hide any friend's hive, you can find them here. Tap the crossed eye icon to manage hidden content.",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Target 3: Contacts Tab
    targets.add(
      TargetFocus(
        identify: "contacts_tab",
        keyTarget: _contactsTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Friends & Contacts",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20.0,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 10.0),
                    child: Text(
                      "Find friends, search contacts, and send friend requests here to grow your Hive network.",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Target 4: Marketplace Tab
    targets.add(
      TargetFocus(
        identify: "marketplace_tab",
        keyTarget: _marketplaceTabKey,
        alignSkip: Alignment.topRight, 
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Marketplace",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20.0,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 10.0),
                    child: Text(
                      "Discover products and gift ideas coming soon directly within the app!",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black.withOpacity(0.8),
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('has_seen_tutorial_${user.uid}', true);
        }
      },
      onSkip: () {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          SharedPreferences.getInstance().then((prefs) => 
            prefs.setBool('has_seen_tutorial_${user.uid}', true));
        }
        return true; 
      },
    )..show(context: context);
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  void _initShareIntent() {
    // ... existing implementation remains same, just ensuring we successfully replaced the block above ...
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && mounted) {
        _handleSharedFiles(value);
      }
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });
    
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && mounted) {
        _handleSharedFiles(value);
      }
    });
  }

  // ... (rest of methods) ...

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
    final temporarilyHidden = ref.watch(temporarilyHiddenHivesProvider);

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

  @override
  Widget build(BuildContext context) {
    // ... existing build logic ...
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
                      const CircularLogo(size: 40, padding: 6, showShadow: false),
                      const SizedBox(width: 12),
                      Text(
                        AppConstants.appName,
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Hidden Hives Icon with Tutorial Key
                  GestureDetector(
                    key: _hiddenHivesKey,
                    onTap: () {
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (_) => const HiddenHivesPage()),
                       );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.visibility_off_outlined,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            
            // ... (Rest of body) ...
            Expanded(
              child: IndexedStack(
                index: _currentNavIndex,
                children: [
                   _buildHomeContent(ref.watch(hiveListProvider), Theme.of(context)),
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
        key: _fabKey, // Tutorial Key
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        overlayOpacity: 0.5,
        spacing: 16,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.star_outline),
            label: AppLocalizations.of(context)!.createWish,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            onTap: _showCreateWishSheet,
          ),
          SpeedDialChild(
            child: const Icon(Icons.hive_outlined),
            label: AppLocalizations.of(context)!.createHive,
            backgroundColor: Theme.of(context).colorScheme.primary,
            onTap: _showCreateHiveSheet,
          ),
        ],
      ),
      
      // ... (Bottom Nav) ...
      bottomNavigationBar: CurvedNavigationBar(
        index: _currentNavIndex,
        backgroundColor: Colors.transparent,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        buttonBackgroundColor: Theme.of(context).colorScheme.primary,
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
                 return Container(key: _contactsTabKey, child: const Icon(Icons.people, size: 28));
              }

              return Container(
                key: _contactsTabKey,
                child: Badge(
                  label: Text('$requestCount'),
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  child: const Icon(Icons.people, size: 28),
                ),
              );
            },
          ),
          
          Container(key: _marketplaceTabKey, child: const Icon(Icons.shopping_bag_outlined, size: 28)),
          const Icon(Icons.settings_outlined, size: 28),
        ],
      ),
    );
  }

  // No changes needed here, just deleting the duplicate block. But I must provide valid content for _handleSharedFiles first.
  
  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (_isHandlingShare) return;
    _isHandlingShare = true;

    String? foundUrl;
    String? foundImage;
    String? foundText;

    // URL regex: In Dart raw strings (r'...'), backslash is NOT doubled.
    final urlRegExp = RegExp(
      r'https?://(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&/=]*)',
      caseSensitive: false,
    );

    // Debug: Log all shared content
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

    // Iterate through all shared content
    for (final file in files) {
      final content = file.path;
      final message = file.message ?? '';
      
      if (file.type == SharedMediaType.url) {
        foundUrl ??= content;
      } else if (file.type == SharedMediaType.text || file.type == SharedMediaType.file) {
        if (foundText == null || content.length > (foundText?.length ?? 0)) {
          foundText = content;
        }
        
        // Try extract URL from text
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
        foundImage ??= content; 
      }
      
      // Fallback Checks
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

      if (foundUrl == null && message.isNotEmpty) {
         final matchesMessage = urlRegExp.allMatches(message);
         for (final match in matchesMessage) {
            final val = match.group(0);
            if (val != null) {
               foundUrl = val;
               break;
            }
         }
         if (foundText == null && message.length > 5) {
            foundText = message;
         }
      }
    }

    // Fallback if no URL found in loop but inside text
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

    String? initialTitle;
    String? initialImage = foundImage; 
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
        String? title = metadata.title;
        if (title != null && title.length > 50) {
          title = '${title.substring(0, 50)}...';
        }
        initialTitle = title;
        if (metadata.imageUrl?.isNotEmpty ?? false) {
          initialImage = metadata.imageUrl;
        }
      }
    } else {
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
                ref.read(temporarilyHiddenHivesProvider.notifier).add(hive.id);
                await ref.read(firestoreServiceProvider).hideHive(hive.id);
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
          allowedEditorIds: hive.allowedEditorIds,
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

} // End of class _HomePageState

class _FriendFeedSkeleton extends StatelessWidget {
  const _FriendFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Container(
                width: 150,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
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
                itemBuilder: (_, __) => Container(
                  width: 160,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: 100,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HiveCardSkeleton extends StatelessWidget {
  const _HiveCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

