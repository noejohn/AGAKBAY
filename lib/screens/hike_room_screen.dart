import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:tunga/services/hike_room_service.dart';
import 'package:tunga/widgets/offline_map_widget.dart';

class HikeRoomScreen extends StatefulWidget {
  const HikeRoomScreen({super.key, this.onStartHiking});

  final Future<void> Function(HikeRoom room)? onStartHiking;

  @override
  State<HikeRoomScreen> createState() => _HikeRoomScreenState();
}

class _HikeRoomScreenState extends State<HikeRoomScreen> {
  final HikeRoomService _service = HikeRoomService();
  final TextEditingController _codeController = TextEditingController();

  HikeRoom? _room;
  String _accountType = 'hiker';
  bool _loading = true;
  bool _submitting = false;

  bool get _isGuide => _accountType == 'tour_guide';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await _service.getCurrentUserProfile();
      final room = await _service.getActiveRoom();
      if (!mounted) return;
      setState(() {
        _accountType = _service.accountTypeFromProfile(profile);
        _room = room;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message(_errorText(error));
    }
  }

  Future<void> _joinRoom() async {
    await _run(() async {
      final room = await _service.joinRoom(_codeController.text);
      if (mounted) setState(() => _room = room);
    });
  }

  Future<void> _startRoom(String roomId) async {
    await _run(() => _service.startRoom(roomId));
  }

  Future<void> _endRoom(String roomId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this hike room?'),
        content: const Text(
          'All participants will be removed from the active room. The SOS log remains available in Firestore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Room'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _service.endRoom(roomId);
      if (mounted) setState(() => _room = null);
    });
  }

  Future<void> _leaveRoom(String roomId) async {
    await _run(() async {
      await _service.leaveRoom(roomId);
      if (mounted) setState(() => _room = null);
    });
  }

  Future<void> _kickParticipant(
    HikeRoom room,
    HikeRoomParticipant participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${participant.name}?'),
        content: const Text(
          'This hiker will lose access to the room and its active SOS session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _service.kickParticipant(room.id, participant.userId);
      _message('${participant.name} was removed from the room.');
    });
  }

  Future<void> _openHikingMode(HikeRoom room) async {
    final callback = widget.onStartHiking;
    if (callback == null) {
      _message('Open this room from the main app to start Hiking Mode.');
      return;
    }
    try {
      await _service.setCurrentParticipantHiking(room.id, isHiking: true);
      await callback(room);
    } catch (error) {
      _message(_errorText(error));
    } finally {
      try {
        await _service.setCurrentParticipantHiking(room.id, isHiking: false);
      } catch (_) {
        // The guide may have removed the participant while they were hiking.
      }
    }
  }

  Future<void> _sendSos(String roomId) async {
    await _run(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services before sending SOS.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission is required for SOS.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _service.sendSos(
        roomId: roomId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _message('SOS sent to the Tour Guide through the internet.');
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await operation();
    } catch (error) {
      _message(_errorText(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Hike SOS Room'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _room == null
          ? _buildRoomEntry()
          : StreamBuilder<HikeRoom?>(
              stream: _service.watchRoom(_room!.id),
              initialData: _room,
              builder: (context, snapshot) {
                final room = snapshot.data;
                if (room == null || room.status == HikeRoomStatus.ended) {
                  return const Center(child: Text('This room has ended.'));
                }
                _room = room;
                if (_isGuide) return _buildActiveRoom(room);
                return StreamBuilder<String>(
                  stream: _service.watchCurrentMembership(room.id),
                  initialData: 'active',
                  builder: (context, membershipSnapshot) {
                    final membership = membershipSnapshot.data ?? 'active';
                    if (membership != 'active') {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_remove_rounded,
                                size: 54,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'You are no longer in this room.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Back'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return _buildActiveRoom(room);
                  },
                );
              },
            ),
    );
  }

  Widget _buildRoomEntry() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            _isGuide ? Icons.groups_rounded : Icons.hiking_rounded,
            size: 62,
            color: const Color(0xFF53D97A),
          ),
          const SizedBox(height: 16),
          Text(
            _isGuide ? 'Choose a mountain first' : 'Join your Tour Guide',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _isGuide
                ? 'Open Explore, search for a mountain, select its trail route, then tap Create Hike Room. This ensures every hiker receives the same route.'
                : 'Enter the 6-digit code supplied by your Tour Guide.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          if (_isGuide)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Go Back to Explore'),
            )
          else ...[
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _joinRoom(),
              decoration: const InputDecoration(
                labelText: 'Room code',
                hintText: '123456',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pin_rounded),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _submitting ? null : _joinRoom,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Join Room'),
            ),
          ],
          const SizedBox(height: 24),
          const _HeltecStatusCard(),
        ],
      ),
    );
  }

  Widget _buildActiveRoom(HikeRoom room) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.mountainName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Chip(label: Text(room.status.name.toUpperCase())),
                    ],
                  ),
                  Text('Tour Guide: ${room.guideName}'),
                  const SizedBox(height: 14),
                  const Text('ROOM CODE'),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.code,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                letterSpacing: 7,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy room code',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: room.code),
                          );
                          _message('Room code copied.');
                        },
                        icon: const Icon(Icons.copy_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (room.routePoints.length >= 2) ...[
            const SizedBox(height: 12),
            _SharedRouteMap(room: room),
          ],
          const SizedBox(height: 10),
          const _HeltecStatusCard(),
          const SizedBox(height: 18),
          Text(
            'Participants',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<HikeRoomParticipant>>(
            stream: _service.watchParticipants(room.id),
            builder: (context, snapshot) {
              final participants = snapshot.data ?? const [];
              if (participants.isEmpty) {
                return const Text('Waiting for participants...');
              }
              return Card(
                child: Column(
                  children: participants
                      .map((participant) {
                        final isReady = participant.deviceStatus == 'connected';
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              participant.role == 'tour_guide'
                                  ? Icons.emoji_people_rounded
                                  : Icons.hiking_rounded,
                            ),
                          ),
                          title: Text(participant.name),
                          subtitle: Text(
                            '${participant.role == 'tour_guide' ? 'Tour Guide' : 'Hiker'} • '
                            '${participant.activityStatus == 'hiking' ? 'Hiking' : 'In room'}',
                          ),
                          trailing: _isGuide && participant.role != 'tour_guide'
                              ? IconButton(
                                  tooltip: 'Remove participant',
                                  onPressed: _submitting
                                      ? null
                                      : () =>
                                            _kickParticipant(room, participant),
                                  icon: const Icon(
                                    Icons.person_remove_rounded,
                                    color: Colors.redAccent,
                                  ),
                                )
                              : Tooltip(
                                  message: isReady
                                      ? 'Heltec connected'
                                      : 'Heltec protocol not connected',
                                  child: Icon(
                                    isReady
                                        ? Icons.bluetooth_connected_rounded
                                        : Icons.bluetooth_disabled_rounded,
                                    color: isReady
                                        ? Colors.greenAccent
                                        : Colors.orange,
                                  ),
                                ),
                        );
                      })
                      .toList(growable: false),
                ),
              );
            },
          ),
          if (_isGuide) ...[
            const SizedBox(height: 20),
            Text(
              'SOS Alerts',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _SosList(roomId: room.id, service: _service),
          ],
          const SizedBox(height: 22),
          if (_isGuide && room.status == HikeRoomStatus.waiting)
            FilledButton.icon(
              onPressed: _submitting ? null : () => _startRoom(room.id),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Hike Session'),
            ),
          if (room.status == HikeRoomStatus.active) ...[
            FilledButton.icon(
              onPressed: _submitting ? null : () => _openHikingMode(room),
              icon: const Icon(Icons.hiking_rounded),
              label: const Text('START HIKING'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF53D97A),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_isGuide && room.status == HikeRoomStatus.active)
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _endRoom(room.id),
              icon: const Icon(Icons.stop_circle_rounded),
              label: const Text('End Hike Room'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
            ),
          if (!_isGuide && room.status == HikeRoomStatus.active)
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _sendSos(room.id),
              icon: const Icon(Icons.sos_rounded),
              label: const Text('Send SOS from Room'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
            ),
          if (!_isGuide && room.status == HikeRoomStatus.waiting)
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _leaveRoom(room.id),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Leave Room'),
            ),
        ],
      ),
    );
  }
}

class _SharedRouteMap extends StatelessWidget {
  const _SharedRouteMap({required this.room});

  final HikeRoom room;

  @override
  Widget build(BuildContext context) {
    final points = room.routePoints
        .map((point) => ll.LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final markers = <fm.Marker>[
      fm.Marker(
        point: points.first,
        width: 42,
        height: 42,
        child: const Icon(
          Icons.trip_origin_rounded,
          color: Color(0xFF53D97A),
          size: 34,
        ),
      ),
      fm.Marker(
        point: points.last,
        width: 42,
        height: 42,
        child: const Icon(
          Icons.flag_rounded,
          color: Color(0xFFFFD76A),
          size: 34,
        ),
      ),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.routeName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (room.jumpOffLabel.isNotEmpty)
                  Text('Jump-off: ${room.jumpOffLabel}'),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: OfflineMapWidget(
              initialLatitude: points.first.latitude,
              initialLongitude: points.first.longitude,
              initialZoom: 14,
              markers: markers,
              polylines: [
                fm.Polyline(
                  points: points,
                  color: const Color(0xFF53D97A),
                  strokeWidth: 5,
                ),
              ],
              showScaleLayer: false,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text('This route was selected by your Tour Guide.'),
          ),
        ],
      ),
    );
  }
}

class _HeltecStatusCard extends StatelessWidget {
  const _HeltecStatusCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.withValues(alpha: 0.12),
      child: const ListTile(
        leading: Icon(Icons.bluetooth_disabled_rounded, color: Colors.orange),
        title: Text('Heltec device: Not connected'),
        subtitle: Text(
          'Room and internet SOS are working. The Heltec BLE/LoRa protocol must be integrated before offline radio SOS can be enabled.',
        ),
      ),
    );
  }
}

class _SosList extends StatelessWidget {
  const _SosList({required this.roomId, required this.service});

  final String roomId;
  final HikeRoomService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomSosEvent>>(
      stream: service.watchSosEvents(roomId),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const [];
        if (events.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('No SOS alerts'),
            ),
          );
        }
        return Column(
          children: events
              .map((event) {
                final acknowledged = event.status == 'acknowledged';
                return Card(
                  color: acknowledged
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.18),
                  child: ListTile(
                    leading: Icon(
                      acknowledged ? Icons.done_all_rounded : Icons.sos_rounded,
                      color: acknowledged
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    title: Text('${event.senderName} sent SOS'),
                    subtitle: Text(
                      '${event.latitude.toStringAsFixed(6)}, ${event.longitude.toStringAsFixed(6)}',
                    ),
                    trailing: acknowledged
                        ? const Text('ACKNOWLEDGED')
                        : FilledButton(
                            onPressed: () async {
                              try {
                                await service.acknowledgeSos(roomId, event.id);
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            },
                            child: const Text('Acknowledge'),
                          ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}
