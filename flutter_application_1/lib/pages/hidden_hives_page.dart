import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/app_refresh.dart';
import '../widgets/hive_card.dart';
import '../widgets/hive_title.dart';
import '../core/theme/app_theme.dart';
import '../core/constants/app_constants.dart';

class HiddenHivesPage extends ConsumerStatefulWidget {
  const HiddenHivesPage({super.key});

  @override
  ConsumerState<HiddenHivesPage> createState() => _HiddenHivesPageState();
}

class _HiddenHivesPageState extends ConsumerState<HiddenHivesPage> {
  
  Future<List<HiveModel>> _fetchHiddenFeed(List<FriendProfile> friends, List<String> hiddenHiveIds) async {
    // We pass onlyHidden: true to get ONLY the hives that are in hiddenHiveIds
    return ref.read(firestoreServiceProvider).getFriendsFeed(
      friends, 
      hiddenHiveIds: hiddenHiveIds,
      onlyHidden: true,
    );
  }

  Future<void> _unhideHive(String hiveId) async {
    try {
      // Clear optimistic hiding state if present
      ref.read(temporarilyHiddenHivesProvider.notifier).remove(hiveId);
      
      await ref.read(firestoreServiceProvider).unhideHive(hiveId);
      // Invalidate providers to refresh other screens
      ref.invalidate(friendFeedProvider);
      setState(() {}); // Rebuild to refresh this list
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Hive unhidden')),
         );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to unhide: $e')),
         );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: HiveTitle('Hidden hives', size: 34),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: myUserAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (myUser) {
                  if (myUser == null) {
                    return const Center(child: Text('User not signed in'));
                  }

                  if (myUser.hiddenHiveIds.isEmpty) {
                    return _empty(theme, 'Nothing hidden',
                        'Long-press a hive in Friends\' hives to hide it from '
                        'your feed.');
                  }

                  return AppRefresh(
                    onRefresh: () async {
                      if (mounted) setState(() {});
                    },
                    child: FutureBuilder<List<HiveModel>>(
                      future: _fetchHiddenFeed(
                          myUser.friends, myUser.hiddenHiveIds),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }

                        final hives = snapshot.data ?? [];
                        if (hives.isEmpty) {
                          // The owner may have deleted a hive that is still
                          // listed as hidden.
                          return _empty(theme, 'Nothing to show',
                              'The hives you hid are no longer available.');
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            mainAxisExtent: 188,
                          ),
                          itemCount: hives.length,
                          itemBuilder: (context, index) {
                            final hive = hives[index];
                            final ownerProfile = myUser.friends.firstWhere(
                              (f) => f.uid == hive.ownerId,
                              orElse: () => FriendProfile(
                                  uid: '',
                                  displayName: hive.ownerDisplayName,
                                  email: ''),
                            );

                            return Stack(
                              children: [
                                // Dimmed, because these are the ones being
                                // kept out of the way.
                                Opacity(
                                  opacity: 0.55,
                                  child: HiveCard(
                                    title: hive.title,
                                    items: hive.itemCount,
                                    price: hive.totalCost,
                                    imageUrl: hive.imageUrl.isNotEmpty
                                        ? hive.imageUrl
                                        : AppConstants.fallbackImage,
                                    ownerName: ownerProfile.displayName,
                                    tintSeed: hive.id,
                                    colorKey: hive.cardColor,
                                    isCompact: true,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.undo_rounded),
                                    iconSize: 18,
                                    tooltip: 'Unhide',
                                    onPressed: () => _unhideHive(hive.id),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppTheme.ink,
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme, String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off_outlined,
                size: 64, color: AppTheme.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
