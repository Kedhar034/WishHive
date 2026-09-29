import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/hive_card.dart';
import '../widgets/hive_title.dart';
import '../core/theme/app_theme.dart';
import '../widgets/skeleton_hive_card.dart';
import '../widgets/app_refresh.dart';
import '../services/firestore_service.dart';
import '../core/constants/app_constants.dart';
import 'product_detail_page.dart';
import 'hidden_hives_page.dart';
import 'contacts_page.dart';

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
          cardColor: hive.cardColor,
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
      body: SafeArea(
        bottom: false,
        child: myUserAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (myUser) {
            if (myUser == null) {
              return const Center(child: Text('User not signed in'));
            }

            // No early return on an empty friends list — a hive reached
            // through a share link belongs here even when the two are not
            // friends.
            return ref.watch(friendFeedProvider).when(
              loading: () => ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 90, 16, 100),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, __) => const SkeletonHiveCard(),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (allHives) {
                final hives = allHives
                    .where((h) => !_temporarilyHidden.contains(h.id))
                    .toList();

                return AppRefresh(
                  onRefresh: () async {
                    FirestoreService.clearProfileCache();
                    ref.invalidate(friendFeedProvider);
                    await ref.read(friendFeedProvider.future);
                  },
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (Navigator.of(context).canPop())
                                Padding(
                                  padding: const EdgeInsets.only(right: 4, top: 4),
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    tooltip: 'Back',
                                    onPressed: () => Navigator.of(context).maybePop(),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      myUser.friends.isEmpty
                                          ? 'Shared with you'
                                          : 'From ${myUser.friends.length} '
                                              '${myUser.friends.length == 1 ? 'friend' : 'friends'}',
                                      style: const TextStyle(
                                          fontFamily: AppTheme.fontFamily,
                                          fontSize: 15,
                                          color: AppTheme.muted),
                                    ),
                                    const SizedBox(height: 2),
                                    const HiveTitle("Friends' hives", size: 40),
                                  ],
                                ),
                              ),
                              // Search for someone and add them; hiding
                              // lives behind the eye.
                              IconButton(
                                icon: const Icon(Icons.person_add_alt_1_outlined),
                                tooltip: 'Add a friend',
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.surface,
                                  padding: const EdgeInsets.all(12),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const ContactsPage()),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.visibility_off_outlined),
                                tooltip: 'Hidden hives',
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.surface,
                                  padding: const EdgeInsets.all(12),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const HiddenHivesPage()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (hives.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 64,
                                    color: AppTheme.muted.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                Text('Nothing here yet',
                                    style: theme.textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(
                                  'Add friends from Contacts, or open a hive '
                                  'someone shared with you.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              mainAxisExtent: 188,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final hive = hives[index];
                                final ownerProfile = myUser.friends.firstWhere(
                                  (f) => f.uid == hive.ownerId,
                                  orElse: () => FriendProfile(
                                      uid: '',
                                      displayName: hive.ownerDisplayName,
                                      email: ''),
                                );

                                return GestureDetector(
                                  onTap: () => _openHiveDetail(hive),
                                  onLongPress: () => _showHideHiveDialog(hive),
                                  child: HiveCard(
                                    heroTag: 'feed-hive-${hive.id}',
                                    title: hive.title,
                                    items: hive.itemCount,
                                    price: hive.totalCost,
                                    imageUrl: hive.imageUrl.isNotEmpty
                                        ? hive.imageUrl
                                        : AppConstants.fallbackImage,
                                    ownerName: ownerProfile.displayName,
                                    dateLabel: _formatDate(hive.createdAt),
                                    tintSeed: hive.id,
                                    isCompact: true,
                                  ),
                                );
                              },
                              childCount: hives.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Short enough for the chip on a grid card, which is about six characters
  /// wide before it starts to ellipsise.
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'New';
  }
}
