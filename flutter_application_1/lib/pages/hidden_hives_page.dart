import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';
import '../models/hive_model.dart';
import '../models/user_model.dart';
import '../widgets/hive_card.dart';
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
      appBar: AppBar(
        title: const Text('Hidden Hives'),
        centerTitle: true,
      ),
      body: myUserAsync.when(
        data: (myUser) {
          if (myUser == null) return const Center(child: Text('User not signed in'));
          
          if (myUser.hiddenHiveIds.isEmpty) {
             return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No hidden hives',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<List<HiveModel>>(
            future: _fetchHiddenFeed(myUser.friends, myUser.hiddenHiveIds),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final hives = snapshot.data ?? [];

              if (hives.isEmpty) {
                // This might happen if hidden hives were deleted by owner
                return const Center(child: Text('No hidden hives found.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: hives.length,
                itemBuilder: (context, index) {
                  final hive = hives[index];
                  // Find owner profile for display
                  final ownerProfile = myUser.friends.firstWhere(
                    (f) => f.uid == hive.ownerId,
                    orElse: () => FriendProfile(uid: '', displayName: 'Unknown', email: ''),
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (ownerProfile.photoUrl?.isNotEmpty ?? false)
                                ? CachedNetworkImageProvider(ownerProfile.photoUrl!)
                                : null,
                            child: (ownerProfile.photoUrl?.isEmpty ?? true)
                                ? Text(ownerProfile.displayName.characters.first.toUpperCase())
                                : null,
                          ),
                          title: Text(hive.title),
                          subtitle: Text('by ${hive.ownerDisplayName}'),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.undo),
                            label: const Text('Unhide'),
                            onPressed: () => _unhideHive(hive.id),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        // Small preview of hive image
                        if (hive.imageUrl.isNotEmpty)
                          SizedBox(
                            height: 120,
                            width: double.infinity,
                            child: CachedNetworkImage(
                              imageUrl: hive.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: Colors.grey[200]),
                              errorWidget: (_, __, ___) => const Icon(Icons.error),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
