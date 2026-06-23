import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tunga/services/activity_sync_service.dart';
import 'package:tunga/services/activity_tracking_service.dart';
import 'package:tunga/services/offline_activity_database.dart';
import 'package:tunga/widgets/offline_map_widget.dart';

class OfflineActivityTrackerScreen extends StatefulWidget {
  const OfflineActivityTrackerScreen({super.key});

  @override
  State<OfflineActivityTrackerScreen> createState() =>
      _OfflineActivityTrackerScreenState();
}

class _OfflineActivityTrackerScreenState
    extends State<OfflineActivityTrackerScreen> {
  final ActivityTrackingService _trackingService =
      ActivityTrackingService.shared;
  final ActivitySyncService _syncService = ActivitySyncService.shared;
  final OfflineActivityDatabase _database = OfflineActivityDatabase.instance;

  StreamSubscription<ActivityTrackingSnapshot>? _trackingSubscription;
  ActivityTrackingSnapshot _snapshot = ActivityTrackingService.shared.snapshot;
  List<OfflineActivity> _recentActivities = const <OfflineActivity>[];
  String _activityType = 'hike';
  int _intervalSeconds = 5;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _trackingService.initialize();
    _trackingSubscription = _trackingService.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    });
    await _refreshRecentActivities();
    if (!mounted) return;
    setState(() {
      _snapshot = _trackingService.snapshot;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshRecentActivities() async {
    final activities = await _database.getRecentActivities();
    if (!mounted) return;
    setState(() => _recentActivities = activities);
  }

  Future<void> _startActivity() async {
    await _trackingService.startActivity(
      activityType: _activityType,
      updateInterval: Duration(seconds: _intervalSeconds),
      distanceFilterMeters: _intervalSeconds >= 10 ? 8 : 5,
    );
    await _refreshRecentActivities();
  }

  Future<void> _stopActivity() async {
    final activity = await _trackingService.stopActivity();
    await _refreshRecentActivities();
    if (activity == null || !mounted) return;
    unawaited(_syncPending());
    final points = await _database.getActivityPoints(activity.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            ActivitySummaryScreen(activity: activity, points: points),
      ),
    );
    await _refreshRecentActivities();
  }

  Future<void> _syncPending() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await _syncService.syncPendingActivities();
      await _refreshRecentActivities();
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = _snapshot.activity;
    final canStart =
        activity == null || activity.status == ActivityStatus.finished;
    final canPause = _snapshot.isTracking && !_snapshot.isPaused;
    final canResume = _snapshot.isPaused;
    final canStop =
        activity != null && activity.status != ActivityStatus.finished;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline GPS Tracker'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sync activities',
            onPressed: _syncing ? null : _syncPending,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBanner(snapshot: _snapshot),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 260,
                      child: _RoutePreview(points: _snapshot.points),
                    ),
                    const SizedBox(height: 16),
                    _MetricGrid(snapshot: _snapshot),
                    const SizedBox(height: 18),
                    if (canStart) ...[
                      _ActivityOptions(
                        activityType: _activityType,
                        intervalSeconds: _intervalSeconds,
                        onActivityTypeChanged: (value) {
                          setState(() => _activityType = value);
                        },
                        onIntervalChanged: (value) {
                          setState(() => _intervalSeconds = value);
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canStart ? _startActivity : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Activity'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canPause
                                ? _trackingService.pauseActivity
                                : null,
                            icon: const Icon(Icons.pause_rounded),
                            label: const Text('Pause'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canResume
                                ? _trackingService.resumeActivity
                                : null,
                            icon: const Icon(Icons.replay_rounded),
                            label: const Text('Resume'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canStop ? _stopActivity : null,
                        icon: const Icon(Icons.stop_circle_rounded),
                        label: const Text('Stop Activity'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD84334),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_snapshot.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _snapshot.errorMessage!,
                        style: const TextStyle(color: Color(0xFFFFA39A)),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Text(
                      'Recent Activities',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _RecentActivities(
                      activities: _recentActivities,
                      onOpen: (activity) async {
                        final navigator = Navigator.of(context);
                        final points = await _database.getActivityPoints(
                          activity.id,
                        );
                        if (!mounted) return;
                        await navigator.push(
                          MaterialPageRoute<void>(
                            builder: (context) => ActivitySummaryScreen(
                              activity: activity,
                              points: points,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class ActivitySummaryScreen extends StatelessWidget {
  const ActivitySummaryScreen({
    super.key,
    required this.activity,
    required this.points,
  });

  final OfflineActivity activity;
  final List<OfflineActivityPoint> points;

  @override
  Widget build(BuildContext context) {
    final snapshot = ActivityTrackingSnapshot(
      activity: activity,
      points: points,
      isTracking: false,
      isPaused: false,
      isOffline: !activity.synced,
      statusMessage: activity.synced ? 'Synced' : 'Saved offline',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Activity Summary')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 280, child: _RoutePreview(points: points)),
              const SizedBox(height: 16),
              _MetricGrid(snapshot: snapshot),
              const SizedBox(height: 18),
              _SummaryRow(
                icon: Icons.timer_rounded,
                label: 'Total Time',
                value: _formatDuration(snapshot.duration),
              ),
              _SummaryRow(
                icon: Icons.route_rounded,
                label: 'Total Distance',
                value: '${snapshot.distanceKm.toStringAsFixed(2)} km',
              ),
              _SummaryRow(
                icon: Icons.speed_rounded,
                label: 'Average Pace',
                value: _formatPace(snapshot.averagePaceSecondsPerKm),
              ),
              _SummaryRow(
                icon: Icons.terrain_rounded,
                label: 'Elevation Gain',
                value: '${activity.elevationGainMeters.toStringAsFixed(0)} m',
              ),
              _SummaryRow(
                icon: activity.synced
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                label: 'Sync Status',
                value: activity.synced ? 'Synced' : 'Saved locally',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snapshot});

  final ActivityTrackingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final isActive = snapshot.isTracking || snapshot.isPaused;
    final color = snapshot.isOffline
        ? const Color(0xFF78E08F)
        : const Color(0xFF7CCBFF);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF102016),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Row(
        children: [
          Icon(
            snapshot.isPaused
                ? Icons.pause_circle_filled_rounded
                : isActive
                ? Icons.gps_fixed_rounded
                : Icons.gps_not_fixed_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.statusMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? 'GPS points are stored locally as they arrive.'
                      : 'Start an activity to record offline GPS data.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePreview extends StatelessWidget {
  const _RoutePreview({required this.points});

  final List<OfflineActivityPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0B1711),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          'Route line will appear after GPS points are recorded',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
      );
    }

    final mapPoints = points
        .map<Map<String, double>>(
          (point) => {'latitude': point.latitude, 'longitude': point.longitude},
        )
        .toList(growable: false);
    final polyline = TrailPolylineConverter.convertToPolyline(
      mapPoints,
      color: const Color(0xFF48D1FF),
      strokeWidth: 4,
    );
    final markers = TrailPolylineConverter.convertToMarkers(mapPoints);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: OfflineMapWidget(
        initialLatitude: points.last.latitude,
        initialLongitude: points.last.longitude,
        initialZoom: 15,
        markers: markers,
        polylines: [polyline],
        showScaleLayer: false,
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});

  final ActivityTrackingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _MetricTile(
              label: 'Distance',
              value: '${snapshot.distanceKm.toStringAsFixed(2)} km',
            ),
            const SizedBox(width: 10),
            _MetricTile(
              label: 'Time',
              value: _formatDuration(snapshot.duration),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MetricTile(
              label: 'Pace',
              value: _formatPace(snapshot.averagePaceSecondsPerKm),
            ),
            const SizedBox(width: 10),
            _MetricTile(
              label: 'Speed',
              value:
                  '${(snapshot.averageSpeedMps * 3.6).toStringAsFixed(1)} km/h',
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityOptions extends StatelessWidget {
  const _ActivityOptions({
    required this.activityType,
    required this.intervalSeconds,
    required this.onActivityTypeChanged,
    required this.onIntervalChanged,
  });

  final String activityType;
  final int intervalSeconds;
  final ValueChanged<String> onActivityTypeChanged;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity Type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'hike', label: Text('Hike')),
            ButtonSegment(value: 'walk', label: Text('Walk')),
            ButtonSegment(value: 'run', label: Text('Run')),
            ButtonSegment(value: 'cycle', label: Text('Bike')),
          ],
          selected: {activityType},
          onSelectionChanged: (values) => onActivityTypeChanged(values.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 14),
        Text(
          'GPS Update Interval',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 5, label: Text('5 sec')),
            ButtonSegment(value: 10, label: Text('10 sec')),
          ],
          selected: {intervalSeconds},
          onSelectionChanged: (values) => onIntervalChanged(values.first),
        ),
      ],
    );
  }
}

class _RecentActivities extends StatelessWidget {
  const _RecentActivities({required this.activities, required this.onOpen});

  final List<OfflineActivity> activities;
  final ValueChanged<OfflineActivity> onOpen;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return Text(
        'No activities recorded yet.',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      );
    }

    return Column(
      children: [
        for (final activity in activities)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              activity.synced ? Icons.cloud_done_rounded : Icons.cloud_off,
              color: activity.synced
                  ? const Color(0xFF78E08F)
                  : const Color(0xFFFFC857),
            ),
            title: Text(
              '${activity.activityType.toUpperCase()} - ${(activity.distanceMeters / 1000).toStringAsFixed(2)} km',
            ),
            subtitle: Text(
              '${_formatDuration(Duration(seconds: activity.durationSeconds))} - ${activity.status.name}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpen(activity),
          ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF78E08F)),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

String _formatPace(double secondsPerKm) {
  if (secondsPerKm <= 0 || secondsPerKm.isNaN || secondsPerKm.isInfinite) {
    return '-- /km';
  }
  final minutes = secondsPerKm ~/ 60;
  final seconds = secondsPerKm.round().remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
}
