import 'package:flutter_test/flutter_test.dart';
import 'package:tunga/services/agak_packing_list.dart';

void main() {
  group('buildPackingList', () {
    test('tailors items to trail conditions and difficulty', () {
      final items = buildPackingList(
        difficulty: 'hard',
        trailTypes: ['overnight', 'technical'],
        features: ['waterfall', 'wildlife-sanctuary'],
      );

      expect(items, contains('Sleeping bag rated for cold nights'));
      expect(items, contains('Gloves, and check with your guide on rope/technical gear needs'));
      expect(items, contains('Swimwear or a dry bag if you plan to take a dip'));
      expect(items, contains('Confirm guide/permit requirements for this protected area in advance'));
      expect(items, contains('Trekking poles'));
      expect(items, contains('Water (at least 2-3L)'));
    });

    test('includes each recommendation only once when inputs overlap or repeat', () {
      final items = buildPackingList(
        difficulty: 'hard',
        elevationMasl: 2500,
        trailTypes: ['Overnight', 'overnight', 'TECHNICAL', 'technical'],
        features: [
          'sunrise-viewpoint',
          'SUNRISE-VIEWPOINT',
          'forest',
          'Forest-edge',
          'waterfall',
          'lake',
        ],
      );

      expect(items.toSet().length, items.length,
          reason: 'Packing list entries should not be duplicated.');
      expect(
        items.where((item) => item == 'Insulating jacket or thermal layer for the cold summit push'),
        hasLength(1),
      );
      expect(items.where((item) => item == 'Beanie and gloves'), hasLength(1));
      expect(items.where((item) => item == 'Trekking poles'), hasLength(1));
    });

    test('returns the same ordered recommendations for the same inputs', () {
      List<String> generate() => buildPackingList(
        difficulty: 'Moderate',
        elevationMasl: 2500,
        trailTypes: ['overnight', 'technical'],
        features: ['forest', 'lake'],
      );

      expect(generate(), equals(generate()));
    });
  });
}
