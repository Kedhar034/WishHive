// Model parsing tests.
//
//   flutter test
//
// These exercise the real production parsing paths with plain maps — no fake
// Firestore, and nothing that can reach the live database.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/hive_model.dart';
import 'package:flutter_application_1/models/user_model.dart';
import 'package:flutter_application_1/models/wish_model.dart';

void main() {
  group('FriendProfile.fromMap', () {
    test('parses a complete record', () {
      final f = FriendProfile.fromMap({
        'uid': 'u1',
        'displayName': 'Alice',
        'photoUrl': 'a.jpg',
        'email': 'alice@example.com',
      });
      expect(f.uid, 'u1');
      expect(f.displayName, 'Alice');
      expect(f.photoUrl, 'a.jpg');
      expect(f.email, 'alice@example.com');
    });

    // The bug this guards: a single record missing a field used to throw a
    // TypeError, which propagated out of UserModel.fromFirestore and left every
    // screen in the app showing "Error:" with no way to recover.
    test('a missing email does not throw', () {
      final f = FriendProfile.fromMap({'uid': 'u1', 'displayName': 'Alice'});
      expect(f.email, '');
      expect(f.uid, 'u1');
    });

    test('a missing displayName does not throw', () {
      final f = FriendProfile.fromMap({'uid': 'u1', 'email': 'a@b.com'});
      expect(f.displayName, 'User');
    });

    test('a completely empty record does not throw', () {
      final f = FriendProfile.fromMap({});
      expect(f.uid, '');
      expect(f.displayName, 'User');
      expect(f.email, '');
      expect(f.photoUrl, isNull);
    });

    test('a null photoUrl is preserved', () {
      final f = FriendProfile.fromMap({'uid': 'u1', 'photoUrl': null});
      expect(f.photoUrl, isNull);
    });
  });

  group('UserModel.fromMap', () {
    test('an empty document yields safe defaults', () {
      final u = UserModel.fromMap({}, 'uid1');
      expect(u.uid, 'uid1');
      expect(u.email, '');
      expect(u.displayName, 'User');
      expect(u.username, isNull);
      expect(u.friends, isEmpty);
      expect(u.friendRequestsSent, isEmpty);
      expect(u.friendRequestsReceived, isEmpty);
      expect(u.mutedFriends, isEmpty);
      expect(u.hiddenHiveIds, isEmpty);
    });

    test('parses friends, requests, mutes and hidden hives', () {
      final u = UserModel.fromMap({
        'email': 'a@b.com',
        'displayName': 'Alice',
        'username': 'alice',
        'friends': [
          {'uid': 'u2', 'displayName': 'Bob', 'email': 'b@c.com'},
        ],
        'friendRequestsSent': ['u3'],
        'friendRequestsReceived': ['u4'],
        'mutedFriends': ['u2'],
        'hiddenHiveIds': ['h1'],
      }, 'u1');

      expect(u.friends.single.uid, 'u2');
      expect(u.friendRequestsSent, ['u3']);
      expect(u.friendRequestsReceived, ['u4']);
      expect(u.mutedFriends, ['u2']);
      expect(u.hiddenHiveIds, ['h1']);
    });

    test('tolerates legacy string-only friend entries', () {
      final u = UserModel.fromMap({
        'friends': ['u2', 'u3'],
      }, 'u1');
      expect(u.friends.map((f) => f.uid), ['u2', 'u3']);
      expect(u.friends.first.displayName, 'Unknown');
    });

    test('one malformed friend does not break the whole document', () {
      final u = UserModel.fromMap({
        'displayName': 'Alice',
        'friends': [
          {'uid': 'u2', 'displayName': 'Bob', 'email': 'b@c.com'},
          {'uid': 'u3'}, // missing displayName and email
        ],
      }, 'u1');

      expect(u.displayName, 'Alice');
      expect(u.friends.length, 2);
      expect(u.friends[1].email, '');
    });
  });

  group('HiveModel.fromMap', () {
    test('an empty document yields safe defaults', () {
      final h = HiveModel.fromMap({}, 'h1');
      expect(h.id, 'h1');
      expect(h.title, 'Untitled');
      expect(h.privacy, HivePrivacy.private);
      expect(h.allowedViewerIds, isEmpty);
      expect(h.audienceIds, isEmpty);
      expect(h.isPublic, isFalse);
      expect(h.itemCount, 0);
      expect(h.totalCost, 0.0);
    });

    test('reads the new viewerIds / editorIds field names', () {
      final h = HiveModel.fromMap({
        'viewerIds': ['u2'],
        'editorIds': ['u3'],
      }, 'h1');
      expect(h.allowedViewerIds, ['u2']);
      expect(h.allowedEditorIds, ['u3']);
    });

    // v1.0.3 wrote only the legacy spelling; those documents must still parse.
    test('falls back to the legacy allowedViewerIds / allowedEditorIds', () {
      final h = HiveModel.fromMap({
        'allowedViewerIds': ['u2'],
        'allowedEditorIds': ['u3'],
      }, 'h1');
      expect(h.allowedViewerIds, ['u2']);
      expect(h.allowedEditorIds, ['u3']);
    });

    test('prefers the new field name when both are present', () {
      final h = HiveModel.fromMap({
        'viewerIds': ['new'],
        'allowedViewerIds': ['old'],
      }, 'h1');
      expect(h.allowedViewerIds, ['new']);
    });

    test('parses audienceIds and isPublic', () {
      final h = HiveModel.fromMap({
        'audienceIds': ['u1', 'u2'],
        'isPublic': true,
      }, 'h1');
      expect(h.audienceIds, ['u1', 'u2']);
      expect(h.isPublic, isTrue);
    });

    test('parses every privacy mode', () {
      expect(HiveModel.fromMap({'privacy': 'private'}, 'h').privacy,
          HivePrivacy.private);
      expect(HiveModel.fromMap({'privacy': 'friends'}, 'h').privacy,
          HivePrivacy.friends);
      expect(HiveModel.fromMap({'privacy': 'specific'}, 'h').privacy,
          HivePrivacy.specific);
      expect(HiveModel.fromMap({'privacy': 'public'}, 'h').privacy,
          HivePrivacy.public);
    });

    // Anything unrecognised must fall back to the most restrictive mode, never
    // to a permissive one.
    test('an unknown privacy value falls back to private', () {
      expect(HiveModel.fromMap({'privacy': 'nonsense'}, 'h').privacy,
          HivePrivacy.private);
      expect(HiveModel.fromMap({}, 'h').privacy, HivePrivacy.private);
    });

    test('coerces numeric types', () {
      final h = HiveModel.fromMap({'itemCount': 3, 'totalCost': 250}, 'h1');
      expect(h.itemCount, 3);
      expect(h.totalCost, 250.0);
    });
  });

  group('HiveModel.toFirestore', () {
    test('writes both the new and legacy field spellings', () {
      final data = const HiveModel(
        id: 'h1',
        title: 'Birthday',
        allowedViewerIds: ['u2'],
        allowedEditorIds: ['u3'],
      ).toFirestore();

      expect(data['viewerIds'], ['u2']);
      expect(data['allowedViewerIds'], ['u2']);
      expect(data['editorIds'], ['u3']);
      expect(data['allowedEditorIds'], ['u3']);
    });

    // The Cloud Function owns audienceIds and the rules reject a client that
    // tries to set it. Writing it here would make every hive save fail.
    test('never writes audienceIds', () {
      final data = const HiveModel(
        id: 'h1',
        title: 'Birthday',
        audienceIds: ['u1', 'u2', 'u3'],
      ).toFirestore();

      expect(data.containsKey('audienceIds'), isFalse);
    });

    test('round-trips through fromMap', () {
      const original = HiveModel(
        id: 'h1',
        title: 'Birthday',
        note: 'a note',
        privacy: HivePrivacy.specific,
        allowedViewerIds: ['u2', 'u3'],
        allowedEditorIds: ['u2'],
        itemCount: 2,
        totalCost: 750.0,
        ownerId: 'u1',
      );

      final parsed = HiveModel.fromMap(original.toFirestore(), 'h1');
      expect(parsed.title, original.title);
      expect(parsed.note, original.note);
      expect(parsed.privacy, original.privacy);
      expect(parsed.allowedViewerIds, original.allowedViewerIds);
      expect(parsed.allowedEditorIds, original.allowedEditorIds);
      expect(parsed.itemCount, original.itemCount);
      expect(parsed.totalCost, original.totalCost);
      expect(parsed.ownerId, original.ownerId);
    });
  });

  group('WishModel.fromMap', () {
    test('an empty document yields safe defaults', () {
      final w = WishModel.fromMap({}, 'w1');
      expect(w.id, 'w1');
      expect(w.name, 'No Name');
      expect(w.cost, 0.0);
      expect(w.quantity, 1);
      expect(w.fulfilledBy, '');
      expect(w.addedByUid, '');
      expect(w.isNote, isFalse);
      expect(w.date, isNull);
    });

    // ownerSeen drives the unseen-fulfilled badge. Defaulting to false would
    // light up a notification for every wish ever created.
    test('ownerSeen defaults to true', () {
      expect(WishModel.fromMap({}, 'w1').ownerSeen, isTrue);
      expect(WishModel.fromMap({'ownerSeen': false}, 'w1').ownerSeen, isFalse);
    });

    test('parses a contributed wish', () {
      final w = WishModel.fromMap({
        'name': 'Headphones',
        'hiveId': 'h1',
        'cost': 500,
        'quantity': 2,
        'addedByUid': 'u2',
        'addedByName': 'Bob',
        'fulfilledBy': 'u3',
        'fulfilledByName': 'Carol',
        'ownerSeen': false,
      }, 'w1');

      expect(w.name, 'Headphones');
      expect(w.hiveId, 'h1');
      expect(w.cost, 500.0);
      expect(w.quantity, 2);
      expect(w.addedByUid, 'u2');
      expect(w.fulfilledBy, 'u3');
      expect(w.ownerSeen, isFalse);
    });

    test('images default to empty so existing wishes still parse', () {
      final w = WishModel.fromMap({'name': 'Old wish'}, 'w1');
      expect(w.images, isEmpty);
      expect(w.imageUrl, '');
    });

    test('parses a scraped image gallery', () {
      final w = WishModel.fromMap({
        'name': 'Kurta',
        'imageUrl': 'https://cdn.example.com/1.jpg',
        'images': [
          'https://cdn.example.com/1.jpg',
          'https://cdn.example.com/2.jpg',
          'https://cdn.example.com/3.jpg',
        ],
      }, 'w1');

      expect(w.images.length, 3);
      expect(w.imageUrl, w.images.first);
    });

    test('images survive a toFirestore round trip', () {
      final original = WishModel(
        id: 'w1',
        name: 'Shoes',
        imageUrl: 'https://cdn.example.com/a.jpg',
        images: const ['https://cdn.example.com/a.jpg', 'https://cdn.example.com/b.jpg'],
        hiveId: 'h1',
        cost: 2499,
      );
      final parsed = WishModel.fromMap(original.toFirestore(), 'w1');
      expect(parsed.images, original.images);
      expect(parsed.imageUrl, original.imageUrl);
      expect(parsed.cost, 2499);
    });

    test('an unparseable date becomes null rather than throwing', () {
      expect(WishModel.fromMap({'date': 'not-a-date'}, 'w1').date, isNull);
      expect(WishModel.fromMap({'date': null}, 'w1').date, isNull);
    });
  });
}
