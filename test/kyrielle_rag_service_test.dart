import 'package:flutter_test/flutter_test.dart';
import 'package:tunga/services/kyrielle_rag_service.dart';

void main() {
  group('retrieveRelevantChunksLocally', () {
    test('finds the Davao watershed rule without an embedding API', () {
      final results = retrieveRelevantChunksLocally(
        'Is trekking allowed in Davao City watershed areas?',
      );

      expect(results, isNotEmpty);
      expect(results.first.id, 'HSM-PH-FAQ-09');
      expect(results.first.text, contains('without prior approval'));
    });

    test('finds instructions for creating a Hike Room', () {
      final results = retrieveRelevantChunksLocally(
        'How do I make a Hike Room?',
      );

      expect(results, isNotEmpty);
      expect(results.first.id, 'hike_room_create');
      expect(results.first.text, contains('mapped trail route'));
    });

    test('finds instructions for joining a Hike Room', () {
      final results = retrieveRelevantChunksLocally(
        'How can a hiker join a room with a code?',
      );

      expect(results, isNotEmpty);
      expect(results.first.id, 'hike_room_join');
      expect(results.first.text, contains('six-digit code'));
    });

    test('returns no match for empty or generic stop-word-only queries', () {
      expect(retrieveRelevantChunksLocally(''), isEmpty);
      expect(retrieveRelevantChunksLocally('How do I?'), isEmpty);
    });
  });

  test(
    'returns grounded local answers when no embedding API key is set',
    () async {
      final results = await KyrielleRagService.instance.retrieveRelevantAnswers(
        'Is trekking allowed in Davao City watershed areas?',
        apiKey: '',
      );

      expect(results, isNotEmpty);
      expect(results.first, contains('without prior approval'));
    },
  );
}
