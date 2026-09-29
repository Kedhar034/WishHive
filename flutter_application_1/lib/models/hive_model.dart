import 'package:cloud_firestore/cloud_firestore.dart';

enum HivePrivacy { public, private, friends, specific }

class HiveModel {
  final String id;
  final String title;
  final String imageUrl;

  /// Card colour key, one of AppTheme.namedTints. Null means the colour
  /// is derived from the id, which is how every hive made before the
  /// picker existed still looks right.
  final String? cardColor;
  final String note;
  final HivePrivacy privacy;
  final List<String> allowedViewerIds; // Firestore: viewerIds (legacy: allowedViewerIds)
  final List<String> allowedEditorIds; // Firestore: editorIds (legacy: allowedEditorIds)
  final List<String> audienceIds;      // Resolved by Cloud Function. Never written by the client.
  final bool isPublic;
  final String shareId;                // Random token used in the share URL. Not the document id.
  final bool linkShareEnabled;
  final int itemCount;
  final double totalCost;
  final DateTime? createdAt;
  final String ownerId;
  final String ownerDisplayName;

  const HiveModel({
    required this.id,
    required this.title,
    this.imageUrl = '',
    this.cardColor,
    this.note = '',
    this.privacy = HivePrivacy.private,
    this.allowedViewerIds = const [],
    this.allowedEditorIds = const [],
    this.audienceIds = const [],
    this.isPublic = false,
    this.shareId = '',
    this.linkShareEnabled = false,
    this.itemCount = 0,
    this.totalCost = 0.0,
    this.createdAt,
    this.ownerId = '',
    this.ownerDisplayName = '',
  });

  factory HiveModel.fromFirestore(DocumentSnapshot doc) =>
      HiveModel.fromMap(doc.data() as Map<String, dynamic>? ?? {}, doc.id);

  /// Parsing split out from [fromFirestore] so it can be exercised directly in
  /// tests without a Firestore instance.
  factory HiveModel.fromMap(Map<String, dynamic> data, String id) {
    return HiveModel(
      id: id,
      title: data['title'] as String? ?? 'Untitled',
      imageUrl: data['imageUrl'] as String? ?? '',
      cardColor: data['cardColor'] as String?,
      note: data['note'] as String? ?? '',
      privacy: _parsePrivacy(data['privacy'] as String?),
      allowedViewerIds:
          List<String>.from(data['viewerIds'] ?? data['allowedViewerIds'] ?? []),
      allowedEditorIds:
          List<String>.from(data['editorIds'] ?? data['allowedEditorIds'] ?? []),
      audienceIds: List<String>.from(data['audienceIds'] ?? []),
      isPublic: data['isPublic'] as bool? ?? false,
      shareId: data['shareId'] as String? ?? '',
      linkShareEnabled: data['linkShareEnabled'] as bool? ?? false,
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
      totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseDate(data['createdAt']),
      ownerId: data['ownerId'] as String? ?? '',
      ownerDisplayName: data['ownerDisplayName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'imageUrl': imageUrl,
      if (cardColor != null) 'cardColor': cardColor,
      'note': note,
      'privacy': privacy.name,
      'viewerIds': allowedViewerIds,
      'editorIds': allowedEditorIds,
      'allowedViewerIds': allowedViewerIds,
      'allowedEditorIds': allowedEditorIds,
      'isPublic': isPublic,
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
    String? cardColor,
    String? note,
    HivePrivacy? privacy,
    List<String>? allowedViewerIds,
    List<String>? allowedEditorIds,
    List<String>? audienceIds,
    bool? isPublic,
    String? shareId,
    bool? linkShareEnabled,
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
      cardColor: cardColor ?? this.cardColor,
      note: note ?? this.note,
      privacy: privacy ?? this.privacy,
      allowedViewerIds: allowedViewerIds ?? this.allowedViewerIds,
      allowedEditorIds: allowedEditorIds ?? this.allowedEditorIds,
      audienceIds: audienceIds ?? this.audienceIds,
      isPublic: isPublic ?? this.isPublic,
      shareId: shareId ?? this.shareId,
      linkShareEnabled: linkShareEnabled ?? this.linkShareEnabled,
      itemCount: itemCount ?? this.itemCount,
      totalCost: totalCost ?? this.totalCost,
      createdAt: createdAt ?? this.createdAt,
      ownerId: ownerId ?? this.ownerId,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
    );
  }

  /// Anything that is not a resolved Timestamp becomes null rather than
  /// throwing — an unresolved server timestamp is not a real date.
  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
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
