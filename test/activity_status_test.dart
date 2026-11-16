import 'package:flutter_test/flutter_test.dart';
import 'package:tunga/services/offline_activity_database.dart';

void main() {
  group('ActivityStatus.fromDb', () {
    test('parses every valid database status', () {
      expect(ActivityStatus.fromDb('recording'), ActivityStatus.recording);
      expect(ActivityStatus.fromDb('paused'), ActivityStatus.paused);
      expect(ActivityStatus.fromDb('finished'), ActivityStatus.finished);
    });

    test('falls back to finished for an unknown value', () {
      expect(ActivityStatus.fromDb('in_progress'), ActivityStatus.finished);
    });
  });
}
