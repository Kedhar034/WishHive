import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
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
import 'marketplace_page.dart';
import 'settings_page.dart';
import '../services/metadata_service.dart';
import '../widgets/shimmer_loading.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentNavIndex = 0;
  late StreamSubscription _intentDataStreamSubscription;
  bool _isHandlingShare = false;

  @override
  void initState() {
    super.initState();
    _initShareIntent();
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

    // Iterate through all shared content to find best URL and Text
    for (final file in files) {
      if (file.type == SharedMediaType.text) {
        // If we haven't found a text yet, or this one is longer (more likely to be description), keep it.
        if (foundText == null || file.path.length > foundText.length) {
            foundText = file.path;
        }
        
        // Try extract URL if we haven't found one yet
        if (foundUrl == null) {
            final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
            final match = urlRegExp.firstMatch(file.path);
            if (match != null) {
              foundUrl = match.group(0);
            }
        }
      } else if (file.type == SharedMediaType.image) {
        foundImage ??= file.path; // Keep first image
      }
    }

    // Fallback: Check if the text itself IS a URL if regex didn't catch it inside text
    if (foundUrl == null && foundText != null) {
         final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
         final match = urlRegExp.firstMatch(foundText);
         foundUrl = match?.group(0);
    }

    String? initialTitle;
    String? initialImage = foundImage; // Use shared image by default
    String? finalUrl = foundUrl;

    if (foundUrl != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fetching product details...')),
        );
      }

      final metadata = await MetadataService.extract(foundUrl);
      if (metadata != null) {
        initialTitle = metadata.title;
        // Prefer metadata image if available (usually cleaner product shot)
        // unless we want to prioritize the shared user image? 
        // Metadata image is better for "Wish" visually usually.
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

  void _openHiveDetail(HiveModel hive) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductDetailPage(
          hiveId: hive.id,
          title: hive.title,
          imageUrl: hive.imageUrl,
          ownerId: hive.ownerId,
          ownerDisplayName: hive.ownerDisplayName,
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
      return hiveList.when(
        data: (snapshot) {
          final hiveDocs = snapshot.docs;
          if (hiveDocs.isEmpty) {
            return Center(
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
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: hiveDocs.length,
            itemBuilder: (context, index) {
              final doc = hiveDocs[index];
              final hive = HiveModel.fromFirestore(doc);

              return GestureDetector(
                onTap: () => _openHiveDetail(hive),
                onLongPress: () => _editHive(hive),
                child: HiveCard(
                  heroTag: 'hive-${hive.id}',
                  title: hive.title,
                  items: hive.itemCount,
                  price: hive.totalCost,
                  imageUrl: hive.imageUrl.isNotEmpty
                      ? hive.imageUrl
                      : AppConstants.fallbackImage,
                  ownerName: (hive.ownerId != uid && hive.ownerDisplayName != null)
                      ? hive.ownerDisplayName
                      : null,
                ),
              );
            },
          );
        },
        loading: () => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: 4,
          itemBuilder: (context, index) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: _HiveCardSkeleton(),
            );
          },
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Error loading hives:\n$e', textAlign: TextAlign.center),
            ],
          ),
        ),
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
          const Icon(Icons.home, size: 28),
          
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

class _HiveCardSkeleton extends StatelessWidget {
  const _HiveCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
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
