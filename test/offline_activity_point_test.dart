import 'package:flutter_test/flutter_test.dart';
import 'package:tunga/services/offline_activity_database.dart';

void main() {
  group('OfflineActivityPoint serialization', () {
    final timestamp = DateTime.utc(2025, 3, 8, 12, 34, 56, 789);

    test('toMap returns database column names and UTC epoch milliseconds', () {
      final point = OfflineActivityPoint(
        id: 42,
        activityId: 'activity-1',
        latitude: 14.5995,
        longitude: 120.9842,
        timestamp: timestamp,
        altitudeMeters: 12.5,
        accuracyMeters: 3.2,
        speedMps: 1.4,
        distanceFromStartMeters: 56.7,
      );

      expect(point.toMap(), {
        'activity_id': 'activity-1',
        'latitude': 14.5995,
        'longitude': 120.9842,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'altitude_meters': 12.5,
        'accuracy_meters': 3.2,
        'speed_mps': 1.4,
        'distance_from_start_meters': 56.7,
      });
      expect(point.toMap(), isNot(contains('id')));
    });

    test('toSyncMap returns API field names and ISO 8601 timestamp', () {
      final point = OfflineActivityPoint(
        id: 42,
        activityId: 'activity-1',
        latitude: 14.5995,
        longitude: 120.9842,
        timestamp: timestamp,
        altitudeMeters: 12.5,
        accuracyMeters: 3.2,
        speedMps: 1.4,
        distanceFromStartMeters: 56.7,
      );

      expect(point.toSyncMap(), {
        'latitude': 14.5995,
        'longitude': 120.9842,
        'timestamp': timestamp.toIso8601String(),
        'altitudeMeters': 12.5,
        'accuracyMeters': 3.2,
        'speedMps': 1.4,
        'distanceFromStartMeters': 56.7,
      });
      expect(point.toSyncMap(), isNot(contains('id')));
      expect(point.toSyncMap(), isNot(contains('activity_id')));
    });

    test('both maps preserve nullable measurements as null', () {
      final point = OfflineActivityPoint(
        activityId: 'activity-2',
        latitude: 0,
        longitude: 0,
        timestamp: timestamp,
        distanceFromStartMeters: 0,
      );

      expect(point.toMap(), containsPair('altitude_meters', isNull));
      expect(point.toMap(), containsPair('accuracy_meters', isNull));
      expect(point.toMap(), containsPair('speed_mps', isNull));
      expect(point.toSyncMap(), containsPair('altitudeMeters', isNull));
      expect(point.toSyncMap(), containsPair('accuracyMeters', isNull));
      expect(point.toSyncMap(), containsPair('speedMps', isNull));
    });
  });
}
