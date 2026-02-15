import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/wish_model.dart';
import '../models/user_model.dart';
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
final wishesByHiveProvider = StreamProvider.autoDispose.family<List<WishModel>, String>((ref, hiveId) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream<List<WishModel>>.empty();
  return ref.read(firestoreServiceProvider).wishesStream(uid, hiveId);
});

// ─── Upload Service Provider ────────────────────────────────────────

final uploadServiceProvider = NotifierProvider<UploadService, List<UploadTask>>(() {
  return UploadService();
});

// Alias for currentUserStreamProvider to fix compilation error
final userProvider = currentUserStreamProvider;
