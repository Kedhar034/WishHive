import 'package:cloud_firestore/cloud_firestore.dart';

enum HivePrivacy { public, private, friends, specific }

class HiveModel {
  final String id;
  final String title;
  final String imageUrl;
  final String note;
  final HivePrivacy privacy;
  final List<String> allowedViewerIds; // For HivePrivacy.specific (view only)
  final List<String> allowedEditorIds; // For HivePrivacy.specific (can add wishes)
  final int itemCount;
  final double totalCost;
  final DateTime? createdAt;
  final String ownerId;
  final String ownerDisplayName;

  const HiveModel({
    required this.id,
    required this.title,
    this.imageUrl = '',
    this.note = '',
    this.privacy = HivePrivacy.private,
    this.allowedViewerIds = const [],
    this.allowedEditorIds = const [],
    this.itemCount = 0,
    this.totalCost = 0.0,
    this.createdAt,
    this.ownerId = '',
    this.ownerDisplayName = '',
  });

  factory HiveModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HiveModel(
      id: doc.id,
      title: data['title'] as String? ?? 'Untitled',
      imageUrl: data['imageUrl'] as String? ?? '',
      note: data['note'] as String? ?? '',
      privacy: _parsePrivacy(data['privacy'] as String?),
      allowedViewerIds: List<String>.from(data['allowedViewerIds'] ?? []),
      allowedEditorIds: List<String>.from(data['allowedEditorIds'] ?? []),
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
      totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      ownerId: data['ownerId'] as String? ?? '',
      ownerDisplayName: data['ownerDisplayName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'imageUrl': imageUrl,
      'note': note,
      'privacy': privacy.name,
      'allowedViewerIds': allowedViewerIds,
      'allowedEditorIds': allowedEditorIds,
      'id': id,
      'itemCount': itemCount,
      'totalCost': totalCost,
      'createdAt': FieldValue.serverTimestamp(),
      'ownerId': ownerId,
      'ownerDisplayName': ownerDisplayName,
    };
  }

  HiveModel copyWith({
    String? id,
    String? title,
    String? imageUrl,
    String? note,
    HivePrivacy? privacy,
    List<String>? allowedViewerIds,
    List<String>? allowedEditorIds,
    int? itemCount,
    double? totalCost,
    DateTime? createdAt,
    String? ownerId,
    String? ownerDisplayName,
  }) {
    return HiveModel(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      note: note ?? this.note,
      privacy: privacy ?? this.privacy,
      allowedViewerIds: allowedViewerIds ?? this.allowedViewerIds,
      allowedEditorIds: allowedEditorIds ?? this.allowedEditorIds,
      itemCount: itemCount ?? this.itemCount,
      totalCost: totalCost ?? this.totalCost,
      createdAt: createdAt ?? this.createdAt,
      ownerId: ownerId ?? this.ownerId,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
    );
  }

  static HivePrivacy _parsePrivacy(String? value) {
    switch (value) {
      case 'public':
        return HivePrivacy.public;
      case 'friends':
        return HivePrivacy.friends;
      case 'specific':
        return HivePrivacy.specific;
      default:
        return HivePrivacy.private;
    }
  }
}
