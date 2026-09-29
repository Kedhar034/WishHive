import 'package:cloud_firestore/cloud_firestore.dart';

/// One document per friendship edge at users/{uid}/friends/{friendUid}.
/// The document id is the friend's uid.
class Friendship {
  final String friendUid;
  final DateTime? since;

  const Friendship({required this.friendUid, this.since});

  factory Friendship.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Friendship(
      friendUid: doc.id,
      since: (data['since'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'since': FieldValue.serverTimestamp()};
  }
}

/// One document per inbound request at users/{uid}/friendRequests/{fromUid}.
/// The document id is the sender's uid, which is what makes flooding impossible:
/// a sender can only ever create one document, named after themselves.
class FriendRequest {
  final String fromUid;
  final String fromName;
  final DateTime? sentAt;

  const FriendRequest({
    required this.fromUid,
    this.fromName = '',
    this.sentAt,
  });

  factory FriendRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FriendRequest(
      fromUid: doc.id,
      fromName: data['fromName'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fromName': fromName,
      'sentAt': FieldValue.serverTimestamp(),
    };
  }
}
