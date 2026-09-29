import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/hive_model.dart';
import '../models/wish_model.dart';
import '../models/public_profile.dart';
import '../models/friendship.dart';
import '../models/user_settings.dart';

/// New-schema data layer.
///
/// Reads and writes the migrated structure:
///   hives/{hiveId}                      top-level, carries audienceIds
///   hives/{hiveId}/wishes/{wishId}      access inherited from the hive
///   users/{uid}/friends/{friendUid}     one document per relationship
///   users/{uid}/friendRequests/{from}   inbound only
///   users/{uid}/sentRequests/{to}       outbound mirror for the Sent state
///   users/{uid}/public/profile          no private data
///   users/{uid}/settings/prefs
///   usernames/{lowercaseName}
///
/// Runs alongside [FirestoreService] during the migration. Nothing here is
/// wired up until the call sites are flipped.
class FirestoreServiceV2 {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static final Map<String, PublicProfile> _profileCache = {};

  // ─── Public profiles ──────────────────────────────────────────────────────

  DocumentReference _profileRef(String uid) =>
      _db.doc('users/$uid/public/profile');

  Stream<PublicProfile?> profileStream(String uid) {
    return _profileRef(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final p = PublicProfile.fromFirestore(doc, uid);
      _profileCache[uid] = p;
      return p;
    });
  }

  /// Cached read. Profiles change rarely, so this avoids re-reading the same
  /// document on every screen — the main saving that replaces the old
  /// denormalised friend copies.
  Future<PublicProfile?> getProfile(String uid, {bool refresh = false}) async {
    if (!refresh && _profileCache.containsKey(uid)) return _profileCache[uid];
    try {
      final doc = await _profileRef(uid).get();
      if (!doc.exists) return null;
      final p = PublicProfile.fromFirestore(doc, uid);
      _profileCache[uid] = p;
      return p;
    } catch (e) {
      debugPrint('getProfile($uid) failed: $e');
      return null;
    }
  }

  Future<Map<String, PublicProfile>> getProfiles(List<String> uids) async {
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
      final p = await getProfile(uid);
      if (p != null) out[uid] = p;
    }));
    return out;
  }

  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? photoUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (displayName != null) data['displayName'] = displayName;
    if (username != null) data['username'] = username.toLowerCase();
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    await _profileRef(uid).set(data, SetOptions(merge: true));
    _profileCache.remove(uid);
  }

  static void clearProfileCache() => _profileCache.clear();

  // ─── Usernames ────────────────────────────────────────────────────────────

  /// Atomic claim. Creating a document whose id IS the username fails if the
  /// name is taken, which is what replaces the old read-then-write race.
  Future<bool> claimUsername(String username) async {
    final uid = _uid;
    if (uid == null) return false;
    final name = username.toLowerCase().trim();
    if (name.isEmpty) return false;
    try {
      await _db.doc('usernames/$name').set({'uid': uid});
      return true;
    } catch (e) {
      debugPrint('claimUsername($name) failed: $e');
      return false;
    }
  }

  Future<bool> isUsernameAvailable(String username) async {
    final name = username.toLowerCase().trim();
    if (name.isEmpty) return false;
    try {
      final doc = await _db.doc('usernames/$name').get();
      if (!doc.exists) return true;
      return doc.data()?['uid'] == _uid;
    } catch (e) {
      debugPrint('isUsernameAvailable($name) failed: $e');
      return false;
    }
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  /// Queries public profiles only. Private data can no longer leak through
  /// search results.
  Future<List<PublicProfile>> searchUsers(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    try {
      final exact = await _db.doc('usernames/$q').get();
      if (exact.exists) {
        final uid = exact.data()?['uid'] as String?;
        if (uid != null) {
          final p = await getProfile(uid, refresh: true);
          if (p != null) return [p];
        }
      }

      final snap = await _db
          .collectionGroup('public')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q')
          .limit(20)
          .get();

      return snap.docs.map((d) {
        final uid = d.reference.parent.parent!.id;
        final p = PublicProfile.fromFirestore(d, uid);
        _profileCache[uid] = p;
        return p;
      }).toList();
    } catch (e) {
      debugPrint('searchUsers($q) failed: $e');
      return [];
    }
  }

  // ─── Friends ──────────────────────────────────────────────────────────────

  Stream<List<String>> friendIdsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users/$uid/friends')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  Future<List<String>> getFriendIds() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db.collection('users/$uid/friends').get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<void> removeFriend(String friendUid) async {
    await _fns.httpsCallable('removeFriend').call({'friendUid': friendUid});
  }

  // ─── Friend requests ──────────────────────────────────────────────────────

  Stream<List<FriendRequest>> incomingRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users/$uid/friendRequests')
        .snapshots()
        .map((s) => s.docs.map(FriendRequest.fromFirestore).toList());
  }

  Stream<List<String>> sentRequestIdsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users/$uid/sentRequests')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  /// The sender writes one document, named after themselves, into the target's
  /// inbox. That single constraint is what makes request flooding impossible.
  Future<void> sendFriendRequest(String targetUid, {String myName = ''}) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    if (uid == targetUid) throw Exception('Cannot add yourself');

    await _db.doc('users/$targetUid/friendRequests/$uid').set({
      'sentAt': FieldValue.serverTimestamp(),
      'fromName': myName,
    });
    await _db.doc('users/$uid/sentRequests/$targetUid').set({
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptFriendRequest(String requesterUid) async {
    await _fns
        .httpsCallable('acceptFriendRequest')
        .call({'requesterUid': requesterUid});
  }

  Future<void> rejectFriendRequest(String requesterUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.doc('users/$uid/friendRequests/$requesterUid').delete();
    await _db
        .doc('users/$requesterUid/sentRequests/$uid')
        .delete()
        .catchError((_) {});
  }

  Future<void> cancelFriendRequest(String targetUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.doc('users/$targetUid/friendRequests/$uid').delete();
    await _db.doc('users/$uid/sentRequests/$targetUid').delete();
  }

  // ─── Blocking ─────────────────────────────────────────────────────────────

  Stream<List<String>> blockedIdsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users/$uid/blocked')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  Future<List<String>> getBlockedIds() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db.collection('users/$uid/blocked').get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Blocking also removes any friendship and cancels pending requests in both
  /// directions, so a blocked user loses access to everything immediately.
  Future<void> blockUser(String targetUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    if (uid == targetUid) throw Exception('Cannot block yourself');

    await _db.doc('users/$uid/blocked/$targetUid').set({
      'blockedAt': FieldValue.serverTimestamp(),
    });

    try {
      await removeFriend(targetUid);
    } catch (_) {
      // Not friends — nothing to undo.
    }
    await _db.doc('users/$uid/friendRequests/$targetUid').delete().catchError((_) {});
    await _db.doc('users/$targetUid/friendRequests/$uid').delete().catchError((_) {});
    await _db.doc('users/$uid/sentRequests/$targetUid').delete().catchError((_) {});
    await _db.doc('users/$targetUid/sentRequests/$uid').delete().catchError((_) {});
  }

  Future<void> unblockUser(String targetUid) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.doc('users/$uid/blocked/$targetUid').delete();
  }

  // ─── Reporting ────────────────────────────────────────────────────────────

  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String targetOwnerUid,
    required String reason,
    String details = '',
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.collection('reports').add({
      'reporterUid': uid,
      'targetType': targetType,
      'targetId': targetId,
      'targetOwnerUid': targetOwnerUid,
      'reason': reason,
      'details': details.length > 1000 ? details.substring(0, 1000) : details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Account deletion ─────────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    await _fns.httpsCallable('deleteAccount').call();
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  DocumentReference _settingsRef(String uid) => _db.doc('users/$uid/settings/prefs');

  Stream<UserSettings> settingsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const UserSettings());
    return _settingsRef(uid)
        .snapshots()
        .map((d) => d.exists ? UserSettings.fromFirestore(d) : const UserSettings());
  }

  Future<void> muteFriend(String friendId) => _settingsArray('mutedFriends', friendId, true);
  Future<void> unmuteFriend(String friendId) => _settingsArray('mutedFriends', friendId, false);
  Future<void> hideHive(String hiveId) => _settingsArray('hiddenHiveIds', hiveId, true);
  Future<void> unhideHive(String hiveId) => _settingsArray('hiddenHiveIds', hiveId, false);

  Future<void> _settingsArray(String field, String value, bool add) async {
    final uid = _uid;
    if (uid == null) return;
    await _settingsRef(uid).set({
      field: add ? FieldValue.arrayUnion([value]) : FieldValue.arrayRemove([value]),
    }, SetOptions(merge: true));
  }

  // ─── Hives ────────────────────────────────────────────────────────────────

  CollectionReference get _hives => _db.collection('hives');

  Stream<List<HiveModel>> myHivesStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _hives
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(HiveModel.fromFirestore).toList());
  }

  Stream<HiveModel?> hiveStream(String hiveId) {
    return _hives
        .doc(hiveId)
        .snapshots()
        .map((d) => d.exists ? HiveModel.fromFirestore(d) : null);
  }

  Future<String> createHive(HiveModel hive) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final ref = _hives.doc();
    final data = hive.copyWith(id: ref.id, ownerId: uid).toFirestore();
    data.remove('audienceIds');
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateHive(HiveModel hive) async {
    await _hives.doc(hive.id).update({
      'title': hive.title,
      'imageUrl': hive.imageUrl,
      'note': hive.note,
      'privacy': hive.privacy.name,
      'viewerIds': hive.allowedViewerIds,
      'editorIds': hive.allowedEditorIds,
      'allowedViewerIds': hive.allowedViewerIds,
      'allowedEditorIds': hive.allowedEditorIds,
    });
  }

  /// Wishes and Storage objects are cleaned up by the onHiveDelete function.
  Future<void> deleteHive(String hiveId) => _hives.doc(hiveId).delete();

  // ─── Feed ─────────────────────────────────────────────────────────────────

  /// One query replaces the old two-queries-per-friend fan-out.
  /// Own hives are filtered out client-side; `arrayContains` cannot be combined
  /// with an inequality on another field.
  Stream<List<HiveModel>> feedStream({int limit = 20}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _hives
        .where('audienceIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit * 2)
        .snapshots()
        .map((s) => s.docs
            .map(HiveModel.fromFirestore)
            .where((h) => h.ownerId != uid)
            .take(limit)
            .toList());
  }

  Future<({List<HiveModel> hives, DocumentSnapshot? cursor})> fetchFeedPage({
    DocumentSnapshot? cursor,
    int limit = 20,
  }) async {
    final uid = _uid;
    if (uid == null) return (hives: <HiveModel>[], cursor: null);

    Query q = _hives
        .where('audienceIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (cursor != null) q = q.startAfterDocument(cursor);

    final snap = await q.get();
    final hives = snap.docs
        .map(HiveModel.fromFirestore)
        .where((h) => h.ownerId != uid)
        .toList();
    return (hives: hives, cursor: snap.docs.isEmpty ? null : snap.docs.last);
  }

  // ─── Wishes ───────────────────────────────────────────────────────────────

  CollectionReference _wishes(String hiveId) =>
      _db.collection('hives/$hiveId/wishes');

  Stream<List<WishModel>> wishesStream(String hiveId) {
    return _wishes(hiveId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(WishModel.fromFirestore).toList());
  }

  /// The path no longer depends on who is writing, so an editor adding a wish
  /// to someone else's hive uses exactly the same call as the owner.
  Future<String> createWish(
      String hiveId, String hiveOwnerId, WishModel wish) async {
    final ref = _wishes(hiveId).doc();
    final data = wish.copyWith(id: ref.id, hiveId: hiveId).toFirestore();
    data['hiveOwnerId'] = hiveOwnerId;
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateWish(String hiveId, WishModel wish) async {
    await _wishes(hiveId).doc(wish.id).update({
      'name': wish.name,
      'subtitle': wish.subtitle,
      'imageUrl': wish.imageUrl,
      'note': wish.note,
      'link': wish.link,
      'cost': wish.cost,
      'quantity': wish.quantity,
      'date': wish.date != null ? Timestamp.fromDate(wish.date!) : null,
    });
  }

  Future<void> setWishImage(String hiveId, String wishId, String url) =>
      _wishes(hiveId).doc(wishId).update({'imageUrl': url});

  Future<void> deleteWish(String hiveId, String wishId) =>
      _wishes(hiveId).doc(wishId).delete();

  Future<void> markWishSeen(String hiveId, String wishId) =>
      _wishes(hiveId).doc(wishId).update({'ownerSeen': true});

  Future<void> toggleWishFulfillment({
    required String hiveId,
    required String wishId,
    required String fulfillerId,
    required String fulfillerName,
    required String hiveOwnerId,
    bool isOwnerOverride = false,
  }) async {
    final ref = _wishes(hiveId).doc(wishId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Wish does not exist');

      final data = snap.data() as Map<String, dynamic>;
      final current = data['fulfilledBy'] as String? ?? '';

      if (current.isEmpty) {
        tx.update(ref, {
          'fulfilledBy': fulfillerId,
          'fulfilledByName': fulfillerName,
          'ownerSeen': fulfillerId == hiveOwnerId,
        });
      } else if (current == fulfillerId || isOwnerOverride) {
        tx.update(ref, {
          'fulfilledBy': '',
          'fulfilledByName': '',
          'ownerSeen': true,
        });
      } else {
        throw Exception('Wish already fulfilled by someone else');
      }
    });
  }

  Stream<Map<String, int>> unseenWishesByHiveStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(const {});
    return _db
        .collectionGroup('wishes')
        .where('hiveOwnerId', isEqualTo: uid)
        .where('ownerSeen', isEqualTo: false)
        .snapshots()
        .map((s) {
      final counts = <String, int>{};
      for (final doc in s.docs) {
        final hiveId = doc.reference.parent.parent?.id;
        if (hiveId != null) counts[hiveId] = (counts[hiveId] ?? 0) + 1;
      }
      return counts;
    });
  }
}
