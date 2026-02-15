import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/hive_card.dart';
import '../core/constants/app_constants.dart';
import 'product_detail_page.dart';

class FriendFeedPage extends ConsumerStatefulWidget {
  const FriendFeedPage({super.key});

  @override
  ConsumerState<FriendFeedPage> createState() => _FriendFeedPageState();
}

class _FriendFeedPageState extends ConsumerState<FriendFeedPage> {
  Future<List<HiveModel>>? _feedFuture;

  @override
  void initState() {
    super.initState();
    // Initial fetch handled in build via ref.watch logic or standard FutureBuilder
  }

  Future<List<HiveModel>> _fetchFeed(List<FriendProfile> friends) async {
    final friendIds = friends.map((f) => f.uid).toList();
    if (friendIds.isEmpty) return [];
    return ref.read(firestoreServiceProvider).getFriendsFeed(friendIds);
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
    final myUserAsync = ref.watch(currentUserStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Feed'),
        centerTitle: true,
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

          // Fetch feed using FutureBuilder
          return FutureBuilder<List<HiveModel>>(
            future: _fetchFeed(myUser.friends),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final hives = snapshot.data ?? [];

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
                                  backgroundImage: NetworkImage(
                                    ownerProfile.photoUrl ?? 'https://via.placeholder.com/150'
                                  ),
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
