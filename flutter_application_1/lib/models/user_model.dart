
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendProfile {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String email;

  const FriendProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.email,
  });

  factory FriendProfile.fromMap(Map<String, dynamic> map) {
    return FriendProfile(
      uid: map['uid'] as String,
      displayName: map['displayName'] as String,
      photoUrl: map['photoUrl'] as String?,
      email: map['email'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'email': email,
    };
  }
}

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? username;
  final String? photoUrl;
  final List<FriendProfile> friends;
  final List<String> friendRequestsSent;
  final List<String> friendRequestsReceived;
  final List<String> mutedFriends;
  final List<String> hiddenHiveIds; // New: Hide specific hives

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.username,
    this.photoUrl,
    this.friends = const [],
    this.friendRequestsSent = const [],
    this.friendRequestsReceived = const [],
    this.mutedFriends = const [],
    this.hiddenHiveIds = const [],
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Parse friends list safely handling legacy string IDs if necessary (though we are starting fresh)
    final friendsData = data['friends'] as List<dynamic>? ?? [];
    final friendsList = friendsData.map((f) {
      if (f is Map<String, dynamic>) {
        return FriendProfile.fromMap(f);
      }
      return FriendProfile(uid: f.toString(), displayName: 'Unknown', email: '');
    }).toList();

    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'User',
      username: data['username'] as String?,
      photoUrl: data['photoUrl'] as String?,
      friends: friendsList,
      friendRequestsSent: List<String>.from(data['friendRequestsSent'] ?? []),
      friendRequestsReceived: List<String>.from(data['friendRequestsReceived'] ?? []),
      mutedFriends: List<String>.from(data['mutedFriends'] ?? []),
      hiddenHiveIds: List<String>.from(data['hiddenHiveIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
      'friends': friends.map((f) => f.toMap()).toList(),
      'friendRequestsSent': friendRequestsSent,
      'friendRequestsReceived': friendRequestsReceived,
      'mutedFriends': mutedFriends,
      'hiddenHiveIds': hiddenHiveIds,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? username,
    String? photoUrl,
    List<FriendProfile>? friends,
    List<String>? friendRequestsSent,
    List<String>? friendRequestsReceived,
    List<String>? mutedFriends,
    List<String>? hiddenHiveIds,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      friends: friends ?? this.friends,
      friendRequestsSent: friendRequestsSent ?? this.friendRequestsSent,
      friendRequestsReceived: friendRequestsReceived ?? this.friendRequestsReceived,
      mutedFriends: mutedFriends ?? this.mutedFriends,
      hiddenHiveIds: hiddenHiveIds ?? this.hiddenHiveIds,
    );
  }
}
