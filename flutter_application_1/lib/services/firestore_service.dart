import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/hive_model.dart';
import '../models/wish_model.dart';
import '../models/user_model.dart';
import '../models/public_profile.dart';
import 'image_storage_service.dart';

/// Centralized Firestore service for all Hive and Wish CRUD operations.
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference _hivesCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('hives');
  }

  CollectionReference _wishesCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('wishes');
  }
  
  CollectionReference get _usersCollection {
    return _firestore.collection('users');
  }

  // ─── Public profiles ──────────────────────────────────────────────
  // Read once and cached, replacing the copies that used to be denormalised
  // into every friend's document.

  static final Map<String, PublicProfile> _profileCache = {};

  Future<PublicProfile?> getPublicProfile(String uid, {bool refresh = false}) async {
    if (!refresh && _profileCache.containsKey(uid)) return _profileCache[uid];
    try {
      final doc = await _firestore.doc('users/$uid/public/profile').get();
      if (!doc.exists) return null;
      final p = PublicProfile.fromFirestore(doc, uid);
      _profileCache[uid] = p;
      return p;
    } catch (e) {
      debugPrint('getPublicProfile($uid) failed: $e');
      return null;
    }
  }

  Future<Map<String, PublicProfile>> getPublicProfiles(List<String> uids) async {
    final out = <String, PublicProfile>{};
    final missing = <String>[];
    for (final uid in uids) {
      final cached = _profileCache[uid];
      if (cached != null) {
        out[uid] = cached;
      } else {
        missing.add(uid);
      }
    }
    await Future.wait(missing.map((uid) async {
      final p = await getPublicProfile(uid);
      if (p != null) out[uid] = p;
    }));
    return out;
  }

  static void clearProfileCache() => _profileCache.clear();

  // ─── User & Friend Operations ─────────────────────────────────────

  /// Create or update a user document.
  Future<void> updateUser(UserModel user) async {
    try {
      final data = user.toFirestore();
      // Remove null values to avoid overwriting existing data with null
      data.removeWhere((key, value) => value == null);

      // CRITICAL FIX: Prevent overwriting social graph arrays with empty lists
      // when updating profile details (e.g. username/photo).
      // These fields are managed efficiently by atomic arrayUnion/arrayRemove operations.
      data.remove('friends');
      data.remove('friendRequestsSent');
      data.remove('friendRequestsReceived');
      // Also owned by dedicated operations (muteFriend / hideHive). An empty
      // list survives the null-strip above, so any caller constructing a fresh
      // UserModel rather than using copyWith would otherwise erase them.
      data.remove('mutedFriends');
      data.remove('hiddenHiveIds');

      await _usersCollection.doc(user.uid).set(
            data,
            SetOptions(merge: true),
          );
          
      // Background fan-out sync to update friend lists with new name/photo
      _syncUserProfileToFriends(user).catchError((e) => debugPrint('Error syncing profile: $e'));
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  /// Search for users by username.
  ///
  /// Reads public profiles only. The previous version queried whole user
  /// documents, so every search returned the matched users' email addresses
  /// and their entire friends list \u2014 including those friends' emails.
  Future<List<UserModel>> searchUsers(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    try {
      // Exact username first \u2014 the claim document maps name to uid directly.
      final claim = await _firestore.doc('usernames/$q').get();
      if (claim.exists) {
        final uid = claim.data()?['uid'] as String?;
        if (uid != null) {
          final p = await getPublicProfile(uid, refresh: true);
          if (p != null) return [_asUserModel(p)];
        }
      }

      final snap = await _firestore
          .collectionGroup('public')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q\uf8ff')
          .limit(20)
          .get();

      return snap.docs.map((d) {
        final uid = d.reference.parent.parent!.id;
        final p = PublicProfile.fromFirestore(d, uid);
        _profileCache[uid] = p;
        return _asUserModel(p);
      }).toList();
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  UserModel _asUserModel(PublicProfile p) => UserModel(
        uid: p.uid,
        email: '', // never exposed through search
        displayName: p.displayName,
        username: p.username,
        photoUrl: p.photoUrl,
      );

  /// Check if a username is available (case-insensitive).
  ///
  /// Advisory only — two users can pass this at the same moment. Use
  /// [claimUsername] to actually take the name.
  Future<bool> isUsernameAvailable(String username) async {
    final name = username.toLowerCase().trim();
    if (name.isEmpty) return false;

    // Preferred check. If this collection is unreadable — rules not deployed
    // yet — fall through to the legacy check rather than reporting every name
    // as taken.
    try {
      final doc = await _firestore.doc('usernames/$name').get();
      if (doc.exists) return doc.data()?['uid'] == _uid;
    } catch (e) {
      debugPrint('usernames lookup unavailable, using legacy check: $e');
    }

    try {
      final query = await _usersCollection
          .where('username', isEqualTo: name)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return true;
      return query.docs.first.id == _uid;
    } catch (e) {
      debugPrint('Error checking username: $e');
      return false; // Fail safe
    }
  }

  /// Atomically take [username], returning false if someone else got there
  /// first. The document id *is* the name, and the rules forbid overwriting an
  /// existing one, so the create either succeeds or the name was taken — there
  /// is no window between checking and claiming.
  Future<bool> claimUsername(String username) async {
    final uid = _uid;
    if (uid == null) return false;
    final name = username.toLowerCase().trim();
    if (name.isEmpty) return false;

    try {
      await _firestore.doc('usernames/$name').set({'uid': uid});
    } catch (e) {
      // A denied write means either the name is held by someone else, or the
      // usernames rules are not deployed. Read it back to tell those apart —
      // otherwise an undeployed ruleset blocks every signup.
      try {
        final doc = await _firestore.doc('usernames/$name').get();
        if (doc.exists && doc.data()?['uid'] != uid) {
          debugPrint('Username "$name" is held by another account');
          return false;
        }
      } catch (_) {
        // Not even readable — the collection isn't live yet.
      }
      debugPrint('Username claim unavailable, continuing without it: $e');
      return true;
    }

    // Release any name this user previously held.
    try {
      final previous = await _firestore
          .collection('usernames')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in previous.docs) {
        if (doc.id != name) await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Could not release previous username: $e');
    }
    return true;
  }
  
  /// Send a friend request to [targetUid].
  Future<void> sendFriendRequest(String targetUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    
    try {
      final batch = _firestore.batch();
      
      // 1. Add to sender's 'sent' list
      final senderRef = _usersCollection.doc(uid);
      batch.update(senderRef, {
        'friendRequestsSent': FieldValue.arrayUnion([targetUid])
      });
      
      // 2. Add to target's 'received' list
      final targetRef = _usersCollection.doc(targetUid);
      batch.update(targetRef, {
        'friendRequestsReceived': FieldValue.arrayUnion([uid])
      });
      
      await batch.commit();
    } catch (e) {
      debugPrint('Error sending friend request: $e');
      rethrow;
    }
  }
  
  /// Accept a friend request from [requesterUid].
  Future<void> acceptFriendRequest(String requesterUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    
    try {
      final meRef = _usersCollection.doc(uid);
      final requesterRef = _usersCollection.doc(requesterUid);
      
      await _firestore.runTransaction((transaction) async {
        final meDoc = await transaction.get(meRef);
        final requesterDoc = await transaction.get(requesterRef);
        
        if (!meDoc.exists || !requesterDoc.exists) {
          throw Exception('User not found');
        }
        
        final meData = UserModel.fromFirestore(meDoc);
        final requesterData = UserModel.fromFirestore(requesterDoc);
        
        final meProfile = FriendProfile(
          uid: meData.uid,
          displayName: meData.displayName,
          photoUrl: meData.photoUrl,
          email: meData.email,
        );
        
        final requesterProfile = FriendProfile(
          uid: requesterData.uid,
          displayName: requesterData.displayName,
          photoUrl: requesterData.photoUrl,
          email: requesterData.email,
        );
        
        // 1. Update Me: Add Friend, Remove Request Received
        transaction.update(meRef, {
          'friends': FieldValue.arrayUnion([requesterProfile.toMap()]),
          'friendRequestsReceived': FieldValue.arrayRemove([requesterUid]),
        });
        
        // 2. Update Requester: Add Friend, Remove Request Sent
        transaction.update(requesterRef, {
          'friends': FieldValue.arrayUnion([meProfile.toMap()]),
          'friendRequestsSent': FieldValue.arrayRemove([uid]),
        });
      });
    } catch (e) {
      debugPrint('Error accepting friend request: $e');
      rethrow;
    }
  }
  
  /// Propagates a changed name/photo into friends' denormalised copies.
  ///
  /// Swaps only this user's own card via arrayRemove/arrayUnion. The previous
  /// implementation rewrote each friend's entire array from a stale read, which
  /// silently deleted any friendship added while the loop was running.
  ///
  /// Deleted once reads move to users/{uid}/public/profile.
  Future<void> _syncUserProfileToFriends(UserModel user) async {
    try {
      final meDoc = await _usersCollection.doc(user.uid).get();
      if (!meDoc.exists) return;

      final latestMe = UserModel.fromFirestore(meDoc);
      if (latestMe.friends.isEmpty) return;

      final newCard = FriendProfile(
        uid: latestMe.uid,
        displayName: latestMe.displayName,
        photoUrl: latestMe.photoUrl,
        email: latestMe.email,
      ).toMap();

      for (final friend in latestMe.friends) {
        final friendRef = _usersCollection.doc(friend.uid);
        try {
          final friendDoc = await friendRef.get();
          if (!friendDoc.exists) continue;

          final theirView = UserModel.fromFirestore(friendDoc)
              .friends
              .where((f) => f.uid == user.uid)
              .toList();
          if (theirView.isEmpty) continue;

          final oldCard = theirView.first.toMap();
          if (_sameCard(oldCard, newCard)) continue;

          await friendRef.update({
            'friends': FieldValue.arrayRemove([oldCard])
          });
          await friendRef.update({
            'friends': FieldValue.arrayUnion([newCard])
          });
        } catch (e) {
          debugPrint('Profile sync skipped for ${friend.uid}: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to sync profile to friends: $e');
    }
  }

  bool _sameCard(Map<String, dynamic> a, Map<String, dynamic> b) {
    return a['uid'] == b['uid'] &&
        a['displayName'] == b['displayName'] &&
        a['photoUrl'] == b['photoUrl'] &&
        a['email'] == b['email'];
  }
  
  /// Remove a friendship, in both directions.
  ///
  /// Also revokes any specific-hive access granted to them, so the hives they
  /// could see disappear along with the friendship rather than lingering as
  /// stale grants.
  Future<void> removeFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final meRef = _usersCollection.doc(uid);
      final themRef = _usersCollection.doc(friendUid);

      final meSnap = await meRef.get();
      final themSnap = await themRef.get();

      // arrayRemove needs the exact stored map, so read each side's copy.
      if (meSnap.exists) {
        final theirCard = UserModel.fromFirestore(meSnap)
            .friends
            .where((f) => f.uid == friendUid)
            .toList();
        if (theirCard.isNotEmpty) {
          await meRef.update({
            'friends': FieldValue.arrayRemove([theirCard.first.toMap()]),
          });
        }
      }

      if (themSnap.exists) {
        final myCard = UserModel.fromFirestore(themSnap)
            .friends
            .where((f) => f.uid == uid)
            .toList();
        if (myCard.isNotEmpty) {
          await themRef.update({
            'friends': FieldValue.arrayRemove([myCard.first.toMap()]),
          });
        }
      }

      // Drop any pending request either way, and unmute.
      await meRef.update({
        'friendRequestsSent': FieldValue.arrayRemove([friendUid]),
        'friendRequestsReceived': FieldValue.arrayRemove([friendUid]),
        'mutedFriends': FieldValue.arrayRemove([friendUid]),
      });
      await themRef.update({
        'friendRequestsSent': FieldValue.arrayRemove([uid]),
        'friendRequestsReceived': FieldValue.arrayRemove([uid]),
      }).catchError((_) {});

      await _revokeHiveAccessFor(uid, friendUid);

      // Keep the migrated structure in step where it already exists.
      await _firestore.doc('users/$uid/friends/$friendUid').delete().catchError((_) {});
      await _firestore.doc('users/$friendUid/friends/$uid').delete().catchError((_) {});
    } catch (e) {
      debugPrint('Error removing friend: $e');
      rethrow;
    }
  }

  /// Strip [friendUid] from every access list on [uid]'s hives.
  Future<void> _revokeHiveAccessFor(String uid, String friendUid) async {
    final hives = await _hivesCollection(uid).get();
    for (final doc in hives.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final viewers = List<String>.from(
          data['viewerIds'] ?? data['allowedViewerIds'] ?? []);
      final editors = List<String>.from(
          data['editorIds'] ?? data['allowedEditorIds'] ?? []);

      if (!viewers.contains(friendUid) && !editors.contains(friendUid)) continue;

      viewers.remove(friendUid);
      editors.remove(friendUid);
      await doc.reference.update({
        'viewerIds': viewers,
        'editorIds': editors,
        'allowedViewerIds': viewers,
        'allowedEditorIds': editors,
      });
    }
  }

  /// Withdraw a request this user sent to [targetUid].
  Future<void> cancelFriendRequest(String targetUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final batch = _firestore.batch();
      batch.update(_usersCollection.doc(uid), {
        'friendRequestsSent': FieldValue.arrayRemove([targetUid]),
      });
      batch.update(_usersCollection.doc(targetUid), {
        'friendRequestsReceived': FieldValue.arrayRemove([uid]),
      });
      await batch.commit();

      // Keep the migrated structure in step where it already exists.
      await _firestore
          .doc('users/$targetUid/friendRequests/$uid')
          .delete()
          .catchError((_) {});
      await _firestore
          .doc('users/$uid/sentRequests/$targetUid')
          .delete()
          .catchError((_) {});
    } catch (e) {
      debugPrint('Error cancelling friend request: $e');
      rethrow;
    }
  }

  /// File a moderation report. Write-only for users — only moderators read the
  /// `reports` collection.
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String targetOwnerUid,
    required String reason,
    String details = '',
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    await _firestore.collection('reports').add({
      'reporterUid': uid,
      'targetType': targetType,
      'targetId': targetId,
      'targetOwnerUid': targetOwnerUid,
      'reason': reason.length > 64 ? reason.substring(0, 64) : reason,
      'details': details.length > 1000 ? details.substring(0, 1000) : details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reject a friend request from [requesterUid].
  Future<void> rejectFriendRequest(String requesterUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    
    try {
      final batch = _firestore.batch();
      
      final meRef = _usersCollection.doc(uid);
      final requesterRef = _usersCollection.doc(requesterUid);
      
      // 1. Update Me: Remove Request Received
      batch.update(meRef, {
        'friendRequestsReceived': FieldValue.arrayRemove([requesterUid]),
      });
      
      // 2. Update Requester: Remove Request Sent
      batch.update(requesterRef, {
        'friendRequestsSent': FieldValue.arrayRemove([uid]),
      });
      
      await batch.commit();
    } catch (e) {
      debugPrint('Error rejecting friend request: $e');
      rethrow;
    }
  }

  /// Mute a friend (hide their hives from feed).
  Future<void> muteFriend(String friendId) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      await _usersCollection.doc(uid).update({
        'mutedFriends': FieldValue.arrayUnion([friendId])
      });
    } catch (e) {
      debugPrint('Error muting friend: $e');
      rethrow;
    }
  }

  /// Unmute a friend.
  Future<void> unmuteFriend(String friendId) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      await _usersCollection.doc(uid).update({
        'mutedFriends': FieldValue.arrayRemove([friendId])
      });
    } catch (e) {
      debugPrint('Error unmuting friend: $e');
      rethrow;
    }
  }

  /// Get a single user by ID.
  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user $userId: $e');
      return null;
    }
  }

  /// Get multiple users by ID. Reads public profiles, not full user documents.
  Future<List<UserModel>> getUsers(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    try {
      final profiles = await getPublicProfiles(userIds);
      return userIds
          .where(profiles.containsKey)
          .map((uid) => _asUserModel(profiles[uid]!))
          .toList();
    } catch (e) {
      debugPrint('Error fetching users batch: $e');
      return [];
    }
  }

  /// Stream of my User object (for real-time updates on requests/friends).
  Stream<UserModel?> get myUserStream {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return userStream(uid);
  }

  /// Stream of a specific user's object by UID.
  Stream<UserModel?> userStream(String uid) {
    return _usersCollection.doc(uid).snapshots().map((doc) {
      if (doc.exists) return UserModel.fromFirestore(doc);
      return null;
    });
  }

  // ─── Hive Operations ──────────────────────────────────────────────

  /// Create a new hive. Returns the generated document ID.
  Future<String> createHive(HiveModel hive) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final docRef = _hivesCollection(uid).doc();
      // Fetch user profile if display name is missing
      String displayName = hive.ownerDisplayName;
      if (displayName.isEmpty) {
         final userDoc = await _usersCollection.doc(uid).get();
         if (userDoc.exists) {
           final user = UserModel.fromFirestore(userDoc);
           displayName = user.displayName;
         }
      }
      
      final hiveWithId = hive.copyWith(
        id: docRef.id, 
        ownerId: uid,
        ownerDisplayName: displayName,
      );
      await docRef.set(hiveWithId.toFirestore());
      debugPrint('Hive created: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating hive: $e');
      rethrow;
    }
  }

  /// Update an existing hive.
  Future<void> updateHive(HiveModel hive) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      await _hivesCollection(uid).doc(hive.id).update({
        'title': hive.title,
        'imageUrl': hive.imageUrl,
        'note': hive.note,
        'privacy': hive.privacy.name,
        'viewerIds': hive.allowedViewerIds,
        'editorIds': hive.allowedEditorIds,
        'allowedViewerIds': hive.allowedViewerIds,
        'allowedEditorIds': hive.allowedEditorIds,
        // Null clears it, which puts the card back on its id-derived tint.
        'cardColor': hive.cardColor,
      });
    } catch (e) {
      debugPrint('Error updating hive: $e');
      rethrow;
    }
  }

  static const String shareDomain = 'flutterapplication-77c19.web.app';

  /// Returns the shareable URL for [hiveId], generating the token on first use.
  ///
  /// The token is random and separate from the document id, so links cannot be
  /// guessed and a leaked one can be killed without deleting the hive.
  Future<String> ensureShareLink(String hiveId) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    final ref = _firestore.doc('hives/$hiveId');
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Hive not found');

    final data = snap.data() as Map<String, dynamic>;
    if (data['ownerId'] != uid) throw Exception('Only the owner can share this hive');

    var shareId = data['shareId'] as String? ?? '';
    final enabled = data['linkShareEnabled'] as bool? ?? false;

    if (shareId.isEmpty || !enabled) {
      if (shareId.isEmpty) shareId = _randomShareId();
      await ref.update({'shareId': shareId, 'linkShareEnabled': true});
      await _hivesCollection(uid)
          .doc(hiveId)
          .update({'shareId': shareId, 'linkShareEnabled': true})
          .catchError((_) {});
    }

    return 'https://$shareDomain/h/$shareId';
  }

  /// Stops new people redeeming the link. Anyone already granted keeps access
  /// until the owner removes them in Manage Access.
  Future<void> disableShareLink(String hiveId) async {
    await _firestore.doc('hives/$hiveId').update({'linkShareEnabled': false});
    final uid = _uid;
    if (uid != null) {
      await _hivesCollection(uid)
          .doc(hiveId)
          .update({'linkShareEnabled': false})
          .catchError((_) {});
    }
  }

  static const _shareAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

  String _randomShareId() {
    final rand = Random.secure();
    return List.generate(12, (_) => _shareAlphabet[rand.nextInt(_shareAlphabet.length)])
        .join();
  }

  /// Delete a hive and all its associated wishes, including image cleanup.
  Future<void> deleteHive(String hiveId) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      // Get all wishes for this hive to clean up images
      final wishesSnapshot = await _wishesCollection(uid)
          .where('hiveId', isEqualTo: hiveId)
          .get();

      // Batched so a mid-loop failure cannot leave orphaned wishes behind,
      // which would keep firing the unseen-fulfilled badge for a hive that no
      // longer exists.
      for (var i = 0; i < wishesSnapshot.docs.length; i += 400) {
        final end = (i + 400 < wishesSnapshot.docs.length)
            ? i + 400
            : wishesSnapshot.docs.length;
        final batch = _firestore.batch();
        for (final wishDoc in wishesSnapshot.docs.sublist(i, end)) {
          batch.delete(wishDoc.reference);
        }
        await batch.commit();
      }

      for (final wishDoc in wishesSnapshot.docs) {
        final wishData = wishDoc.data() as Map<String, dynamic>;
        final imageUrl = wishData['imageUrl'] as String? ?? '';
        if (ImageStorageService.isLocalPath(imageUrl)) {
          await ImageStorageService.deleteImage(imageUrl);
        }
      }

      // Delete hive image
      final hiveDoc = await _hivesCollection(uid).doc(hiveId).get();
      if (hiveDoc.exists) {
        final hiveData = hiveDoc.data() as Map<String, dynamic>;
        final imageUrl = hiveData['imageUrl'] as String? ?? '';
        if (ImageStorageService.isLocalPath(imageUrl)) {
          await ImageStorageService.deleteImage(imageUrl);
        }
      }

      // Delete the hive document
      await _hivesCollection(uid).doc(hiveId).delete();
      debugPrint('Hive deleted: $hiveId');
    } catch (e) {
      debugPrint('Error deleting hive: $e');
      rethrow;
    }
  }

  /// Stream of hive snapshots for the current user.
  Stream<QuerySnapshot> hivesStream(String uid) {
    return _hivesCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ─── Wish Operations ──────────────────────────────────────────────

  /// Create a new wish and update the parent hive's aggregates.
  Future<String> createWish(WishModel wish) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final docRef = _wishesCollection(uid).doc();
      final wishWithId = wish.copyWith(id: docRef.id);
      await docRef.set(wishWithId.toFirestore());

      // Update hive aggregates atomically
      await _hivesCollection(uid).doc(wish.hiveId).update({
        'itemCount': FieldValue.increment(1),
        'totalCost': FieldValue.increment(wish.cost),
      });

      debugPrint('Wish created: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating wish: $e');
      rethrow;
    }
  }

  /// Add a wish to a friend's hive (when caller has edit-access).
  /// Writes to [hiveOwnerId]'s wishes sub-collection, not the caller's.
  Future<String> addWishToFriendsHive(String hiveOwnerId, WishModel wish) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final docRef = _wishesCollection(hiveOwnerId).doc();
      final wishWithId = wish.copyWith(id: docRef.id);
      await docRef.set(wishWithId.toFirestore());

      // Update hive aggregates atomically
      await _hivesCollection(hiveOwnerId).doc(wish.hiveId).update({
        'itemCount': FieldValue.increment(1),
        'totalCost': FieldValue.increment(wish.cost),
      });

      debugPrint('Friend added wish: ${docRef.id} to hive owner: $hiveOwnerId');
      return docRef.id;
    } catch (e) {
      debugPrint('Error adding wish to friends hive: \$e');
      rethrow;
    }
  }

  /// Update an existing wish.
  ///
  /// [ownerId] is the hive owner — pass it when a friend edits a wish in
  /// someone else's hive, otherwise the write targets the wrong collection.
  ///
  /// Keeps the parent hive's aggregates correct. The previous version changed
  /// `cost` without touching `totalCost`, so a hive's total was wrong from the
  /// first price edit onwards and never recovered.
  Future<void> updateWish(WishModel wish, {String? ownerId}) async {
    final uid = ownerId ?? _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final ref = _wishesCollection(uid).doc(wish.id);
      final before = await ref.get();
      if (!before.exists) throw Exception('Wish not found');

      final beforeData = before.data() as Map<String, dynamic>;
      final oldCost = (beforeData['cost'] as num?)?.toDouble() ?? 0.0;
      final oldHiveId = beforeData['hiveId'] as String? ?? wish.hiveId;

      await ref.update({
        'name': wish.name,
        'subtitle': wish.subtitle,
        'imageUrl': wish.imageUrl,
        'hiveId': wish.hiveId,
        'note': wish.note,
        'link': wish.link,
        'cost': wish.cost,
        'quantity': wish.quantity,
        'date': wish.date != null ? Timestamp.fromDate(wish.date!) : null,
        'fulfilledBy': wish.fulfilledBy,
        'fulfilledByName': wish.fulfilledByName,
      });

      if (oldHiveId == wish.hiveId) {
        final delta = wish.cost - oldCost;
        if (delta != 0) {
          await _hivesCollection(uid).doc(wish.hiveId).update({
            'totalCost': FieldValue.increment(delta),
          });
        }
      } else {
        // Moved to a different hive — correct both.
        await _hivesCollection(uid).doc(oldHiveId).update({
          'itemCount': FieldValue.increment(-1),
          'totalCost': FieldValue.increment(-oldCost),
        });
        await _hivesCollection(uid).doc(wish.hiveId).update({
          'itemCount': FieldValue.increment(1),
          'totalCost': FieldValue.increment(wish.cost),
        });
      }
    } catch (e) {
      debugPrint('Error updating wish: $e');
      rethrow;
    }
  }

  /// Delete a wish and update the parent hive's aggregates.
  ///
  /// [ownerId] is the hive owner — pass it when a friend deletes a wish they
  /// contributed to someone else's hive.
  Future<void> deleteWish(String wishId, {String? ownerId}) async {
    final uid = ownerId ?? _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      // Get wish data for aggregate update and image cleanup
      final wishDoc = await _wishesCollection(uid).doc(wishId).get();
      if (!wishDoc.exists) {
        throw Exception('Wish not found');
      }

      final wishData = wishDoc.data() as Map<String, dynamic>;
      final cost = (wishData['cost'] as num?)?.toDouble() ?? 0.0;
      final hiveId = wishData['hiveId'] as String;
      final imageUrl = wishData['imageUrl'] as String? ?? '';

      // Clean up image if it's a local file
      if (ImageStorageService.isLocalPath(imageUrl)) {
        await ImageStorageService.deleteImage(imageUrl);
      }

      // Delete the wish document
      await _wishesCollection(uid).doc(wishId).delete();

      // Update hive aggregates
      await _hivesCollection(uid).doc(hiveId).update({
        'itemCount': FieldValue.increment(-1),
        'totalCost': FieldValue.increment(-cost),
      });

      debugPrint('Wish deleted: $wishId');
    } catch (e) {
      debugPrint('Error deleting wish: $e');
      rethrow;
    }
  }


  /// Stream of wishes for a specific hive.
  Stream<List<WishModel>> wishesStream(String uid, String hiveId) {
    return _wishesCollection(uid)
        .where('hiveId', isEqualTo: hiveId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => WishModel.fromFirestore(doc)).toList());
  }

  /// Toggle fulfillment status of a wish.
  Future<void> toggleWishFulfillment({
    required String hiveOwnerId,
    required String wishId,
    required String fulfillerId,
    required String fulfillerName,
    bool isOwnerOverride = false,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final docRef = _wishesCollection(hiveOwnerId).doc(wishId);
      
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Wish does not exist');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final currentFulfilledBy = data['fulfilledBy'] as String? ?? '';

        if (currentFulfilledBy.isEmpty) {
          // Claim it — set ownerSeen to false if a FRIEND is fulfilling (not the owner)
          final isFriendFulfilling = fulfillerId != hiveOwnerId;
          transaction.update(docRef, {
            'fulfilledBy': fulfillerId,
            'fulfilledByName': fulfillerName,
            'ownerSeen': !isFriendFulfilling, // false = needs notification
          });
        } else if (currentFulfilledBy == fulfillerId) {
          // Unclaim it (I claimed it, so I can unclaim it)
          transaction.update(docRef, {
            'fulfilledBy': '',
            'fulfilledByName': '',
            'ownerSeen': true,
          });
        } else if (isOwnerOverride) {
           // I am the OWNER, and someone else claimed it. I can reset it.
           transaction.update(docRef, {
            'fulfilledBy': '',
            'fulfilledByName': '',
            'ownerSeen': true,
          });
        } else {
          // Claimed by someone else, and I am not owner -> Error
          throw Exception('Wish already fulfilled by someone else');
        }
      });
    } catch (e) {
      debugPrint('Error toggling wish fulfillment: $e');
      rethrow;
    }
  }

  /// Mark a specific wish as seen by the owner (clears notification dot).
  Future<void> markWishSeen(String wishId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _wishesCollection(uid).doc(wishId).update({'ownerSeen': true});
    } catch (e) {
      debugPrint('Error marking wish seen: $e');
    }
  }

  /// Stream the count of unseen fulfilled wishes for the current user.
  Stream<int> unseenFulfilledWishesCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    return _wishesCollection(uid)
        .where('ownerSeen', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Stream a map of HiveID -> Count of unseen fulfilled wishes.
  Stream<Map<String, int>> unseenWishesByHiveStream() {
    final uid = _uid;
    if (uid == null) return Stream.value({});

    return _wishesCollection(uid)
        .where('ownerSeen', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
           final Map<String, int> counts = {};
           for (var doc in snapshot.docs) {
             final data = doc.data() as Map<String, dynamic>;
             final hiveId = data['hiveId'] as String?;
             if (hiveId != null) {
               counts[hiveId] = (counts[hiveId] ?? 0) + 1;
             }
           }
           return counts;
        });
  }

  // ─── Friend Feed ──────────────────────────────────────────────────

  /// Fetch a feed of hives from friends.
  /// 
  /// [friends] list provides IDs and display names (for accurate attribution).
  /// [mutedFriendIds] allows filtering out hidden friends.
  // Friend Feed
  /// Live feed.
  ///
  /// Everything that changes who may see a hive — accepting a friend request,
  /// granting or revoking view/edit, unfriending — ends up rewriting
  /// `audienceIds` from a Cloud Function. Listening rather than fetching means
  /// those changes arrive on their own; the previous one-shot fetch ran before
  /// the function had finished and then never retried, which is why a newly
  /// accepted friend's hives only appeared after an app restart.
  Stream<List<HiveModel>> feedStream({
    List<String> mutedFriendIds = const [],
    List<String> hiddenHiveIds = const [],
    bool onlyHidden = false,
    int limit = 60,
  }) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);

    return _firestore
        .collection('hives')
        .where('audienceIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) => _decorateFeed(
              snapshot,
              uid,
              mutedFriendIds: mutedFriendIds,
              hiddenHiveIds: hiddenHiveIds,
              onlyHidden: onlyHidden,
            ));
  }

  Future<List<HiveModel>> _decorateFeed(
    QuerySnapshot snapshot,
    String uid, {
    required List<String> mutedFriendIds,
    required List<String> hiddenHiveIds,
    required bool onlyHidden,
  }) async {
    final hives = <HiveModel>[];
    for (final doc in snapshot.docs) {
      final hive = HiveModel.fromFirestore(doc);
      if (hive.ownerId.isEmpty || hive.ownerId == uid) continue;
      if (mutedFriendIds.contains(hive.ownerId)) continue;
      if (hiddenHiveIds.contains(hive.id) != onlyHidden) continue;
      hives.add(hive);
    }

    final profiles =
        await getPublicProfiles(hives.map((h) => h.ownerId).toSet().toList());

    return hives.map((h) {
      final name = profiles[h.ownerId]?.displayName;
      return h.copyWith(
        ownerDisplayName:
            (name != null && name.isNotEmpty) ? name : h.ownerDisplayName,
      );
    }).toList();
  }

  /// One indexed query, replacing the previous two-queries-per-friend fan-out.
  ///
  /// `audienceIds` is resolved server-side by the onHiveWrite function, so this
  /// returns exactly the hives the caller is entitled to see regardless of
  /// privacy mode — and the security rules enforce the same condition.
  Future<List<HiveModel>> getFriendsFeed(
    List<FriendProfile> friends, {
    List<String> mutedFriendIds = const [],
    List<String> hiddenHiveIds = const [],
    bool onlyHidden = false,
    int limit = 60,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    try {
      final snapshot = await _firestore
          .collection('hives')
          .where('audienceIds', arrayContains: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final hives = <HiveModel>[];
      for (final doc in snapshot.docs) {
        final hive = HiveModel.fromFirestore(doc);
        if (hive.ownerId.isEmpty || hive.ownerId == uid) continue;
        if (mutedFriendIds.contains(hive.ownerId)) continue;
        if (hiddenHiveIds.contains(hive.id) != onlyHidden) continue;
        hives.add(hive);
      }

      // Owner names come from the single public profile document rather than
      // the copies that used to be denormalised into every friend's document.
      final profiles =
          await getPublicProfiles(hives.map((h) => h.ownerId).toSet().toList());

      return hives.map((h) {
        final name = profiles[h.ownerId]?.displayName;
        return h.copyWith(
          ownerDisplayName:
              (name != null && name.isNotEmpty) ? name : h.ownerDisplayName,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching friend feed: $e');
      return [];
    }
  }

  /// Hide a specific hive from the feed.
  Future<void> hideHive(String hiveId) async {
    final uid = _uid;
    if (uid == null) return;
    await _usersCollection.doc(uid).update({
      'hiddenHiveIds': FieldValue.arrayUnion([hiveId]),
    });
  }

  /// Unhide a specific hive.
  Future<void> unhideHive(String hiveId) async {
    final uid = _uid;
    if (uid == null) return;
    await _usersCollection.doc(uid).update({
      'hiddenHiveIds': FieldValue.arrayRemove([hiveId]),
    });
  }
}
