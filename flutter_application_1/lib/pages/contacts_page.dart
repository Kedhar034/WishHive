import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/providers.dart';
import '../widgets/avatar_image.dart';
import '../core/theme/app_theme.dart';

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Timer? _debounce;

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
      return;
    }

    if (mounted) setState(() => _isSearching = true);
    try {
      final results = await ref.read(firestoreServiceProvider).searchUsers(query);
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _sendRequest(String targetUid) async {
    try {
      await ref.read(firestoreServiceProvider).sendFriendRequest(targetUid);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Sent!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _acceptRequest(String requesterUid) async {
    try {
      await ref.read(firestoreServiceProvider).acceptFriendRequest(requesterUid);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend Accepted!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _rejectRequest(String requesterUid) async {
    try {
      await ref.read(firestoreServiceProvider).rejectFriendRequest(requesterUid);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Rejected')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find your friends!!'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: myUserAsync.when(
        data: (myUser) {
          if (myUser == null) return const Center(child: Text('User not found'));

          return TabBarView(
            controller: _tabController,
            children: [
              // 1. Friends Tab (Contains Search + Friends List)
              _buildFriendsTab(myUser),
              
              // 2. Requests List
              _buildRequestsList(myUser.friendRequestsReceived),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildFriendsTab(UserModel me) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search and add new friends',
              hintText: 'Search by username or email',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: Colors.grey[200],
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_isSearching && _searchController.text.isNotEmpty)
          Expanded(child: _buildSearchResultsListView(me))
        else
          Expanded(child: _buildFriendsList(me.friends)),
      ],
    );
  }

  Widget _buildSearchResultsListView(UserModel me) {
     // Filter out myself from results
     final filteredResults = _searchResults.where((u) => u.uid != me.uid).toList();

     if (filteredResults.isEmpty) {
       return Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
             const SizedBox(height: 16),
             Text(
               'No other users found',
               style: TextStyle(color: Colors.grey[600], fontSize: 16),
             ),
           ],
         ),
       );
     }

     return ListView.builder(
        itemCount: filteredResults.length,
        itemBuilder: (context, index) {
          final user = filteredResults[index];
          
          final isFriend = me.friends.any((f) => f.uid == user.uid);
          final isPending = me.friendRequestsSent.contains(user.uid);
          final hasReceived = me.friendRequestsReceived.contains(user.uid);

          final displayName = (user.username != null && user.username!.isNotEmpty)
              ? user.username![0].toUpperCase() + user.username!.substring(1)
              : user.displayName;
          final subtitle = user.username != null ? '@${user.username}' : user.email;

          return ListTile(
            leading: AvatarImage(url: user.photoUrl),
            title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle),
            trailing: isFriend
                ? const Icon(Icons.check_circle, color: Colors.green)
                : isPending
                    ? const Text('Sent', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                    : hasReceived
                        ? ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                            onPressed: () => _acceptRequest(user.uid), 
                            child: const Text('Accept'),
                          )
                        : ElevatedButton(
                            onPressed: () => _sendRequest(user.uid), 
                            child: const Text('Add'),
                          ),
          );
        },
      );
  }

  Widget _buildFriendsList(List<FriendProfile> friends) {
    if (friends.isEmpty) {
      return const Center(child: Text('No friends yet. Search above to add some!'));
    }
    
    return ListView.builder(
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return ListTile(
          leading: AvatarImage(url: friend.photoUrl),
          title: Text(friend.displayName),
          subtitle: Text(friend.email),
          onTap: () {
             // Navigate to friend's profile
          },
        );
      },
    );
  }

  Widget _buildRequestsList(List<String> requestIds) {
    if (requestIds.isEmpty) {
      return const Center(child: Text('No pending requests'));
    }

    // transform list of IDs into a stream of List<UserModel>?
    // Actually, simpler: Just use a widget that watches a provider for THESE users.
    // Or, since we want instant updates, we can just key the FutureBuilder?
    // No, FutureBuilder is not 'instant' enough if the underlying data changes. 
    // Ideally, we should stream each user document.
    
    // For now, let's allow manual refresh or auto-refresh by keying it to the length/IDs.
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {}); // Triggers rebuild of FutureBuilder
      },
      child: FutureBuilder<List<UserModel>>(
        // Key the FutureBuilder so it rebuilds when the list of IDs changes instantly
        key: ValueKey(requestIds.join(',')), 
        future: ref.read(firestoreServiceProvider).getUsers(requestIds),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
             // Allow retry
             return Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Text('Error: ${snapshot.error}'),
                   IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState((){}))
                 ],
               ));
          }

          final users = snapshot.data ?? [];
          if (users.isEmpty) {
             return const Center(child: Text('No requests found'));
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: AvatarImage(url: user.photoUrl),
                title: Text(user.displayName),
                subtitle: const Text('Wants to be your friend'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _acceptRequest(user.uid),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _rejectRequest(user.uid),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
