import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum ActivityStatus {
  recording,
  paused,
  finished;

  static ActivityStatus fromDb(String value) {
    return ActivityStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ActivityStatus.finished,
    );
  }
}

class OfflineActivity {
  const OfflineActivity({
    required this.id,
    required this.activityType,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.durationSeconds,
    required this.movingDurationSeconds,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.averageSpeedMps,
    required this.synced,
    required this.syncKey,
    this.syncedAt,
  });

  final String id;
  final String activityType;
  final ActivityStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final int movingDurationSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final double averageSpeedMps;
  final bool synced;
  final String syncKey;
  final DateTime? syncedAt;

  factory OfflineActivity.fromMap(Map<String, Object?> map) {
    return OfflineActivity(
      id: map['id'] as String,
      activityType: map['activity_type'] as String,
      status: ActivityStatus.fromDb(map['status'] as String),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        map['started_at'] as int,
        isUtc: true,
      ).toLocal(),
      endedAt: map['ended_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['ended_at'] as int,
              isUtc: true,
            ).toLocal(),
      durationSeconds: map['duration_seconds'] as int,
      movingDurationSeconds: map['moving_duration_seconds'] as int,
      distanceMeters: (map['distance_meters'] as num).toDouble(),
      elevationGainMeters: (map['elevation_gain_meters'] as num).toDouble(),
      averageSpeedMps: (map['average_speed_mps'] as num).toDouble(),
      synced: (map['synced'] as int) == 1,
      syncKey: map['sync_key'] as String,
      syncedAt: map['synced_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['synced_at'] as int,
              isUtc: true,
            ).toLocal(),
    );
  }
}

class OfflineActivityPoint {
  const OfflineActivityPoint({
    this.id,
    required this.activityId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitudeMeters,
    this.accuracyMeters,
    this.speedMps,
    required this.distanceFromStartMeters,
  });

  final int? id;
  final String activityId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final double? speedMps;
  final double distanceFromStartMeters;

  Map<String, Object?> toMap() {
    return {
      'activity_id': activityId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
      'altitude_meters': altitudeMeters,
      'accuracy_meters': accuracyMeters,
      'speed_mps': speedMps,
      'distance_from_start_meters': distanceFromStartMeters,
    };
  }

  Map<String, Object?> toSyncMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'altitudeMeters': altitudeMeters,
      'accuracyMeters': accuracyMeters,
      'speedMps': speedMps,
      'distanceFromStartMeters': distanceFromStartMeters,
    };
  }

  factory OfflineActivityPoint.fromMap(Map<String, Object?> map) {
    return OfflineActivityPoint(
      id: map['id'] as int?,
      activityId: map['activity_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int,
        isUtc: true,
      ).toLocal(),
      altitudeMeters: (map['altitude_meters'] as num?)?.toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num?)?.toDouble(),
      speedMps: (map['speed_mps'] as num?)?.toDouble(),
      distanceFromStartMeters: (map['distance_from_start_meters'] as num)
          .toDouble(),
    );
  }
}

class PendingTrailSubmission {
  const PendingTrailSubmission({
    required this.id,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

class OfflineActivityDatabase {
  OfflineActivityDatabase._();

  static final OfflineActivityDatabase instance = OfflineActivityDatabase._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'offline_activities.db');
    final opened = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE activities (
            id TEXT PRIMARY KEY,
            activity_type TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            moving_duration_seconds INTEGER NOT NULL DEFAULT 0,
            distance_meters REAL NOT NULL DEFAULT 0,
            elevation_gain_meters REAL NOT NULL DEFAULT 0,
            average_speed_mps REAL NOT NULL DEFAULT 0,
            synced INTEGER NOT NULL DEFAULT 0,
            sync_key TEXT NOT NULL UNIQUE,
            synced_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE activity_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            activity_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            altitude_meters REAL,
            accuracy_meters REAL,
            speed_mps REAL,
            distance_from_start_meters REAL NOT NULL DEFAULT 0,
            FOREIGN KEY(activity_id) REFERENCES activities(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_points_activity_time ON activity_points(activity_id, timestamp)',
        );
        await db.execute(
          'CREATE INDEX idx_activities_sync ON activities(synced, status)',
        );
        await _createPendingTrailSubmissionsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPendingTrailSubmissionsTable(db);
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<OfflineActivity> createActivity({
    required String activityType,
    required DateTime startedAt,
  }) async {
    final db = await database;
    final utcStartedAt = startedAt.toUtc();
    final id = 'activity_${utcStartedAt.millisecondsSinceEpoch}';
    final syncKey = '${id}_${utcStartedAt.millisecondsSinceEpoch}';
    await db.insert('activities', {
      'id': id,
      'activity_type': activityType,
      'status': ActivityStatus.recording.name,
      'started_at': utcStartedAt.millisecondsSinceEpoch,
      'duration_seconds': 0,
      'moving_duration_seconds': 0,
      'distance_meters': 0.0,
      'elevation_gain_meters': 0.0,
      'average_speed_mps': 0.0,
      'synced': 0,
      'sync_key': syncKey,
    });
    return (await getActivity(id))!;
  }

  Future<void> insertPoint(OfflineActivityPoint point) async {
    final db = await database;
    await db.insert('activity_points', point.toMap());
  }

  Future<void> updateActivity({
    required String id,
    ActivityStatus? status,
    DateTime? endedAt,
    int? durationSeconds,
    int? movingDurationSeconds,
    double? distanceMeters,
    double? elevationGainMeters,
    double? averageSpeedMps,
  }) async {
    final values = <String, Object?>{};
    if (status != null) values['status'] = status.name;
    if (endedAt != null) {
      values['ended_at'] = endedAt.toUtc().millisecondsSinceEpoch;
    }
    if (durationSeconds != null) values['duration_seconds'] = durationSeconds;
    if (movingDurationSeconds != null) {
      values['moving_duration_seconds'] = movingDurationSeconds;
    }
    if (distanceMeters != null) values['distance_meters'] = distanceMeters;
    if (elevationGainMeters != null) {
      values['elevation_gain_meters'] = elevationGainMeters;
    }
    if (averageSpeedMps != null) values['average_speed_mps'] = averageSpeedMps;
    if (values.isEmpty) return;

    final db = await database;
    await db.update('activities', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markActivitySynced(String id) async {
    final db = await database;
    await db.update(
      'activities',
      {'synced': 1, 'synced_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<OfflineActivity?> getActivity(String id) async {
    final db = await database;
    final rows = await db.query(
      'activities',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineActivity.fromMap(rows.first);
  }

  Future<OfflineActivity?> getActiveActivity() async {
    final db = await database;
    final rows = await db.query(
      'activities',
      where: 'status IN (?, ?)',
      whereArgs: [ActivityStatus.recording.name, ActivityStatus.paused.name],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineActivity.fromMap(rows.first);
  }

  Future<List<OfflineActivity>> getRecentActivities({int limit = 20}) async {
    final db = await database;
    final rows = await db.query(
      'activities',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(OfflineActivity.fromMap).toList();
  }

  Future<List<OfflineActivity>> getUnsyncedFinishedActivities() async {
    final db = await database;
    final rows = await db.query(
      'activities',
      where: 'synced = 0 AND status = ?',
      whereArgs: [ActivityStatus.finished.name],
      orderBy: 'started_at ASC',
    );
    return rows.map(OfflineActivity.fromMap).toList();
  }

  Future<List<OfflineActivityPoint>> getActivityPoints(
    String activityId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'activity_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(OfflineActivityPoint.fromMap).toList();
  }

  Future<String> queueTrailSubmission(Map<String, dynamic> payload) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final id = 'trail_${now.microsecondsSinceEpoch}';
    final storedPayload = <String, dynamic>{
      ...payload,
      'localSubmissionId': id,
    };
    await db.insert('pending_trail_submissions', {
      'id': id,
      'payload_json': jsonEncode(storedPayload),
      'created_at': now.millisecondsSinceEpoch,
      'synced': 0,
    });
    return id;
  }

  Future<List<PendingTrailSubmission>> getPendingTrailSubmissions() async {
    final db = await database;
    final rows = await db.query(
      'pending_trail_submissions',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) {
          final decoded = jsonDecode(row['payload_json'] as String);
          return PendingTrailSubmission(
            id: row['id'] as String,
            payload: Map<String, dynamic>.from(decoded as Map),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
              isUtc: true,
            ).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<void> markTrailSubmissionSynced(String id) async {
    final db = await database;
    await db.update(
      'pending_trail_submissions',
      {'synced': 1, 'synced_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> _createPendingTrailSubmissionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_trail_submissions (
        id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trail_submissions_sync '
      'ON pending_trail_submissions(synced, created_at)',
    );
  }
}
