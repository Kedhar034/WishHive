// The card colour has to survive the whole way to Firestore and back.
//
// updateHive writes an explicit field map rather than toFirestore(), so a new
// field is easy to add to the model and then forget to persist — which is
// exactly what happened: picking a colour on an existing hive did nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/hive_model.dart';

void main() {
  group('HiveModel.cardColor', () {
    test('defaults to null so existing hives keep their derived tint', () {
      expect(HiveModel.fromMap({}, 'h1').cardColor, isNull);
    });

    test('parses a named key and a hex value alike', () {
      expect(HiveModel.fromMap({'cardColor': 'blush'}, 'h1').cardColor, 'blush');
      expect(
          HiveModel.fromMap({'cardColor': '#7ed6a5'}, 'h1').cardColor, '#7ed6a5');
    });

    test('is written out when set', () {
      const hive = HiveModel(id: 'h1', title: 'Birthday', cardColor: 'blue');
      expect(hive.toFirestore()['cardColor'], 'blue');
    });

    test('is omitted when never picked', () {
      const hive = HiveModel(id: 'h1', title: 'Birthday');
      expect(hive.toFirestore().containsKey('cardColor'), isFalse);
    });

    test('survives a round trip', () {
      const original = HiveModel(id: 'h1', title: 'Birthday', cardColor: '#7ed6a5');
      expect(HiveModel.fromMap(original.toFirestore(), 'h1').cardColor,
          '#7ed6a5');
    });

    test('copyWith keeps the existing colour when none is supplied', () {
      const original = HiveModel(id: 'h1', title: 'A', cardColor: 'butter');
      expect(original.copyWith(title: 'B').cardColor, 'butter');
      expect(original.copyWith(cardColor: 'sky').cardColor, 'sky');
    });
  });
}
