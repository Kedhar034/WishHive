import 'package:cloud_firestore/cloud_firestore.dart';

class WishModel {
  final String id;
  final String name;
  final String subtitle;
  final String imageUrl;
  final String hiveId;
  final DateTime? date;
  final int quantity;
  final String note;
  final String link;
  final double cost;
  final DateTime? createdAt;
  final String fulfilledBy;
  final String fulfilledByName;
  final bool ownerSeen; // false when a friend fulfills — triggers notification dot
  final String addedByUid; // UID of who added this wish (empty = owner added it)
  final String addedByName; // Display name of who added this wish

  WishModel({
    required this.id,
    required this.name,
    this.subtitle = '',
    required this.imageUrl,
    required this.hiveId,
    this.date,
    this.quantity = 1,
    this.note = '',
    this.link = '',
    this.cost = 0.0,
    this.createdAt,
    this.fulfilledBy = '',
    this.fulfilledByName = '',
    this.ownerSeen = true,
    this.addedByUid = '',
    this.addedByName = '',
  });

  factory WishModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WishModel(
      id: doc.id,
      name: data['name'] as String? ?? 'No Name',
      subtitle: data['subtitle'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      hiveId: data['hiveId'] as String? ?? '',
      date: _parseDate(data['date']),
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      note: data['note'] as String? ?? '',
      link: data['link'] as String? ?? '',
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      fulfilledBy: data['fulfilledBy'] as String? ?? '',
      fulfilledByName: data['fulfilledByName'] as String? ?? '',
      ownerSeen: data['ownerSeen'] as bool? ?? true,
      addedByUid: data['addedByUid'] as String? ?? '',
      addedByName: data['addedByName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'hiveId': hiveId,
      'date': date != null ? Timestamp.fromDate(date!) : null,
      'quantity': quantity,
      'note': note,
      'link': link,
      'cost': cost,
      'createdAt': FieldValue.serverTimestamp(),
      'fulfilledBy': fulfilledBy,
      'fulfilledByName': fulfilledByName,
      'ownerSeen': ownerSeen,
      'addedByUid': addedByUid,
      'addedByName': addedByName,
    };
  }

  WishModel copyWith({
    String? id,
    String? name,
    String? subtitle,
    String? imageUrl,
    String? hiveId,
    DateTime? date,
    int? quantity,
    String? note,
    String? link,
    double? cost,
    DateTime? createdAt,
    String? fulfilledBy,
    String? fulfilledByName,
    bool? ownerSeen,
    String? addedByUid,
    String? addedByName,
  }) {
    return WishModel(
      id: id ?? this.id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      hiveId: hiveId ?? this.hiveId,
      date: date ?? this.date,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
      link: link ?? this.link,
      cost: cost ?? this.cost,
      createdAt: createdAt ?? this.createdAt,
      fulfilledBy: fulfilledBy ?? this.fulfilledBy,
      fulfilledByName: fulfilledByName ?? this.fulfilledByName,
      ownerSeen: ownerSeen ?? this.ownerSeen,
      addedByUid: addedByUid ?? this.addedByUid,
      addedByName: addedByName ?? this.addedByName,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
