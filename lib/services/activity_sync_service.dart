import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tunga/services/offline_activity_database.dart';

class ActivitySyncService {
  ActivitySyncService({
    OfflineActivityDatabase? database,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
  }) : _database = database ?? OfflineActivityDatabase.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _connectivity = connectivity ?? Connectivity();

  static final ActivitySyncService shared = ActivitySyncService();

  final OfflineActivityDatabase _database;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Connectivity _connectivity;

  bool _syncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void startAutoSync() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (!results.contains(ConnectivityResult.none)) {
        syncPendingActivities();
      }
    });
    syncPendingActivities();
  }

  Future<int> syncPendingActivities() async {
    if (_syncing) return 0;
    final user = _auth.currentUser;
    if (user == null) return 0;

    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return 0;

    _syncing = true;
    var syncedCount = 0;
    try {
      final activities = await _database.getUnsyncedFinishedActivities();
      for (final activity in activities) {
        try {
          final synced = await _uploadActivity(user.uid, activity);
          if (synced) {
            await _database.markActivitySynced(activity.id);
            syncedCount++;
          }
        } catch (_) {
          // Keep the local activity pending for the next reconnect attempt.
        }
      }
      final trailSubmissions = await _database.getPendingTrailSubmissions();
      for (final submission in trailSubmissions) {
        try {
          await _firestore
              .collection('trail_submissions')
              .doc(submission.id)
              .set({
                ...submission.payload,
                'submittedBy': user.uid,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
          await _database.markTrailSubmissionSynced(submission.id);
          syncedCount++;
        } catch (_) {
          // Keep the route pending until Firestore is reachable again.
        }
      }
    } finally {
      _syncing = false;
    }
    return syncedCount;
  }

  Future<bool> _uploadActivity(String userId, OfflineActivity activity) async {
    final points = await _database.getActivityPoints(activity.id);
    final activityRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('offline_activities')
        .doc(activity.syncKey);

    final existing = await activityRef.get();
    if (existing.exists && existing.data()?['uploadComplete'] == true) {
      return true;
    }

    await activityRef.set({
      'localActivityId': activity.id,
      'syncKey': activity.syncKey,
      'activityType': activity.activityType,
      'status': activity.status.name,
      'startedAt': Timestamp.fromDate(activity.startedAt.toUtc()),
      'endedAt': activity.endedAt == null
          ? null
          : Timestamp.fromDate(activity.endedAt!.toUtc()),
      'durationSeconds': activity.durationSeconds,
      'movingDurationSeconds': activity.movingDurationSeconds,
      'distanceMeters': activity.distanceMeters,
      'elevationGainMeters': activity.elevationGainMeters,
      'averageSpeedMps': activity.averageSpeedMps,
      'pointCount': points.length,
      'uploadComplete': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (var start = 0; start < points.length; start += 400) {
      final batch = _firestore.batch();
      final end = (start + 400) > points.length ? points.length : start + 400;
      for (var index = start; index < end; index++) {
        final point = points[index];
        final docId = index.toString().padLeft(8, '0');
        batch.set(
          activityRef.collection('points').doc(docId),
          point.toSyncMap(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    await activityRef.set({
      'uploadComplete': true,
      'syncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }
}
