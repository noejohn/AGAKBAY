// The full Admin Dashboard shell shown after a successful sign-in —
// sidebar navigation + main content area. Only "Dashboard" has real
// content wired up so far; the rest are placeholders until their backing
// Cloud Functions/collections exist (tour guide application review,
// trail review, device registry, audit logs, etc. — see the project's
// admin-plan sequencing).
//
// Where real Firestore data already exists (trail_submissions,
// hike_rooms, users' self-declared tour_guide/guideVerified fields),
// the stat cards and lists below are wired to live streams rather than
// hardcoded demo numbers — anything without a backing collection yet
// honestly shows "—" or an empty-state message instead of invented data.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../admin_main.dart' show AdminColors;

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _navItems = [
  _NavItem('Dashboard', Icons.grid_view_rounded),
  _NavItem('Tour Guide Verification', Icons.badge_outlined),
  _NavItem('Trail Verification', Icons.alt_route_rounded),
  _NavItem('Hike Room Monitoring', Icons.terrain_rounded),
  _NavItem('SOS Monitoring', Icons.warning_amber_rounded),
  _NavItem('Bluetooth Devices', Icons.bluetooth),
  _NavItem('User Management', Icons.people_outline_rounded),
  _NavItem('Notifications', Icons.notifications_outlined),
  _NavItem('Audit Logs', Icons.description_outlined),
];

class AdminDashboardShell extends StatefulWidget {
  const AdminDashboardShell({super.key, required this.user, required this.onSignOut});

  final User user;
  final VoidCallback onSignOut;

  @override
  State<AdminDashboardShell> createState() => _AdminDashboardShellState();
}

class _AdminDashboardShellState extends State<AdminDashboardShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          selected: _selected,
          onSelect: (i) => setState(() => _selected = i),
          user: widget.user,
          onSignOut: widget.onSignOut,
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF4F6F5),
            child: switch (_selected) {
              0 => const _DashboardOverviewPage(),
              1 => const _TourGuideVerificationPage(),
              2 => const _TrailVerificationPage(),
              _ => _ComingSoonPage(title: _navItems[_selected].label),
            },
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.onSignOut,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final User user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: AdminColors.backgroundTop,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AdminColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.terrain_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Agakbay',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Admin Dashboard',
                        style: TextStyle(color: AdminColors.accent, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _navItems.length,
              itemBuilder: (context, i) {
                final item = _navItems[i];
                final isSelected = i == selected;
                return Material(
                  color: isSelected ? AdminColors.accent : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Icon(item.icon, color: Colors.white, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white24))),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AdminColors.accent,
                  child: Text(
                    (user.email ?? '?').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Admin',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        user.email ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                  tooltip: 'Sign out',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showNotWiredUpYet(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Approve/reject isn\'t wired up yet — this is a UI preview.')),
  );
}

class _DashboardOverviewPage extends StatelessWidget {
  const _DashboardOverviewPage();

  @override
  Widget build(BuildContext context) {
    final pendingGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');
    final approvedGuidesQuery = FirebaseFirestore.instance
        .collection('users')
        .where('accountType', isEqualTo: 'tour_guide')
        .where('guideVerified', isEqualTo: true);
    final pendingTrailsQuery = FirebaseFirestore.instance
        .collection('trail_submissions')
        .where('status', isEqualTo: 'pending');
    final activeRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dashboard Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Summary of activity on the Agakbay platform', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: pendingGuidesQuery.snapshots(),
            builder: (context, guideSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: pendingTrailsQuery.snapshots(),
                builder: (context, trailSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: activeRoomsQuery.snapshots(),
                    builder: (context, roomSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: approvedGuidesQuery.snapshots(),
                        builder: (context, approvedSnap) {
                          return _StatGrid(
                            pendingGuides: guideSnap.data?.docs.length,
                            pendingTrails: trailSnap.data?.docs.length,
                            activeRooms: roomSnap.data?.docs.length,
                            approvedGuides: approvedSnap.data?.docs.length,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 28),
          _SectionCard(
            title: 'Pending Tour Guide Applications',
            child: StreamBuilder<QuerySnapshot>(
              stream: pendingGuidesQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _StreamErrorRow(snap.error);
                }
                if (!snap.hasData) {
                  return const _LoadingRow();
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _EmptyRow('No pending guide applications.');
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return _ListRow(
                      title: (data['fullName'] as String?) ?? (data['applicantEmail'] as String?) ?? d.id,
                      subtitle: (data['applicantEmail'] as String?) ?? '',
                      onReview: () => _showNotWiredUpYet(context),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Pending Trail Route Submissions',
            child: StreamBuilder<QuerySnapshot>(
              stream: pendingTrailsQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _StreamErrorRow(snap.error);
                }
                if (!snap.hasData) {
                  return const _LoadingRow();
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _EmptyRow('No pending trail submissions.');
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final distance = (data['distanceKm'] as num?)?.toStringAsFixed(1);
                    final elevation = (data['elevationGainMasl'] as num?)?.round();
                    final subtitleParts = <String>[
                      if (distance != null) '$distance km',
                      if (elevation != null) '$elevation m elevation',
                    ];
                    return _ListRow(
                      title: (data['trailName'] as String?) ?? (data['mountainName'] as String?) ?? d.id,
                      subtitle: subtitleParts.join(' • '),
                      onReview: () => _showNotWiredUpYet(context),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Recent Admin Actions',
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_actions')
                  .orderBy('createdAt', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _StreamErrorRow(snap.error);
                }
                if (!snap.hasData) {
                  return const _LoadingRow();
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _EmptyRow('No admin actions logged yet.');
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final action = (data['action'] as String?) ?? 'unknown_action';
                    final target = (data['targetId'] as String?) ?? '';
                    return _ListRow(
                      title: '${_actionVerb(action)} $target',
                      subtitle: _formatTimestamp(data['createdAt']),
                      onReview: null,
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _actionVerb(String action) {
  switch (action) {
    case 'approve_tour_guide':
      return 'Approved Tour Guide';
    case 'reject_tour_guide':
      return 'Rejected Tour Guide';
    default:
      return action;
  }
}

String _formatTimestamp(Object? value) {
  if (value is! Timestamp) {
    return '';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final date = value.toDate();
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class _TourGuideVerificationPage extends StatelessWidget {
  const _TourGuideVerificationPage();

  @override
  Widget build(BuildContext context) {
    final pendingGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tour Guide Verification', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'I-review ang mga application ng aspiring tour guides',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: pendingGuidesQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: _StreamErrorRow(snap.error)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const Center(
                    child: Text('No pending tour guide applications.', style: TextStyle(color: Colors.black45)),
                  ),
                );
              }
              return Column(
                children: docs
                    .map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _GuideApplicationCard(
                          applicationId: d.id,
                          data: d.data() as Map<String, dynamic>,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.black45, fontSize: 12));
}

class _GuideApplicationCard extends StatefulWidget {
  const _GuideApplicationCard({required this.applicationId, required this.data});

  final String applicationId;
  final Map<String, dynamic> data;

  @override
  State<_GuideApplicationCard> createState() => _GuideApplicationCardState();
}

class _GuideApplicationCardState extends State<_GuideApplicationCard> {
  bool _submitting = false;

  Future<void> _review(String decision) async {
    setState(() => _submitting = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('reviewTourGuideApplication').call({
        'applicationId': widget.applicationId,
        'decision': decision,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decision == 'approve' ? 'Approved.' : 'Rejected.'),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'Failed to submit decision.')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _notWiredUp(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature isn\'t wired up yet.')));
  }

  void _viewDocuments(BuildContext context) {
    final idUrl = widget.data['idImageUrl'] as String?;
    final certUrl = widget.data['certificateImageUrl'] as String?;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ID & Certificate'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Government ID', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (idUrl != null)
                  Image.network(idUrl, fit: BoxFit.contain)
                else
                  const Text('Not provided.', style: TextStyle(color: Colors.black45)),
                const SizedBox(height: 20),
                const Text('Certificate', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (certUrl != null)
                  Image.network(certUrl, fit: BoxFit.contain)
                else
                  const Text('Not provided.', style: TextStyle(color: Colors.black45)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final fullName = (data['fullName'] as String?) ?? widget.applicationId;
    final email = (data['applicantEmail'] as String?) ?? '';
    final contact = (data['contactNumber'] as String?) ?? '—';
    final experience = (data['experienceYears'] as String?) ?? '—';
    final mountains = (data['mountainsHandled'] as String?) ?? '—';
    final submitted = _formatTimestamp(data['submittedAt']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Contact: $contact', style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                    if (email.isNotEmpty)
                      Text(email, style: const TextStyle(color: AdminColors.accent, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Experience'),
          Text('$experience years', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const _FieldLabel('Mountains Handled'),
          Text(mountains, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const _FieldLabel('Submitted'),
          Text(submitted.isEmpty ? '—' : submitted, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _viewDocuments(context),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View Full Profile & ID/Certificates'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : () => _review('approve'),
                  style: FilledButton.styleFrom(backgroundColor: AdminColors.accent),
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : () => _review('reject'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => _notWiredUp('"Request changes"'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                  child: const Text('Request Changes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<LatLng> _decodeRoutePoints(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((point) {
        final lat = (point['lat'] as num?)?.toDouble();
        final lon = (point['lon'] as num?)?.toDouble();
        return (lat != null && lon != null) ? LatLng(lat, lon) : null;
      })
      .whereType<LatLng>()
      .toList();
}

CameraPosition _routeCameraPosition(List<LatLng> points) {
  var minLat = points.first.latitude, maxLat = points.first.latitude;
  var minLon = points.first.longitude, maxLon = points.first.longitude;
  for (final p in points) {
    minLat = p.latitude < minLat ? p.latitude : minLat;
    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
    minLon = p.longitude < minLon ? p.longitude : minLon;
    maxLon = p.longitude > maxLon ? p.longitude : maxLon;
  }
  final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  // Rough zoom heuristic from the route's span — good enough for a
  // preview card; the map is still fully pannable/zoomable/tiltable if a
  // closer look is needed. Tilted by default (45°) per the requested look.
  final spanDegrees = (maxLat - minLat).abs() > (maxLon - minLon).abs()
      ? (maxLat - minLat).abs()
      : (maxLon - minLon).abs();
  final zoom = spanDegrees == 0 ? 15.0 : (14 - (spanDegrees * 100)).clamp(9.0, 15.0);
  return CameraPosition(target: center, zoom: zoom, tilt: 45);
}

class _TrailVerificationPage extends StatelessWidget {
  const _TrailVerificationPage();

  @override
  Widget build(BuildContext context) {
    final pendingTrailsQuery = FirebaseFirestore.instance
        .collection('trail_submissions')
        .where('status', isEqualTo: 'pending');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trail Route Verification', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'I-verify ang GPS route ng mga na-submit na trail',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: pendingTrailsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: _StreamErrorRow(snap.error)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const Center(
                    child: Text('No pending trail submissions.', style: TextStyle(color: Colors.black45)),
                  ),
                );
              }
              return Column(
                children: docs
                    .map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _TrailSubmissionCard(
                          submissionId: d.id,
                          data: d.data() as Map<String, dynamic>,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );
}

class _TrailMapPreview extends StatelessWidget {
  const _TrailMapPreview({required this.points});
  final List<LatLng> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: const Color(0xFFF0F2F1), borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Text('No route points recorded.', style: TextStyle(color: Colors.black45))),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: GoogleMap(
          initialCameraPosition: _routeCameraPosition(points),
          polylines: {
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: AdminColors.accent,
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          },
          markers: {
            Marker(
              markerId: const MarkerId('start'),
              position: points.first,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'Start'),
            ),
            Marker(
              markerId: const MarkerId('end'),
              position: points.last,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'End'),
            ),
          },
          // These four are what make the preview tiltable/rotatable/
          // zoomable by the admin, not just a static picture of the route.
          tiltGesturesEnabled: true,
          rotateGesturesEnabled: true,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }
}

class _TrailSubmissionCard extends StatelessWidget {
  const _TrailSubmissionCard({required this.submissionId, required this.data});

  final String submissionId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = (data['trailName'] as String?) ?? (data['mountainName'] as String?) ?? submissionId;
    final submittedBy = data['submittedBy'] as String?;
    final distance = (data['distanceKm'] as num?)?.toStringAsFixed(1);
    final elevation = (data['elevationGainMasl'] as num?)?.round();
    final points = _decodeRoutePoints(data['routePoints']);
    final submitted = _formatTimestamp(data['createdAt']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (submittedBy != null)
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(submittedBy).get(),
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>?;
                          final name = userData?['fullName'] as String?;
                          return Text(
                            'Submitted by ${name ?? submittedBy}',
                            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                          );
                        },
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TrailMapPreview(points: points),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatColumn(label: 'Distance', value: distance != null ? '$distance km' : '—')),
              Expanded(
                child: _StatColumn(label: 'Elevation Gain', value: elevation != null ? '$elevation m' : '—'),
              ),
              Expanded(child: _StatColumn(label: 'GPS Points', value: '${points.length}')),
              Expanded(child: _StatColumn(label: 'Submitted', value: submitted.isEmpty ? '—' : submitted)),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Route comparison isn\'t wired up yet.'))),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Compare with existing route on this mountain'),
              style: TextButton.styleFrom(foregroundColor: AdminColors.accent, padding: EdgeInsets.zero),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Trail approve/reject isn\'t wired up yet — submissions currently '
                        'auto-publish on upload (see onTrailSubmissionCreated).',
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: AdminColors.accent),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Trail approve/reject isn\'t wired up yet — submissions currently '
                        'auto-publish on upload (see onTrailSubmissionCreated).',
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('"Request changes" isn\'t wired up yet.')),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                  child: const Text('Request Changes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCardData {
  const _StatCardData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.pendingGuides,
    required this.pendingTrails,
    required this.activeRooms,
    required this.approvedGuides,
  });

  final int? pendingGuides;
  final int? pendingTrails;
  final int? activeRooms;
  final int? approvedGuides;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCardData('Pending Guide Apps', pendingGuides?.toString() ?? '—', Icons.person_add_alt_1, Colors.orange),
      _StatCardData(
        'Pending Trail Submissions',
        pendingTrails?.toString() ?? '—',
        Icons.alt_route_rounded,
        Colors.blue,
      ),
      _StatCardData(
        'Active Hike Rooms',
        activeRooms?.toString() ?? '—',
        Icons.terrain_rounded,
        AdminColors.accent,
      ),
      // Not backed by a query yet — SOS status lives per-room in a
      // sos_events subcollection with no aggregate view built so far.
      const _StatCardData('Active SOS Alerts', '—', Icons.warning_amber_rounded, Colors.red),
      // No device-registry collection exists yet (Bluetooth device
      // management hasn't been built).
      const _StatCardData('Registered Devices', '—', Icons.bluetooth, Colors.indigo),
      _StatCardData(
        'Approved / Rejected',
        '${approvedGuides ?? '—'} / —',
        Icons.fact_check_outlined,
        Colors.black87,
      ),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 3.2,
      children: cards.map((c) => _StatCard(data: c)).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.label, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                const SizedBox(height: 8),
                Text(data.value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, required this.subtitle, this.onReview});
  final String title;
  final String subtitle;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          if (onReview != null)
            TextButton(
              onPressed: onReview,
              style: TextButton.styleFrom(foregroundColor: AdminColors.backgroundTop),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('Review'), Icon(Icons.chevron_right, size: 16)],
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(message, style: const TextStyle(color: Colors.black45, fontSize: 13)),
  );
}

// A StreamBuilder that only checks `!snap.hasData` never distinguishes
// "still loading" from "the query failed" — it just spins forever on a
// permission-denied or missing-index error. This surfaces that error
// instead, most commonly a Firestore rules deploy that hasn't happened
// yet (`firebase deploy --only firestore:rules`).
class _StreamErrorRow extends StatelessWidget {
  const _StreamErrorRow(this.error);
  final Object? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text('Failed to load: $error', style: const TextStyle(color: Colors.red, fontSize: 13)),
  );
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Coming soon.', style: TextStyle(color: Colors.black45)),
      ],
    ),
  );
}
