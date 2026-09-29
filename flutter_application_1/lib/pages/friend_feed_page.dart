import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/hive_card.dart';
import '../widgets/skeleton_hive_card.dart';
import '../widgets/app_refresh.dart';
import '../services/firestore_service.dart';
import '../widgets/avatar_image.dart';
import '../core/constants/app_constants.dart';
import 'product_detail_page.dart';
import 'hidden_hives_page.dart';

class FriendFeedPage extends ConsumerStatefulWidget {
  const FriendFeedPage({super.key});

  @override
  ConsumerState<FriendFeedPage> createState() => _FriendFeedPageState();
}

class _FriendFeedPageState extends ConsumerState<FriendFeedPage> {
  // Optimistic hiding state
  final Set<String> _temporarilyHidden = {};

  @override
  void initState() {
    super.initState();
    // Initial fetch handled in build via ref.watch logic or standard FutureBuilder
  }

  void _openHiveDetail(HiveModel hive) {
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
          heroTag: 'feed-hive-${hive.id}',
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
                // Optimistic Update: Hide immediately
                setState(() {
                  _temporarilyHidden.add(hive.id);
                });

                // Hide in backend
                await ref.read(firestoreServiceProvider).hideHive(hive.id);
                
                // Do NOT invalidate immediately to avoid jitter
                // ref.invalidate(friendFeedProvider); 

                messenger.showSnackBar(
                    SnackBar(
                      content: Text('Hidden "${hive.title}"'),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () async {
                           setState(() {
                             _temporarilyHidden.remove(hive.id);
                           });
                           await ref.read(firestoreServiceProvider).unhideHive(hive.id);
                           ref.invalidate(friendFeedProvider);
                        },
                      ),
                    ),
                  );
              } catch (e) {
                // Revert if failed
                setState(() {
                  _temporarilyHidden.remove(hive.id);
                });
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

  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Feed'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined, color: Colors.black87),
            tooltip: 'Hidden Hives',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HiddenHivesPage()),
              );
            },
          ),
        ],
      ),
      body: myUserAsync.when(
        data: (myUser) {
          if (myUser == null) return const Center(child: Text('User not signed in'));
          
          // No early return on an empty friends list — a hive reached through a
          // share link belongs here even when the two aren't friends.
          return ref.watch(friendFeedProvider).when(
            loading: () => ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (_, __) => const SkeletonHiveCard(),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (allHives) {
              // Filter out optimistically hidden hives
              final hives = allHives.where((h) => !_temporarilyHidden.contains(h.id)).toList();

              if (hives.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 72, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Nothing here yet',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        const Text(
                          'Add friends from Contacts, or open a hive someone '
                          'shared with you.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return AppRefresh(
                onRefresh: () async {
                  FirestoreService.clearProfileCache();
                  ref.invalidate(friendFeedProvider);
                  await ref.read(friendFeedProvider.future);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: hives.length,
                  itemBuilder: (context, index) {
                    final hive = hives[index];
                    // Find owner profile for display
                    final ownerProfile = myUser.friends.firstWhere(
                      (f) => f.uid == hive.ownerId,
                      orElse: () => FriendProfile(uid: '', displayName: 'Unknown', email: ''),
                    );

                    return GestureDetector(
                      onTap: () => _openHiveDetail(hive),
                      onLongPress: () => _showHideHiveDialog(hive),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Owner Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                AvatarImage(
                                  url: ownerProfile.photoUrl,
                                  radius: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ownerProfile.displayName,
                                  style: theme.textTheme.labelLarge,
                                ),
                                const Spacer(),
                                Text(
                                  _formatDate(hive.createdAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          // Hive Card
                          HiveCard(
                            heroTag: 'feed-hive-${hive.id}',
                            title: hive.title,
                            items: hive.itemCount,
                            price: hive.totalCost,
                            imageUrl: hive.imageUrl.isNotEmpty
                                ? hive.imageUrl
                                : AppConstants.fallbackImage,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
