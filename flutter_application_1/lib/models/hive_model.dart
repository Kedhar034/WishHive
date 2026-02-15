import 'package:cloud_firestore/cloud_firestore.dart';

enum HivePrivacy { public, private, friends }

class HiveModel {
  final String id;
  final String title;
  final String imageUrl;
  final String note;
  final HivePrivacy privacy;
  final int itemCount;
  final double totalCost;
  final DateTime? createdAt;
  final String ownerId;
  final String ownerDisplayName; // Added

  const HiveModel({
    required this.id,
    required this.title,
    this.imageUrl = '',
    this.note = '',
    this.privacy = HivePrivacy.private,
    this.itemCount = 0,
    this.totalCost = 0.0,
    this.createdAt,
    this.ownerId = '',
    this.ownerDisplayName = '', // Added default
  });

  factory HiveModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HiveModel(
      id: doc.id,
      title: data['title'] as String? ?? 'Untitled',
      imageUrl: data['imageUrl'] as String? ?? '',
      note: data['note'] as String? ?? '',
      privacy: _parsePrivacy(data['privacy'] as String?),
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
      totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      ownerId: data['ownerId'] as String? ?? '',
      ownerDisplayName: data['ownerDisplayName'] as String? ?? '', // Added
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'imageUrl': imageUrl,
      'note': note,
      'privacy': privacy.name,
      'id': id,
      'itemCount': itemCount,
      'totalCost': totalCost,
      'createdAt': FieldValue.serverTimestamp(),
      'ownerId': ownerId,
      'ownerDisplayName': ownerDisplayName, // Added
    };
  }

  HiveModel copyWith({
    String? id,
    String? title,
    String? imageUrl,
    String? note,
    HivePrivacy? privacy,
    int? itemCount,
    double? totalCost,
    DateTime? createdAt,
    String? ownerId,
    String? ownerDisplayName, // Added
  }) {
    return HiveModel(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      note: note ?? this.note,
      privacy: privacy ?? this.privacy,
      itemCount: itemCount ?? this.itemCount,
      totalCost: totalCost ?? this.totalCost,
      createdAt: createdAt ?? this.createdAt,
      ownerId: ownerId ?? this.ownerId,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName, // Added
    );
  }

  static HivePrivacy _parsePrivacy(String? value) {
    switch (value) {
      case 'public':
        return HivePrivacy.public;
      case 'friends':
        return HivePrivacy.friends;
      default:
        return HivePrivacy.private;
    }
  }
}
