import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class IncidentReportDialog extends StatefulWidget {
  const IncidentReportDialog({
    super.key,
    required this.reportId,
    required this.canRespond,
  });

  final String reportId;
  final bool canRespond;

  @override
  State<IncidentReportDialog> createState() => _IncidentReportDialogState();
}

class _IncidentReportDialogState extends State<IncidentReportDialog> {
  bool _updating = false;
  String? _actionError;

  Future<void> _updateReport({required String action}) async {
    setState(() {
      _updating = true;
      _actionError = null;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateIncidentReportStatus')
          .call({'reportId': widget.reportId, 'action': action});
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = 'Could not update the report: $error');
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportRef = FirebaseFirestore.instance
        .collection('incident_reports')
        .doc(widget.reportId);
    return AlertDialog(
      title: const Text('Hike Incident Report'),
      content: SizedBox(
        width: 480,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: reportRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load the filed report: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.data!.exists) {
              return const Text('This incident report is no longer available.');
            }
            final report = snapshot.data!.data()!;
            final status = report['status']?.toString() ?? 'submitted';
            final response = report['response']?.toString();
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(_statusLabel(status)),
                  ),
                  Text(
                    '${report['guideName'] ?? 'Tour Guide'} filed a report '
                    'for ${report['mountainName'] ?? 'the hike'}.',
                  ),
                  const SizedBox(height: 12),
                  Text('Hiker: ${report['hikerName'] ?? 'Hiker'}'),
                  Text('SOS reason: ${report['category'] ?? ''}'),
                  Text(
                    'Source: ${report['source'] == 'lora_relay_unverified' ? 'LoRa relay (not online-verified)' : 'Acknowledged online SOS'}',
                  ),
                  Text('Room: ${report['roomCode'] ?? ''}'),
                  Text(
                    'Location: ${report['latitude'] ?? 'Unavailable'}, '
                    '${report['longitude'] ?? 'Unavailable'}',
                  ),
                  const SizedBox(height: 12),
                  Text('Guide report:\n${report['guideNotes'] ?? ''}'),
                  if (report['acknowledgedByName'] != null) ...[
                    const SizedBox(height: 12),
                    Text('Acknowledged by ${report['acknowledgedByName']}.'),
                  ],
                  if (report['respondersSentByName'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Responders sent by ${report['respondersSentByName']}.',
                    ),
                  ],
                  if (report['respondedByName'] != null) ...[
                    const SizedBox(height: 8),
                    Text('Marked responded by ${report['respondedByName']}.'),
                  ],
                  if (response != null && response.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Mountain Head response'
                      '${report['respondedByName'] == null ? '' : ' · ${report['respondedByName']}'}:',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(response),
                  ],
                  if (_actionError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _actionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (_updating)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (widget.canRespond)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: reportRef.snapshots(),
            builder: (context, snapshot) {
              final status = snapshot.data?.data()?['status']?.toString();
              if (_updating || status == null || !snapshot.hasData) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != 'responded')
                    FilledButton.icon(
                      onPressed: () => _updateReport(
                        action: switch (status) {
                          'acknowledged' => 'send_responders',
                          'responders_sent' => 'resolve',
                          _ => 'acknowledge',
                        },
                      ),
                      icon: Icon(switch (status) {
                        'acknowledged' => Icons.support_agent_rounded,
                        'responders_sent' => Icons.task_alt_rounded,
                        _ => Icons.check_circle_outline_rounded,
                      }),
                      label: Text(switch (status) {
                        'acknowledged' => 'Mark responders sent',
                        'responders_sent' => 'Mark responded',
                        _ => 'Acknowledge report',
                      }),
                    ),
                ],
              );
            },
          ),
        TextButton(
          onPressed: _updating ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'acknowledged' => 'Acknowledged',
      'responders_sent' => 'Responders sent',
      'responded' => 'Responded',
      _ => 'Filed',
    };
  }
}
