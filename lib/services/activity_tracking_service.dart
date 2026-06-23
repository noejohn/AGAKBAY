import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tunga/services/offline_activity_database.dart';

class ActivityTrackingSnapshot {
  const ActivityTrackingSnapshot({
    this.activity,
    required this.points,
    required this.isTracking,
    required this.isPaused,
    required this.isOffline,
    required this.statusMessage,
    this.errorMessage,
  });

  final OfflineActivity? activity;
  final List<OfflineActivityPoint> points;
  final bool isTracking;
  final bool isPaused;
  final bool isOffline;
  final String statusMessage;
  final String? errorMessage;

  double get distanceKm => (activity?.distanceMeters ?? 0) / 1000;

  Duration get duration => Duration(seconds: activity?.durationSeconds ?? 0);

  Duration get movingDuration =>
      Duration(seconds: activity?.movingDurationSeconds ?? 0);

  double get averageSpeedMps => activity?.averageSpeedMps ?? 0;

  double get averagePaceSecondsPerKm {
    if (distanceKm <= 0) return 0;
    return movingDuration.inSeconds / distanceKm;
  }

  ActivityTrackingSnapshot copyWith({
    OfflineActivity? activity,
    List<OfflineActivityPoint>? points,
    bool? isTracking,
    bool? isPaused,
    bool? isOffline,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ActivityTrackingSnapshot(
      activity: activity ?? this.activity,
      points: points ?? this.points,
      isTracking: isTracking ?? this.isTracking,
      isPaused: isPaused ?? this.isPaused,
      isOffline: isOffline ?? this.isOffline,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage,
    );
  }

  static const empty = ActivityTrackingSnapshot(
    points: <OfflineActivityPoint>[],
    isTracking: false,
    isPaused: false,
    isOffline: false,
    statusMessage: 'Ready',
  );
}

class ActivityTrackingService {
  ActivityTrackingService({
    OfflineActivityDatabase? database,
    Connectivity? connectivity,
  }) : _database = database ?? OfflineActivityDatabase.instance,
       _connectivity = connectivity ?? Connectivity();

  static final ActivityTrackingService shared = ActivityTrackingService();

  final OfflineActivityDatabase _database;
  final Connectivity _connectivity;

  final StreamController<ActivityTrackingSnapshot> _snapshotController =
      StreamController<ActivityTrackingSnapshot>.broadcast();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _durationTimer;
  Timer? _periodicSaveTimer;

  ActivityTrackingSnapshot _snapshot = ActivityTrackingSnapshot.empty;
  Duration _updateInterval = const Duration(seconds: 5);
  int _distanceFilterMeters = 5;
  DateTime? _lastAcceptedAt;
  OfflineActivityPoint? _lastPoint;
  double _distanceMeters = 0;
  double _elevationGainMeters = 0;
  int _movingDurationSeconds = 0;

  Stream<ActivityTrackingSnapshot> get snapshots => _snapshotController.stream;

  ActivityTrackingSnapshot get snapshot => _snapshot;

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    final active = await _database.getActiveActivity();
    final isOffline = _isOffline(results);
    if (active != null) {
      final points = await _database.getActivityPoints(active.id);
      _hydrateStats(active, points);
      _snapshot = ActivityTrackingSnapshot(
        activity: active,
        points: points,
        isTracking: active.status == ActivityStatus.recording,
        isPaused: active.status == ActivityStatus.paused,
        isOffline: isOffline,
        statusMessage: active.status == ActivityStatus.paused
            ? 'Paused - saved offline'
            : _statusForConnectivity(isOffline),
      );
      _startDurationTimer();
      if (active.status == ActivityStatus.recording) {
        await _startPositionStream();
      }
    } else {
      _snapshot = ActivityTrackingSnapshot.empty.copyWith(
        isOffline: isOffline,
        statusMessage: isOffline ? 'Offline - ready for GPS' : 'Ready',
      );
    }
    _emit();
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final offline = _isOffline(results);
      _snapshot = _snapshot.copyWith(
        isOffline: offline,
        statusMessage: _snapshot.isTracking
            ? _statusForConnectivity(offline)
            : offline
            ? 'Offline - ready for GPS'
            : 'Ready',
      );
      _emit();
    });
  }

  Future<void> startActivity({
    String activityType = 'hike',
    Duration updateInterval = const Duration(seconds: 5),
    int distanceFilterMeters = 5,
  }) async {
    final permissionReady = await _ensureLocationPermission();
    if (!permissionReady) {
      _setError('Location permission or GPS is disabled.');
      return;
    }

    await stopActiveRecoveryIfNeeded();
    _updateInterval = updateInterval;
    _distanceFilterMeters = distanceFilterMeters;
    _lastAcceptedAt = null;
    _lastPoint = null;
    _distanceMeters = 0;
    _elevationGainMeters = 0;
    _movingDurationSeconds = 0;

    final activity = await _database.createActivity(
      activityType: activityType,
      startedAt: DateTime.now(),
    );
    _snapshot = ActivityTrackingSnapshot(
      activity: activity,
      points: const <OfflineActivityPoint>[],
      isTracking: true,
      isPaused: false,
      isOffline: _snapshot.isOffline,
      statusMessage: _statusForConnectivity(_snapshot.isOffline),
    );
    _emit();
    _startDurationTimer();
    await _startPositionStream();

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings(foreground: false),
      );
      await _handlePosition(position, force: true);
    } catch (_) {
      _setError('Waiting for GPS fix...');
    }
  }

  Future<void> pauseActivity() async {
    final activity = _snapshot.activity;
    if (activity == null || _snapshot.isPaused) return;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _database.updateActivity(
      id: activity.id,
      status: ActivityStatus.paused,
      durationSeconds: _durationSeconds(activity),
      movingDurationSeconds: _movingDurationSeconds,
      distanceMeters: _distanceMeters,
      elevationGainMeters: _elevationGainMeters,
      averageSpeedMps: _averageSpeedMps,
    );
    final updated = await _database.getActivity(activity.id);
    _snapshot = _snapshot.copyWith(
      activity: updated,
      isTracking: false,
      isPaused: true,
      statusMessage: 'Paused - saved offline',
    );
    _emit();
  }

  Future<void> resumeActivity() async {
    final activity = _snapshot.activity;
    if (activity == null || !_snapshot.isPaused) return;
    final permissionReady = await _ensureLocationPermission();
    if (!permissionReady) {
      _setError('Location permission or GPS is disabled.');
      return;
    }
    await _database.updateActivity(
      id: activity.id,
      status: ActivityStatus.recording,
    );
    final updated = await _database.getActivity(activity.id);
    _snapshot = _snapshot.copyWith(
      activity: updated,
      isTracking: true,
      isPaused: false,
      statusMessage: _statusForConnectivity(_snapshot.isOffline),
    );
    _emit();
    await _startPositionStream();
  }

  Future<OfflineActivity?> stopActivity() async {
    final activity = _snapshot.activity;
    if (activity == null) return null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _durationTimer?.cancel();
    _periodicSaveTimer?.cancel();
    final endedAt = DateTime.now();
    await _database.updateActivity(
      id: activity.id,
      status: ActivityStatus.finished,
      endedAt: endedAt,
      durationSeconds: _durationSeconds(activity, now: endedAt),
      movingDurationSeconds: _movingDurationSeconds,
      distanceMeters: _distanceMeters,
      elevationGainMeters: _elevationGainMeters,
      averageSpeedMps: _averageSpeedMps,
    );
    final finished = await _database.getActivity(activity.id);
    _snapshot = ActivityTrackingSnapshot(
      activity: finished,
      points: _snapshot.points,
      isTracking: false,
      isPaused: false,
      isOffline: _snapshot.isOffline,
      statusMessage: finished?.synced == true
          ? 'Activity synced'
          : 'Activity saved offline',
    );
    _emit();
    return finished;
  }

  Future<void> stopActiveRecoveryIfNeeded() async {
    final active = await _database.getActiveActivity();
    if (active == null) return;
    await _database.updateActivity(
      id: active.id,
      status: ActivityStatus.finished,
      endedAt: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    _durationTimer?.cancel();
    _periodicSaveTimer?.cancel();
    await _snapshotController.close();
  }

  Future<void> _startPositionStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _locationSettings(),
        ).listen(
          (position) => unawaited(_handlePosition(position)),
          onError: (_) => _setError('GPS signal interrupted. Reconnecting...'),
        );
  }

  LocationSettings _locationSettings({bool foreground = true}) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _distanceFilterMeters,
        intervalDuration: _updateInterval,
        foregroundNotificationConfig: foreground
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Agakbay activity tracking',
                notificationText: 'Tracking Offline - GPS Active',
                notificationChannelName: 'Activity tracking',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: _distanceFilterMeters,
    );
  }

  Future<void> _handlePosition(Position position, {bool force = false}) async {
    final activity = _snapshot.activity;
    if (activity == null || _snapshot.isPaused) return;

    final now = position.timestamp.toLocal();
    final lastAcceptedAt = _lastAcceptedAt;
    if (!force &&
        lastAcceptedAt != null &&
        now.difference(lastAcceptedAt) < _updateInterval) {
      return;
    }

    final previous = _lastPoint;
    var segmentMeters = 0.0;
    if (previous != null) {
      segmentMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (!force && segmentMeters < 2) return;
      if (segmentMeters > 250) return;
      final elapsed = now.difference(previous.timestamp).inSeconds;
      if (elapsed > 0) {
        _movingDurationSeconds += elapsed;
      }
      final previousAltitude = previous.altitudeMeters;
      final altitude = _validAltitude(position);
      if (previousAltitude != null && altitude != null) {
        final gain = altitude - previousAltitude;
        if (gain > 1 && gain < 100) {
          _elevationGainMeters += gain;
        }
      }
    }

    _distanceMeters += segmentMeters;
    final point = OfflineActivityPoint(
      activityId: activity.id,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: now,
      altitudeMeters: _validAltitude(position),
      accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
      speedMps: position.speed.isFinite && position.speed >= 0
          ? position.speed
          : null,
      distanceFromStartMeters: _distanceMeters,
    );

    await _database.insertPoint(point);
    _lastPoint = point;
    _lastAcceptedAt = now;
    await _saveStats(activity);

    final updated = await _database.getActivity(activity.id);
    _snapshot = _snapshot.copyWith(
      activity: updated,
      points: <OfflineActivityPoint>[..._snapshot.points, point],
      errorMessage: null,
      statusMessage: _statusForConnectivity(_snapshot.isOffline),
    );
    _emit();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _periodicSaveTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final activity = _snapshot.activity;
      if (activity == null || activity.status == ActivityStatus.finished) {
        return;
      }
      _snapshot = _snapshot.copyWith(
        activity: OfflineActivity(
          id: activity.id,
          activityType: activity.activityType,
          status: activity.status,
          startedAt: activity.startedAt,
          endedAt: activity.endedAt,
          durationSeconds: _durationSeconds(activity),
          movingDurationSeconds: _movingDurationSeconds,
          distanceMeters: _distanceMeters,
          elevationGainMeters: _elevationGainMeters,
          averageSpeedMps: _averageSpeedMps,
          synced: activity.synced,
          syncKey: activity.syncKey,
          syncedAt: activity.syncedAt,
        ),
      );
      _emit();
    });
    _periodicSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final activity = _snapshot.activity;
      if (activity != null && activity.status != ActivityStatus.finished) {
        unawaited(_saveStats(activity));
      }
    });
  }

  Future<void> _saveStats(OfflineActivity activity) {
    return _database.updateActivity(
      id: activity.id,
      durationSeconds: _durationSeconds(activity),
      movingDurationSeconds: _movingDurationSeconds,
      distanceMeters: _distanceMeters,
      elevationGainMeters: _elevationGainMeters,
      averageSpeedMps: _averageSpeedMps,
    );
  }

  void _hydrateStats(
    OfflineActivity activity,
    List<OfflineActivityPoint> points,
  ) {
    _distanceMeters = activity.distanceMeters;
    _elevationGainMeters = activity.elevationGainMeters;
    _movingDurationSeconds = activity.movingDurationSeconds;
    _lastPoint = points.isEmpty ? null : points.last;
    _lastAcceptedAt = _lastPoint?.timestamp;
  }

  int _durationSeconds(OfflineActivity activity, {DateTime? now}) {
    final end = now ?? activity.endedAt ?? DateTime.now();
    return end.difference(activity.startedAt).inSeconds.clamp(0, 1 << 31);
  }

  double get _averageSpeedMps {
    if (_movingDurationSeconds <= 0) return 0;
    return _distanceMeters / _movingDurationSeconds;
  }

  double? _validAltitude(Position position) {
    if (!position.altitude.isFinite || position.altitude.abs() > 12000) {
      return null;
    }
    return position.altitude;
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  bool _isOffline(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.none);
  }

  String _statusForConnectivity(bool offline) {
    return offline ? 'Tracking Offline - GPS Active' : 'Tracking - GPS Active';
  }

  void _setError(String message) {
    _snapshot = _snapshot.copyWith(errorMessage: message);
    _emit();
  }

  void _emit() {
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }
}
