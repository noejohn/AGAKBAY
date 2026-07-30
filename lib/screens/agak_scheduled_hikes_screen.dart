import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agak_behavior.dart';
import '../models/agak_mountain.dart';
import '../services/agak_behavior_database.dart';
import '../services/agak_controller.dart';
import '../services/agak_packing_list.dart';
import '../widgets/agak_theme.dart';

/// Standalone "My Scheduled Hikes" surface, reached from the hamburger
/// menu. Deliberately separate from the AGAK companion screens — AGAK
/// reacts to scheduled hikes (reminders, packing tips) but doesn't own
/// scheduling UI itself.
class AgakScheduledHikesScreen extends StatefulWidget {
  const AgakScheduledHikesScreen({super.key, this.onScheduleNewHike});

  /// Opens the "pick a mountain, then a date" flow. Optional so this
  /// screen/file has no compile-time dependency on main.dart; when null,
  /// the add actions are hidden. The list refreshes itself via
  /// [AgakController]'s listener once a hike is actually saved, so this
  /// doesn't need to know when the flow finishes.
  final VoidCallback? onScheduleNewHike;

  @override
  State<AgakScheduledHikesScreen> createState() =>
      _AgakScheduledHikesScreenState();
}

class _AgakScheduledHikesScreenState extends State<AgakScheduledHikesScreen> {
  List<ScheduledHikeEntry> _hikes = const [];
  List<MountainCatalogEntry> _catalog = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    AgakController.instance.addListener(_onAgakChanged);
  }

  @override
  void dispose() {
    AgakController.instance.removeListener(_onAgakChanged);
    super.dispose();
  }

  void _onAgakChanged() {
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final db = AgakBehaviorDatabase.instance;
      final hikes = await db.getUpcomingScheduledHikes();
      final catalog = await db.getCatalog();
      if (!mounted) return;
      setState(() {
        _hikes = hikes;
        _catalog = catalog;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load your scheduled hikes. Pull down to retry.";
        _loading = false;
      });
      debugPrint('AgakScheduledHikesScreen load failed: $error');
    }
  }

  MountainCatalogEntry? _catalogMatch(ScheduledHikeEntry hike) {
    if (hike.mountainId == null) return null;
    for (final entry in _catalog) {
      if (entry.matchKey == hike.mountainId) return entry;
    }
    return null;
  }

  Future<void> _cancel(ScheduledHikeEntry hike) async {
    final id = hike.id;
    if (id == null) return;
    await AgakBehaviorDatabase.instance.cancelScheduledHike(id);
    unawaited(AgakController.instance.refresh(force: true));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canScheduleNew = widget.onScheduleNewHike != null;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'My Scheduled Hikes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (canScheduleNew)
                      IconButton(
                        tooltip: 'Schedule a hike',
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          color: AgakColors.accent,
                        ),
                        onPressed: widget.onScheduleNewHike,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AgakColors.accent,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AgakColors.accent,
                        child: _error != null
                            ? _ErrorState(message: _error!, onRetry: _load)
                            : _hikes.isEmpty
                            ? _EmptyState(canScheduleNew: canScheduleNew, onScheduleNewHike: widget.onScheduleNewHike)
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  24,
                                ),
                                children: _hikes.map((hike) {
                                  final catalogMatch = _catalogMatch(hike);
                                  return _ScheduledHikeCard(
                                    hike: hike,
                                    packingList: buildPackingList(
                                      difficulty:
                                          catalogMatch?.difficulty ??
                                          hike.difficulty ??
                                          'Moderate',
                                      elevationMasl:
                                          catalogMatch?.elevationMasl ??
                                          hike.elevationMasl,
                                      trailTypes:
                                          catalogMatch?.trailTypes ??
                                          const [],
                                      features:
                                          catalogMatch?.features ?? const [],
                                    ),
                                    onCancel: () => _cancel(hike),
                                  );
                                }).toList(),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canScheduleNew, this.onScheduleNewHike});

  final bool canScheduleNew;
  final VoidCallback? onScheduleNewHike;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
      children: [
        Container(
          width: 88,
          height: 88,
          margin: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            color: AgakColors.border.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.event_available_rounded,
            size: 40,
            color: AgakColors.accentSoft,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          "You don't have any upcoming hikes scheduled yet.",
          textAlign: TextAlign.center,
          style: AgakText.body.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        if (canScheduleNew) ...[
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onScheduleNewHike,
              style: FilledButton.styleFrom(
                backgroundColor: AgakColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.event_available_rounded),
              label: const Text(
                'Schedule a Hike',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFF7A7A).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: Color(0xFFFF8A8A),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AgakText.body.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AgakColors.accent,
              side: const BorderSide(color: AgakColors.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduledHikeCard extends StatelessWidget {
  const _ScheduledHikeCard({
    required this.hike,
    required this.packingList,
    required this.onCancel,
  });

  final ScheduledHikeEntry hike;
  final List<String> packingList;
  final VoidCallback onCancel;

  String get _whenLabel {
    final days = hike.daysUntil;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  String _formatDate(DateTime date) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasNotes = hike.notes != null && hike.notes!.isNotEmpty;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: cardShape,
          collapsedShape: cardShape,
          backgroundColor: AgakColors.surface,
          collapsedBackgroundColor: AgakColors.surface,
          iconColor: AgakColors.accentSoft,
          collapsedIconColor: Colors.white54,
          childrenPadding: EdgeInsets.zero,
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AgakColors.border.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: AgakColors.accentSoft,
              size: 20,
            ),
          ),
          title: Text(
            hike.mountainName,
            style: AgakText.cardTitle.copyWith(color: Colors.white),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '$_whenLabel · ${_formatDate(hike.scheduledDate)}'
              '${hasNotes ? '\n${hike.notes}' : ''}',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF8A8A),
                  size: 20,
                ),
                tooltip: 'Cancel hike',
                onPressed: onCancel,
                visualDensity: VisualDensity.compact,
              ),
              const Icon(Icons.expand_more_rounded, color: Colors.white54),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              decoration: BoxDecoration(
                color: AgakColors.surfaceRaised,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'WHAT TO BRING',
                    style: AgakText.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...packingList.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: AgakColors.accent,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
