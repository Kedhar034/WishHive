import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/hive_model.dart';
import '../models/wish_model.dart';
import '../models/user_model.dart';
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

  // ─── User & Friend Operations ─────────────────────────────────────

  /// Create or update a user document.
  Future<void> updateUser(UserModel user) async {
    try {
      final data = user.toFirestore();
      // Remove null values to avoid overwriting existing data (like username) with null
      // when syncing from Auth providers that don't provide all fields.
      data.removeWhere((key, value) => value == null);

      await _usersCollection.doc(user.uid).set(
            data,
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  /// Search for users by username prefix or exact email.
  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final queryLower = query.toLowerCase().trim();
      if (queryLower.isEmpty) return [];

      // 1. Exact Email Match (Priority)
      final emailQuery = await _usersCollection
          .where('email', isEqualTo: queryLower)
          .limit(5)
          .get();
      
      if (emailQuery.docs.isNotEmpty) {
        return emailQuery.docs
            .map((doc) => UserModel.fromFirestore(doc))
            .toList();
      }

      // 2. Username Prefix Match
      // This allows finding "kedhareesh" by typing "ked"
      final usernameQuery = await _usersCollection
          .where('username', isGreaterThanOrEqualTo: queryLower)
          .where('username', isLessThan: '$queryLower\uf8ff')
          .limit(10) // Limit results for performance
          .get();
      
      return usernameQuery.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList();

    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  /// Check if a username is available (case-insensitive).
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _usersCollection
          .where('username', isEqualTo: username.toLowerCase().trim())
          .limit(1)
          .get();
      return query.docs.isEmpty;
    } catch (e) {
      debugPrint('Error checking username: $e');
      return false; // Fail safe
    }
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
      final batch = _firestore.batch();
      
      final meRef = _usersCollection.doc(uid);
      final requesterRef = _usersCollection.doc(requesterUid);
      
      // Fetch both users to get their profile details for denormalization
      final meDoc = await meRef.get();
      final requesterDoc = await requesterRef.get();
      
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
      batch.update(meRef, {
        'friends': FieldValue.arrayUnion([requesterProfile.toMap()]),
        'friendRequestsReceived': FieldValue.arrayRemove([requesterUid]),
      });
      
      // 2. Update Requester: Add Friend, Remove Request Sent
      batch.update(requesterRef, {
        'friends': FieldValue.arrayUnion([meProfile.toMap()]),
        'friendRequestsSent': FieldValue.arrayRemove([uid]),
      });
      
      await batch.commit();
    } catch (e) {
      debugPrint('Error accepting friend request: $e');
      rethrow;
    }
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

  /// Get multiple users by ID (Batch fetch).
  Future<List<UserModel>> getUsers(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    
    try {
      // Firestore 'whereIn' is limited to 10 values. We must chunk the requests.
      const int chuckSize = 10;
      List<UserModel> allUsers = [];
      
      for (var i = 0; i < userIds.length; i += chuckSize) {
        final end = (i + chuckSize < userIds.length) ? i + chuckSize : userIds.length;
        final chunk = userIds.sublist(i, end);
        
        final query = await _usersCollection.where(FieldPath.documentId, whereIn: chunk).get();
        
        final chunkUsers = query.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
        allUsers.addAll(chunkUsers);
      }
      
      return allUsers; // Note: they might not be in the same order as userIds
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
      });
    } catch (e) {
      debugPrint('Error updating hive: $e');
      rethrow;
    }
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

      // Delete wish images and wish documents
      for (final wishDoc in wishesSnapshot.docs) {
        final wishData = wishDoc.data() as Map<String, dynamic>;
        final imageUrl = wishData['imageUrl'] as String? ?? '';
        if (ImageStorageService.isLocalPath(imageUrl)) {
          await ImageStorageService.deleteImage(imageUrl);
        }
        await wishDoc.reference.delete();
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

  /// Update an existing wish.
  Future<void> updateWish(WishModel wish) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      await _wishesCollection(uid).doc(wish.id).update({
        'name': wish.name,
        'subtitle': wish.subtitle, // Update subtitle
        'imageUrl': wish.imageUrl,
        'note': wish.note,
        'link': wish.link,
        'cost': wish.cost,
        'quantity': wish.quantity,
        'date': wish.date != null ? Timestamp.fromDate(wish.date!) : null,
        'fulfilledBy': wish.fulfilledBy,
        'fulfilledByName': wish.fulfilledByName,
      });
    } catch (e) {
      debugPrint('Error updating wish: $e');
      rethrow;
    }
  }

  /// Delete a wish and update the parent hive's aggregates.
  Future<void> deleteWish(String wishId) async {
    final uid = _uid;
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
          // Claim it (Anyone allowed to see it can claim it)
          transaction.update(docRef, {
            'fulfilledBy': fulfillerId,
            'fulfilledByName': fulfillerName,
          });
        } else if (currentFulfilledBy == fulfillerId) {
          // Unclaim it (I claimed it, so I can unclaim it)
          transaction.update(docRef, {
            'fulfilledBy': '',
            'fulfilledByName': '',
          });
        } else if (isOwnerOverride) {
           // I am the OWNER, and someone else claimed it. I can reset it.
           transaction.update(docRef, {
            'fulfilledBy': '',
            'fulfilledByName': '',
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

  // ─── Friend Feed ──────────────────────────────────────────────────

  /// Fetch a feed of hives from friends.
  /// 
  /// Since Firestore doesn't support easy "OR" queries across many users, 
  /// we fetch hives for each friend individually and merge them client-side.
  /// This is suitable for small friend counts. For scale, we'd need a dedicated feed collection.
  Future<List<HiveModel>> getFriendsFeed(List<String> friendIds) async {
    if (friendIds.isEmpty) return [];

    try {
      // Chunk friends to avoid hitting Firestore limits if we were using 'whereIn' (max 30).
      // But here we are using collectionGroup with 'ownerId' check? 
      // No, collectionGroup queries all hives.
      // Easiest robust way for < 50 friends:
      // Loop through friends, get their latest public/friend hives.
      
      List<HiveModel> allHives = [];
      const int hivesPerFriend = 3; // Get top 3 latest hives per friend to keep it fast

      // Parallel fetch
      final futures = friendIds.map((fid) async {
        final query = _hivesCollection(fid)
            .where('privacy', whereIn: ['public', 'friends']) // Only public or friend-visible
            .orderBy('createdAt', descending: true)
            .limit(hivesPerFriend);
            
        final snapshot = await query.get();
        return snapshot.docs.map((doc) {
           final hive = HiveModel.fromFirestore(doc);
           // Manually attach ownerId if not present (though it should be in the model)
           return hive.copyWith(ownerId: fid); 
        }).toList();
      });

      final List<List<HiveModel>> results = await Future.wait(futures);
      
      for (var hives in results) {
        allHives.addAll(hives);
      }

      // Sort combined list by date descending
      allHives.sort((a, b) {
        final aDate = a.createdAt ?? DateTime(0);
        final bDate = b.createdAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      return allHives;
    } catch (e) {
      debugPrint('Error fetching friend feed: $e');
      return [];
    }
  }
}
