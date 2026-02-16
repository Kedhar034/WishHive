import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
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

  // Phone contacts
  List<Contact> _phoneContacts = [];
  bool _contactsLoaded = false;
  bool _contactsPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPhoneContacts();
  }

  Timer? _debounce;

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPhoneContacts() async {
    // Step 1: Check permission separately
    bool hasPermission = false;
    try {
      hasPermission = await FlutterContacts.requestPermission();
    } catch (e) {
      debugPrint('Error requesting contacts permission: $e');
    }

    if (!hasPermission) {
      if (mounted) setState(() => _contactsPermissionDenied = true);
      return;
    }

    // Step 2: Permission granted — now load contacts
    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) {
        setState(() {
          _phoneContacts = contacts;
          _contactsLoaded = true;
          _contactsPermissionDenied = false; // Reset in case it was set before
        });
      }
    } catch (e) {
      debugPrint('Error loading contacts (permission OK): $e');
      // Permission was granted but loading failed — don't show "denied" UI
      if (mounted) {
        setState(() {
          _phoneContacts = [];
          _contactsLoaded = true; // Show empty list, not "denied" UI
          _contactsPermissionDenied = false;
        });
      }
    }
  }

  void _inviteContact(Contact contact) {
    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
    final name = contact.displayName;
    final inviteText = 'Hey $name! 🐝 Join me on WishHive — the app to organize & share your wishlists with friends. Download it here: https://play.google.com/store/apps/details?id=com.wishhive.app';
    
    Share.share(inviteText);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _acceptRequest(String requesterUid) async {
    try {
      await ref.read(firestoreServiceProvider).acceptFriendRequest(requesterUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend Accepted!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _rejectRequest(String requesterUid) async {
    try {
      await ref.read(firestoreServiceProvider).rejectFriendRequest(requesterUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Rejected')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserAsync = ref.watch(currentUserStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
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
              // 1. Friends Tab (Contains Search + Friends List + Phone Contacts)
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
    final searchQuery = _searchController.text.toLowerCase();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search friends or contacts',
              hintText: 'Search by name, username, or email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: Colors.grey[200],
            ),
            onChanged: (val) {
              _onSearchChanged(val);
              setState(() {}); // Update clear button visibility
            },
          ),
        ),
        if (_isSearching && _searchController.text.isNotEmpty)
          Expanded(child: _buildSearchResultsListView(me))
        else
          Expanded(child: _buildFriendsAndContactsList(me, searchQuery)),
      ],
    );
  }

  Widget _buildFriendsAndContactsList(UserModel me, String searchQuery) {
    // Filter friends by search
    final friends = searchQuery.isEmpty
        ? me.friends
        : me.friends.where((f) =>
            f.displayName.toLowerCase().contains(searchQuery) ||
            f.email.toLowerCase().contains(searchQuery)).toList();

    // Filter phone contacts by search, and exclude existing friends
    final friendEmails = me.friends.map((f) => f.email.toLowerCase()).toSet();
    final filteredContacts = _phoneContacts.where((c) {
      // Exclude contacts that are already friends (match by email)
      final contactEmails = c.emails.map((e) => e.address.toLowerCase()).toSet();
      if (contactEmails.intersection(friendEmails).isNotEmpty) return false;
      // Filter by search
      if (searchQuery.isNotEmpty) {
        return c.displayName.toLowerCase().contains(searchQuery) ||
            c.phones.any((p) => p.number.contains(searchQuery));
      }
      return true;
    }).toList();

    return CustomScrollView(
      slivers: [
        // ─── Friends Section ───────────────────────────────────
        if (friends.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Your Friends',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final friend = friends[index];
                return ListTile(
                  leading: AvatarImage(url: friend.photoUrl),
                  title: Text(friend.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(friend.email),
                  trailing: Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                );
              },
              childCount: friends.length,
            ),
          ),
        ] else if (searchQuery.isEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No friends yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Search above to find users or invite contacts below!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],

        // ─── Divider ───────────────────────────────────────────
        if (friends.isNotEmpty && (filteredContacts.isNotEmpty || !_contactsLoaded))
          SliverToBoxAdapter(
            child: Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey[300]),
          ),

        // ─── Phone Contacts Section ──────────────────────────
        if (_contactsPermissionDenied)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.contacts_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Contacts permission denied',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadPhoneContacts,
                    child: const Text('Grant Permission'),
                  ),
                ],
              ),
            ),
          )
        else if (!_contactsLoaded)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (filteredContacts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Invite from Contacts',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filteredContacts.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAmber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final contact = filteredContacts[index];
                final phone = contact.phones.isNotEmpty ? contact.phones.first.number : 'No phone';
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryAmber.withValues(alpha: 0.15),
                    child: Text(
                      contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: AppTheme.primaryAmber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(phone, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  trailing: OutlinedButton.icon(
                    onPressed: () => _inviteContact(contact),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Invite'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryAmber,
                      side: BorderSide(color: AppTheme.primaryAmber.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                );
              },
              childCount: filteredContacts.length,
            ),
          ),
        ],

        // Bottom padding for nav bar
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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

  Widget _buildRequestsList(List<String> requestIds) {
    if (requestIds.isEmpty) {
      return const Center(child: Text('No pending requests'));
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: FutureBuilder<List<UserModel>>(
        key: ValueKey(requestIds.join(',')), 
        future: ref.read(firestoreServiceProvider).getUsers(requestIds),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
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
