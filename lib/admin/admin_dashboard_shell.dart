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
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFFE5E7E6),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _navItems[_selected].label,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _NotificationBell(
                        onOpenSosMonitoring: () {
                          setState(() => _selected = 4);
                        },
                        onOpenAuditLogs: () {
                          setState(() => _selected = 7);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: switch (_selected) {
                    0 => _DashboardOverviewPage(
                        onNavigate: (index) => setState(() => _selected = index),
                      ),
                    1 => const _TourGuideVerificationPage(),
                    2 => const _TrailVerificationPage(),
                    3 => const _HikeRoomMonitoringPage(),
                    4 => const _SosMonitoringPage(),
                    5 => const _BluetoothDevicesPage(),
                    6 => const _UserManagementPage(),
                    7 => const _AuditLogsPage(),
                    _ => _ComingSoonPage(
                        title: _navItems[_selected].label,
                    ),
                  },
                ),
              ],
            ),
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

class _NotificationBell extends StatefulWidget {
  const _NotificationBell({
    required this.onOpenSosMonitoring,
    required this.onOpenAuditLogs,
  });

  final VoidCallback onOpenSosMonitoring;
  final VoidCallback onOpenAuditLogs;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _recentNotifications() {
    return FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> _openNotifications(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
  ) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final buttonTopLeft = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    final buttonBottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    final position = RelativeRect.fromLTRB(
      buttonTopLeft.dx,
      buttonBottomRight.dy + 4,
      overlay.size.width - buttonBottomRight.dx,
      overlay.size.height - buttonBottomRight.dy - 4,
    );

    await showMenu<void>(
      context: context,
      position: position,
      color: Colors.white,
      elevation: 8,
      constraints: const BoxConstraints(
        minWidth: 360,
        maxWidth: 420,
        maxHeight: 520,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _NotificationPopupContent(
            notifications: notifications,
            onOpenSosMonitoring: widget.onOpenSosMonitoring,
            onOpenAuditLogs: widget.onOpenAuditLogs,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _recentNotifications(),
      builder: (context, recentSnapshot) {
        final notifications = recentSnapshot.data?.docs ?? [];

        final hasUnread = notifications.any(
          (notification) => notification.data()['isRead'] != true,
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {
                _openNotifications(
                  context,
                  notifications,
                );
              },
              icon: const Icon(
                Icons.notifications_outlined,
                size: 25,
              ),
            ),

            // Small unread indicator instead of a number.
            if (hasUnread)
              Positioned(
                right: 7,
                top: 5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotificationPopupContent extends StatefulWidget {
  const _NotificationPopupContent({
    required this.notifications,
    required this.onOpenSosMonitoring,
    required this.onOpenAuditLogs,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications;
  final VoidCallback onOpenSosMonitoring;
  final VoidCallback onOpenAuditLogs;

  @override
  State<_NotificationPopupContent> createState() =>
      _NotificationPopupContentState();
}

class _NotificationPopupContentState
    extends State<_NotificationPopupContent> {
  bool _showUnreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final filteredNotifications = _showUnreadOnly
        ? widget.notifications
            .where(
              (notification) =>
                  notification.data()['isRead'] != true,
            )
            .toList()
        : widget.notifications;

    return SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Notifications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),

          // All / Unread
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showUnreadOnly = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: !_showUnreadOnly
                          ? Colors.blue.shade50
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: !_showUnreadOnly
                            ? Colors.blue
                            : Colors.black54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showUnreadOnly = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _showUnreadOnly
                          ? Colors.blue.shade50
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'Unread',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _showUnreadOnly
                            ? Colors.blue
                            : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 18),

          // Notifications
          if (filteredNotifications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 30,
              ),
              child: Center(
                child: Text(
                  'No notifications.',
                  style: TextStyle(
                    color: Colors.black54,
                  ),
                ),
              ),
            )
          else
              SizedBox(
                height: 400,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: filteredNotifications.map(
                    (notification) {
                      final data = notification.data();
                      final title =
                          data['title']?.toString() ?? 'Notification';
                      final message =
                          data['message']?.toString() ?? '';
                      final isRead =
                          data['isRead'] == true;

                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final notificationRef = FirebaseFirestore.instance
                              .collection('notifications')
                              .doc(notification.id);

                          // Mark only this notification as read.
                          if (!isRead) {
                            await notificationRef.update({
                              'isRead': true,
                            });
                          }

                          if (!context.mounted) return;

                          Navigator.of(context).pop();

                          // SOS notifications open the SOS Monitoring page.
                          if (data['type']?.toString() == 'sos') {
                            widget.onOpenSosMonitoring();
                          } else if (data['type']?.toString() ==
                                  'trail_submission' ||
                              data['type']?.toString() == 'admin_action') {
                            widget.onOpenAuditLogs();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isRead
                                ? Colors.transparent
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isRead
                                    ? Icons.notifications_none
                                    : Icons.notifications_active,
                                color: isRead
                                    ? Colors.black45
                                    : Colors.blue,
                                size: 21,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isRead
                                            ? FontWeight.w500
                                            : FontWeight.w800,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if (message.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Unread identifier
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(
                                    left: 8,
                                    top: 5,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),
        ],
      ),
    );
  }
}

class _DashboardOverviewPage extends StatelessWidget {
  const _DashboardOverviewPage({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final pendingGuidesQuery = FirebaseFirestore.instance
        .collection('users')
        .where('accountType', isEqualTo: 'tour_guide')
        .where('guideVerified', isEqualTo: false);
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
    final activeSosQuery = FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .where('status', isEqualTo: 'sent');
    final devicesQuery = FirebaseFirestore.instance.collection('bluetooth_devices');
    final approvedActionsQuery = FirebaseFirestore.instance
        .collection('admin_actions')
        .where('action', isEqualTo: 'approve_tour_guide');
    final rejectedActionsQuery = FirebaseFirestore.instance
        .collection('admin_actions')
        .where('action', isEqualTo: 'reject_tour_guide');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dashboard Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Summary of activity on the Agakbay platform', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: pendingGuidesQuery.snapshots(),
            builder: (context, guideSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: pendingTrailsQuery.snapshots(),
                builder: (context, trailSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: activeRoomsQuery.snapshots(),
                    builder: (context, roomSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: activeSosQuery.snapshots(),
                            builder: (context, sosSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: devicesQuery.snapshots(),
                              builder: (context, deviceSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: approvedActionsQuery.snapshots(),
                                builder: (context, approvedActionsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: rejectedActionsQuery.snapshots(),
                                  builder: (context, rejectedActionsSnap) => _StatGrid(
                                    pendingGuides: guideSnap.data?.docs.length,
                                    pendingTrails: trailSnap.data?.docs.length,
                                    activeRooms: roomSnap.data?.docs.length,
                                    activeSos: sosSnap.data?.docs.length,
                                    registeredDevices: deviceSnap.data?.docs.length,
                                    approvedGuides: approvedActionsSnap.data?.docs.length,
                                    rejectedGuides: rejectedActionsSnap.data?.docs.length,
                                    onNavigate: onNavigate,
                                  ),
                                ),
                              ),
                            ),
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
                      title: (data['fullName'] as String?) ?? (data['email'] as String?) ?? d.id,
                      subtitle: (data['email'] as String?) ?? '',
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
                      onReview: () => onNavigate(2),
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
    case 'create_admin':
      return 'Created Admin Account';
    case 'approve_tour_guide':
      return 'Approved Tour Guide';
    case 'reject_tour_guide':
      return 'Rejected Tour Guide';
    case 'revoke_admin':
      return 'Revoked Admin Access';
    case 'suspend':
      return 'Suspended Account';
    case 'restore':
      return 'Restored Account';
    case 'delete_user_account':
      return 'Deleted Account';
    case 'connected':
      return 'Connected';
    case 'disconnected':
      return 'Disconnected';
    case 'device_changed':
      return 'Device Updated';
    case 'rename_bluetooth_device':
      return 'Renamed Bluetooth Device';
    case 'submit_trail_route':
      return 'Submitted Trail Route';
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

void _showGuideReviewDialog(
  BuildContext context, {
  required String uid,
  required Map<String, dynamic> data,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Review Tour Guide Application'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: _GuideApplicationCard(
            uid: uid,
            data: data,
            onReviewed: () => Navigator.of(dialogContext).pop(),
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
  const _GuideApplicationCard({required this.uid, required this.data});

  final String applicationId;
  final Map<String, dynamic> data;
  final VoidCallback? onReviewed;

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
        widget.onReviewed?.call();
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
  // closer look is needed. Tilted by default (45Â°) per the requested look.
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
  const _StatCardData(this.label, this.value, this.icon, this.color, this.destination);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final int destination;
}
class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.pendingGuides,
    required this.pendingTrails,
    required this.activeRooms,
    required this.activeSos,
    required this.registeredDevices,
    required this.approvedGuides,
    required this.rejectedGuides,
    required this.onNavigate,
  });

  final int? pendingGuides;
  final int? pendingTrails;
  final int? activeRooms;
  final int? activeSos;
  final int? registeredDevices;
  final int? approvedGuides;
  final int? rejectedGuides;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCardData('Pending Guide Apps', pendingGuides?.toString() ?? '-', Icons.person_add_alt_1, Colors.orange, 1),
      _StatCardData('Pending Trail Submissions', pendingTrails?.toString() ?? '-', Icons.alt_route_rounded, Colors.blue, 2),
      _StatCardData('Active Hike Rooms', activeRooms?.toString() ?? '-', Icons.terrain_rounded, AdminColors.accent, 3),
      _StatCardData('Active SOS Alerts', activeSos?.toString() ?? '-', Icons.warning_amber_rounded, Colors.red, 4),
      _StatCardData('Registered Devices', registeredDevices?.toString() ?? '-', Icons.bluetooth, Colors.indigo, 5),
      _StatCardData('Approved / Rejected', '${approvedGuides ?? '-'} / ${rejectedGuides ?? '-'}', Icons.fact_check_outlined, Colors.black87, 7),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 3.2,
      children: cards.map((card) => _StatCard(
        data: card,
        onTap: () => onNavigate(card.destination),
      )).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data, required this.onTap});
  final _StatCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
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
        ),
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

class _HikeRoomMonitoringPage extends StatelessWidget {
  const _HikeRoomMonitoringPage();

  @override
  Widget build(BuildContext context) {
    final activeRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hike Room Monitoring',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Monitor active hiking rooms and their participants',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: activeRoomsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _StreamErrorRow(snap.error);
              }

              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final rooms = snap.data!.docs;

              if (rooms.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No active hike rooms.',
                      style: TextStyle(color: Colors.black45),
                    ),
                  ),
                );
              }

              return Column(
                children: rooms.map((room) {
                  final data =
                      room.data() as Map<String, dynamic>;

                  return _HikeRoomCard(
                    roomId: room.id,
                    data: data,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HikeRoomCard extends StatelessWidget {
  const _HikeRoomCard({
    required this.roomId,
    required this.data,
  });

  final String roomId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final roomCode =
        data['roomCode'] as String? ?? roomId;

    final mountainName =
        data['mountainName'] as String? ?? '—';

    final guideName =
        data['guideName'] as String? ?? '—';

    final routeName =
        data['routeName'] as String? ?? '—';

    final status =
        data['status'] as String? ?? '—';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============================================================
          // ROOM HEADER
          // ============================================================
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mountainName,
                      style: const TextStyle(
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AdminColors.accent
                      .withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    color: AdminColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ============================================================
          // GUIDE / ROUTE
          // ============================================================
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Guide',
                  value: guideName,
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'Route',
                  value: routeName,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ============================================================
          // PARTICIPANTS
          // ============================================================
          const Text(
            'Participants',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),

          const SizedBox(height: 10),

          _RoomParticipants(
            roomId: roomId,
          ),
        ],
      ),
    );
  }
}

String _formatLastLocation(dynamic value) {
  if (value is Timestamp) {
    final dateTime = value.toDate();
    final difference = DateTime.now().difference(dateTime);

    if (difference.inSeconds < 10) {
      return 'Updated just now';
    }

    if (difference.inMinutes < 1) {
      return 'Updated ${difference.inSeconds}s ago';
    }

    if (difference.inHours < 1) {
      return 'Updated ${difference.inMinutes}m ago';
    }

    if (difference.inDays < 1) {
      return 'Updated ${difference.inHours}h ago';
    }

    return 'Updated ${difference.inDays}d ago';
  }

  return 'Location update time unavailable';
}
// ======================================================================
// ROOM PARTICIPANTS
// ======================================================================

class _RoomParticipants extends StatelessWidget {
  const _RoomParticipants({
    required this.roomId,
  });

  final String roomId;

  bool _isOffline(
    String deviceStatus,
    String activityStatus,
  ) {
    final device =
        deviceStatus.toLowerCase().trim();

    final activity =
        activityStatus.toLowerCase().trim();

    return device == 'offline' ||
        device == 'disconnected' ||
        device == 'not_connected' ||
        activity == 'offline';
  }

  @override
  Widget build(BuildContext context) {
    final participantsQuery =
        FirebaseFirestore.instance
            .collection('hike_rooms')
            .doc(roomId)
            .collection('participants');

    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: participantsQuery.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _StreamErrorRow(snap.error);
        }

        if (!snap.hasData) {
          return const LinearProgressIndicator();
        }

        final participants =
            snap.data!.docs.where((participant) {
          final data = participant.data();

          return (data['membershipStatus']
                      ?.toString() ??
                  'active') ==
              'active';
        }).toList();

        if (participants.isEmpty) {
          return const Text(
            'No active participants in this room.',
            style: TextStyle(
              color: Colors.black45,
            ),
          );
        }

        final connectedCount = participants.where((participant) {
          final data = participant.data();
          return data['deviceStatus']?.toString() == 'connected';
        }).length;

        final disconnectedCount = participants.where((participant) {
          final data = participant.data();
          return data['deviceStatus']?.toString() == 'disconnected';
        }).length;

        final noDeviceCount =
            participants.length - connectedCount - disconnectedCount;


        // ==============================================================
        // CREATE MAP MARKERS
        // ==============================================================

        final Set<Marker> participantMarkers =
            {};

        final List<
            Map<String, dynamic>> participantsWithLocation =
            [];

        for (final participant in participants) {
          final data = participant.data();

          final name =
              data['name']?.toString() ??
                  participant.id;

          final role =
              data['role']?.toString() ?? '—';

          final activityStatus =
              data['activityStatus']
                      ?.toString() ??
                  '—';

          final deviceStatus =
              data['deviceStatus']
                      ?.toString() ??
                  '—';

          final latitude =
              (data['latitude'] as num?)
                  ?.toDouble();

          final longitude =
              (data['longitude'] as num?)
                  ?.toDouble();

          final lastLocationAt =
              data['lastLocationAt'];

          final isOffline = _isOffline(
            deviceStatus,
            activityStatus,
          );

          if (latitude != null &&
              longitude != null) {
            participantsWithLocation.add({
              'id': participant.id,
              'name': name,
              'role': role,
              'activityStatus':
                  activityStatus,
              'deviceStatus':
                  deviceStatus,
              'latitude': latitude,
              'longitude': longitude,
              'lastLocationAt':
                  lastLocationAt,
              'isOffline': isOffline,
            });

            participantMarkers.add(
              Marker(
                markerId:
                    MarkerId(participant.id),
                position: LatLng(
                  latitude,
                  longitude,
                ),
                infoWindow: InfoWindow(
                  title: name,
                  snippet: isOffline
                      ? 'Last known location'
                      : 'Current location',
                ),
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(
                    Icons.people,
                    size: 18,
                  ),
                  label: Text(
                    '${participants.length} participants',
                  ),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.bluetooth_connected,
                    size: 18,
                  ),
                  label: Text(
                    '$connectedCount Connected',
                  ),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.bluetooth_disabled,
                    size: 18,
                  ),
                  label: Text(
                    '$disconnectedCount Disconnected',
                  ),
                ),
                if (noDeviceCount > 0)
                  Chip(
                    avatar: const Icon(
                      Icons.bluetooth,
                      size: 18,
                    ),
                    label: Text(
                      '$noDeviceCount No device',
                    ),
                  ),
              ],
            ),

            // ==============================================================
            // PARTICIPANT LOCATION MAP
            // ==============================================================
            if (participantsWithLocation.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ParticipantLocationMap(
                participants: participantsWithLocation,
                markers: participantMarkers,
              ),
            ],

            const SizedBox(height: 14),

            ...participants.map((participant) {
              final data = participant.data();

              final name =
                  data['name']?.toString() ?? 'Unknown hiker';

              final deviceStatus =
                  data['deviceStatus']?.toString() ?? 'unknown';

              final deviceName =
                  data['deviceName']?.toString() ??
                      'No device connected';

              final lastBluetoothAt =
                  data['lastBluetoothAt'];

              return _BluetoothParticipantTile(
                deviceId: data['deviceId']?.toString(),
                name: name,
                deviceStatus: deviceStatus,
                deviceName: deviceName,
                lastBluetoothAt: lastBluetoothAt,
                lastLocationText: _formatLastLocation(
                  data['lastLocationAt'],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}


// ======================================================================
// PARTICIPANT LOCATION MAP
// ======================================================================

class _ParticipantLocationMap
    extends StatelessWidget {
  const _ParticipantLocationMap({
    required this.participants,
    required this.markers,
  });

  final List<Map<String, dynamic>>
      participants;

  final Set<Marker> markers;

  LatLng _initialPosition() {
    if (participants.isNotEmpty) {
      final first =
          participants.first;

      final latitude =
          first['latitude'] as double;

      final longitude =
          first['longitude'] as double;

      return LatLng(
        latitude,
        longitude,
      );
    }

    // Fallback location.
    // The map will normally use the first
    // participant's actual GPS coordinates.
    return const LatLng(
      7.0731,
      125.6128,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black12,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(
              target: _initialPosition(),
              zoom: 14,
            ),

            markers: markers,

            zoomControlsEnabled: true,

            myLocationButtonEnabled:
                false,

            mapToolbarEnabled:
                false,

            compassEnabled:
                true,

            zoomGesturesEnabled:
                true,

            scrollGesturesEnabled:
                true,

            rotateGesturesEnabled:
                true,

            tiltGesturesEnabled:
                false,
          ),

          // ============================================================
          // MAP LABEL
          // ============================================================

          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(
                  8,
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 6,
                    color: Colors.black12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                    Icons
                        .location_on_rounded,
                    size: 17,
                    color:
                        AdminColors.accent,
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  Text(
                    '${markers.length} '
                    '${markers.length == 1 ? 'participant' : 'participants'} '
                    'with location',
                    style:
                        const TextStyle(
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SosMonitoringPage extends StatelessWidget {
  const _SosMonitoringPage();

  Stream<QuerySnapshot<Map<String, dynamic>>> _activeRoomsStream() {
    return FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sosStream(
    String roomId,
  ) {
    return FirebaseFirestore.instance
        .collection('hike_rooms')
        .doc(roomId)
        .collection('sos_events')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeRoomsStream(),
      builder: (context, roomSnapshot) {
        if (roomSnapshot.hasError) {
          return _SosPageMessage(
            icon: Icons.error_outline_rounded,
            message: 'Failed to load active hike rooms.',
            detail: roomSnapshot.error.toString(),
          );
        }

        if (!roomSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final rooms = roomSnapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(
              'SOS Monitoring',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Monitor SOS alerts from active hike rooms.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),

            if (rooms.isEmpty)
              const _SosPageMessage(
                icon: Icons.check_circle_outline_rounded,
                message: 'No active hike rooms.',
                detail: 'SOS alerts will appear here when a hike session is active.',
              )
            else
              ...rooms.map(
                (room) => _SosRoomAlerts(
                  roomId: room.id,
                  roomData: room.data(),
                  sosStream: _sosStream(room.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SosRoomAlerts extends StatelessWidget {
  const _SosRoomAlerts({
    required this.roomId,
    required this.roomData,
    required this.sosStream,
  });

  final String roomId;
  final Map<String, dynamic> roomData;
  final Stream<QuerySnapshot<Map<String, dynamic>>> sosStream;

  @override
  Widget build(BuildContext context) {
    final mountainName =
        roomData['mountainName']?.toString() ?? 'Unnamed hike';

    final roomCode =
        roomData['roomCode']?.toString() ?? roomId;

    final guideName =
        roomData['guideName']?.toString() ?? 'Tour Guide';

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.terrain_rounded,
                  color: AdminColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mountainName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  label: Text('Room $roomCode'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tour Guide: $guideName',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: sosStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _SosPageMessage(
                    icon: Icons.error_outline_rounded,
                    message: 'Unable to load SOS events.',
                    detail: snapshot.error.toString(),
                  );
                }

                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }

                final events = snapshot.data!.docs;

                if (events.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No SOS events recorded for this room.',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }

                final sosPoints = events
                    .map((event) {
                      final data = event.data();
                      final latitude = (data['latitude'] as num?)?.toDouble();
                      final longitude = (data['longitude'] as num?)?.toDouble();

                      if (latitude == null || longitude == null) {
                        return null;
                      }

                      return _SosMapPoint(
                        eventId: event.id,
                        senderName: data['senderName']?.toString() ?? 'Unknown hiker',
                        latitude: latitude,
                        longitude: longitude,
                      );
                    })
                    .whereType<_SosMapPoint>()
                    .toList(growable: false);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sosPoints.isNotEmpty) ...[
                      _SosRoomMap(points: sosPoints),
                      const SizedBox(height: 16),
                    ],
                    ...events.map((event) {
                      return _SosAlertCard(
                        roomId: roomId,
                        eventId: event.id,
                        eventData: event.data(),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SosMapPoint {
  const _SosMapPoint({
    required this.eventId,
    required this.senderName,
    required this.latitude,
    required this.longitude,
  });

  final String eventId;
  final String senderName;
  final double latitude;
  final double longitude;
}

class _SosRoomMap extends StatelessWidget {
  const _SosRoomMap({
    required this.points,
  });

  final List<_SosMapPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstPoint = points.first;

    final markers = points.map((point) {
      return Marker(
        markerId: MarkerId(point.eventId),
        position: LatLng(
          point.latitude,
          point.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(
          title: 'SOS: ${point.senderName}',
          snippet:
              '${point.latitude.toStringAsFixed(6)}, '
              '${point.longitude.toStringAsFixed(6)}',
        ),
      );
    }).toSet();

    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(
            firstPoint.latitude,
            firstPoint.longitude,
          ),
          zoom: 14,
        ),
        markers: markers,
        tiltGesturesEnabled: true,
        rotateGesturesEnabled: true,
        zoomGesturesEnabled: true,
        scrollGesturesEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
      ),
    );
  }
}

class _SosAlertCard extends StatelessWidget {
  const _SosAlertCard({
    required this.roomId,
    required this.eventId,
    required this.eventData,
  });

  final String roomId;
  final String eventId;
  final Map<String, dynamic> eventData;

  @override
  Widget build(BuildContext context) {
    final senderName =
        eventData['senderName']?.toString().trim().isNotEmpty == true
            ? eventData['senderName'].toString()
            : 'Unknown hiker';

    final status = eventData['status']?.toString() ?? 'sent';

    final latitude = (eventData['latitude'] as num?)?.toDouble();
    final longitude = (eventData['longitude'] as num?)?.toDouble();

    final createdAt = eventData['createdAt'];
    final DateTime? createdTime =
        createdAt is Timestamp ? createdAt.toDate() : null;

    final acknowledged = status == 'acknowledged';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  acknowledged
                      ? Icons.check_circle_rounded
                      : Icons.sos_rounded,
                  color: acknowledged
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SOS from $senderName',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: acknowledged
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    acknowledged ? 'ACKNOWLEDGED' : 'PENDING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: acknowledged
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (latitude != null && longitude != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${latitude.toStringAsFixed(6)}, '
                      '${longitude.toStringAsFixed(6)}',
                    ),
                  ),
                ],
              )
            else
              const Row(
                children: [
                  Icon(Icons.location_off_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Location unavailable'),
                ],
              ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  createdTime != null
                      ? _formatSosTime(createdTime)
                      : 'Time unavailable',
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Room: $roomId',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 4),

            Text(
              'SOS ID: $eventId',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}


String _formatSosTime(DateTime time) {
  final local = time.toLocal();

  String twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

class _SosPageMessage extends StatelessWidget {
  const _SosPageMessage({
    required this.icon,
    required this.message,
    required this.detail,
  });

  final IconData icon;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.black54,
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

class _BluetoothDevicesPage extends StatelessWidget {
  const _BluetoothDevicesPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          'Bluetooth Devices',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Registered Heltec devices, current assignment, and connectivity history.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('bluetooth_devices')
              .orderBy('updatedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _StreamErrorRow(snapshot.error);
            }
            if (!snapshot.hasData) return const _LoadingRow();
            final devices = snapshot.data!.docs;
            if (devices.isEmpty) {
              return const _EmptyRow(
                'Devices will appear after they connect to the app for the first time.',
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 26,
                  columns: const [
                    DataColumn(label: Text('Device name')),
                    DataColumn(label: Text('Hardware ID')),
                    DataColumn(label: Text('Assignment')),
                    DataColumn(label: Text('Connection')),
                    DataColumn(label: Text('Last seen')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: devices.map((device) {
                    final data = device.data();
                    final deviceId = data['deviceId']?.toString() ?? '';
                    final name = data['displayName']?.toString().trim().isNotEmpty == true
                        ? data['displayName'].toString().trim()
                        : (data['deviceName']?.toString() ?? 'Heltec device');
                    final lastActivity = data['lastActivityAt'];
                    final activityDate = lastActivity is Timestamp
                        ? lastActivity.toDate()
                        : null;
                    final recent = activityDate != null &&
                        DateTime.now().difference(activityDate).inMinutes < 5;
                    final connected = data['lastStatus'] == 'connected' && recent;
                    final connection = connected
                        ? 'Connected'
                        : data['lastStatus'] == 'connected'
                            ? 'Last connected (stale)'
                            : data['lastStatus'] == 'disconnected'
                                ? 'Disconnected'
                                : 'Unknown';
                    return DataRow(cells: [
                      DataCell(Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(SelectableText(deviceId.isEmpty ? 'Unavailable' : deviceId)),
                      DataCell(_BluetoothDeviceAssignmentCell(
                        roomId: data['lastRoomId']?.toString(),
                        participantId: data['lastParticipantId']?.toString(),
                        roomCode: data['lastRoomCode']?.toString(),
                        deviceId: deviceId,
                      )),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                            size: 18, color: connected ? Colors.green : Colors.grey),
                        const SizedBox(width: 6),
                        Text(connection),
                      ])),
                      DataCell(Text(_formatBluetoothTimestamp(lastActivity))),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton.icon(
                          onPressed: () => _showBluetoothConnectivityHistory(
                            context, deviceId: deviceId, deviceName: name),
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('History'),
                        ),
                        TextButton.icon(
                          onPressed: () => _renameBluetoothDevice(
                            context, deviceId: deviceId, deviceData: data),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Rename'),
                        ),
                      ])),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BluetoothDeviceAssignmentCell extends StatelessWidget {
  const _BluetoothDeviceAssignmentCell({
    required this.roomId,
    required this.participantId,
    required this.roomCode,
    required this.deviceId,
  });

  final String? roomId;
  final String? participantId;
  final String? roomCode;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    if (roomId == null || roomId!.isEmpty ||
        participantId == null || participantId!.isEmpty) {
      return const Text('Available');
    }
    final roomRef = FirebaseFirestore.instance.collection('hike_rooms').doc(roomId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, roomSnapshot) {
        if (!roomSnapshot.hasData || roomSnapshot.data?.data()?['status'] != 'active') {
          return const Text('Available');
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: roomRef.collection('participants').doc(participantId).snapshots(),
          builder: (context, participantSnapshot) {
            final participant = participantSnapshot.data?.data();
            final occupied = participantSnapshot.hasData &&
                participantSnapshot.data!.exists &&
                participant?['membershipStatus'] == 'active' &&
                participant?['deviceId']?.toString() == deviceId;
            return Text(occupied ? 'Occupied Â· Room ${roomCode ?? roomId}' : 'Available');
          },
        );
      },
    );
  }
}

String _bluetoothDeviceKey(String id) =>
    base64Url.encode(utf8.encode(id)).replaceAll('=', '');

String _formatBluetoothTimestamp(dynamic value) {
  if (value is! Timestamp) return 'Unknown time';
  final date = value.toDate();
  return '${date.month}/${date.day}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')}';
}

void _showBluetoothConnectivityHistory(
  BuildContext context, {
  required String deviceId,
  required String deviceName,
}) {
  if (deviceId.isEmpty) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deviceName),
        content: const Text(
          'Connectivity history will be available after this device reconnects and reports its hardware ID.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }

  final query = FirebaseFirestore.instance
      .collection('bluetooth_devices')
      .doc(_bluetoothDeviceKey(deviceId))
      .collection('activity')
      .orderBy('occurredAt', descending: true);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$deviceName Connectivity History'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID: $deviceId', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: query.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Unable to load history: ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final events = snapshot.data!.docs;
                  if (events.isEmpty) {
                    return const Center(
                      child: Text('No connectivity history recorded yet.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = events[index].data();
                      final status = event['deviceStatus']?.toString() ??
                          event['eventType']?.toString() ?? 'Activity';
                      final connected = status == 'connected';
                      final room = event['roomCode']?.toString() ??
                          event['roomId']?.toString() ?? 'Unknown';
                      final participant =
                          event['participantName']?.toString() ?? 'Unknown participant';
                      return ListTile(
                        leading: Icon(
                          connected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: connected ? Colors.green : Colors.grey,
                        ),
                        title: Text(_actionVerb(status)),
                        subtitle: Text('$participant Â· Room $room'),
                        trailing: Text(
                          _formatBluetoothTimestamp(event['occurredAt']),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _renameBluetoothDevice(
  BuildContext context, {
  required String deviceId,
  required Map<String, dynamic> deviceData,
}) async {
  final controller = TextEditingController(
    text: deviceData['displayName']?.toString() ??
        deviceData['deviceName']?.toString() ?? '',
  );
  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Set Device Name'),
      content: TextField(
        controller: controller,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (newName == null || newName.isEmpty || !context.mounted) return;
  try {
    await FirebaseFunctions.instance.httpsCallable('renameBluetoothDevice').call({
      'deviceId': deviceId,
      'displayName': newName,
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device name updated.')),
    );
  } on FirebaseFunctionsException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.message ?? 'Could not rename device.')),
    );
  }
}

class _BluetoothParticipantTile extends StatelessWidget {
  const _BluetoothParticipantTile({
    required this.deviceId,
    required this.name,
    required this.deviceStatus,
    required this.deviceName,
    required this.lastBluetoothAt,
    required this.lastLocationText,
  });

  final String? deviceId;
  final String name;
  final String deviceStatus;
  final String deviceName;
  final dynamic lastBluetoothAt;
  final String lastLocationText;

  String _formatBluetoothTime(dynamic value) {
    if (value is Timestamp) {
      final dateTime = value.toDate();

      return '${dateTime.month}/${dateTime.day}/${dateTime.year} '
          '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}';
    }

    return 'Unknown';
  }

  bool _isBluetoothStatusStale(dynamic value) {
    if (value is! Timestamp) {
      return true;
    }

    final lastUpdate = value.toDate();
    final difference = DateTime.now().difference(lastUpdate);

    return difference.inMinutes >= 5;
  }

  void _showConnectivityHistory(BuildContext context) {
    _showBluetoothConnectivityHistory(
      context,
      deviceId: deviceId ?? '',
      deviceName: deviceName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = deviceStatus == 'connected';
    final disconnected = deviceStatus == 'disconnected';
    final statusStale = _isBluetoothStatusStale(lastBluetoothAt);

    return InkWell(
      onTap: () => _showConnectivityHistory(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.black12,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
        children: [
          Icon(
            connected
                ? Icons.bluetooth_connected
                : disconnected
                    ? Icons.bluetooth_disabled
                    : Icons.bluetooth,
            color: connected
                ? Colors.green
                : disconnected
                    ? Colors.grey
                    : Colors.orange,
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deviceName,
                  style: const TextStyle(
                    color: Colors.black54,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showConnectivityHistory(context),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Connectivity history'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lastBluetoothAt == null
                      ? 'Last update: No data'
                      : 'Last update: ${_formatBluetoothTime(lastBluetoothAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
                const SizedBox(height: 4),
                const SizedBox(height: 4),
                Text(
                  'Location: $lastLocationText',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          Chip(
            label: Text(
              connected && !statusStale
                  ? 'Connected'
                  : connected && statusStale
                      ? 'Status may be stale'
                      : disconnected
                          ? 'Disconnected'
                          : 'No device',
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _UserManagementPage extends StatefulWidget {
  const _UserManagementPage();

  @override
  State<_UserManagementPage> createState() =>
      _UserManagementPageState();
}

class _UserManagementPageState extends State<_UserManagementPage> {
  final TextEditingController _searchController =
      TextEditingController();
  String _accountTypeFilter = 'all';

  String _effectiveAccountType(Map<String, dynamic> data) {
    if (data['adminAccess'] == true ||
        data['role'] == 'admin' ||
        data['accountType'] == 'admin') {
      return 'admin';
    }
    final accountType = data['accountType']?.toString();
    return accountType == 'tour_guide' ? 'tour_guide' : 'hiker';
  }

  String _userDisplayName(Map<String, dynamic> data) {
    for (final key in const ['fullName', 'displayName', 'name']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'Unnamed User';
  }

  void _showCreateAdminDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _CreateAdminAccountDialog(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersQuery = FirebaseFirestore.instance
        .collection('users')
        .orderBy('email');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'View and manage AGAKBAY user and admin accounts.',
            style: TextStyle(
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 20),

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _showCreateAdminDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Admin Account'),
            ),
          ),
          const SizedBox(height: 12),

            TextField(
              controller: _searchController,
              onChanged: (_) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _accountTypeFilter,
                decoration: const InputDecoration(
                  labelText: 'Filter by account type',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All account types')),
                  DropdownMenuItem(value: 'hiker', child: Text('Hiker')),
                  DropdownMenuItem(value: 'tour_guide', child: Text('Tour Guide')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _accountTypeFilter = value);
                  }
                },
              ),
            ),

            const SizedBox(height: 16),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: usersQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: _StreamErrorRow(snapshot.error),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final searchText = _searchController.text.trim().toLowerCase();

              final users = snapshot.data!.docs.where((user) {
                final data = user.data();

                final email = data['email']?.toString().toLowerCase() ?? '';

                final displayName = _userDisplayName(data).toLowerCase();
                final accountType = _effectiveAccountType(data);

                final matchesSearch = email.contains(searchText) ||
                    displayName.contains(searchText);
                final matchesType = _accountTypeFilter == 'all' ||
                    accountType == _accountTypeFilter;
                return matchesSearch && matchesType;
              }).toList();

              if (users.isEmpty) {
                final hasSearch = _searchController.text.trim().isNotEmpty;
                final emptyMessage = hasSearch
                    ? 'No users match your search and account type filter.'
                    : _accountTypeFilter == 'all'
                        ? 'No user accounts found.'
                        : 'No ${_accountTypeFilter == 'tour_guide' ? 'tour guide' : _accountTypeFilter} accounts found.';

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      emptyMessage,
                      style: const TextStyle(
                        color: Colors.black45,
                      ),
                    ),
                  ),
                );
              }

              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('User')),
                      DataColumn(label: Text('Account Type')),
                      DataColumn(label: Text('Email Status')),
                      DataColumn(label: Text('Guide Status')),
                      DataColumn(label: Text('Joined')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: users.map((user) {
                      final data = user.data();

                      final email =
                          data['email']?.toString() ?? 'No email';

                      final displayName = _userDisplayName(data);

                      final accountType = _effectiveAccountType(data);

                      final guideVerified =
                          data['guideVerified'] == true;

                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              accountType == 'tour_guide'
                                  ? 'Tour Guide'
                                  : accountType == 'admin'
                                      ? 'Admin'
                                      : 'Hiker',
                            ),
                          ),
                          DataCell(
                            Text(
                              data['emailVerified'] == true
                                  ? 'Verified'
                                  : 'Not Verified',
                              style: TextStyle(
                                color: data['emailVerified'] == true
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            accountType == 'tour_guide'
                                ? Text(
                                    guideVerified
                                        ? 'Verified'
                                        : 'Pending',
                                    style: TextStyle(
                                      color: guideVerified
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : const Text(
                                    'N/A',
                                    style: TextStyle(
                                      color: Colors.black45,
                                    ),
                                  ),
                          ),
                          DataCell(
                            Text(
                              data['createdAt'] != null
                                  ? _formatUserDate(data['createdAt'])
                                  : 'Unknown',
                              style: const TextStyle(
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              tooltip: 'View user details',
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: () {
                                _showUserDetails(context, data, user.id);
                              },
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  String _formatUserDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();

      return '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return 'Unknown';
  }

  Future<void> _manageUserAccount(
    BuildContext dialogContext,
    String userId,
    String action,
  ) async {
    final descriptions = <String, String>{
      'revoke_admin': 'Remove this user\'s admin access?',
      'suspend': 'Suspend this account? They will be signed out and unable to sign in.',
      'restore': 'Restore this account\'s access?',
      'delete': 'Permanently delete this sign-in account and its user profile? Authored activity records may remain.',
    };
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Confirm account change'),
        content: Text(descriptions[action]!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('manageUserAccount').call({
        'uid': userId,
        'action': action,
      });
      if (!mounted || !dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account updated: ${descriptions[action]}')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not update this account.')),
      );
    }
  }

  void _showUserDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String userId,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final fullName = _userDisplayName(data);

        final username =
            data['username']?.toString() ?? 'Not provided';

        final email =
            data['email']?.toString() ?? 'Not provided';

        final accountType =
            data['accountType']?.toString() ?? 'Not provided';

        final role =
            data['role']?.toString() ?? 'Not provided';

        final emailVerified =
            data['emailVerified'] == true;

        final accountConfirmed =
            data['accountTypeConfirmed'] == true;

        final guideVerified =
            data['guideVerified'] == true;

        final onboardingComplete =
            data['onboardingComplete'] == true;

        final skillLevel =
            data['skillLevel']?.toString() ?? 'Not provided';

        final verificationMethod =
            data['verificationMethod']?.toString() ?? 'Not provided';

        final activeHikeRoomId =
            data['activeHikeRoomId']?.toString();
        final hasAdminAccess = data['adminAccess'] == true ||
            data['role'] == 'admin' || data['accountType'] == 'admin';
        final isSuspended = data['accountSuspended'] == true;

        return AlertDialog(
          title: const Text('User Details'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserDetailRow(
                    label: 'Full Name',
                    value: fullName,
                  ),
                  _UserDetailRow(
                    label: 'Username',
                    value: username,
                  ),
                  _UserDetailRow(
                    label: 'Email',
                    value: email,
                  ),
                  _UserDetailRow(
                    label: 'Account Type',
                    value: accountType,
                  ),
                  _UserDetailRow(
                    label: 'Admin Access',
                    value: hasAdminAccess ? 'Granted' : 'Not granted',
                  ),
                  _UserDetailRow(
                    label: 'Account Status',
                    value: isSuspended ? 'Suspended' : 'Active',
                  ),
                  _UserDetailRow(
                    label: 'Role',
                    value: role,
                  ),
                  _UserDetailRow(
                    label: 'Email Verified',
                    value: emailVerified
                        ? 'Verified'
                        : 'Not Verified',
                  ),
                  _UserDetailRow(
                    label: 'Account Confirmed',
                    value: accountConfirmed
                        ? 'Confirmed'
                        : 'Not Confirmed',
                  ),
                  _UserDetailRow(
                    label: 'Guide Verified',
                    value: guideVerified
                        ? 'Verified'
                        : 'Not Verified',
                  ),
                  _UserDetailRow(
                    label: 'Onboarding',
                    value: onboardingComplete
                        ? 'Complete'
                        : 'Incomplete',
                  ),
                  _UserDetailRow(
                    label: 'Skill Level',
                    value: skillLevel,
                  ),
                  _UserDetailRow(
                    label: 'Verification Method',
                    value: verificationMethod,
                  ),
                  _UserDetailRow(
                    label: 'Joined',
                    value: data['createdAt'] != null
                        ? _formatUserDate(data['createdAt'])
                        : 'Unknown',
                  ),
                  _UserDetailRow(
                    label: 'User ID',
                    value: userId,
                  ),
                  _UserDetailRow(
                    label: 'Active Hike Room',
                    value: activeHikeRoomId != null &&
                            activeHikeRoomId.isNotEmpty
                        ? activeHikeRoomId
                        : 'None',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (hasAdminAccess)
              TextButton.icon(
                onPressed: () => _manageUserAccount(
                  dialogContext,
                  userId,
                  'revoke_admin',
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Revoke Admin'),
              ),
            TextButton.icon(
              onPressed: () => _manageUserAccount(
                dialogContext,
                userId,
                isSuspended ? 'restore' : 'suspend',
              ),
              icon: Icon(isSuspended ? Icons.lock_open_outlined : Icons.block),
              label: Text(isSuspended ? 'Restore Account' : 'Suspend Account'),
            ),
            TextButton.icon(
              onPressed: () => _manageUserAccount(
                dialogContext,
                userId,
                'delete',
              ),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete Account', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _CreateAdminAccountDialog extends StatefulWidget {
  const _CreateAdminAccountDialog();

  @override
  State<_CreateAdminAccountDialog> createState() =>
      _CreateAdminAccountDialogState();
}

class _CreateAdminAccountDialogState extends State<_CreateAdminAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _creating = false;
  String? _error;
  String? _resetLink;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createAdminAccount')
          .call<Map<String, dynamic>>({
            'fullName': _nameController.text.trim(),
            'email': _emailController.text.trim(),
          });
      if (!mounted) return;
      setState(() => _resetLink = result.data['resetLink'] as String?);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Could not create the account.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not create the account. Please try again.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _resetLink != null;
    return AlertDialog(
      title: Text(created ? 'Admin Account Created' : 'Create Admin Account'),
      content: SizedBox(
        width: 480,
        child: created
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send this password setup link to the new admin. It can be used to choose their sign-in password.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(_resetLink!),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Enter the admin’s name.'
                          : null,
                    ),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(email)
                            ? null
                            : 'Enter a valid email address.';
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: Text(created ? 'Done' : 'Cancel'),
        ),
        if (created)
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _resetLink!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password setup link copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy Link'),
          )
        else
          FilledButton(
            onPressed: _creating ? null : _createAccount,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create Account'),
          ),
      ],
    );
  }
}

class _UserDetailRow extends StatelessWidget {
  const _UserDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _AuditLogsPage extends StatelessWidget {
  const _AuditLogsPage();

  @override
  Widget build(BuildContext context) {
    final logsQuery = FirebaseFirestore.instance
        .collection('admin_actions')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: logsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: _StreamErrorRow(snapshot.error),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data!.docs;
        if (logs.isEmpty) {
          return const Center(child: _EmptyRow('No audit records found.'));
        }

        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit Logs (${logs.length})',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Action')),
                          DataColumn(label: Text('Actor')),
                          DataColumn(label: Text('Target')),
                          DataColumn(label: Text('Status Change')),
                          DataColumn(label: Text('Record')),
                        ],
                        rows: logs.map((log) {
                          final data = log.data();
                          final previous = data['previousStatus']?.toString();
                          final next = data['newStatus']?.toString();
                          final actor = data['adminId']?.toString() ??
                              data['submittedBy']?.toString();
                          final target = data['trailName']?.toString() ??
                              data['mountainName']?.toString() ??
                              data['targetId']?.toString();
                          final statusChange = [
                            if (previous != null && previous != 'null') previous,
                            if (next != null && next != 'null') next,
                          ].join(' â†’ ');
                          return DataRow(
                            cells: [
                              DataCell(Text(_formatTimestamp(data['createdAt']).isEmpty
                                  ? 'Unknown'
                                  : _formatTimestamp(data['createdAt']))),
                              DataCell(Text(_actionVerb(
                                  data['action']?.toString() ?? 'unknown_action'))),
                              DataCell(Text(actor ?? '—')),
                              DataCell(Text(target ?? '—')),
                              DataCell(Text(statusChange.isEmpty ? '—' : statusChange)),
                              DataCell(
                                TextButton(
                                  onPressed: () => _showAuditRecord(
                                    context,
                                    log.id,
                                    data,
                                  ),
                                  child: const Text('View details'),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAuditRecord(
    BuildContext context,
    String documentId,
    Map<String, dynamic> data,
  ) {
    final fields = <String, dynamic>{'logId': documentId, ...data};
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audit Record'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: fields.entries.map((entry) {
                final value = entry.value is Timestamp
                    ? _formatTimestamp(entry.value)
                    : entry.value?.toString() ?? '—';
                return _UserDetailRow(label: entry.key, value: value);
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
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
