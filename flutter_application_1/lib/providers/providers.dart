import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/wish_model.dart';
import '../models/user_model.dart';
import '../models/hive_model.dart'; // Add this import
import '../services/upload_service.dart'; // Add this import

export '../services/upload_service.dart';

// ─── Firebase Auth Providers ────────────────────────────────────────

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Auth state changes stream provider.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).idTokenChanges();
});

/// UID provider for the currently authenticated user.
final uidProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user?.uid;
});

/// Stream provider for the current User Model (real-time).
final currentUserStreamProvider = StreamProvider<UserModel?>((ref) {
  // Watch UID so this provider updates when auth state changes
  final uid = ref.watch(uidProvider);
  
  if (uid == null) {
    return const Stream.empty();
  }
  
  return ref.watch(firestoreServiceProvider).userStream(uid);
});

// ─── Firestore Service Provider ─────────────────────────────────────

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

// ─── Hive Providers ─────────────────────────────────────────────────

/// Stream of all hives for the current user.
final hiveListProvider = StreamProvider.autoDispose((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream<QuerySnapshot>.empty();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('hives')
      .orderBy('createdAt', descending: true)
      .snapshots();
});

// ─── Wish Providers ─────────────────────────────────────────────────
 
/// Stream of wishes for a specific hive (returns typed WishModel list).

/// Stream of wishes for a specific hive (returns typed WishModel list).
/// Now accepts a record (hiveId, ownerId) to support viewing friends' hives.
final wishesByHiveProvider = StreamProvider.autoDispose.family<List<WishModel>, ({String hiveId, String ownerId})>((ref, args) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream<List<WishModel>>.empty();
  
  // Use the ownerId passed in arguments. If empty, fall back to current user (though logic should handle this upstream)
  final targetOwnerId = args.ownerId.isNotEmpty ? args.ownerId : uid;
  
  return ref.read(firestoreServiceProvider).wishesStream(targetOwnerId, args.hiveId);
});

// ─── Friend Feed Provider ───────────────────────────────────────────

final friendFeedProvider = FutureProvider.autoDispose<List<HiveModel>>((ref) async {
  final user = ref.watch(currentUserStreamProvider).value;
  if (user == null || user.friends.isEmpty) return [];
  
  return ref.read(firestoreServiceProvider).getFriendsFeed(
    user.friends, 
    mutedFriendIds: user.mutedFriends,
    hiddenHiveIds: user.hiddenHiveIds,
  );
});

// ─── Upload Service Provider ────────────────────────────────────────

final uploadServiceProvider = NotifierProvider<UploadService, List<UploadTask>>(() {
  return UploadService();
});

// Alias for currentUserStreamProvider to fix compilation error
// Alias for currentUserStreamProvider to fix compilation error
final userProvider = currentUserStreamProvider;

// ─── UI State Providers ─────────────────────────────────────────────

/// Manages temporarily hidden hives (optimistic updates) across screens.
class TemporarilyHiddenHivesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void add(String id) {
    state = {...state, id};
  }

  void remove(String id) {
    state = state.difference({id});
  }
}

final temporarilyHiddenHivesProvider = NotifierProvider<TemporarilyHiddenHivesNotifier, Set<String>>(TemporarilyHiddenHivesNotifier.new);

// ─── Wish Notification Provider ─────────────────────────────────────

/// Streams count of unseen fulfilled wishes (friend fulfilled, owner hasn't seen).
final unseenFulfilledCountProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(0);
  return ref.watch(firestoreServiceProvider).unseenFulfilledWishesCount();
});

/// Streams map of HiveID -> Unseen Count.
final unseenWishesByHiveProvider = StreamProvider<Map<String, int>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value({});
  return ref.watch(firestoreServiceProvider).unseenWishesByHiveStream();
});

// ─── Navigation Provider ─────────────────────────────────────────────

final navigationProvider = StateProvider<int>((ref) => 0);
