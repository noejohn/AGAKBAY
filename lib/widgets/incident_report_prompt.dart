import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tunga/services/activity_sync_service.dart';
import 'package:tunga/services/hike_room_service.dart';
import 'package:tunga/services/offline_activity_database.dart';

bool isIncidentReportWorthySos(String? reason) {
  final normalized = reason?.trim().toLowerCase() ?? '';
  if (normalized == 'lost' || normalized == 'accident') return true;
  return RegExp(
    r'\b(disaster|calamity|typhoon|hurricane|cyclone|flood|landslide|'
    r'earthquake|volcan|tsunami|wildfire|forest fire|lightning|incident|'
    r'tornado|avalanche|mudslide)\b',
  ).hasMatch(normalized);
}

Future<void> offerIncidentReportAfterSosAcknowledged(
  BuildContext context, {
  required HikeRoom room,
  required RoomSosEvent event,
}) async {
  if (!isIncidentReportWorthySos(event.reason)) return;

  await _offerIncidentReport(
    context,
    room: room,
    senderName: event.senderName,
    reason: event.reason,
    latitude: event.latitude,
    longitude: event.longitude,
    source: 'firestore',
    eventId: event.id,
  );
}

Future<void> offerIncidentReportForOfflineSos(
  BuildContext context, {
  required HikeRoom room,
  required String senderName,
  required String? reason,
  required double? latitude,
  required double? longitude,
  required DateTime? receivedAt,
}) async {
  if (!isIncidentReportWorthySos(reason)) return;

  await _offerIncidentReport(
    context,
    room: room,
    senderName: senderName,
    reason: reason,
    latitude: latitude,
    longitude: longitude,
    source: 'lora',
    receivedAt: receivedAt,
  );
}

Future<void> _offerIncidentReport(
  BuildContext context, {
  required HikeRoom room,
  required String senderName,
  required String? reason,
  required double? latitude,
  required double? longitude,
  required String source,
  String? eventId,
  DateTime? receivedAt,
}) async {
  final notes = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _IncidentReportDialog(
      room: room,
      senderName: senderName,
      reason: reason,
      latitude: latitude,
      longitude: longitude,
      isOfflineRelay: source == 'lora',
    ),
  );
  if (notes == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  String? syncError;
  try {
    final payload = <String, dynamic>{
      'roomId': room.id,
      'guideId': FirebaseAuth.instance.currentUser?.uid,
      'source': source,
      'mountainName': room.mountainName,
      'hikerName': senderName,
      'reason': reason,
      'latitude': latitude,
      'longitude': longitude,
      'guideNotes': notes,
      'eventId': ?eventId,
      'receivedAt': ?receivedAt?.toUtc().toIso8601String(),
    };
    final reportId = source == 'firestore' && eventId != null
        ? 'incident_${room.id}_$eventId'
        : source == 'lora' && receivedAt != null
        ? 'incident_lora_${room.id}_${receivedAt.microsecondsSinceEpoch}'
        : null;
    final queuedReportId = await OfflineActivityDatabase.instance.queueIncidentReport(
      payload,
      id: reportId,
    );
    try {
      await ActivitySyncService.shared.syncPendingActivities();
    } catch (error) {
      syncError = error.toString();
      debugPrint('Could not sync incident report $queuedReportId: $error');
    }
    var stillPending = true;
    try {
      stillPending =
          (await OfflineActivityDatabase.instance.getPendingIncidentReports())
              .any((report) => report.id == queuedReportId);
    } catch (error) {
      syncError = error.toString();
      debugPrint('Could not check incident report $queuedReportId status: $error');
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          stillPending
              ? syncError == null
                    ? 'Incident report saved on this phone. It will be sent to the Mountain Head when internet is available.'
                    : 'Incident report saved on this phone. It could not be sent yet and will be retried.'
              : 'Incident report sent to the Mountain Head.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not save incident report on this phone: $error'),
      ),
    );
  }
}

class _IncidentReportDialog extends StatefulWidget {
  const _IncidentReportDialog({
    required this.room,
    required this.senderName,
    required this.reason,
    required this.latitude,
    required this.longitude,
    required this.isOfflineRelay,
  });

  final HikeRoom room;
  final String senderName;
  final String? reason;
  final double? latitude;
  final double? longitude;
  final bool isOfflineRelay;

  @override
  State<_IncidentReportDialog> createState() => _IncidentReportDialogState();
}

class _IncidentReportDialogState extends State<_IncidentReportDialog> {
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.latitude == null || widget.longitude == null
        ? 'Location unavailable'
        : 'Location: ${widget.latitude!.toStringAsFixed(6)}, '
              '${widget.longitude!.toStringAsFixed(6)}';
    return PopScope(
      canPop: false,
      child: AlertDialog(
      icon: const Icon(Icons.report_problem_rounded),
      title: const Text('Report this incident?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.senderName} · ${widget.reason ?? 'SOS'}\n'
              '${widget.room.mountainName}\n'
              '$location'
              '${widget.isOfflineRelay ? '\nReceived over LoRa; the sender was not verified online.' : ''}',
            ),
            const SizedBox(height: 16),
            const Text(
              'Add details for the Mountain Head. This report will be saved '
              'on this phone first and sent when internet is available.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLength: 2000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Incident details',
                hintText: 'What happened and what action was taken?',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _notesController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_notesController.text.trim()),
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save and Submit'),
        ),
      ],
      ),
    );
  }
}
