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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          selected: _selected,
          onSelect: (i) => setState(() => _selected = i),
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
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, searchConstraints) {
                                final searchWidth = searchConstraints.maxWidth
                                    .clamp(80.0, 320.0)
                                    .toDouble();
                                return Center(
                                  child: SizedBox(
                                    width: searchWidth,
                                    height: 42,
                                    child: _AdminGlobalSearch(
                                      onNavigate: (index) =>
                                          setState(() => _selected = index),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          _NotificationBell(
                            onOpenSosMonitoring: () =>
                                setState(() => _selected = 4),
                            onOpenAuditLogs: () =>
                                setState(() => _selected = 7),
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
                      onNavigate: (index) => setState(() => _selected = index),
                    ),
                    1 => const _TourGuideVerificationPage(),
                    2 => const _TrailVerificationPage(),
                    3 => const _HikeRoomMonitoringPage(),
                    4 => const _SosMonitoringPage(),
                    5 => const _BluetoothDevicesPage(),
                    6 => const _UserManagementPage(),
                    7 => const _AuditLogsPage(),
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

class _AdminSearchResult {
  const _AdminSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.destination,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int destination;
}

class _AdminGlobalSearch extends StatefulWidget {
  const _AdminGlobalSearch({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<_AdminGlobalSearch> createState() => _AdminGlobalSearchState();
}

class _AdminGlobalSearchState extends State<_AdminGlobalSearch> {
  final _controller = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool _matches(
    Map<String, dynamic> data,
    String id,
    String query,
    List<String> fields,
  ) {
    final searchable = [
      id,
      for (final field in fields) data[field]?.toString() ?? '',
    ].join(' ').toLowerCase();
    return searchable.contains(query);
  }

  Future<void> _search() async {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final database = FirebaseFirestore.instance;
      final snapshots = await Future.wait([
        database.collection('users').limit(300).get(),
        database.collection('trail_submissions').limit(300).get(),
        database.collection('mountain_trails').limit(300).get(),
      ]);
      if (!mounted) return;

      final results = <_AdminSearchResult>[];
      final userFields = [
        'fullName',
        'displayName',
        'name',
        'email',
        'username',
      ];
      for (final doc in snapshots[0].docs) {
        final data = doc.data();
        if (!_matches(data, doc.id, query, userFields)) continue;
        results.add(
          _AdminSearchResult(
            title:
                _firstValue(data, ['fullName', 'displayName', 'name']) ??
                _firstValue(data, ['email']) ??
                doc.id,
            subtitle: 'User · ${_firstValue(data, ['email']) ?? doc.id}',
            icon: Icons.person_outline_rounded,
            destination: 6,
          ),
        );
      }

      final trailFields = [
        'trailName',
        'mountainName',
        'name',
        'title',
        'submitterName',
        'submitterEmail',
        'status',
      ];
      for (final doc in snapshots[1].docs) {
        final data = doc.data();
        if (!_matches(data, doc.id, query, trailFields)) continue;
        results.add(
          _AdminSearchResult(
            title:
                _firstValue(data, [
                  'trailName',
                  'mountainName',
                  'title',
                  'name',
                ]) ??
                doc.id,
            subtitle:
                'Trail submission · ${_firstValue(data, ['status']) ?? 'unknown status'}',
            icon: Icons.route_outlined,
            destination: 2,
          ),
        );
      }

      final mountainFields = [
        'mountainName',
        'name',
        'title',
        'region',
        'province',
      ];
      for (final doc in snapshots[2].docs) {
        final data = doc.data();
        if (!_matches(data, doc.id, query, mountainFields)) continue;
        results.add(
          _AdminSearchResult(
            title: _firstValue(data, mountainFields) ?? doc.id,
            subtitle:
                'Mountain trail · ${_firstValue(data, ['status']) ?? 'available'}',
            icon: Icons.terrain_rounded,
            destination: 2,
          ),
        );
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Search results for “${_controller.text.trim()}”'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: results.isEmpty
                ? const Center(
                    child: Text(
                      'No matching mountains, users, or trails found.',
                    ),
                  )
                : ListView.separated(
                    itemCount: results.length > 30 ? 30 : results.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return ListTile(
                        leading: Icon(result.icon, color: AdminColors.accent),
                        title: Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          result.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          widget.onNavigate(result.destination);
                        },
                      );
                    },
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 220;
        final veryCompact = constraints.maxWidth < 160;
        return TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: compact
                ? 'Search...'
                : 'Search mountains, users, trails...',
            prefixIcon: veryCompact ? null : const Icon(Icons.search_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_controller.text.isEmpty || !compact)
                  IconButton(
                    tooltip: 'Search',
                    onPressed: _search,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
              ],
            ),
            filled: true,
            fillColor: const Color(0xFFF4F7F8),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDCE5E9)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDCE5E9)),
            ),
          ),
        );
      },
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
  const _Sidebar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
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
              itemCount: _navItems.length,
              itemBuilder: (context, i) {
                final item = _navItems[i];
                final isSelected = i == selected;
                final section = i == 0
                    ? 'OVERVIEW'
                    : i == 1
                    ? 'VERIFICATION'
                    : i == 3
                    ? 'OPERATIONS'
                    : i == 6
                    ? 'MANAGEMENT'
                    : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section != null && !collapsed && !shortScreen)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : 22,
                          i == 0 ? 0 : 18,
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
                            onTap: () => onSelect(i),
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
            onOpenAuditLogs: widget.onOpenAuditLogs,
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
    required this.onOpenAuditLogs,
    required this.width,
    required this.listHeight,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications;
  final VoidCallback onOpenSosMonitoring;
  final VoidCallback onOpenAuditLogs;
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
                      final notificationRef = FirebaseFirestore.instance
                          .collection('notifications')
                          .doc(notification.id);

                      // Mark only this notification as read.
                      if (!isRead) {
                        await notificationRef.update({'isRead': true});
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
  const _DashboardOverviewPage({required this.user, required this.onNavigate});

  final User user;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final pendingGuidesQuery = FirebaseFirestore.instance
        .collection('tour_guide_applications')
        .where('status', isEqualTo: 'pending');
    final pendingTrailsQuery = FirebaseFirestore.instance
        .collection('trail_submissions')
        .where('status', isEqualTo: 'pending');
    final activeRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active');
    final activeSosQuery = FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .where('status', isEqualTo: 'sent');
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 24),
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
          _OverviewQuickPanels(onNavigate: onNavigate),
          const SizedBox(height: 20),
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
          const _RecentActivityPanel(),
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
  const _OverviewQuickPanels({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final rooms = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', isEqualTo: 'active')
        .snapshots();
    final sos = FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .where('status', isEqualTo: 'sent')
        .snapshots();
    final width = MediaQuery.sizeOf(context).width;
    final roomCard = GestureDetector(
      onTap: () => onNavigate(3),
      child: _SectionCard(
        title: 'Active Hike Rooms',
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: rooms,
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
          stream: sos,
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
  const _GuideApplicationCard({
    required this.applicationId,
    required this.data,
    this.onReviewed,
  });

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
      await FirebaseFunctions.instance
          .httpsCallable('reviewTourGuideApplication')
          .call({'applicationId': widget.applicationId, 'decision': decision});
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
                const Text(
                  'Government ID',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (idUrl != null)
                  Image.network(idUrl, fit: BoxFit.contain)
                else
                  const Text(
                    'Not provided.',
                    style: TextStyle(color: Colors.black45),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Certificate',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (certUrl != null)
                  Image.network(certUrl, fit: BoxFit.contain)
                else
                  const Text(
                    'Not provided.',
                    style: TextStyle(color: Colors.black45),
                  ),
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
                  onPressed: _submitting
                      ? null
                      : () => _notWiredUp('"Request changes"'),
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
  final zoom = spanDegrees == 0
      ? 15.0
      : (14 - (spanDegrees * 100)).clamp(9.0, 15.0);
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
  const _TrailSubmissionCard({required this.submissionId, required this.data});

  final String submissionId;
  final Map<String, dynamic> data;

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
          decision == 'approve' ? 'Approve this trail?' : 'Reject this trail?',
        ),
        content: Text(
          decision == 'approve'
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
      await FirebaseFunctions.instance
          .httpsCallable('reviewTrailSubmission')
          .call({'submissionId': widget.submissionId, 'decision': decision});
      if (!mounted) return;
      await _showAccountActionResultDialog(
        context,
        success: true,
        title: decision == 'approve' ? 'Trail Approved' : 'Trail Rejected',
        message: decision == 'approve'
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
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _reviewing ? null : () => _review('reject'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('"Request changes" isn\'t wired up yet.'),
                    ),
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

class _HikeRoomMonitoringPage extends StatelessWidget {
  const _HikeRoomMonitoringPage();

  @override
  Widget build(BuildContext context) {
    final currentRoomsQuery = FirebaseFirestore.instance
        .collection('hike_rooms')
        .where('status', whereIn: ['waiting', 'active']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
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
  const _SosMonitoringPage();

  @override
  State<_SosMonitoringPage> createState() => _SosMonitoringPageState();
}

class _SosMonitoringPageState extends State<_SosMonitoringPage> {
  bool _cleaningOrphanedAlerts = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _sosEventsStream() {
    return FirebaseFirestore.instance
        .collectionGroup('sos_events')
        .orderBy('createdAt', descending: true)
        .snapshots();
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
        final acknowledgedCount = events
            .where(
              (event) => event.data()['status']?.toString() == 'acknowledged',
            )
            .length;
        final unacknowledgedEvents = events
            .where(
              (event) => event.data()['status']?.toString() != 'acknowledged',
            )
            .toList(growable: false);
        final sosPoints = unacknowledgedEvents
            .map((event) {
              final data = event.data();
              final latitude = (data['latitude'] as num?)?.toDouble();
              final longitude = (data['longitude'] as num?)?.toDouble();
              if (latitude == null || longitude == null) return null;
              return _SosMapPoint(
                eventId: event.id,
                senderName: data['senderName']?.toString().trim() ?? '',
                latitude: latitude,
                longitude: longitude,
              );
            })
            .whereType<_SosMapPoint>()
            .toList(growable: false);

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(
              'SOS Monitoring',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Live SOS events from Firebase.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined),
                label: const Text('Remove SOS from deleted users'),
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
              child: Row(
                children: [
                  Icon(
                    Icons.warning_rounded,
                    color: unacknowledgedEvents.isEmpty
                        ? const Color(0xFF12805A)
                        : const Color(0xFFD92F3D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${events.length} total SOS alert${events.length == 1 ? '' : 's'}',
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
                        '$acknowledgedCount acknowledged',
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

            if (events.isEmpty)
              const _SosPageMessage(
                icon: Icons.check_circle_outline_rounded,
                message: 'No SOS alerts recorded.',
                detail:
                    'New alerts will appear here when a hiker sends an SOS.',
              )
            else ...[
              if (unacknowledgedEvents.isNotEmpty && sosPoints.isNotEmpty) ...[
                _SosRoomMap(points: sosPoints),
                const SizedBox(height: 18),
              ],
              ...events.map((event) {
                final data = event.data();
                final roomId =
                    data['roomId']?.toString() ??
                    event.reference.parent.parent?.id ??
                    '';
                return _SosAlertCard(roomId: roomId, eventData: data);
              }),
            ],
          ],
        );
      },
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

class _SosRoomMap extends StatefulWidget {
  const _SosRoomMap({required this.points});

  final List<_SosMapPoint> points;

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
    if (widget.points.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstPoint = widget.points.first;

    final markers = widget.points.map((point) {
      return Marker(
        markerId: MarkerId(point.eventId),
        position: LatLng(point.latitude, point.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: point.senderName.isEmpty
              ? 'SOS alert'
              : 'SOS: ${point.senderName}',
          snippet:
              '${point.latitude.toStringAsFixed(6)}, '
              '${point.longitude.toStringAsFixed(6)}',
        ),
      );
    }).toSet();

    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(firstPoint.latitude, firstPoint.longitude),
          zoom: 14,
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
  const _SosAlertCard({required this.roomId, required this.eventData});

  final String roomId;
  final Map<String, dynamic> eventData;

  @override
  Widget build(BuildContext context) {
    final senderName = eventData['senderName']?.toString().trim() ?? '';

    final acknowledged = eventData['status']?.toString() == 'acknowledged';

    final latitude = (eventData['latitude'] as num?)?.toDouble();
    final longitude = (eventData['longitude'] as num?)?.toDouble();

    final createdAt = eventData['createdAt'];
    final DateTime? createdTime = createdAt is Timestamp
        ? createdAt.toDate()
        : null;
    final acknowledgedAt = eventData['acknowledgedAt'];

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
                  acknowledged ? Icons.check_circle_rounded : Icons.sos_rounded,
                  color: acknowledged
                      ? const Color(0xFF12805A)
                      : Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: senderName.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          'SOS from $senderName',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: (acknowledged ? const Color(0xFF12805A) : Colors.red)
                        .withValues(alpha: 0.15),
                  ),
                  child: Text(
                    acknowledged ? 'ACKNOWLEDGED' : 'NOT ACKNOWLEDGED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: acknowledged
                          ? const Color(0xFF12805A)
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
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: Color(0xFF12805A),
                  ),
                  const SizedBox(width: 8),
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
      padding: const EdgeInsets.all(28),
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
                    final name =
                        data['displayName']?.toString().trim().isNotEmpty ==
                            true
                        ? data['displayName'].toString().trim()
                        : (data['deviceName']?.toString() ?? 'Heltec device');
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
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                                label: const Text('Rename'),
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
  const _UserManagementPage();

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
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'View and manage AGAKBAY user and admin accounts.',
            style: TextStyle(color: Colors.black54),
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
                DropdownMenuItem(
                  value: 'all',
                  child: Text('All account types'),
                ),
                DropdownMenuItem(value: 'hiker', child: Text('Hiker')),
                DropdownMenuItem(
                  value: 'tour_guide',
                  child: Text('Tour Guide'),
                ),
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
    final descriptions = <String, String>{
      'revoke_admin': 'Remove this user\'s admin access?',
      'suspend':
          'Suspend this account? They will be signed out and unable to sign in.',
      'restore': 'Restore this account\'s access?',
      'delete':
          'Permanently delete this sign-in account and its user profile? Authored activity records may remain.',
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
          'The sign-in account and profile data have been permanently deleted.',
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
        message: error.message ?? 'Something went wrong. Please try again.',
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
            if (hasAdminAccess)
              TextButton.icon(
                onPressed: () =>
                    _manageUserAccount(dialogContext, userId, 'revoke_admin'),
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
              onPressed: () =>
                  _manageUserAccount(dialogContext, userId, 'delete'),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text(
                'Delete Account',
                style: TextStyle(color: Colors.red),
              ),
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
      setState(
        () => _error = 'Could not create the account. Please try again.',
      );
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
              Row(
                children: [
                  Text(
                    'Audit Logs (${logs.length})',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
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
                          final action =
                              data['action']?.toString() ?? 'unknown_action';
                          final previous = data['previousStatus']?.toString();
                          final next = data['newStatus']?.toString();
                          // Prefers the human-readable email/name written at
                          // the time of the action; falls back to the raw
                          // uid only for older records written before that
                          // enrichment existed.
                          final actor =
                              data['adminEmail']?.toString() ??
                              data['submitterName']?.toString() ??
                              data['adminId']?.toString() ??
                              data['submittedBy']?.toString() ??
                              (action == 'auto_close_abandoned_room'
                                  ? 'System'
                                  : null);
                          final target =
                              data['targetName']?.toString() ??
                              data['trailName']?.toString() ??
                              data['mountainName']?.toString() ??
                              data['targetEmail']?.toString() ??
                              data['targetId']?.toString();
                          final statusChange = [
                            if (previous != null && previous != 'null')
                              previous,
                            if (next != null && next != 'null') next,
                          ].join(' → ');
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  _formatTimestamp(data['createdAt']).isEmpty
                                      ? 'Unknown'
                                      : _formatTimestamp(data['createdAt']),
                                ),
                              ),
                              DataCell(Text(_actionVerb(action))),
                              DataCell(Text(actor ?? '—')),
                              DataCell(Text(target ?? '—')),
                              DataCell(
                                Text(statusChange.isEmpty ? '—' : statusChange),
                              ),
                              DataCell(
                                TextButton(
                                  onPressed: () =>
                                      _showAuditRecord(context, log.id, data),
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
    final action = data['action']?.toString() ?? 'unknown_action';
    final adminEmail = data['adminEmail']?.toString();
    final adminId = data['adminId']?.toString();
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
                  label: 'Admin',
                  value: adminEmail ?? adminId ?? '—',
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
