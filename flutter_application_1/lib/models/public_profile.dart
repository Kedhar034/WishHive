import 'package:cloud_firestore/cloud_firestore.dart';

/// Stored at users/{uid}/public/profile — readable by any signed-in user.
/// Never contains private data such as email.
class PublicProfile {
  final String uid;
  final String displayName;
  final String? username;
  final String? photoUrl;
  final int friendCount;

  const PublicProfile({
    required this.uid,
    required this.displayName,
    this.username,
    this.photoUrl,
    this.friendCount = 0,
  });

  factory PublicProfile.fromFirestore(DocumentSnapshot doc, String uid) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PublicProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? 'User',
      username: data['username'] as String?,
      photoUrl: data['photoUrl'] as String?,
      friendCount: (data['friendCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
      'friendCount': friendCount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  PublicProfile copyWith({
    String? uid,
    String? displayName,
    String? username,
    String? photoUrl,
    int? friendCount,
  }) {
    return PublicProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      friendCount: friendCount ?? this.friendCount,
    );
  }
}
