import 'package:cloud_firestore/cloud_firestore.dart';

/// Stored at users/{uid}/settings/prefs — private to the owner.
/// Kept out of the main user document so a profile update can never wipe it.
class UserSettings {
  final List<String> mutedFriends;
  final List<String> hiddenHiveIds;

  const UserSettings({
    this.mutedFriends = const [],
    this.hiddenHiveIds = const [],
  });

  factory UserSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserSettings(
      mutedFriends: List<String>.from(data['mutedFriends'] ?? []),
      hiddenHiveIds: List<String>.from(data['hiddenHiveIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'mutedFriends': mutedFriends,
      'hiddenHiveIds': hiddenHiveIds,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserSettings copyWith({
    List<String>? mutedFriends,
    List<String>? hiddenHiveIds,
  }) {
    return UserSettings(
      mutedFriends: mutedFriends ?? this.mutedFriends,
      hiddenHiveIds: hiddenHiveIds ?? this.hiddenHiveIds,
    );
  }
}
