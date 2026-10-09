// The full Admin Dashboard shell shown after a successful sign-in —
// sidebar navigation + main content area. Sections are backed by Firestore
// streams and callable Cloud Functions for verification, monitoring, device
// management, user management, and audit history.
//
// Where real Firestore data already exists (trail_submissions,
// hike_rooms, and user profiles),
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
import '../data/davao_mountains.dart';
import 'incident_report_dialog.dart';

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
  _NavItem('Incident Reports', Icons.assignment_late_outlined),
];

EdgeInsets _adminPagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return EdgeInsets.all(
    width < 600
        ? 16
        : width < 1000
        ? 22
        : 28,
  );
}

class _AdminAccess {
  const _AdminAccess({required this.isMountainHead, this.managedMountainName});

  final bool isMountainHead;
  final String? managedMountainName;

  bool get isTourismAdmin => !isMountainHead;
}

List<String> _mountainNameVariants(String mountainName) {
  String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^mt\.?\s*'), 'mount ')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  final normalized = normalize(mountainName);
  final canonical = davaoMountains
      .where((mountain) => normalize(mountain.name) == normalized)
      .map((mountain) => mountain.name)
      .firstOrNull;
  final base = canonical ?? mountainName.trim();
  final variants = <String>{base};
  if (base.toLowerCase().startsWith('mt. ')) {
    final remainder = base.substring(4);
    variants.addAll(['Mt $remainder', 'Mount $remainder']);
  } else if (base.toLowerCase().startsWith('mt ')) {
    final remainder = base.substring(3);
    variants.addAll(['Mt. $remainder', 'Mount $remainder']);
  } else if (base.toLowerCase().startsWith('mount ')) {
    final remainder = base.substring(6);
    variants.addAll(['Mt. $remainder', 'Mt $remainder']);
  }
  variants.add(mountainName.trim());
  return variants.where((name) => name.isNotEmpty).toList(growable: false);
}

class AdminDashboardShell extends StatefulWidget {
  const AdminDashboardShell({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  final User user;
  final VoidCallback onSignOut;

  @override
  State<AdminDashboardShell> createState() => _AdminDashboardShellState();
}

class _AdminDashboardShellState extends State<AdminDashboardShell> {
  int _selected = 0;
  late final Future<_AdminAccess> _accessFuture = _loadAccess();

  Future<_AdminAccess> _loadAccess() async {
    final claims = (await widget.user.getIdTokenResult(true)).claims ?? {};
    if (claims['admin'] != true) {
      throw StateError('Admin access is no longer available. Sign in again.');
    }
    if (claims['adminRole'] == 'mountain_head') {
      final mountainName = claims['managedMountainName'];
      if (mountainName is! String || mountainName.trim().isEmpty) {
        throw StateError('This Mountain Head account has no managed mountain.');
      }
      return _AdminAccess(
        isMountainHead: true,
        managedMountainName: mountainName.trim(),
      );
    }
    if (claims['adminRole'] != 'tourism_admin') {
      throw StateError('This account has an unsupported admin role.');
    }
    return const _AdminAccess(isMountainHead: false);
  }

  void _navigateToPage(int index, _AdminAccess access) {
    if (access.isMountainHead && (index == 5 || index == 7)) return;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not verify admin access: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildDashboard(snapshot.data!);
      },
    );
  }

  Widget _buildDashboard(_AdminAccess access) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          selected: _selected,
          isMountainHead: access.isMountainHead,
          onSelect: (i) => _navigateToPage(i, access),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF4F6F5),
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE5E7E6)),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final headerWidth = constraints.maxWidth;
                      final showTitle = headerWidth >= 700;
                      return Row(
                        children: [
                          if (showTitle)
                            SizedBox(
                              width: 190,
                              child: Text(
                                _navItems[_selected].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          _NotificationBell(
                            access: access,
                            onOpenSosMonitoring: () =>
                                _navigateToPage(4, access),
                            onOpenTrailVerification: () =>
                                _navigateToPage(2, access),
                            onOpenAuditLogs: () => _navigateToPage(7, access),
                          ),
                          const SizedBox(width: 6),
                          Builder(
                            builder: (buttonContext) => Tooltip(
                              message: 'Admin profile',
                              child: GestureDetector(
                                onTap: () => _openAdminProfileMenu(
                                  buttonContext,
                                  widget.user,
                                  widget.onSignOut,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: const Color(
                                          0xFF0C563D,
                                        ),
                                        child: Text(
                                          (widget.user.displayName
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? widget.user.displayName!
                                                        .trim()[0]
                                                  : widget.user.email
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true
                                                  ? widget.user.email!.trim()[0]
                                                  : 'A')
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (headerWidth > 850) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          widget.user.displayName
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? widget.user.displayName!.trim()
                                              : 'Admin',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: switch (_selected) {
                    0 => _DashboardOverviewPage(
                      user: widget.user,
                      access: access,
                      onNavigate: (index) => _navigateToPage(index, access),
                    ),
                    1 => _TourGuideVerificationPage(access: access),
                    2 => _TrailVerificationPage(access: access),
                    3 => _HikeRoomMonitoringPage(access: access),
                    4 => _SosMonitoringPage(access: access),
                    5 =>
                      access.isTourismAdmin
                          ? const _BluetoothDevicesPage()
                          : const _ComingSoonPage(title: 'Access restricted'),
                    6 => _UserManagementPage(access: access),
                    7 =>
                      access.isTourismAdmin
                          ? const _AuditLogsPage()
                          : const _ComingSoonPage(title: 'Access restricted'),
                    8 => _IncidentReportsPage(access: access),
                    _ => _ComingSoonPage(title: _navItems[_selected].label),
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

Future<void> _openAdminProfileMenu(
  BuildContext context,
  User user,
  VoidCallback onSignOut,
) async {
  final button = context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final narrowScreen = overlay.size.width < 600;
  final popupWidth = (overlay.size.width - (narrowScreen ? 24 : 16))
      .clamp(120.0, narrowScreen ? 220.0 : 280.0)
      .toDouble();
  final minPopupWidth = popupWidth
      .clamp(0.0, narrowScreen ? 180.0 : 240.0)
      .toDouble();
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    bottomRight.dy + 4,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy - 4,
  );

  final result = await showMenu<String>(
    context: context,
    position: position,
    color: Colors.white,
    elevation: 8,
    constraints: BoxConstraints(
      minWidth: minPopupWidth,
      maxWidth: popupWidth,
      maxHeight: (overlay.size.height - 16).clamp(120.0, 480.0).toDouble(),
    ),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!.trim()
                  : 'Admin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (user.email?.isNotEmpty == true)
              Text(
                user.email!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'sign_out',
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 18),
            SizedBox(width: 10),
            Text('Sign out'),
          ],
        ),
      ),
    ],
  );
  if (result == 'sign_out') onSignOut();
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.isMountainHead,
    required this.onSelect,
  });

  final int selected;
  final bool isMountainHead;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final visibleIndices = isMountainHead
        ? [0, 1, 2, 3, 4, 6, 8]
        : List.generate(_navItems.length, (index) => index);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final collapsed = screenWidth < 760;
    final compact = screenWidth < 1050;
    final shortScreen = screenHeight < 650;
    final compactFooter = collapsed || shortScreen;
    final sidebarWidth = collapsed
        ? 72.0
        : compact
        ? 220.0
        : 260.0;

    return AnimatedContainer(
      width: sidebarWidth,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      color: const Color(0xFF0A4936),
      child: Column(
        children: [
          SizedBox(
            height: shortScreen
                ? 10
                : collapsed
                ? 16
                : 22,
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed
                  ? 15
                  : compact
                  ? 14
                  : 20,
            ),
            child: collapsed
                ? Container(
                    width: 42,
                    height: 42,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AdminColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      'assets/images/animal.png',
                      fit: BoxFit.cover,
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        width: compact ? 40 : 46,
                        height: compact ? 40 : 46,
                        decoration: BoxDecoration(
                          color: AdminColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/animal.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(width: compact ? 9 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AGAKBAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: compact ? 16 : 18,
                                letterSpacing: 1.1,
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'Navigate · Explore · Stay Safe',
                                style: TextStyle(
                                  color: Color(0xFFB8D5CA),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(
            height: shortScreen
                ? 10
                : collapsed
                ? 16
                : 24,
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: visibleIndices.length,
              itemBuilder: (context, i) {
                final navIndex = visibleIndices[i];
                final item = _navItems[navIndex];
                final isSelected = navIndex == selected;
                final section = navIndex == 0
                    ? 'OVERVIEW'
                    : navIndex == 1
                    ? 'VERIFICATION'
                    : navIndex == 3
                    ? 'OPERATIONS'
                    : navIndex == 6
                    ? 'MANAGEMENT'
                    : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section != null && !collapsed)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : 22,
                          navIndex == 0 ? 0 : 18,
                          12,
                          8,
                        ),
                        child: Text(
                          section,
                          style: const TextStyle(
                            color: Color(0xFFB8D5CA),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: collapsed ? 8 : 10,
                        vertical: 2,
                      ),
                      child: Tooltip(
                        message: collapsed ? item.label : '',
                        child: Material(
                          color: isSelected
                              ? const Color(0xFF14895F)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => onSelect(navIndex),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: collapsed ? 0 : 12,
                                vertical: shortScreen ? 9 : 12,
                              ),
                              child: Row(
                                mainAxisAlignment: collapsed
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  if (!collapsed) ...[
                                    SizedBox(width: compact ? 9 : 12),
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          fontSize: compact ? 12 : 13.5,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white70,
                                        size: 18,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 10 : 14,
              shortScreen ? 6 : 8,
              collapsed ? 10 : 14,
              shortScreen ? 8 : 14,
            ),
            child: compactFooter
                ? Tooltip(
                    message: 'Explore safely',
                    child: Container(
                      height: shortScreen ? 40 : 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF105941),
                        borderRadius: BorderRadius.circular(13),
                        image: const DecorationImage(
                          image: AssetImage(
                            'assets/images/mountain_banner.jpg',
                          ),
                          fit: BoxFit.cover,
                          opacity: 0.35,
                        ),
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        color: Color(0xFFB8E3CB),
                        size: 24,
                      ),
                    ),
                  )
                : Container(
                    width: double.infinity,
                    height: 76,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF105941), Color(0xFF0A4936)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/mountain_banner.jpg',
                          fit: BoxFit.cover,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x990A4936), Color(0x550A4936)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.explore_rounded,
                                color: Color(0xFFB8E3CB),
                                size: 25,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'EXPLORE SAFELY',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Every trail has a story.',
                                      style: TextStyle(
                                        color: Color(0xFFB8D5CA),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

class _NotificationBell extends StatefulWidget {
  const _NotificationBell({
    required this.access,
    required this.onOpenSosMonitoring,
    required this.onOpenTrailVerification,
    required this.onOpenAuditLogs,
  });

  final _AdminAccess access;
  final VoidCallback onOpenSosMonitoring;
  final VoidCallback onOpenTrailVerification;
  final VoidCallback onOpenAuditLogs;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _recentNotifications() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'notifications',
    );
    if (widget.access.isMountainHead) {
      query = query
          .where(
            'type',
            whereIn: const ['sos', 'trail_submission', 'incident_report'],
          )
          .where(
            'mountainName',
            whereIn: _mountainNameVariants(widget.access.managedMountainName!),
          );
    }
    return query.orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  Future<void> _openNotifications(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
  ) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final buttonTopLeft = button.localToGlobal(Offset.zero, ancestor: overlay);

    final buttonBottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final narrowScreen = overlay.size.width < 700;
    final popupWidth = (overlay.size.width - (narrowScreen ? 24 : 16))
        .clamp(180.0, narrowScreen ? 340.0 : 420.0)
        .toDouble();
    final popupMaxHeight = narrowScreen
        ? (overlay.size.height * 0.62).clamp(220.0, 440.0).toDouble()
        : (overlay.size.height - 24).clamp(180.0, 520.0).toDouble();
    final notificationListHeight = (popupMaxHeight - 112)
        .clamp(68.0, 400.0)
        .toDouble();

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
      constraints: BoxConstraints(
        minWidth: popupWidth
            .clamp(0.0, narrowScreen ? 300.0 : 360.0)
            .toDouble(),
        maxWidth: popupWidth,
        maxHeight: popupMaxHeight,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _NotificationPopupContent(
            notifications: notifications,
            onOpenSosMonitoring: widget.onOpenSosMonitoring,
            onOpenTrailVerification: widget.onOpenTrailVerification,
            onOpenAuditLogs: widget.onOpenAuditLogs,
            isMountainHead: widget.access.isMountainHead,
            width: popupWidth,
            listHeight: notificationListHeight,
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
                _openNotifications(context, notifications);
              },
              icon: const Icon(Icons.notifications_outlined, size: 25),
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
                    border: Border.all(color: Colors.white, width: 1.5),
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
    required this.onOpenTrailVerification,
    required this.onOpenAuditLogs,
    required this.isMountainHead,
    required this.width,
    required this.listHeight,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications;
  final VoidCallback onOpenSosMonitoring;
  final VoidCallback onOpenTrailVerification;
  final VoidCallback onOpenAuditLogs;
  final bool isMountainHead;
  final double width;
  final double listHeight;

  @override
  State<_NotificationPopupContent> createState() =>
      _NotificationPopupContentState();
}

class _NotificationPopupContentState extends State<_NotificationPopupContent> {
  bool _showUnreadOnly = false;
  final Map<String, Future<String>> _resolvedMessages = {};

  Future<String> _resolveAdminActivityMessage(
    String notificationId,
    Map<String, dynamic> notification,
  ) {
    return _resolvedMessages.putIfAbsent(notificationId, () async {
      var message = notification['message']?.toString() ?? '';
      final actionId = notification['actionId']?.toString();
      if (actionId == null || actionId.isEmpty) return message;

      final actionSnap = await FirebaseFirestore.instance
          .collection('admin_actions')
          .doc(actionId)
          .get();
      final action = actionSnap.data();
      if (action == null) return message;

      final targetId = action['targetId']?.toString();
      final targetName = action['targetName']?.toString().trim();
      if (targetId != null && targetId.isNotEmpty) {
        final targetEmail = action['targetEmail']?.toString().trim();
        final targetLabel = targetName != null && targetName.isNotEmpty
            ? targetName
            : targetEmail != null && targetEmail.isNotEmpty
            ? targetEmail
            : 'this user';
        message = message.replaceAll(targetId, targetLabel);
      }

      final adminId = action['adminId']?.toString();
      if (adminId != null && adminId.isNotEmpty) {
        final storedName = action['adminName']?.toString().trim();
        String? adminName = storedName != null && storedName.isNotEmpty
            ? storedName
            : null;
        if (adminName == null) {
          final adminSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(adminId)
              .get();
          final profile = adminSnap.data();
          for (final field in const ['fullName', 'displayName', 'name']) {
            final value = profile?[field]?.toString().trim();
            if (value != null && value.isNotEmpty) {
              adminName = value;
              break;
            }
          }
        }
        adminName ??= action['adminEmail']?.toString().trim();
        if (adminName != null && adminName.isNotEmpty) {
          message = message.replaceAll(adminId, adminName);
        }
      }
      return message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotifications = _showUnreadOnly
        ? widget.notifications
              .where((notification) => notification.data()['isRead'] != true)
              .toList()
        : widget.notifications;

    return SizedBox(
      width: widget.width,
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
                        color: !_showUnreadOnly ? Colors.blue : Colors.black54,
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
                        color: _showUnreadOnly ? Colors.blue : Colors.black54,
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
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 30),
              child: Center(
                child: Text(
                  'No notifications.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            SizedBox(
              height: widget.listHeight,
              child: ListView(
                padding: EdgeInsets.zero,
                children: filteredNotifications.map((notification) {
                  final data = notification.data();
                  final title = data['title']?.toString() ?? 'Notification';
                  final message = data['message']?.toString() ?? '';
                  final isRead = data['isRead'] == true;
                  final timeAgo = _relativeNotificationTime(data['createdAt']);

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      final notificationRef = FirebaseFirestore.instance
                          .collection('notifications')
                          .doc(notification.id);

                      // Mark only this notification as read.
                      if (!isRead) {
                        await notificationRef.update({'isRead': true});
                      }

                      if (!context.mounted) return;

                      navigator.pop();
                      if (!navigator.mounted) return;

                      // SOS notifications open the SOS Monitoring page.
                      if (data['type']?.toString() == 'sos') {
                        widget.onOpenSosMonitoring();
                      } else if (data['type']?.toString() ==
                          'trail_submission') {
                        if (widget.isMountainHead) {
                          widget.onOpenTrailVerification();
                        } else {
                          widget.onOpenAuditLogs();
                        }
                      } else if (data['type']?.toString() ==
                          'incident_report') {
                        final reportId = data['reportId']?.toString();
                        await showDialog<void>(
                          context: navigator.context,
                          builder: (dialogContext) => reportId == null
                              ? const AlertDialog(
                                  title: Text('Hike Incident Report'),
                                  content: Text(
                                    'This notification has no report ID.',
                                  ),
                                )
                              : IncidentReportDialog(
                                  reportId: reportId,
                                  canRespond: widget.isMountainHead,
                                ),
                        );
                      } else if (!widget.isMountainHead &&
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
                            color: isRead ? Colors.black45 : Colors.blue,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  FutureBuilder<String>(
                                    future:
                                        data['type']?.toString() ==
                                            'admin_action'
                                        ? _resolveAdminActivityMessage(
                                            notification.id,
                                            data,
                                          )
                                        : Future.value(message),
                                    builder: (context, snapshot) => Text(
                                      snapshot.data ?? message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  timeAgo,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Unread identifier
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 5),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

String _relativeNotificationTime(Object? value) {
  final DateTime? createdAt = switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };
  if (createdAt == null) return 'Time unavailable';

  final difference = DateTime.now().difference(createdAt);
  if (difference.isNegative || difference.inSeconds < 1) return 'Just now';
  if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
}

class _DashboardOverviewPage extends StatelessWidget {
  const _DashboardOverviewPage({
    required this.user,
    required this.access,
    required this.onNavigate,
  });

  final User user;
  final _AdminAccess access;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> pendingGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');
    Query<Map<String, dynamic>> pendingTrailsQuery = FirebaseFirestore.instance
        .collection('trail_submissions')
        .where('status', isEqualTo: 'pending');
    Query<Map<String, dynamic>> activeRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active');
    Query<Map<String, dynamic>> activeSosQuery = FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .where('status', isEqualTo: 'sent');
    if (access.isMountainHead) {
      final mountainName = access.managedMountainName!;
      final mountainNames = _mountainNameVariants(mountainName);
      pendingGuidesQuery = pendingGuidesQuery.where(
        'mountainNames',
        arrayContainsAny: mountainNames,
      );
      pendingTrailsQuery = pendingTrailsQuery.where(
        'mountainName',
        whereIn: mountainNames,
      );
      activeRoomsQuery = activeRoomsQuery.where(
        'mountainName',
        whereIn: mountainNames,
      );
      activeSosQuery = activeSosQuery.where(
        'mountainName',
        whereIn: mountainNames,
      );
    }
    return SingleChildScrollView(
      padding: _adminPagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardWelcomeBanner(user: user),
          const SizedBox(height: 18),
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
                        builder: (context, sosSnap) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StatGrid(
                              pendingGuides: guideSnap.data?.docs.length,
                              pendingTrails: trailSnap.data?.docs.length,
                              activeRooms: roomSnap.data?.docs.length,
                              activeSos: sosSnap.data?.docs.length,
                              onNavigate: onNavigate,
                            ),
                            if (guideSnap.hasError ||
                                trailSnap.hasError ||
                                roomSnap.hasError ||
                                sosSnap.hasError) ...[
                              const SizedBox(height: 8),
                              _StreamErrorRow(
                                guideSnap.error ??
                                    trailSnap.error ??
                                    roomSnap.error ??
                                    sosSnap.error,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 28),
          _OverviewQuickPanels(access: access, onNavigate: onNavigate),
          const SizedBox(height: 20),
          _OverviewIncidentReports(access: access, onNavigate: onNavigate),
          const SizedBox(height: 20),
          if (access.isTourismAdmin || access.isMountainHead)
            _SectionCard(
              title: 'Pending Tour Guide Applications',
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      final data = d.data();
                      return _ListRow(
                        title:
                            (data['fullName'] as String?) ??
                            (data['applicantEmail'] as String?) ??
                            (data['email'] as String?) ??
                            d.id,
                        subtitle:
                            (data['applicantEmail'] as String?) ??
                            (data['email'] as String?) ??
                            '',
                        onReview: () => _showGuideReviewDialog(
                          context,
                          applicationId: d.id,
                          data: data,
                          access: access,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Pending Trail Route Submissions',
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                    final data = d.data();
                    final distance = (data['distanceKm'] as num?)
                        ?.toStringAsFixed(1);
                    final elevation = (data['elevationGainMasl'] as num?)
                        ?.round();
                    final subtitleParts = <String>[
                      if (distance != null) '$distance km',
                      if (elevation != null) '$elevation m elevation',
                    ];
                    return _ListRow(
                      title:
                          (data['trailName'] as String?) ??
                          (data['mountainName'] as String?) ??
                          d.id,
                      subtitle: subtitleParts.join(' • '),
                      onReview: () => onNavigate(2),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          if (access.isTourismAdmin) const _RecentActivityPanel(),
        ],
      ),
    );
  }
}

class _DashboardWelcomeBanner extends StatelessWidget {
  const _DashboardWelcomeBanner({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final profile = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profile,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final profileName =
            [data?['fullName'], data?['displayName'], data?['name']]
                .whereType<String>()
                .map((name) => name.trim())
                .firstWhere((name) => name.isNotEmpty, orElse: () => '');
        final authName = user.displayName?.trim() ?? '';
        final emailName = user.email?.split('@').first.trim() ?? '';
        final adminName = profileName.isNotEmpty
            ? profileName
            : authName.isNotEmpty
            ? authName
            : emailName.isNotEmpty
            ? emailName
            : 'Admin';
        final firstName = adminName.trim().split(RegExp(r'\s+')).first;
        return _buildBanner(context, firstName);
      },
    );
  }

  Widget _buildBanner(BuildContext context, String adminName) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final date = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      width: double.infinity,
      height: width < 520
          ? 184
          : width < 700
          ? 174
          : 170,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/mountain_banner.jpg', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xF2F1F8F5),
                  Color(0xBFEAF4EE),
                  Color(0x14EAF4EE),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0, 0.58, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$greeting, $adminName 👋',
                  style: TextStyle(
                    fontSize: width < 700 ? 23 : 30,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF092F27),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Here's what's happening across the AGAKBAY platform today.",
                  style: TextStyle(fontSize: 15, color: Color(0xFF496A70)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 17,
                      color: Color(0xFF52727A),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${months[date.month - 1]} ${date.day}, ${date.year}',
                      style: const TextStyle(
                        color: Color(0xFF52727A),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent Activity',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('admin_actions')
            .orderBy('createdAt', descending: true)
            .limit(5)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _StreamErrorRow(snapshot.error);
          if (!snapshot.hasData) return const _LoadingRow();
          if (snapshot.data!.docs.isEmpty) {
            return const _EmptyRow('No recent admin activity.');
          }
          return Column(
            children: snapshot.data!.docs.map((doc) {
              final data = doc.data();
              final action = data['action']?.toString() ?? 'activity';
              final target =
                  data['targetName']?.toString() ??
                  data['trailName']?.toString() ??
                  data['mountainName']?.toString() ??
                  data['roomCode']?.toString() ??
                  '';
              final time = _formatTimestamp(data['createdAt']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AdminColors.accent.withValues(
                        alpha: 0.13,
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: AdminColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _actionVerb(action),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (target.isNotEmpty)
                            Text(
                              target,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _OverviewQuickPanels extends StatelessWidget {
  const _OverviewQuickPanels({required this.access, required this.onNavigate});

  final _AdminAccess access;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> rooms = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active');
    Query<Map<String, dynamic>> sos = FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .where('status', isEqualTo: 'sent');
    if (access.isMountainHead) {
      final mountainNames = _mountainNameVariants(access.managedMountainName!);
      rooms = rooms.where('mountainName', whereIn: mountainNames);
      sos = sos.where('mountainName', whereIn: mountainNames);
    }
    final roomsStream = rooms.snapshots();
    final sosStream = sos.snapshots();
    final width = MediaQuery.sizeOf(context).width;
    final roomCard = GestureDetector(
      onTap: () => onNavigate(3),
      child: _SectionCard(
        title: 'Active Hike Rooms',
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: roomsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _StreamErrorRow(snapshot.error);
            if (!snapshot.hasData) return const _LoadingRow();
            final docs = [...snapshot.data!.docs]
              ..sort((a, b) {
                final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
                final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
                if (aTime == null) return bTime == null ? 0 : 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });
            if (docs.isEmpty) return const _EmptyRow('No active hike rooms.');
            return Column(
              children: docs.take(3).map((doc) {
                final room = doc.data();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: const Color(
                          0xFF12805A,
                        ).withValues(alpha: .12),
                        child: const Icon(
                          Icons.terrain_rounded,
                          color: Color(0xFF12805A),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room['mountainName']?.toString() ?? 'Hike room',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Guide · ${room['guideName']?.toString() ?? 'Unknown'}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
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
                          color: const Color(0xFFE1F4EA),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF12805A),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
    final sosCard = GestureDetector(
      onTap: () => onNavigate(4),
      child: _SectionCard(
        title: 'SOS Monitoring',
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sosStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _StreamErrorRow(snapshot.error);
            if (!snapshot.hasData) return const _LoadingRow();
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F8F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF12805A),
                      size: 34,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No active SOS alerts',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'There are no open SOS events.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              );
            }
            final alertCount = docs.length;
            final recentAlerts = [...docs]
              ..sort((a, b) {
                final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
                final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
                if (aTime == null) return bTime == null ? 0 : 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD7C7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$alertCount Active SOS Alert${alertCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xFFD92F3D),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xFFFFD8CF),
                        child: Icon(
                          Icons.warning_rounded,
                          color: Color(0xFFD92F3D),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...recentAlerts.take(3).map((doc) {
                    final alert = doc.data();
                    final name = alert['senderName']?.toString().trim() ?? '';
                    final roomCode = alert['roomCode']?.toString().trim() ?? '';
                    final roomId = alert['roomId']?.toString().trim() ?? '';
                    final roomLabel = roomCode.isNotEmpty ? roomCode : roomId;
                    final latitude = (alert['latitude'] as num?)?.toDouble();
                    final longitude = (alert['longitude'] as num?)?.toDouble();
                    final details = <String>[
                      if (roomLabel.isNotEmpty) 'Room $roomLabel',
                      if (latitude != null && longitude != null)
                        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                      if (alert['createdAt'] != null)
                        _formatTimestamp(alert['createdAt']),
                    ];
                    return Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_rounded,
                            color: Color(0xFFD92F3D),
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (name.isNotEmpty)
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                if (details.isNotEmpty)
                                  Text(
                                    details.join(' · '),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            (alert['status']?.toString() ?? '').toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFD92F3D),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (width < 900) {
      return Column(children: [roomCard, const SizedBox(height: 16), sosCard]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: roomCard),
        const SizedBox(width: 16),
        Expanded(flex: 4, child: sosCard),
      ],
    );
  }
}

class _OverviewIncidentReports extends StatelessWidget {
  const _OverviewIncidentReports({
    required this.access,
    required this.onNavigate,
  });

  final _AdminAccess access;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> reports = FirebaseFirestore.instance
        .collection('incident_reports');
    if (access.isMountainHead) {
      reports = reports.where(
        'mountainName',
        whereIn: _mountainNameVariants(access.managedMountainName!),
      );
    }
    reports = reports.orderBy('createdAt', descending: true).limit(4);

    return _SectionCard(
      title: 'Recent Incident Reports',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reports.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _StreamErrorRow(snapshot.error);
          if (!snapshot.hasData) return const _LoadingRow();
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const _EmptyRow('No incident reports have been filed.');
          }

          return Column(
            children: [
              for (final doc in docs) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onNavigate(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: _incidentStatusColor(
                            _reportStatus(doc.data()),
                          ).withValues(alpha: 0.12),
                          child: Icon(
                            _incidentStatusIcon(_reportStatus(doc.data())),
                            color: _incidentStatusColor(
                              _reportStatus(doc.data()),
                            ),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${doc.data()['mountainName'] ?? 'Unknown mountain'} · '
                                '${doc.data()['category'] ?? 'Incident'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Hiker: ${doc.data()['hikerName'] ?? 'Hiker'} · '
                                'Guide: ${doc.data()['guideName'] ?? 'Tour Guide'} · '
                                '${_formatTimestamp(doc.data()['createdAt'])}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _IncidentReportStatusBadge(
                          status: _reportStatus(doc.data()),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                  ),
                ),
                if (doc != docs.last) const Divider(height: 1),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onNavigate(8),
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('View all incident reports'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Color _incidentStatusColor(String status) => switch (status) {
  'acknowledged' => Colors.blue,
  'responders_sent' => Colors.deepPurple,
  'responded' => Colors.green,
  _ => Colors.orange,
};

IconData _incidentStatusIcon(String status) => switch (status) {
  'acknowledged' => Icons.visibility_rounded,
  'responders_sent' => Icons.support_agent_rounded,
  'responded' => Icons.check_circle_rounded,
  _ => Icons.assignment_late_rounded,
};

class _IncidentReportStatusBadge extends StatelessWidget {
  const _IncidentReportStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _incidentStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        _incidentStatusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _actionVerb(String action) {
  switch (action) {
    case 'send_sos':
      return 'Sent SOS Alert';
    case 'acknowledge_sos':
      return 'Acknowledged SOS Alert';
    case 'bluetooth_connected':
      return 'Bluetooth Device Connected';
    case 'bluetooth_disconnected':
      return 'Bluetooth Device Disconnected';
    case 'bluetooth_device_changed':
      return 'Bluetooth Device Updated';
    case 'create_hike_room':
      return 'Created Hike Room';
    case 'start_hike_room':
      return 'Started Hike Room';
    case 'end_hike_room':
      return 'Ended Hike Room';
    case 'join_hike_room':
      return 'Joined Hike Room';
    case 'leave_hike_room':
      return 'Left Hike Room';
    case 'remove_hike_participant':
      return 'Removed Hiker from Room';
    case 'start_hiking':
      return 'Started Hiking';
    case 'return_to_room':
      return 'Returned to Room';
    case 'cleanup_orphaned_sos_events':
      return 'Removed SOS from Deleted Users';
    case 'create_admin':
      return 'Created Admin Account';
    case 'mountain_head_recommendation':
      return 'Submitted Mountain Head Recommendation';
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
    case 'auto_close_abandoned_room':
      return 'Auto-Closed Abandoned Hike Room';
    case 'rename_bluetooth_device':
      return 'Renamed Bluetooth Device';
    case 'submit_trail_route':
      return 'Submitted Trail Route';
    case 'approve_trail_submission':
      return 'Approved Trail Submission';
    case 'reject_trail_submission':
      return 'Rejected Trail Submission';
    default:
      return action;
  }
}

String _formatTimestamp(Object? value) {
  if (value is! Timestamp) {
    return '';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = value.toDate();
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

Future<void> _showAccountActionResultDialog(
  BuildContext context, {
  required bool success,
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        success ? Icons.check_circle_rounded : Icons.error_rounded,
        color: success ? AdminColors.accent : Colors.red,
        size: 44,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: FilledButton.styleFrom(backgroundColor: AdminColors.accent),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

void _showGuideReviewDialog(
  BuildContext context, {
  required String applicationId,
  required Map<String, dynamic> data,
  required _AdminAccess access,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Review Tour Guide Application'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: _GuideApplicationCard(
            applicationId: applicationId,
            data: data,
            isMountainHead: access.isMountainHead,
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
  const _TourGuideVerificationPage({required this.access});

  final _AdminAccess access;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> pendingGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');
    if (access.isMountainHead) {
      pendingGuidesQuery = pendingGuidesQuery.where(
        'mountainNames',
        arrayContainsAny: _mountainNameVariants(access.managedMountainName!),
      );
    }
    Query<Map<String, dynamic>> legacyGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');
    if (access.isMountainHead) {
      legacyGuidesQuery = legacyGuidesQuery.where(
          'mountainsHandled',
          whereIn: _mountainNameVariants(access.managedMountainName!),
        );
    }

    return SingleChildScrollView(
      padding: _adminPagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tour Guide Verification',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'I-review ang mga application ng aspiring tour guides',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No pending tour guide applications.',
                      style: TextStyle(color: Colors.black45),
                    ),
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
                          data: d.data(),
                          isMountainHead: access.isMountainHead,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (access.isMountainHead)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: legacyGuidesQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return _StreamErrorRow(snap.error);
                if (!snap.hasData) return const _LoadingRow();
                final docs = snap.data!.docs
                    .where((doc) => doc.data()['mountainNames'] is! List)
                    .toList();
                if (docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Existing applications for ${access.managedMountainName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    ...docs.map(
                      (doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _GuideApplicationCard(
                          applicationId: doc.id,
                          data: doc.data(),
                          isMountainHead: true,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RecommendationNotice extends StatelessWidget {
  const _RecommendationNotice({required this.recommendation});

  final Map<String, dynamic> recommendation;

  @override
  Widget build(BuildContext context) {
    final decision = recommendation['decision']?.toString() ?? 'review';
    final mountainName =
        recommendation['mountainName']?.toString() ?? 'managed mountain';
    final reason = recommendation['reason']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mountain Head recommendation for $mountainName: '
            '${decision == 'approve' ? 'Approve' : 'Reject'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(reason),
          ],
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
  const _GuideApplicationCard({
    required this.applicationId,
    required this.data,
    required this.isMountainHead,
    this.onReviewed,
  });

  final String applicationId;
  final Map<String, dynamic> data;
  final bool isMountainHead;
  final VoidCallback? onReviewed;

  @override
  State<_GuideApplicationCard> createState() => _GuideApplicationCardState();
}

class _GuideApplicationCardState extends State<_GuideApplicationCard> {
  bool _submitting = false;

  Future<void> _review(String decision) async {
    setState(() => _submitting = true);
    try {
      if (widget.isMountainHead) {
        await FirebaseFunctions.instance
            .httpsCallable('recommendAdminReview')
            .call({
              'targetType': 'tour_guide_application',
              'targetId': widget.applicationId,
              'decision': decision,
            });
      } else {
        await FirebaseFunctions.instance
            .httpsCallable('reviewTourGuideApplication')
            .call({
              'applicationId': widget.applicationId,
              'decision': decision,
            });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isMountainHead
                  ? 'Recommendation sent to the Tourism Admin.'
                  : decision == 'approve'
                  ? 'Approved.'
                  : 'Rejected.',
            ),
          ),
        );
        widget.onReviewed?.call();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Failed to submit decision.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
                const Text(
                  'Government ID',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _DocumentImage(url: idUrl),
                const SizedBox(height: 20),
                const Text(
                  'Certificate',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _DocumentImage(url: certUrl),
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
    final recommendation = data['mountainHeadRecommendation'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
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
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Contact: $contact',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: const TextStyle(
                          color: AdminColors.accent,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Experience'),
          Text(
            '$experience years',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Mountains Handled'),
          Text(mountains, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const _FieldLabel('Submitted'),
          Text(
            submitted.isEmpty ? '—' : submitted,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _viewDocuments(context),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View Full Profile & ID/Certificates'),
          ),
          const SizedBox(height: 16),
          if (recommendation is Map<String, dynamic> &&
              !widget.isMountainHead) ...[
            _RecommendationNotice(recommendation: recommendation),
            const SizedBox(height: 12),
          ],
          if (widget.isMountainHead && recommendation is Map<String, dynamic>)
            _RecommendationNotice(recommendation: recommendation)
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _review('approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminColors.accent,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.isMountainHead
                                ? 'Recommend Approve'
                                : 'Approve',
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _review('reject'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: Text(
                      widget.isMountainHead ? 'Recommend Reject' : 'Reject',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A submitted ID/certificate photo. Firebase Storage download URLs embed
/// their own access token, so [Image.network] alone should be able to load
/// one regardless of Storage security rules — but a plain Image.network
/// with no errorBuilder fails completely silently on Flutter Web (CORS and
/// permission failures both just render nothing, with no clue why), which
/// is exactly what made these look "not submitted" even when they were.
/// This surfaces the actual error and a copyable link as a fallback the
/// admin can open directly in a new tab.
class _DocumentImage extends StatelessWidget {
  const _DocumentImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) {
      return const Text(
        'Not provided.',
        style: TextStyle(color: Colors.black45),
      );
    }
    final thumbnail = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        },
        // Kept only as a fallback — storage.setCorsConfiguration (see
        // scripts/setStorageCors.js) should make this the rare path now,
        // not the normal one. Without it, a failed load used to render as
        // nothing at all, which read as "the applicant submitted nothing."
        errorBuilder: (context, error, stackTrace) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Could not load this image here (likely a browser CORS or '
                'permission restriction on the admin web dashboard).',
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open directly instead:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SelectableText(url, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showFullImageView(context, url),
        child: thumbnail,
      ),
    );
  }
}

void _showFullImageView(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => GestureDetector(
      // Tap anywhere outside the image to close — standard lightbox
      // behavior, no close button needed to find first.
      onTap: () => Navigator.of(dialogContext).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: GestureDetector(
                  // Swallow taps on the image itself so only the backdrop
                  // closes the viewer — otherwise pinch/pan gestures on the
                  // image would also trigger the dismiss-on-tap above.
                  onTap: () {},
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
  final zoom = spanDegrees == 0
      ? 15.0
      : (14 - (spanDegrees * 100)).clamp(9.0, 15.0);
  return CameraPosition(target: center, zoom: zoom, tilt: 45);
}

class _TrailVerificationPage extends StatelessWidget {
  const _TrailVerificationPage({required this.access});

  final _AdminAccess access;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> pendingTrailsQuery = FirebaseFirestore.instance
        .collection('trail_submissions')
        .where('status', isEqualTo: 'pending');
    if (access.isMountainHead) {
      pendingTrailsQuery = pendingTrailsQuery.where(
        'mountainName',
        whereIn: _mountainNameVariants(access.managedMountainName!),
      );
    }

    return SingleChildScrollView(
      padding: _adminPagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trail Route Verification',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'I-verify ang GPS route ng mga na-submit na trail',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No pending trail submissions.',
                      style: TextStyle(color: Colors.black45),
                    ),
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
                          data: d.data(),
                          isMountainHead: access.isMountainHead,
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
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No route points recorded.',
            style: TextStyle(color: Colors.black45),
          ),
        ),
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
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: const InfoWindow(title: 'Start'),
            ),
            Marker(
              markerId: const MarkerId('end'),
              position: points.last,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
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

class _TrailSubmissionCard extends StatefulWidget {
  const _TrailSubmissionCard({
    required this.submissionId,
    required this.data,
    required this.isMountainHead,
  });

  final String submissionId;
  final Map<String, dynamic> data;
  final bool isMountainHead;

  @override
  State<_TrailSubmissionCard> createState() => _TrailSubmissionCardState();
}

class _TrailSubmissionCardState extends State<_TrailSubmissionCard> {
  bool _reviewing = false;

  Future<void> _review(String decision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.isMountainHead
              ? decision == 'approve'
                    ? 'Recommend approval?'
                    : 'Recommend rejection?'
              : decision == 'approve'
              ? 'Approve this trail?'
              : 'Reject this trail?',
        ),
        content: Text(
          widget.isMountainHead
              ? 'This sends your recommendation to the Tourism Admin. The trail will not be published until the Tourism Admin makes a final decision.'
              : decision == 'approve'
              ? 'This publishes the route on this mountain and notifies the submitter and other hikers who\'ve done it before.'
              : 'The submitter will be notified their trail was not approved.',
        ),
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

    setState(() => _reviewing = true);
    try {
      if (widget.isMountainHead) {
        await FirebaseFunctions.instance
            .httpsCallable('recommendAdminReview')
            .call({
              'targetType': 'trail_submission',
              'targetId': widget.submissionId,
              'decision': decision,
            });
      } else {
        await FirebaseFunctions.instance
            .httpsCallable('reviewTrailSubmission')
            .call({'submissionId': widget.submissionId, 'decision': decision});
      }
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: true,
        title: widget.isMountainHead
            ? 'Recommendation Sent'
            : decision == 'approve'
            ? 'Trail Approved'
            : 'Trail Rejected',
        message: widget.isMountainHead
            ? 'The Tourism Admin will make the final decision.'
            : decision == 'approve'
            ? 'The route is now published and the submitter and other hikers have been notified.'
            : 'The submitter has been notified.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: false,
        title: 'Could Not Update Submission',
        message: error.message ?? 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final submissionId = widget.submissionId;
    final title =
        (data['trailName'] as String?) ??
        (data['mountainName'] as String?) ??
        submissionId;
    final submittedBy = data['submittedBy'] as String?;
    final distance = (data['distanceKm'] as num?)?.toStringAsFixed(1);
    final elevation = (data['elevationGainMasl'] as num?)?.round();
    final points = _decodeRoutePoints(data['routePoints']);
    final submitted = _formatTimestamp(data['createdAt']);
    final recommendation = data['mountainHeadRecommendation'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (submittedBy != null)
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(submittedBy)
                            .get(),
                        builder: (context, userSnap) {
                          final userData =
                              userSnap.data?.data() as Map<String, dynamic>?;
                          final name = userData?['fullName'] as String?;
                          return Text(
                            'Submitted by ${name ?? submittedBy}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12.5,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TrailMapPreview(points: points),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Distance',
                  value: distance != null ? '$distance km' : '—',
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'Elevation Gain',
                  value: elevation != null ? '$elevation m' : '—',
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'GPS Points',
                  value: '${points.length}',
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'Submitted',
                  value: submitted.isEmpty ? '—' : submitted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Route comparison isn\'t wired up yet.'),
                ),
              ),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Compare with existing route on this mountain'),
              style: TextButton.styleFrom(
                foregroundColor: AdminColors.accent,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (recommendation is Map<String, dynamic> &&
              !widget.isMountainHead) ...[
            _RecommendationNotice(recommendation: recommendation),
            const SizedBox(height: 12),
          ],
          if (widget.isMountainHead && recommendation is Map<String, dynamic>)
            _RecommendationNotice(recommendation: recommendation)
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _reviewing ? null : () => _review('approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminColors.accent,
                    ),
                    child: _reviewing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.isMountainHead
                                ? 'Recommend Approve'
                                : 'Approve',
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _reviewing ? null : () => _review('reject'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: Text(
                      widget.isMountainHead ? 'Recommend Reject' : 'Reject',
                    ),
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
  const _StatCardData(
    this.label,
    this.value,
    this.icon,
    this.color,
    this.destination,
  );
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
    required this.onNavigate,
  });

  final int? pendingGuides;
  final int? pendingTrails;
  final int? activeRooms;
  final int? activeSos;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCardData(
        'Pending Guide Apps',
        pendingGuides?.toString() ?? '-',
        Icons.groups_rounded,
        const Color(0xFF12805A),
        1,
      ),
      _StatCardData(
        'Pending Trail Submissions',
        pendingTrails?.toString() ?? '-',
        Icons.landscape_rounded,
        const Color(0xFF2387CC),
        2,
      ),
      _StatCardData(
        'Active Hike Rooms',
        activeRooms?.toString() ?? '-',
        Icons.directions_walk_rounded,
        const Color(0xFF12805A),
        3,
      ),
      _StatCardData(
        'Active SOS Alerts',
        activeSos?.toString() ?? '-',
        Icons.warning_rounded,
        const Color(0xFFD92F3D),
        4,
      ),
    ];
    final width = MediaQuery.sizeOf(context).width;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: width > 1250
          ? 4
          : width > 720
          ? 2
          : 1,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      // Keep enough vertical room for the label and value at narrow widths,
      // where the dashboard content is reduced by the navigation sidebar.
      childAspectRatio: width > 1250
          ? 2.05
          : width > 720
          ? 2.2
          : 2.6,
      children: cards
          .map(
            (card) => _StatCard(
              data: card,
              onTap: () => onNavigate(card.destination),
            ),
          )
          .toList(),
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
      color: Color.alphaBlend(
        data.color.withValues(alpha: 0.055),
        Colors.white,
      ),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: data.color.withValues(alpha: 0.13)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: Color(0xFF173B34),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      data.value,
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        color: data.color,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (onReview != null)
            TextButton(
              onPressed: onReview,
              style: TextButton.styleFrom(
                foregroundColor: AdminColors.backgroundTop,
              ),
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: LinearProgressIndicator(),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: const TextStyle(color: Colors.black45, fontSize: 13),
    ),
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
    child: Text(
      'Failed to load: $error',
      style: const TextStyle(color: Colors.red, fontSize: 13),
    ),
  );
}

class _IncidentReportsPage extends StatefulWidget {
  const _IncidentReportsPage({required this.access});

  final _AdminAccess access;

  @override
  State<_IncidentReportsPage> createState() => _IncidentReportsPageState();
}

class _IncidentReportsPageState extends State<_IncidentReportsPage> {
  static const _pageSize = 20;

  int _pageIndex = 0;
  String _selectedStatus = 'all';
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _pageCursors = [
    null,
  ];

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> reports = FirebaseFirestore.instance.collection(
      'incident_reports',
    );
    if (widget.access.isMountainHead) {
      reports = reports.where(
        'mountainName',
        whereIn: _mountainNameVariants(widget.access.managedMountainName!),
      );
    }
    reports = reports.orderBy('createdAt', descending: true);
    final pageCursor = _pageCursors[_pageIndex];
    if (pageCursor != null) {
      reports = reports.startAfterDocument(pageCursor);
    }
    reports = reports.limit(_pageSize + 1);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: reports.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: _adminPagePadding(context),
            child: _StreamErrorRow(snapshot.error),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final reportDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final seenReportEvents = <String>{};
        for (final report in snapshot.data!.docs.take(_pageSize)) {
          final data = report.data();
          final eventId = data['eventId']?.toString().trim() ?? '';
          final roomId = data['roomId']?.toString() ?? '';
          final uniqueKey = eventId.isEmpty ? report.id : '$roomId:$eventId';
          if (seenReportEvents.add(uniqueKey)) reportDocs.add(report);
        }
        final submittedCount = reportDocs
            .where((doc) => _reportStatus(doc.data()) == 'submitted')
            .length;
        final acknowledgedCount = reportDocs
            .where((doc) => _reportStatus(doc.data()) == 'acknowledged')
            .length;
        final respondersSentCount = reportDocs
            .where((doc) => _reportStatus(doc.data()) == 'responders_sent')
            .length;
        final respondedCount = reportDocs
            .where((doc) => _reportStatus(doc.data()) == 'responded')
            .length;
        final visibleReportDocs = _selectedStatus == 'all'
            ? reportDocs
            : reportDocs
                  .where(
                    (doc) => _reportStatus(doc.data()) == _selectedStatus,
                  )
                  .toList(growable: false);

        return Container(
          color: const Color(0xFFFFF6E5),
          child: ListView(
            key: ValueKey(_pageIndex),
            padding: _adminPagePadding(context),
            children: [
            Text(
              'Incident Reports',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              widget.access.isMountainHead
                  ? 'Acknowledge each report, mark when responders are sent, then mark it responded once resolved.'
                  : 'Monitor hike incident reports across all mountains.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _IncidentReportCount(
                  label: 'All',
                  count: reportDocs.length,
                  selected: _selectedStatus == 'all',
                  onTap: () => setState(() => _selectedStatus = 'all'),
                ),
                _IncidentReportCount(
                  label: 'Filed',
                  count: submittedCount,
                  color: Colors.orange,
                  selected: _selectedStatus == 'submitted',
                  onTap: () => setState(() => _selectedStatus = 'submitted'),
                ),
                _IncidentReportCount(
                  label: 'Acknowledged',
                  count: acknowledgedCount,
                  color: Colors.blue,
                  selected: _selectedStatus == 'acknowledged',
                  onTap: () =>
                      setState(() => _selectedStatus = 'acknowledged'),
                ),
                _IncidentReportCount(
                  label: 'Responders sent',
                  count: respondersSentCount,
                  color: Colors.deepPurple,
                  selected: _selectedStatus == 'responders_sent',
                  onTap: () =>
                      setState(() => _selectedStatus = 'responders_sent'),
                ),
                _IncidentReportCount(
                  label: 'Responded',
                  count: respondedCount,
                  color: Colors.green,
                  selected: _selectedStatus == 'responded',
                  onTap: () => setState(() => _selectedStatus = 'responded'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (reportDocs.isEmpty)
              const _EmptyRow('No incident reports have been filed.')
            else if (visibleReportDocs.isEmpty)
              _EmptyRow(
                'No ${_incidentStatusLabel(_selectedStatus).toLowerCase()} reports on this page.',
              )
            else
              for (final reportDoc in visibleReportDocs)
                _IncidentReportListCard(
                  reportId: reportDoc.id,
                  data: reportDoc.data(),
                  canRespond: widget.access.isMountainHead,
                ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pageIndex == 0
                      ? null
                      : () => setState(() => _pageIndex--),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                const SizedBox(width: 16),
                Text('Page ${_pageIndex + 1}'),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: snapshot.data!.docs.length <= _pageSize
                      ? null
                      : () {
                          final nextPage = _pageIndex + 1;
                          if (nextPage == _pageCursors.length) {
                            _pageCursors.add(
                              snapshot.data!.docs[_pageSize - 1],
                            );
                          }
                          setState(() => _pageIndex = nextPage);
                        },
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

String _reportStatus(Map<String, dynamic> report) {
  final status = report['status']?.toString();
  if (status == 'acknowledged' ||
      status == 'responders_sent' ||
      status == 'responded') {
    return status!;
  }
  return 'submitted';
}

String _incidentStatusLabel(String status) => switch (status) {
  'acknowledged' => 'Acknowledged',
  'responders_sent' => 'Responders sent',
  'responded' => 'Responded',
  _ => 'Filed',
};

class _IncidentReportCount extends StatelessWidget {
  const _IncidentReportCount({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color = AdminColors.accent,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter $label incident reports. $count reports.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.20 : 0.08),
              border: Border.all(
                color: color.withValues(alpha: selected ? 0.85 : 0.40),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 11, color: color),
                const SizedBox(width: 10),
                Text('$label: $count', style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncidentReportListCard extends StatelessWidget {
  const _IncidentReportListCard({
    required this.reportId,
    required this.data,
    required this.canRespond,
  });

  final String reportId;
  final Map<String, dynamic> data;
  final bool canRespond;

  @override
  Widget build(BuildContext context) {
    final status = _reportStatus(data);
    final statusColor = switch (status) {
      'responded' => Colors.green,
      'acknowledged' => Colors.blue,
      'responders_sent' => Colors.deepPurple,
      _ => Colors.orange,
    };
    final created = _formatTimestamp(data['createdAt']);
    final subject =
        '${data['mountainName'] ?? 'Unknown mountain'} · '
        '${data['category'] ?? 'Incident'}';
    final details =
        'Hiker: ${data['hikerName'] ?? 'Hiker'} · '
        'Guide: ${data['guideName'] ?? 'Tour Guide'}'
        '${created.isEmpty ? '' : ' · $created'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFFFFDF2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE8DCC1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reportDetails = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(Icons.report_problem_outlined, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          _incidentStatusLabel(status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subject,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          );

          final reportActions = OutlinedButton.icon(
            onPressed: () => _openReport(context),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Review report'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF356B3C),
              side: const BorderSide(color: Color(0xFF9C947E)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          );

          return Padding(
            padding: const EdgeInsets.all(12),
            child: constraints.maxWidth < 560
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      reportDetails,
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: reportActions,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: reportDetails),
                      const SizedBox(width: 12),
                      reportActions,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _openReport(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          IncidentReportDialog(reportId: reportId, canRespond: canRespond),
    );
  }
}

class _HikeRoomMonitoringPage extends StatelessWidget {
  const _HikeRoomMonitoringPage({required this.access});

  final _AdminAccess access;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> currentRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', whereIn: ['waiting', 'active']);
    Query<Map<String, dynamic>> historyQuery = FirebaseFirestore.instance
        .collection('hike_room_history')
        .orderBy('endedAt', descending: true)
        .limit(50);
    if (access.isMountainHead) {
      currentRoomsQuery = currentRoomsQuery.where(
        'mountainName',
        whereIn: _mountainNameVariants(access.managedMountainName!),
      );
      historyQuery = FirebaseFirestore.instance
          .collection('hike_room_history')
          .where(
            'mountainName',
            whereIn: _mountainNameVariants(access.managedMountainName!),
          )
          .orderBy('endedAt', descending: true)
          .limit(50);
    }

    return SingleChildScrollView(
      padding: _adminPagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hike Room Monitoring',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Monitor waiting and active hiking rooms and their participants',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _showHikeHistoryDialog(context, historyQuery),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Hike History'),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: currentRoomsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _StreamErrorRow(snap.error);
              }

              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
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
                      'No waiting or active hike rooms.',
                      style: TextStyle(color: Colors.black45),
                    ),
                  ),
                );
              }

              return Column(
                children: rooms.map((room) {
                  final data = room.data() as Map<String, dynamic>;

                  return _HikeRoomCard(roomId: room.id, data: data);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _showHikeHistoryDialog(
  BuildContext context,
  Query<Map<String, dynamic>> historyQuery,
) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hike History'),
      content: SizedBox(
        width: size.width < 700 ? size.width * 0.9 : 720,
        height: size.height * 0.68,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Completed hikes with the guide, participants, and hike times.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              _HikeRoomHistoryList(query: historyQuery),
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

class _HikeRoomHistoryList extends StatefulWidget {
  const _HikeRoomHistoryList({required this.query});

  final Query<Map<String, dynamic>> query;

  @override
  State<_HikeRoomHistoryList> createState() => _HikeRoomHistoryListState();
}

class _HikeRoomHistoryListState extends State<_HikeRoomHistoryList> {
  static const _pageSize = 10;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _StreamErrorRow(snapshot.error);
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final records = snapshot.data!.docs;
        if (records.isEmpty) {
          return const _EmptyRow('No completed hike history yet.');
        }
        final pageCount = (records.length / _pageSize).ceil();
        final currentPage = _page.clamp(0, pageCount - 1);
        final pageRecords = records
            .skip(currentPage * _pageSize)
            .take(_pageSize);
        return Column(
          children: [
            for (final record in pageRecords)
              _HikeRoomHistoryCard(data: record.data()),
            if (records.length > _pageSize)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: currentPage > 0
                          ? () => setState(() => _page = currentPage - 1)
                          : null,
                      child: const Text('Previous'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('Page ${currentPage + 1} of $pageCount'),
                    ),
                    OutlinedButton(
                      onPressed: currentPage + 1 < pageCount
                          ? () => setState(() => _page = currentPage + 1)
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HikeRoomHistoryCard extends StatelessWidget {
  const _HikeRoomHistoryCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final participants = (data['participants'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((participant) => Map<String, dynamic>.from(participant))
        .toList(growable: false);
    final started = _formatHikeHistoryTimestamp(data['startedAt']);
    final ended = _formatHikeHistoryTimestamp(data['endedAt']);
    final duration = data['durationSeconds'] as int?;
    final durationLabel = duration == null
        ? 'Duration unavailable'
        : '${duration ~/ 3600}h ${(duration % 3600) ~/ 60}m';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      child: ExpansionTile(
        leading: const Icon(Icons.history_rounded, color: AdminColors.accent),
        title: Text(
          '${data['mountainName'] ?? 'Hike'} · Room ${data['roomCode'] ?? '—'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Guide: ${data['guideName'] ?? '—'} · $ended · '
          '${participants.length} participants',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Route: ${data['routeName'] ?? '—'}'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Started: ${started.isEmpty ? '—' : started}'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ended: ${ended.isEmpty ? '—' : ended} · $durationLabel',
            ),
          ),
          const Divider(height: 22),
          for (final participant in participants)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                participant['role'] == 'tour_guide'
                    ? Icons.badge_outlined
                    : Icons.person_outline_rounded,
              ),
              title: Text(participant['name']?.toString() ?? 'Hiker'),
              subtitle: Text(
                '${participant['role'] ?? 'hiker'} · '
                '${participant['activityStatus'] ?? 'in_room'} · '
                '${participant['membershipStatus'] ?? 'active'}\n'
                'Joined ${_formatHikeHistoryTimestamp(participant['joinedAt'])}'
                '${participant['hikingStartedAt'] == null ? '' : ' · Hike started ${_formatHikeHistoryTimestamp(participant['hikingStartedAt'])}'}'
                '${participant['returnedToRoomAt'] == null ? '' : ' · Returned ${_formatHikeHistoryTimestamp(participant['returnedToRoomAt'])}'}'
                '${(participant['stopReason']?.toString().trim().isNotEmpty ?? false) ? '\nEnd-hike reason: ${participant['stopReason']}' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}

String _formatHikeHistoryTimestamp(Object? value) {
  if (value is! Timestamp) return '—';
  final date = value.toDate().toLocal();
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${_formatTimestamp(value)} at $hour:$minute $period';
}

class _HikeRoomCard extends StatelessWidget {
  const _HikeRoomCard({required this.roomId, required this.data});

  final String roomId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final roomCode = data['roomCode'] as String? ?? roomId;

    final mountainName = data['mountainName'] as String? ?? '—';

    final guideName = data['guideName'] as String? ?? '—';

    final routeName = data['routeName'] as String? ?? '—';

    final status = data['status'] as String? ?? '—';

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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: const TextStyle(color: Colors.black54),
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
                  color: AdminColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
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
                child: _StatColumn(label: 'Guide', value: guideName),
              ),
              Expanded(
                child: _StatColumn(label: 'Route', value: routeName),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ============================================================
          // PARTICIPANTS
          // ============================================================
          const Text(
            'Participants',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),

          const SizedBox(height: 10),

          _RoomParticipants(roomId: roomId),
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
  const _RoomParticipants({required this.roomId});

  final String roomId;

  bool _isOffline(String deviceStatus, String activityStatus) {
    final device = deviceStatus.toLowerCase().trim();

    final activity = activityStatus.toLowerCase().trim();

    return device == 'offline' ||
        device == 'disconnected' ||
        device == 'not_connected' ||
        activity == 'offline';
  }

  @override
  Widget build(BuildContext context) {
    final participantsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .doc(roomId)
        .collection('participants');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: participantsQuery.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _StreamErrorRow(snap.error);
        }

        if (!snap.hasData) {
          return const LinearProgressIndicator();
        }

        final participants = snap.data!.docs.where((participant) {
          final data = participant.data();

          return (data['membershipStatus']?.toString() ?? 'active') == 'active';
        }).toList();

        if (participants.isEmpty) {
          return const Text(
            'No active participants in this room.',
            style: TextStyle(color: Colors.black45),
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

        final Set<Marker> participantMarkers = {};

        final List<Map<String, dynamic>> participantsWithLocation = [];

        for (final participant in participants) {
          final data = participant.data();

          final name = data['name']?.toString() ?? participant.id;

          final role = data['role']?.toString() ?? '—';

          final activityStatus = data['activityStatus']?.toString() ?? '—';

          final deviceStatus = data['deviceStatus']?.toString() ?? '—';

          final latitude = (data['latitude'] as num?)?.toDouble();

          final longitude = (data['longitude'] as num?)?.toDouble();

          final lastLocationAt = data['lastLocationAt'];

          final isOffline = _isOffline(deviceStatus, activityStatus);

          if (latitude != null && longitude != null) {
            participantsWithLocation.add({
              'id': participant.id,
              'name': name,
              'role': role,
              'activityStatus': activityStatus,
              'deviceStatus': deviceStatus,
              'latitude': latitude,
              'longitude': longitude,
              'lastLocationAt': lastLocationAt,
              'isOffline': isOffline,
            });

            participantMarkers.add(
              Marker(
                markerId: MarkerId(participant.id),
                position: LatLng(latitude, longitude),
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
                  avatar: const Icon(Icons.people, size: 18),
                  label: Text('${participants.length} participants'),
                ),
                Chip(
                  avatar: const Icon(Icons.bluetooth_connected, size: 18),
                  label: Text('$connectedCount Connected'),
                ),
                Chip(
                  avatar: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: Text('$disconnectedCount Disconnected'),
                ),
                if (noDeviceCount > 0)
                  Chip(
                    avatar: const Icon(Icons.bluetooth, size: 18),
                    label: Text('$noDeviceCount No device'),
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

              final name = data['name']?.toString() ?? 'Unknown hiker';

              final deviceStatus =
                  data['deviceStatus']?.toString() ?? 'unknown';

              final deviceName =
                  data['deviceName']?.toString() ?? 'No device connected';

              final lastBluetoothAt = data['lastBluetoothAt'];

              return _BluetoothParticipantTile(
                deviceId: data['deviceId']?.toString(),
                name: name,
                deviceStatus: deviceStatus,
                deviceName: deviceName,
                lastBluetoothAt: lastBluetoothAt,
                lastLocationText: _formatLastLocation(data['lastLocationAt']),
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

class _ParticipantLocationMap extends StatelessWidget {
  const _ParticipantLocationMap({
    required this.participants,
    required this.markers,
  });

  final List<Map<String, dynamic>> participants;

  final Set<Marker> markers;

  LatLng _initialPosition() {
    if (participants.isNotEmpty) {
      final first = participants.first;

      final latitude = first['latitude'] as double;

      final longitude = first['longitude'] as double;

      return LatLng(latitude, longitude);
    }

    // Fallback location.
    // The map will normally use the first
    // participant's actual GPS coordinates.
    return const LatLng(7.0731, 125.6128);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition(),
              zoom: 14,
            ),

            markers: markers,

            zoomControlsEnabled: true,

            myLocationButtonEnabled: false,

            mapToolbarEnabled: false,

            compassEnabled: true,

            zoomGesturesEnabled: true,

            scrollGesturesEnabled: true,

            rotateGesturesEnabled: true,

            tiltGesturesEnabled: false,
          ),

          // ============================================================
          // MAP LABEL
          // ============================================================
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(blurRadius: 6, color: Colors.black12),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 17,
                    color: AdminColors.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${markers.length} '
                    '${markers.length == 1 ? 'participant' : 'participants'} '
                    'with location',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _SosMonitoringPage extends StatefulWidget {
  const _SosMonitoringPage({required this.access});

  final _AdminAccess access;

  @override
  State<_SosMonitoringPage> createState() => _SosMonitoringPageState();
}

class _SosMonitoringPageState extends State<_SosMonitoringPage> {
  bool _cleaningOrphanedAlerts = false;
  _SosAlertFilter _filter = _SosAlertFilter.all;
  DateTimeRange? _dateRange;
  int _page = 0;
  Set<String> _deletedSenderIds = {};
  String? _deletedSenderLookupError;

  static const _pageSize = 10;
  static const _maxLoadedAlerts = 100;

  @override
  void initState() {
    super.initState();
    if (widget.access.isTourismAdmin) _loadDeletedSenderIds();
  }

  void _selectFilter(_SosAlertFilter filter) {
    setState(() {
      _filter = filter;
      _page = 0;
    });
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) {
        DateTime? start = _dateRange?.start;
        DateTime? end = _dateRange?.end;
        final today = DateTime(now.year, now.month, now.day);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canApply = start != null &&
                end != null &&
                !end!.isBefore(start!);

            return AlertDialog(
              title: const Text('Filter SOS alerts'),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choose the date range for SOS alerts.'),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: start ?? end ?? today,
                          firstDate: DateTime(2020),
                          lastDate: today,
                          helpText: 'Select start date',
                        );
                        if (picked == null) return;
                        setDialogState(() {
                          start = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                          if (end != null && end!.isBefore(start!)) end = null;
                        });
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        start == null
                            ? 'Start date'
                            : 'Start: ${start!.month}/${start!.day}/${start!.year}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: end ?? start ?? today,
                          firstDate: start ?? DateTime(2020),
                          lastDate: today,
                          helpText: 'Select end date',
                        );
                        if (picked == null) return;
                        setDialogState(() {
                          end = DateTime(picked.year, picked.month, picked.day);
                        });
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        end == null
                            ? 'End date'
                            : 'End: ${end!.month}/${end!.day}/${end!.year}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canApply
                      ? () => Navigator.pop(
                          dialogContext,
                          DateTimeRange(start: start!, end: end!),
                        )
                      : null,
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _dateRange = DateTimeRange(
        start: DateTime(range.start.year, range.start.month, range.start.day),
        end: DateTime(range.end.year, range.end.month, range.end.day),
      );
      _page = 0;
    });
  }

  Future<void> _loadDeletedSenderIds() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getDeletedSosSenderIds')
          .call<Map<String, dynamic>>();
      final senderIds = result.data['senderIds'];
      if (senderIds is! List || senderIds.any((uid) => uid is! String)) {
        throw StateError('Invalid response while resolving deleted SOS users.');
      }
      if (!mounted) return;
      setState(() {
        _deletedSenderIds = senderIds.cast<String>().toSet();
        _deletedSenderLookupError = null;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _deletedSenderLookupError =
            error.message ?? 'Could not identify deleted SOS users.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletedSenderLookupError = error.toString());
    }
  }

  String _senderName(Map<String, dynamic> eventData) {
    final senderId = eventData['senderId']?.toString() ?? '';
    final senderName = eventData['senderName']?.toString().trim() ?? '';
    final wasAnonymized =
        senderId.isEmpty && senderName.toLowerCase() == 'user';
    if ((senderId.isNotEmpty && _deletedSenderIds.contains(senderId)) ||
        wasAnonymized) {
      return 'Deleted user';
    }
    return senderName;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sosEventsStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collectionGroup('sos_events');
    final range = _dateRange;
    if (range != null) {
      query = query
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start.toUtc()),
          )
          .where(
            'createdAt',
            isLessThan: Timestamp.fromDate(
              range.end.add(const Duration(days: 1)).toUtc(),
            ),
          );
    }
    if (widget.access.isMountainHead) {
      query = query.where(
        'mountainName',
        whereIn: _mountainNameVariants(widget.access.managedMountainName!),
      );
    }
    query = query
        .orderBy('createdAt', descending: true)
        .limit(_maxLoadedAlerts);
    return query.snapshots();
  }

  Future<void> _removeOrphanedAlerts() async {
    setState(() => _cleaningOrphanedAlerts = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('cleanupOrphanedSosEvents')
          .call<Map<String, dynamic>>();
      if (!mounted) return;
      final data = result.data;
      final deletedEvents = data['deletedSosEvents'] ?? 0;
      final deletedNotifications = data['deletedSosNotifications'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed $deletedEvents orphaned SOS alerts and $deletedNotifications notifications.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Could not remove orphaned SOS alerts.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove orphaned SOS alerts: $error')),
      );
    } finally {
      if (mounted) setState(() => _cleaningOrphanedAlerts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sosEventsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SosPageMessage(
            icon: Icons.error_outline_rounded,
            message: 'Failed to load SOS alerts.',
            detail: snapshot.error.toString(),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data!.docs;
        final acknowledgedEvents = events
            .where(
              (event) => event.data()['status']?.toString() == 'acknowledged',
            )
            .toList(growable: false);
        final unacknowledgedEvents = events
            .where(
              (event) => event.data()['status']?.toString() != 'acknowledged',
            )
            .toList(growable: false);
        final displayedEvents = switch (_filter) {
          _SosAlertFilter.all => events,
          _SosAlertFilter.acknowledged => acknowledgedEvents,
          _SosAlertFilter.unacknowledged => unacknowledgedEvents,
        };
        final pageCount = (displayedEvents.length / _pageSize).ceil();
        final currentPage = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
        final pageEvents = displayedEvents
            .skip(currentPage * _pageSize)
            .take(_pageSize)
            .toList(growable: false);
        final mapEvents = _filter == _SosAlertFilter.acknowledged
            ? acknowledgedEvents
            : unacknowledgedEvents;
        final sosPoints = mapEvents
            .map((event) {
              final data = event.data();
              final latitude = (data['latitude'] as num?)?.toDouble();
              final longitude = (data['longitude'] as num?)?.toDouble();
              if (latitude == null || longitude == null) return null;
              return _SosMapPoint(
                eventId: event.id,
                senderName: _senderName(data),
                latitude: latitude,
                longitude: longitude,
              );
            })
            .whereType<_SosMapPoint>()
            .toList(growable: false);

        return Column(
          children: [
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  padding: _adminPagePadding(context),
                  children: [
                    Text(
                      'SOS Monitoring',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Live SOS events from Firebase.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    if (widget.access.isTourismAdmin &&
                        _deletedSenderLookupError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Could not verify deleted SOS users: '
                        '$_deletedSenderLookupError',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (widget.access.isTourismAdmin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _cleaningOrphanedAlerts
                              ? null
                              : _removeOrphanedAlerts,
                          icon: _cleaningOrphanedAlerts
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Remove SOS from deleted users'),
                        ),
                      ),
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: unacknowledgedEvents.isEmpty
                            ? const Color(0xFFEAF5EF)
                            : const Color(0xFFFFF1E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: unacknowledgedEvents.isEmpty
                              ? const Color(0xFFCDE8D8)
                              : const Color(0xFFFFD7C7),
                        ),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 8,
                        spacing: 16,
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color: unacknowledgedEvents.isEmpty
                                ? const Color(0xFF12805A)
                                : const Color(0xFFD92F3D),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: MediaQuery.sizeOf(context).width < 600
                                ? double.infinity
                                : 260,
                            child: Text(
                              events.length == _maxLoadedAlerts
                                  ? 'Showing latest $_maxLoadedAlerts SOS alerts'
                                  : '${events.length} total SOS alert${events.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: unacknowledgedEvents.isEmpty
                                    ? const Color(0xFF12805A)
                                    : const Color(0xFFD92F3D),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${unacknowledgedEvents.length} not acknowledged',
                                style: const TextStyle(
                                  color: Color(0xFFD92F3D),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${acknowledgedEvents.length} acknowledged',
                                style: const TextStyle(
                                  color: Color(0xFF12805A),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (events.isNotEmpty &&
                        (_filter == _SosAlertFilter.acknowledged ||
                            sosPoints.isNotEmpty)) ...[
                      _SosRoomMap(
                        points: sosPoints,
                        showMarkers: _filter != _SosAlertFilter.acknowledged,
                      ),
                      const SizedBox(height: 18),
                    ],
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 8,
                      spacing: 12,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SosFilterChip(
                              label: 'All',
                              count: events.length,
                              selected: _filter == _SosAlertFilter.all,
                              onSelected: () =>
                                  _selectFilter(_SosAlertFilter.all),
                            ),
                            _SosFilterChip(
                              label: 'Acknowledged',
                              count: acknowledgedEvents.length,
                              selected:
                                  _filter == _SosAlertFilter.acknowledged,
                              onSelected: () =>
                                  _selectFilter(_SosAlertFilter.acknowledged),
                            ),
                            _SosFilterChip(
                              label: 'Unacknowledged',
                              count: unacknowledgedEvents.length,
                              selected:
                                  _filter == _SosAlertFilter.unacknowledged,
                              onSelected: () => _selectFilter(
                                _SosAlertFilter.unacknowledged,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _selectDateRange,
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                              ),
                              label: Text(
                                _dateRange == null
                                    ? 'Date range'
                                    : '${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year} – '
                                          '${_dateRange!.end.month}/${_dateRange!.end.day}/${_dateRange!.end.year}',
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            if (_dateRange != null)
                              IconButton(
                                tooltip: 'Clear date filter',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _dateRange = null;
                                  _page = 0;
                                }),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (events.isEmpty)
                      _SosPageMessage(
                        icon: Icons.check_circle_outline_rounded,
                        message: _dateRange == null
                            ? 'No SOS alerts recorded.'
                            : 'No SOS alerts for this date range.',
                        detail: _dateRange == null
                            ? 'New alerts will appear here when a hiker sends an SOS.'
                            : 'Choose another date range or clear the date filter.',
                      )
                    else if (displayedEvents.isEmpty)
                      _SosPageMessage(
                        icon: Icons.filter_alt_off_rounded,
                        message: _dateRange == null
                            ? 'No ${_filter.label.toLowerCase()} SOS alerts.'
                            : 'No ${_filter.label.toLowerCase()} SOS alerts for this date range.',
                        detail: _dateRange == null
                            ? 'Choose another filter to view more SOS alerts.'
                            : 'Choose another date range or clear the date filter.',
                      )
                    else ...[
                      ...pageEvents.map((event) {
                        final data = event.data();
                        final roomId =
                            data['roomId']?.toString() ??
                            event.reference.parent.parent?.id ??
                            '';
                        return _SosAlertCard(
                          roomId: roomId,
                          eventData: data,
                          senderName: _senderName(data),
                        );
                      }),
                      if (displayedEvents.length > _pageSize) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: currentPage > 0
                                  ? () =>
                                        setState(() => _page = currentPage - 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left_rounded),
                              label: const Text('Previous'),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Page ${currentPage + 1} of $pageCount'
                              '${events.length == _maxLoadedAlerts ? ' · latest $_maxLoadedAlerts alerts' : ''}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: currentPage + 1 < pageCount
                                  ? () =>
                                        setState(() => _page = currentPage + 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                              label: const Text('Next'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _SosAlertFilter { all, acknowledged, unacknowledged }

extension on _SosAlertFilter {
  String get label => switch (this) {
    _SosAlertFilter.all => 'all',
    _SosAlertFilter.acknowledged => 'acknowledged',
    _SosAlertFilter.unacknowledged => 'unacknowledged',
  };
}

class _SosFilterChip extends StatelessWidget {
  const _SosFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text('$label ($count)'),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
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

class _SosRoomMap extends StatefulWidget {
  const _SosRoomMap({required this.points, required this.showMarkers});

  final List<_SosMapPoint> points;
  final bool showMarkers;

  @override
  State<_SosRoomMap> createState() => _SosRoomMapState();
}

class _SosRoomMapState extends State<_SosRoomMap> {
  GoogleMapController? _controller;

  void _fitAlertLocations() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null || widget.points.isEmpty) return;

    final locations = widget.points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toSet()
        .toList(growable: false);
    if (locations.length == 1) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(locations.single, 14),
      );
      return;
    }

    final latitudes = locations.map((point) => point.latitude);
    final longitudes = locations.map((point) => point.longitude);
    var minLat = latitudes.reduce((a, b) => a < b ? a : b);
    var maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    var minLng = longitudes.reduce((a, b) => a < b ? a : b);
    var maxLng = longitudes.reduce((a, b) => a > b ? a : b);
    if (minLat == maxLat) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if (minLng == maxLng) {
      minLng -= 0.001;
      maxLng += 0.001;
    }

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        56,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _SosRoomMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAlertLocations());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstPoint = widget.points.firstOrNull;
    final markers = widget.showMarkers
        ? widget.points.map((point) {
            return Marker(
              markerId: MarkerId(point.eventId),
              position: LatLng(point.latitude, point.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(
                title: point.senderName.isEmpty
                    ? 'SOS alert'
                    : 'SOS: ${point.senderName}',
                snippet:
                    '${point.latitude.toStringAsFixed(6)}, '
                    '${point.longitude.toStringAsFixed(6)}',
              ),
            );
          }).toSet()
        : const <Marker>{};

    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: firstPoint == null
              ? const LatLng(7.0731, 125.6128)
              : LatLng(firstPoint.latitude, firstPoint.longitude),
          zoom: firstPoint == null ? 11 : 14,
        ),
        markers: markers,
        onMapCreated: (controller) {
          _controller = controller;
          _fitAlertLocations();
        },
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
    required this.eventData,
    required this.senderName,
  });

  final String roomId;
  final Map<String, dynamic> eventData;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final acknowledged = eventData['status']?.toString() == 'acknowledged';

    final latitude = (eventData['latitude'] as num?)?.toDouble();
    final longitude = (eventData['longitude'] as num?)?.toDouble();

    final createdAt = eventData['createdAt'];
    final DateTime? createdTime = createdAt is Timestamp
        ? createdAt.toDate()
        : null;
    final acknowledgedAt = eventData['acknowledgedAt'];

    final statusChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: (acknowledged ? const Color(0xFF12805A) : Colors.red).withValues(
          alpha: 0.15,
        ),
      ),
      child: Text(
        acknowledged ? 'ACKNOWLEDGED' : 'NOT ACKNOWLEDGED',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: acknowledged ? const Color(0xFF12805A) : Colors.redAccent,
        ),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final titleRow = Row(
                  children: [
                    Icon(
                      acknowledged
                          ? Icons.check_circle_rounded
                          : Icons.sos_rounded,
                      color: acknowledged
                          ? const Color(0xFF12805A)
                          : Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        senderName.isEmpty
                            ? 'SOS alert'
                            : 'SOS from $senderName',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleRow,
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 38),
                        child: statusChip,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: titleRow),
                    const SizedBox(width: 10),
                    statusChip,
                  ],
                );
              },
            ),

            const SizedBox(height: 14),

            if (latitude != null && longitude != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${latitude.toStringAsFixed(6)}, '
                      '${longitude.toStringAsFixed(6)}',
                    ),
                  ),
                ],
              ),
            if (latitude != null && longitude != null && createdTime != null)
              const SizedBox(height: 8),
            if (createdTime != null)
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(_formatSosTime(createdTime)),
                ],
              ),
            if (acknowledged && acknowledgedAt is Timestamp) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: Color(0xFF12805A),
                  ),
                  Text(
                    'Tour guide acknowledged ${_formatSosTime(acknowledgedAt.toDate())}',
                  ),
                ],
              ),
            ],
            if ((eventData['roomCode']?.toString().trim().isNotEmpty ??
                    false) ||
                roomId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Room: ${(eventData['roomCode']?.toString().trim().isNotEmpty ?? false)
                    ? eventData['roomCode']
                    : (eventData['roomId']?.toString().trim().isNotEmpty ?? false)
                    ? eventData['roomId']
                    : roomId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
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
      padding: _adminPagePadding(context),
      children: [
        Text(
          'Bluetooth Devices',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
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
                    final advertisedName =
                        data['deviceName']?.toString().trim() ?? '';
                    final adminLabel =
                        data['displayName']?.toString().trim() ?? '';
                    final name = advertisedName.isNotEmpty
                        ? advertisedName
                        : adminLabel.isNotEmpty
                        ? adminLabel
                        : 'Heltec device';
                    final lastActivity = data['lastActivityAt'];
                    final activityDate = lastActivity is Timestamp
                        ? lastActivity.toDate()
                        : null;
                    final recent =
                        activityDate != null &&
                        DateTime.now().difference(activityDate).inMinutes < 5;
                    final connected =
                        data['lastStatus'] == 'connected' && recent;
                    final connection = connected
                        ? 'Connected'
                        : data['lastStatus'] == 'connected'
                        ? 'Last connected (stale)'
                        : data['lastStatus'] == 'disconnected'
                        ? 'Disconnected'
                        : 'Unknown';
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (adminLabel.isNotEmpty && adminLabel != name)
                                Text(
                                  'Admin label: $adminLabel',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        DataCell(
                          SelectableText(
                            deviceId.isEmpty ? 'Unavailable' : deviceId,
                          ),
                        ),
                        DataCell(
                          _BluetoothDeviceAssignmentCell(
                            roomId: data['lastRoomId']?.toString(),
                            participantId: data['lastParticipantId']
                                ?.toString(),
                            roomCode: data['lastRoomCode']?.toString(),
                            deviceId: deviceId,
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                connected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_disabled,
                                size: 18,
                                color: connected ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(connection),
                            ],
                          ),
                        ),
                        DataCell(Text(_formatBluetoothTimestamp(lastActivity))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    _showBluetoothConnectivityHistory(
                                      context,
                                      deviceId: deviceId,
                                      deviceName: name,
                                    ),
                                icon: const Icon(Icons.history, size: 18),
                                label: const Text('History'),
                              ),
                              TextButton.icon(
                                onPressed: () => _renameBluetoothDevice(
                                  context,
                                  deviceId: deviceId,
                                  deviceData: data,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Set label'),
                              ),
                            ],
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
    if (roomId == null ||
        roomId!.isEmpty ||
        participantId == null ||
        participantId!.isEmpty) {
      return const Text('Available');
    }
    final roomRef = FirebaseFirestore.instance
        .collection('hike_rooms')
        .doc(roomId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, roomSnapshot) {
        if (!roomSnapshot.hasData ||
            roomSnapshot.data?.data()?['status'] != 'active') {
          return const Text('Available');
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: roomRef
              .collection('participants')
              .doc(participantId)
              .snapshots(),
          builder: (context, participantSnapshot) {
            final participant = participantSnapshot.data?.data();
            final occupied =
                participantSnapshot.hasData &&
                participantSnapshot.data!.exists &&
                participant?['membershipStatus'] == 'active' &&
                participant?['deviceId']?.toString() == deviceId;
            return Text(
              occupied ? 'Occupied Â· Room ${roomCode ?? roomId}' : 'Available',
            );
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
            Text(
              'Device ID: $deviceId',
              style: const TextStyle(color: Colors.black54),
            ),
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
                      final status =
                          event['deviceStatus']?.toString() ??
                          event['eventType']?.toString() ??
                          'Activity';
                      final connected = status == 'connected';
                      final room =
                          event['roomCode']?.toString() ??
                          event['roomId']?.toString() ??
                          'Unknown';
                      final participant =
                          event['participantName']?.toString() ??
                          'Unknown participant';
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
    text:
        deviceData['displayName']?.toString() ??
        deviceData['deviceName']?.toString() ??
        '',
  );
  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Set Admin Label'),
      content: TextField(
        controller: controller,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Admin label'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (newName == null || newName.isEmpty || !context.mounted) return;
  try {
    await FirebaseFunctions.instance
        .httpsCallable('renameBluetoothDevice')
        .call({'deviceId': deviceId, 'displayName': newName});
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Device name updated.')));
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
          border: Border.all(color: Colors.black12),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deviceName,
                    style: const TextStyle(color: Colors.black54),
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
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 4),
                  Text(
                    'Location: $lastLocationText',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
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
  const _UserManagementPage({required this.access});

  final _AdminAccess access;

  @override
  State<_UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<_UserManagementPage> {
  final TextEditingController _searchController = TextEditingController();
  String _accountTypeFilter = 'all';

  String _effectiveAccountType(Map<String, dynamic> data) {
    if (data['adminAccess'] == true ||
        data['role'] == 'admin' ||
        data['accountType'] == 'admin') {
      return data['adminRole'] == 'mountain_head'
          ? 'mountain_head'
          : 'tourism_admin';
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
    final usersCollection = FirebaseFirestore.instance.collection('users');
    final usersQuery = widget.access.isMountainHead
        ? usersCollection
              .where('accountType', isEqualTo: 'tour_guide')
              .where(
                'mountainNames',
                arrayContainsAny: _mountainNameVariants(
                  widget.access.managedMountainName!,
                ),
              )
              .orderBy('email')
        : usersCollection.orderBy('email');

    return SingleChildScrollView(
      padding: _adminPagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Management',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.access.isMountainHead
                ? 'Tour guides assigned to ${widget.access.managedMountainName}.'
                : 'View and manage AGAKBAY user and admin accounts.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),

          if (widget.access.isTourismAdmin) ...[
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _showCreateAdminDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Create Admin Account'),
              ),
            ),
            const SizedBox(height: 12),
          ],

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

          if (widget.access.isTourismAdmin)
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
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('All account types'),
                  ),
                  DropdownMenuItem(value: 'hiker', child: Text('Hiker')),
                  DropdownMenuItem(
                    value: 'tour_guide',
                    child: Text('Tour Guide'),
                  ),
                  DropdownMenuItem(
                    value: 'tourism_admin',
                    child: Text('Tourism Admin'),
                  ),
                  DropdownMenuItem(
                    value: 'mountain_head',
                    child: Text('Mountain Head'),
                  ),
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
                  child: Center(child: _StreamErrorRow(snapshot.error)),
                );
              }

              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final searchText = _searchController.text.trim().toLowerCase();

              final users = snapshot.data!.docs.where((user) {
                final data = user.data();

                final email = data['email']?.toString().toLowerCase() ?? '';

                final displayName = _userDisplayName(data).toLowerCase();
                final accountType = _effectiveAccountType(data);

                final matchesSearch =
                    email.contains(searchText) ||
                    displayName.contains(searchText);
                final matchesType =
                    _accountTypeFilter == 'all' ||
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
                      style: const TextStyle(color: Colors.black45),
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

                      final email = data['email']?.toString() ?? 'No email';

                      final displayName = _userDisplayName(data);

                      final accountType = _effectiveAccountType(data);

                      final guideVerified = data['guideVerified'] == true;

                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                            Text(switch (accountType) {
                              'tour_guide' => 'Tour Guide',
                              'tourism_admin' => 'Tourism Admin',
                              'mountain_head' => 'Mountain Head',
                              _ => 'Hiker',
                            }),
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
                                    guideVerified ? 'Verified' : 'Pending',
                                    style: TextStyle(
                                      color: guideVerified
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : const Text(
                                    'N/A',
                                    style: TextStyle(color: Colors.black45),
                                  ),
                          ),
                          DataCell(
                            Text(
                              data['createdAt'] != null
                                  ? _formatUserDate(data['createdAt'])
                                  : 'Unknown',
                              style: const TextStyle(color: Colors.black54),
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
    if (!widget.access.isTourismAdmin) return;

    final descriptions = <String, String>{
      'revoke_admin': 'Remove this user\'s admin access?',
      'suspend':
          'Suspend this account? They will be signed out and unable to sign in.',
      'restore': 'Restore this account\'s access?',
      'delete':
          'Permanently delete this sign-in account, private profile data, guide applications and files, and hike/SOS data? Public community posts, comments, and trail submissions will remain.',
    };
    final successTitles = <String, String>{
      'revoke_admin': 'Admin Access Revoked',
      'suspend': 'Account Suspended',
      'restore': 'Account Restored',
      'delete': 'Account Deleted',
    };
    final successMessages = <String, String>{
      'revoke_admin': 'This user no longer has admin access.',
      'suspend': 'This account has been signed out and can no longer sign in.',
      'restore': 'This account can sign in again.',
      'delete':
          'The sign-in account and private profile data have been deleted. Public community posts, comments, and trail submissions remain.',
    };
    final isDelete = action == 'delete';
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(isDelete ? 'Confirm deletion' : 'Confirm account change'),
        content: Text(
          isDelete
              ? 'Are you sure you want to delete this account?'
              : descriptions[action]!,
        ),
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
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: true,
        title: successTitles[action]!,
        message: successMessages[action]!,
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: false,
        title: 'Could Not Update Account',
        message: [
          'Code: ${error.code}',
          if (error.message?.isNotEmpty == true) error.message!,
          if (error.details != null) 'Details: ${error.details}',
        ].join('\n'),
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

        final username = data['username']?.toString() ?? 'Not provided';

        final email = data['email']?.toString() ?? 'Not provided';

        final accountType = data['accountType']?.toString() ?? 'Not provided';

        final role = data['role']?.toString() ?? 'Not provided';

        final emailVerified = data['emailVerified'] == true;

        final accountConfirmed = data['accountTypeConfirmed'] == true;

        final guideVerified = data['guideVerified'] == true;

        final onboardingComplete = data['onboardingComplete'] == true;

        final skillLevel = data['skillLevel']?.toString() ?? 'Not provided';

        final verificationMethod =
            data['verificationMethod']?.toString() ?? 'Not provided';

        final activeHikeRoomId = data['activeHikeRoomId']?.toString();
        final hasAdminAccess =
            data['adminAccess'] == true ||
            data['role'] == 'admin' ||
            data['accountType'] == 'admin';
        final isSuspended = data['accountSuspended'] == true;

        return AlertDialog(
          title: const Text('User Details'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserDetailRow(label: 'Full Name', value: fullName),
                  _UserDetailRow(label: 'Username', value: username),
                  _UserDetailRow(label: 'Email', value: email),
                  _UserDetailRow(label: 'Account Type', value: accountType),
                  _UserDetailRow(
                    label: 'Admin Access',
                    value: hasAdminAccess ? 'Granted' : 'Not granted',
                  ),
                  if (hasAdminAccess) ...[
                    _UserDetailRow(
                      label: 'Admin Role',
                      value: data['adminRole'] == 'mountain_head'
                          ? 'Mountain Head'
                          : data['adminRole'] == 'tourism_admin'
                          ? 'Tourism Admin'
                          : 'Unassigned (legacy Tourism Admin)',
                    ),
                    if (data['adminRole'] == 'mountain_head')
                      _UserDetailRow(
                        label: 'Managed Mountain',
                        value:
                            data['managedMountainName']?.toString() ??
                            'Not assigned',
                      ),
                  ],
                  _UserDetailRow(
                    label: 'Account Status',
                    value: isSuspended ? 'Suspended' : 'Active',
                  ),
                  _UserDetailRow(label: 'Role', value: role),
                  _UserDetailRow(
                    label: 'Email Verified',
                    value: emailVerified ? 'Verified' : 'Not Verified',
                  ),
                  _UserDetailRow(
                    label: 'Account Confirmed',
                    value: accountConfirmed ? 'Confirmed' : 'Not Confirmed',
                  ),
                  _UserDetailRow(
                    label: 'Guide Verified',
                    value: guideVerified ? 'Verified' : 'Not Verified',
                  ),
                  _UserDetailRow(
                    label: 'Onboarding',
                    value: onboardingComplete ? 'Complete' : 'Incomplete',
                  ),
                  _UserDetailRow(label: 'Skill Level', value: skillLevel),
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
                  _UserDetailRow(label: 'User ID', value: userId),
                  _UserDetailRow(
                    label: 'Active Hike Room',
                    value:
                        activeHikeRoomId != null && activeHikeRoomId.isNotEmpty
                        ? activeHikeRoomId
                        : 'None',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (widget.access.isTourismAdmin && hasAdminAccess)
              TextButton.icon(
                onPressed: () =>
                    _manageUserAccount(dialogContext, userId, 'revoke_admin'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Revoke Admin'),
              ),
            if (widget.access.isTourismAdmin) ...[
              TextButton.icon(
                onPressed: () => _manageUserAccount(
                  dialogContext,
                  userId,
                  isSuspended ? 'restore' : 'suspend',
                ),
                icon: Icon(
                  isSuspended ? Icons.lock_open_outlined : Icons.block,
                ),
                label: Text(
                  isSuspended ? 'Restore Account' : 'Suspend Account',
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _manageUserAccount(dialogContext, userId, 'delete'),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
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
  String _adminRole = 'tourism_admin';
  String? _error;
  String? _resetLink;
  String? _createdAdminRole;
  String? _createdMountainName;

  String? _managedMountainName;

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
            'adminRole': _adminRole,
            if (_adminRole == 'mountain_head')
              'managedMountainName': _managedMountainName,
          });
      final createdRole = result.data['adminRole'];
      final createdMountain = result.data['managedMountainName'];
      if (createdRole != _adminRole ||
          (_adminRole == 'mountain_head' &&
              createdMountain != _managedMountainName)) {
        throw StateError(
          'Firebase did not confirm the selected admin role and mountain. '
          'The account may have been created with different access. '
          'Check the user profile before sharing the password setup link.',
        );
      }
      if (!mounted) return;
      setState(() {
        _resetLink = result.data['resetLink'] as String?;
        _createdAdminRole = createdRole as String;
        _createdMountainName = createdMountain as String?;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Could not create the account.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
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
                  Text(
                    'Assigned role: ${_createdAdminRole == 'mountain_head' ? 'Mountain Head' : 'Tourism Admin'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_createdAdminRole == 'mountain_head')
                    Text('Managed mountain: $_createdMountainName'),
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
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter the admin’s name.'
                          : null,
                    ),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(email)
                            ? null
                            : 'Enter a valid email address.';
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _adminRole,
                      decoration: const InputDecoration(
                        labelText: 'Admin role',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'tourism_admin',
                          child: Text('Tourism Admin — full access'),
                        ),
                        DropdownMenuItem(
                          value: 'mountain_head',
                          child: Text('Mountain Head — assigned mountain'),
                        ),
                      ],
                      onChanged: _creating
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  _adminRole = value;
                                  if (value != 'mountain_head') {
                                    _managedMountainName = null;
                                  }
                                });
                              }
                            },
                    ),
                    if (_adminRole == 'mountain_head')
                      DropdownButtonFormField<String>(
                        initialValue: _managedMountainName,
                        decoration: const InputDecoration(
                          labelText: 'Managed mountain',
                        ),
                        items: davaoMountains
                            .map(
                              (mountain) => DropdownMenuItem(
                                value: mountain.name,
                                child: Text(mountain.label),
                              ),
                            )
                            .toList(),
                        onChanged: _creating
                            ? null
                            : (value) =>
                                  setState(() => _managedMountainName = value),
                        validator: (value) {
                          if (_adminRole == 'mountain_head' && value == null) {
                            return 'Choose the managed mountain.';
                          }
                          return null;
                        },
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
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
  const _UserDetailRow({required this.label, required this.value});

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
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AuditLogsPage extends StatefulWidget {
  const _AuditLogsPage();

  @override
  State<_AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<_AuditLogsPage> {
  bool _backfilling = false;

  Future<void> _backfillOlderRecords() async {
    setState(() => _backfilling = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('backfillAuditLogNames')
          .call();
      if (!mounted) return;
      final updated = (result.data as Map?)?['updated'] ?? 0;
      await _showAccountActionResultDialog(
        context,
        success: true,
        title: 'Older Records Updated',
        message: updated == 0
            ? 'No older records needed fixing — everything already shows names/emails.'
            : 'Filled in the actor/target name or email on $updated older record(s).',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: false,
        title: 'Could Not Fix Older Records',
        message: error.message ?? 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

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
            padding: _adminPagePadding(context),
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
          padding: _adminPagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(
                    'Audit Logs (${logs.length})',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _backfilling ? null : _backfillOlderRecords,
                    icon: _backfilling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Fix Older Records'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _AuditLogsResponsiveTable(
                    logs: logs,
                    onOpenRecord: (log) =>
                        _showAuditRecord(context, log.id, log.data()),
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
    final action = data['action']?.toString() ?? 'unknown_action';
    final adminEmail = data['adminEmail']?.toString();
    final adminId = data['adminId']?.toString();
    final actorName = data['actorName']?.toString();
    final actorEmail = data['actorEmail']?.toString();
    final actorId = data['actorId']?.toString();
    final targetName = data['targetName']?.toString();
    final targetEmail = data['targetEmail']?.toString();
    final targetId = data['targetId']?.toString();
    final previous = data['previousStatus']?.toString();
    final next = data['newStatus']?.toString();
    final reason = data['reason']?.toString();
    final change = [
      if (previous != null && previous != 'null') previous,
      if (next != null && next != 'null') next,
    ].join(' → ');

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_actionVerb(action)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserDetailRow(
                  label: 'Date',
                  value: _formatTimestamp(data['createdAt']).isEmpty
                      ? 'Unknown'
                      : _formatTimestamp(data['createdAt']),
                ),
                _UserDetailRow(
                  label: 'Actor',
                  value:
                      actorName ??
                      actorEmail ??
                      adminEmail ??
                      actorId ??
                      adminId ??
                      '—',
                ),
                if (targetName != null)
                  _UserDetailRow(label: 'Target', value: targetName),
                if (targetEmail != null)
                  _UserDetailRow(
                    label: targetName != null ? 'Target Email' : 'Target',
                    value: targetEmail,
                  ),
                if (targetName == null &&
                    targetEmail == null &&
                    targetId != null)
                  _UserDetailRow(label: 'Target', value: targetId),
                if (data['roomCode'] != null)
                  _UserDetailRow(
                    label: 'Room',
                    value: data['roomCode'].toString(),
                  ),
                if (data['deviceName'] != null)
                  _UserDetailRow(
                    label: 'Bluetooth Device',
                    value: data['deviceName'].toString(),
                  ),
                if (data['transport'] != null)
                  _UserDetailRow(
                    label: 'SOS Transport',
                    value: data['transport'].toString(),
                  ),
                if (data['deletedSosEvents'] != null)
                  _UserDetailRow(
                    label: 'SOS Alerts Removed',
                    value: data['deletedSosEvents'].toString(),
                  ),
                if (data['deletedSosNotifications'] != null)
                  _UserDetailRow(
                    label: 'Notifications Removed',
                    value: data['deletedSosNotifications'].toString(),
                  ),
                if (change.isNotEmpty)
                  _UserDetailRow(label: 'Change', value: change),
                if (reason != null && reason.isNotEmpty && reason != 'null')
                  _UserDetailRow(label: 'Reason', value: reason),
              ],
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

class _AuditLogsResponsiveTable extends StatelessWidget {
  const _AuditLogsResponsiveTable({
    required this.logs,
    required this.onOpenRecord,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> logs;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onOpenRecord;

  Map<String, String> _values(QueryDocumentSnapshot<Map<String, dynamic>> log) {
    final data = log.data();
    final action = data['action']?.toString() ?? 'unknown_action';
    final previous = data['previousStatus']?.toString();
    final next = data['newStatus']?.toString();
    final actor =
        data['actorName']?.toString() ??
        data['actorEmail']?.toString() ??
        data['adminEmail']?.toString() ??
        data['submitterName']?.toString() ??
        data['actorId']?.toString() ??
        data['adminId']?.toString() ??
        data['submittedBy']?.toString() ??
        (action == 'auto_close_abandoned_room' ? 'System' : null);
    final target =
        data['targetName']?.toString() ??
        data['trailName']?.toString() ??
        data['mountainName']?.toString() ??
        data['targetEmail']?.toString() ??
        data['targetId']?.toString();
    final statusChange = [
      if (previous != null && previous != 'null') previous,
      if (next != null && next != 'null') next,
    ].join(' → ');

    return {
      'date': _formatTimestamp(data['createdAt']).isEmpty
          ? 'Unknown'
          : _formatTimestamp(data['createdAt']),
      'action': _actionVerb(action),
      'actor': actor ?? '—',
      'target': target ?? '—',
      'status': statusChange.isEmpty ? '—' : statusChange,
    };
  }

  Widget _cell(String value, {bool header = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Text(
      value,
      softWrap: true,
      maxLines: header ? 2 : null,
      overflow: header ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontWeight: header ? FontWeight.w700 : FontWeight.normal,
        fontSize: header ? 12 : 13,
      ),
    ),
  );

  Widget _mobileRecord(QueryDocumentSnapshot<Map<String, dynamic>> log) {
    final values = _values(log);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    values['action']!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    softWrap: true,
                  ),
                ),
                TextButton(
                  onPressed: () => onOpenRecord(log),
                  child: const Text('View details'),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final entry in [
              MapEntry('Date', values['date']!),
              MapEntry('Actor', values['actor']!),
              MapEntry('Target', values['target']!),
              MapEntry('Status change', values['status']!),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 94,
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Text(entry.value, softWrap: true)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  TableRow _desktopRecord(QueryDocumentSnapshot<Map<String, dynamic>> log) {
    final values = _values(log);
    return TableRow(
      children: [
        _cell(values['date']!),
        _cell(values['action']!),
        _cell(values['actor']!),
        _cell(values['target']!),
        _cell(values['status']!),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: TextButton(
            onPressed: () => onOpenRecord(log),
            child: const Text(
              'View details',
              softWrap: true,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: logs.length,
            itemBuilder: (context, index) => _mobileRecord(logs[index]),
          );
        }

        return SingleChildScrollView(
          child: Table(
            border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFE5E7E6)),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1.15),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.45),
              3: FlexColumnWidth(1.35),
              4: FlexColumnWidth(1.2),
              5: FlexColumnWidth(0.9),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF7F8F7)),
                children: [
                  _cell('Date', header: true),
                  _cell('Action', header: true),
                  _cell('Actor', header: true),
                  _cell('Target', header: true),
                  _cell('Status Change', header: true),
                  _cell('Record', header: true),
                ],
              ),
              for (final log in logs) _desktopRecord(log),
            ],
          ),
        );
      },
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
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Coming soon.', style: TextStyle(color: Colors.black45)),
      ],
    ),
  );
}
