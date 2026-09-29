import 'package:flutter/material.dart';
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
import '../services/share_link_service.dart';
import '../services/share_link_flow.dart';
import '../widgets/hive_card.dart';
import '../widgets/app_refresh.dart';
import '../services/firestore_service.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'product_detail_page.dart';
import 'create_hive_sheet.dart';
import 'create_wish_sheet.dart';
import 'contacts_page.dart';
import 'hidden_hives_page.dart';
import 'marketplace_page.dart';
import 'settings_page.dart';
import 'menu_page.dart';
import '../services/metadata_service.dart';
import '../services/share_logger.dart'; // Import ShareLogger
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
  late StreamSubscription _intentDataStreamSubscription;
  bool _isHandlingShare = false;
  bool _isInitialLoad = true;

  // Scaffold Key for Drawer control
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Tutorial Keys
  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _hiddenHivesKey = GlobalKey(); // To be assigned to the Hidden Hives Icon

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
        if (mounted) {
           // 1. Showcase the 3D menu with a "Peek" animation
           _peekMenu();
           // 2. Then show the coach marks
           _showTutorial();
        }
      });
    }
  }

  void _peekMenu() {
    // Standard drawer peeking is less common, but we can simulate a brief open/close
    _scaffoldKey.currentState?.openDrawer();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _showTutorial() {
  
  List<TargetFocus> targets = [];

  // Target 1: Create Hive (FAB) - Optional depending on menu
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text(
                  "Create a Wish",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22.0,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 10.0),
                  child: Text(
                    "Tap here to quickly add a new wish or create a new Hive category!",
                    style: TextStyle(color: Colors.white, fontSize: 16.0),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  // Target 2: Side Menu (New Navigation)
  targets.add(
    TargetFocus(
      identify: "side_menu",
      keyTarget: _menuKey,
      alignSkip: Alignment.bottomLeft,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text(
                  "Explore the Hive",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22.0,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 10.0),
                  child: Text(
                    "Tap this icon or simply swipe from the left edge to access your Friends, Marketplace, and Settings.",
                    style: TextStyle(color: Colors.white, fontSize: 16.0),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  // Target 3: Hidden Hives Icon
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text(
                  "Hidden Hives",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22.0,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 10.0),
                  child: Text(
                    "Any hives or friends you hide will appear here. Tap the crossed-eye icon to review them anytime.",
                    style: TextStyle(color: Colors.white, fontSize: 16.0),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  TutorialCoachMark(
    targets: targets,
    colorShadow: Colors.black.withValues(alpha: 0.85),
    textSkip: "SKIP",
    paddingFocus: 10,
    opacityShadow: 0.85,
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
  ).show(context: context);
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

  /// Manual refresh. The lists are already live, so this mainly re-reads the
  /// cached public profiles and gives the user visible feedback.
  Future<void> _refreshHome() async {
    FirestoreService.clearProfileCache();
    ref.invalidate(friendFeedProvider);
    ref.invalidate(hiveListProvider);
    ref.invalidate(unseenWishesByHiveProvider);
    await ref.read(friendFeedProvider.future);
  }

  /// Fraction of the screen width that opens the menu on a left swipe.
  ///
  /// Was a flat 220px — over half the screen on a typical phone, which meant
  /// horizontal drags in the friends carousel opened the drawer instead of
  /// scrolling. A proportion scales correctly across phones and tablets.
  /// Raising this makes the menu easier to open and leaves less room to scroll
  /// the carousel; lowering it does the reverse.
  static const double _drawerDragFraction = 0.35;

  static double _drawerDragWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width * _drawerDragFraction + media.padding.left;
  }

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
    final currentNavIndex = ref.watch(navigationProvider);

    return Scaffold(
      key: _scaffoldKey,
      drawer: MenuPage(
        onPageSelected: (index) {
          ref.read(navigationProvider.notifier).setIndex(index);
        },
      ),
      drawerEdgeDragWidth: _drawerDragWidth(context),
      drawerEnableOpenDragGesture: true,
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
                  // App Name and Logo (Left Side) - Now redirects to Home
                  GestureDetector(
                    onTap: () {
                      ref.read(navigationProvider.notifier).setIndex(0);
                    },
                    child: Row(
                      children: [
                        const CircularLogo(size: 40, showShadow: false),
                        const SizedBox(width: 12),
                        Text(
                          AppConstants.appName,
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Hidden Hives Icon (beside menu)
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
                  const SizedBox(width: 8),
                  // Menu Toggle Icon (Right Side)
                  GestureDetector(
                    key: _menuKey,
                    onTap: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAmber,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryAmber.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.menu, color: Colors.white, size: 24),
                        ),
                        // Notification Badge for Side Menu
                        Consumer(
                          builder: (context, ref, _) {
                            final user = ref.watch(currentUserStreamProvider).value;
                            final requestCount = user?.friendRequestsReceived.length ?? 0;
                            final unseenCount = ref.watch(unseenFulfilledCountProvider).value ?? 0;
                            final totalCount = requestCount + unseenCount;
                            
                            if (totalCount == 0) return const SizedBox.shrink();
                            
                            return Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$totalCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // ... (Rest of body) ...
            Expanded(
              child: IndexedStack(
                index: currentNavIndex,
                children: [
                   AppRefresh(
                     onRefresh: _refreshHome,
                     child: _buildHomeContent(
                         ref.watch(hiveListProvider), Theme.of(context)),
                   ),
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

  // First Pass: Try to find explicit URL and Image from structured intents
  for (final file in files) {
    final content = file.path;
    
    if (file.type == SharedMediaType.url && foundUrl == null) {
      foundUrl = content;
    } else if (file.type == SharedMediaType.image && foundImage == null) {
      foundImage = content; // Grab the FIRST image
    } else if (file.type == SharedMediaType.text || file.type == SharedMediaType.file) {
      if (foundText == null || content.length > foundText.length) {
        foundText = content;
      }
    }
  }

  // Second Pass: If no explicit URL found, parse text/messages using regex
  for (final file in files) {
    if (foundUrl != null) break;

    final content = file.path;
    final message = file.message ?? '';

    // Check content text
    if (content.isNotEmpty) {
       final matchesContent = urlRegExp.allMatches(content);
       for (final match in matchesContent) {
          final val = match.group(0);
          if (val != null) {
             foundUrl = val;
             break;
          }
       }
    }

    // Check message text
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

  // Final Fallback: Check the accumulated text variable
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
  double? initialCost;
  List<String>? initialImages;
  String? finalUrl = foundUrl;
  
  await ShareLogger.log('Processing Share: URL=$finalUrl, Image=$initialImage, Text=$foundText');

  // A WishHive share link is an invitation to view a hive, not a product to add
  // to one. Without this the SEND/text intent filter swallows our own links and
  // turns them into a wish.
  if (finalUrl != null) {
    final shareId = ShareLinkService.shareIdFrom(Uri.tryParse(finalUrl) ?? Uri());
    if (shareId != null) {
      _isHandlingShare = false;
      if (mounted) await openSharedHive(context, ref, shareId);
      return;
    }
  }

  if (finalUrl != null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching product details...')),
      );
    }

    final metadata = await MetadataService.extract(finalUrl);
    if (metadata != null) {
      String title = metadata.title;
      // Truncate to a reasonable length if needed, or leave it intact.
      if (title.length > 80) {
        title = '${title.substring(0, 80)}...';
      }
      initialTitle = title;
      // Prefer extracted metadata image if one exists, fallback to intent image
      if (metadata.imageUrl?.isNotEmpty ?? false) {
        initialImage = metadata.imageUrl;
      }
      if (metadata.hasPrice) initialCost = metadata.price;
      if (metadata.images.length > 1) initialImages = metadata.images;
    }
  } else {
      // If no URL but we got text, set title to text
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
        initialCost: initialCost,
        initialImages: initialImages,
      ),
    );
  } else {
    _isHandlingShare = false;
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
              // Captured before the pop — the dialog's context is gone after it.
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                ref.read(temporarilyHiddenHivesProvider.notifier).add(hive.id);
                await ref.read(firestoreServiceProvider).hideHive(hive.id);
                messenger.showSnackBar(
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
              } catch (e) {
                ref.read(temporarilyHiddenHivesProvider.notifier).remove(hive.id);
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to hide: $e')),
                );
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

