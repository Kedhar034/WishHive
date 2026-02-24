import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/hive_card.dart';
import '../widgets/skeleton_hive_card.dart';
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

  Future<List<HiveModel>> _fetchFeed(List<FriendProfile> friends, List<String> mutedFriends, List<String> hiddenHiveIds) async {
    return ref.read(firestoreServiceProvider).getFriendsFeed(
      friends, 
      mutedFriendIds: mutedFriends, 
      hiddenHiveIds: hiddenHiveIds,
    );
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

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
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
                }
              } catch (e) {
                // Revert if failed
                setState(() {
                  _temporarilyHidden.remove(hive.id);
                });
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
          
          if (myUser.friends.isEmpty) {
             return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No friends yet',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text('Add friends from Contacts to see their Hives!'),
                ],
              ),
            );
          }

          return FutureBuilder<List<HiveModel>>(
            future: _fetchFeed(myUser.friends, myUser.mutedFriends, myUser.hiddenHiveIds),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, __) => const SkeletonHiveCard(),
                );
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final allHives = snapshot.data ?? [];
              // Filter out optimistically hidden hives
              final hives = allHives.where((h) => !_temporarilyHidden.contains(h.id)).toList();

              if (hives.isEmpty) {
                return const Center(child: Text('No active Hives from friends yet.'));
              }

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {}); // Triggers rebuild and refetch
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
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: (ownerProfile.photoUrl?.isNotEmpty ?? false)
                                      ? CachedNetworkImageProvider(ownerProfile.photoUrl!)
                                      : null,
                                  child: (ownerProfile.photoUrl?.isEmpty ?? true)
                                      ? Text(ownerProfile.displayName.characters.first.toUpperCase())
                                      : null,
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
