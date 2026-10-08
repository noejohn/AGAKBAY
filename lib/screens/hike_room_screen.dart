import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:tunga/services/heltec_ble_service.dart';
import 'package:tunga/services/hike_room_service.dart';
import 'package:tunga/widgets/offline_map_widget.dart';
import 'package:tunga/widgets/sos_reason_picker.dart';

class HikeRoomScreen extends StatefulWidget {
  const HikeRoomScreen({super.key, this.onStartHiking, this.onBeforeJoinRoom});

  final Future<void> Function(HikeRoom room)? onStartHiking;
  final Future<bool> Function()? onBeforeJoinRoom;

  @override
  State<HikeRoomScreen> createState() => _HikeRoomScreenState();
}

class _HikeRoomScreenState extends State<HikeRoomScreen>
    with WidgetsBindingObserver {
  final HikeRoomService _service = HikeRoomService();
  VoidCallback? _bleListener;
  String? _activeRoomId;
  final TextEditingController _codeController = TextEditingController();

  StreamSubscription<Position>? _locationSubscription;

  HikeRoom? _room;
  String _accountType = 'hiker';
  String _displayName = 'Hiker';
  bool _loading = true;
  bool _submitting = false;
  bool _openingHikingMode = false;

  Timer? _heartbeatTimer;
  String? _heartbeatRoomId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  bool get _isGuide => _accountType == 'tour_guide';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _load();

    final ble = HeltecBleService.instance;

    _bleListener = () {
      final roomId = _activeRoomId;

      if (roomId == null) {
        return;
      }

      final deviceId = ble.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        return;
      }

      unawaited(
        _service
            .updateCurrentParticipantDeviceStatus(
              roomId,
              deviceStatus: ble.isConnected ? 'connected' : 'disconnected',
              deviceId: deviceId,
              deviceName: ble.deviceName,
            )
            .catchError((Object error) {
              debugPrint('Could not record Bluetooth activity: $error');
            }),
      );
    };

    ble.addListener(_bleListener!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    HeltecBleService.instance.removeListener(_bleListener!);
    _locationSubscription?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _sendHeartbeatIfResumed();
    }
  }

  // Only keeps the guide's active room "alive" while their app is actually
  // in the foreground — a backgrounded/closed app simply stops refreshing
  // guideLastActiveAt, and closeAbandonedHikeRooms auto-ends the room once
  // that goes stale, without disrupting a guide who briefly switches apps.
  void _ensureHeartbeat(HikeRoom room) {
    if (!_isGuide || room.status != HikeRoomStatus.active) {
      _stopHeartbeat();
      return;
    }
    if (_heartbeatRoomId == room.id && _heartbeatTimer != null) return;
    _stopHeartbeat();
    _heartbeatRoomId = room.id;
    _sendHeartbeatIfResumed();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _sendHeartbeatIfResumed(),
    );
  }

  void _sendHeartbeatIfResumed() {
    if (_lifecycleState != AppLifecycleState.resumed) return;
    final roomId = _heartbeatRoomId;
    if (roomId == null) return;
    unawaited(
      _service.sendGuideHeartbeat(roomId).catchError((Object error) {
        debugPrint('Could not send guide heartbeat: $error');
      }),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatRoomId = null;
  }

  Future<void> _load() async {
    try {
      final profile = await _service.getCurrentUserProfile();
      final room = await _service.getActiveRoom();
      if (!mounted) return;
      setState(() {
        _accountType = _service.accountTypeFromProfile(profile);
        _displayName = _service.displayName(profile);
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
    final beforeJoin = widget.onBeforeJoinRoom;
    if (!_isGuide && beforeJoin != null && !await beforeJoin()) return;
    if (!mounted) return;
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
      _stopHeartbeat();
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

    // Guards the whole Hiking Mode session — a second tap while it's
    // opening (or already open) must never push a second Hiking Mode.
    if (_openingHikingMode) return;
    setState(() => _openingHikingMode = true);

    try {
      _activeRoomId = room.id;

      // Neither of these is awaited before opening Hiking Mode: the
      // Firestore write only completes once the server acknowledges it
      // (never, with no signal at the trailhead), and a high-accuracy GPS
      // fix can take several seconds — both used to leave the button
      // looking dead, so hikers tapped it again.
      unawaited(
        _service
            .setCurrentParticipantHiking(room.id, isHiking: true)
            .catchError((Object error) {
              debugPrint('Could not mark participant as hiking: $error');
            }),
      );
      unawaited(
        _startParticipantLocationTracking(room.id).catchError((Object error) {
          debugPrint('Could not start room location tracking: $error');
        }),
      );

      await callback(room);
    } catch (error) {
      _message(_errorText(error));
    } finally {
      if (mounted) setState(() => _openingHikingMode = false);
      await _stopParticipantLocationTracking();

      try {
        await _service.setCurrentParticipantHiking(room.id, isHiking: false);
      } catch (_) {
        // The guide may have removed the participant while they were hiking.
      }

      _activeRoomId = null;
    }
  }

  /// Shared by both SOS paths — the phone's own GPS works with zero
  /// signal (satellite-based, same as a dedicated GPS module would be),
  /// so this is safe to use for the offline device path too.
  Future<Position> _getPhoneLocation() async {
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
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _startParticipantLocationTracking(String roomId) async {
    await _stopParticipantLocationTracking();

    // Get an immediate GPS position so Firestore does not have to
    // wait for the first stream event.
    final initialPosition = await _getPhoneLocation();

    // The hike may already have ended while that GPS fix was coming in —
    // don't start a stream nobody will ever stop.
    if (_activeRoomId != roomId) return;

    // Not awaited: a Firestore write only completes on server
    // acknowledgement, which with no signal would keep the live stream
    // below from ever starting. Offline writes still queue and sync later.
    unawaited(
      _service
          .updateCurrentParticipantLocation(
            roomId,
            latitude: initialPosition.latitude,
            longitude: initialPosition.longitude,
          )
          .catchError((Object error) {
            debugPrint('Could not record initial location: $error');
          }),
    );

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _locationSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) async {
            try {
              await _service.updateCurrentParticipantLocation(
                roomId,
                latitude: position.latitude,
                longitude: position.longitude,
              );
            } catch (_) {
              // Ignore individual location-update failures.
              // The next GPS position will try again.
            }
          },
        );
  }

  Future<void> _stopParticipantLocationTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  /// Sends the SOS through the internet AND the Heltec (when connected) at
  /// the same time — never one after the other, since on a weak mountain
  /// signal the internet attempt can hang for over a minute and the
  /// offline LoRa SOS must never wait behind it.
  Future<void> _sendSos(String roomId) async {
    final reason = await showSosReasonPicker(context);
    if (reason == null || !mounted) return;
    await _run(() async {
      // The Heltec's own onboard GPS module is unreliable on the current
      // hardware, so the phone's GPS supplies the coordinates for both
      // paths — the device just relays them over LoRa. Phone GPS works
      // with zero signal too.
      final position = await _getPhoneLocation();
      final ble = HeltecBleService.instance;

      var internetTimedOut = false;
      Object? internetError;

      Future<bool> sendByInternet() async {
        try {
          await _service.sendSos(
            roomId: roomId,
            latitude: position.latitude,
            longitude: position.longitude,
            reason: reason,
          );
          return true;
        } catch (error) {
          internetError = error;
          return false;
        }
      }

      Future<bool> sendByDevice() async {
        if (!ble.isConnected) return false;
        final sent = await ble.sendSos(
          hikerName: _displayName,
          latitude: position.latitude,
          longitude: position.longitude,
          reason: reason,
        );
        if (sent) {
          _message(
            'SOS ($reason) sent over the device. Still trying the internet...',
          );
        }
        return sent;
      }

      final results = await Future.wait([
        sendByInternet().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            internetTimedOut = true;
            return false;
          },
        ),
        sendByDevice(),
      ]);
      final byInternet = results[0];
      final byDevice = results[1];

      if (byInternet && byDevice) {
        _message('SOS ($reason) sent through the internet and your device.');
      } else if (byInternet) {
        _message(
          ble.isConnected
              ? 'SOS ($reason) sent through the internet. The device could not send it.'
              : 'SOS ($reason) sent through the internet.',
        );
      } else if (byDevice) {
        _message(
          internetTimedOut
              ? 'SOS ($reason) sent over the device. Weak signal — the internet could not confirm it yet.'
              : 'SOS ($reason) sent over the device — no internet needed.',
        );
      } else if (internetTimedOut) {
        throw StateError(
          'Weak signal — SOS not confirmed. Connect your Heltec device so SOS also works with no signal.',
        );
      } else {
        throw internetError ??
            StateError(ble.lastError ?? 'Failed to send SOS.');
      }
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
                  _stopHeartbeat();
                  return const Center(child: Text('This room has ended.'));
                }
                _room = room;
                _ensureHeartbeat(room);
                if (_isGuide) {
                  // Blocks leaving this screen (AppBar back, system back
                  // gesture/button) while a hike is active without first
                  // going through the same end-room confirmation as the
                  // explicit "End Room" button — otherwise the room is left
                  // dangling "active" with no one able to close it.
                  return PopScope(
                    canPop: room.status != HikeRoomStatus.active,
                    onPopInvokedWithResult: (didPop, result) async {
                      if (didPop) return;
                      await _endRoom(room.id);
                      if (mounted && _room == null) {
                        Navigator.of(this.context).pop();
                      }
                    },
                    child: _buildActiveRoom(room),
                  );
                }
                return StreamBuilder<String>(
                  stream: _service.watchCurrentMembership(room.id),
                  initialData: 'active',
                  builder: (context, membershipSnapshot) {
                    final membership = membershipSnapshot.data ?? 'active';
                    // 'stopped' (used "I Can't Continue") still counts as
                    // present — they keep SOS and location sharing in case
                    // they need help heading back down alone. Only 'left'/
                    // 'removed'/'room_ended' show the "no longer here" screen.
                    if (membership != 'active' && membership != 'stopped') {
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
          _HeltecStatusCard(isGuide: _isGuide),
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
            _SharedRouteMap(room: room, service: _service, roomId: room.id),
          ],
          const SizedBox(height: 10),
          _HeltecStatusCard(
            guideName: room.guideName,
            mountainName: room.mountainName,
            isGuide: _isGuide,
            service: _service,
            roomId: room.id,
          ),
          if (_isGuide)
            _GuideParticipantCountSync(
              mountainName: room.mountainName,
              service: _service,
              roomId: room.id,
            ),
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
          const SizedBox(height: 20),
          Text(
            'SOS Alerts',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _SosList(roomId: room.id, service: _service, isGuide: _isGuide),
          if (_isGuide) ...[
            const SizedBox(height: 20),
            Text(
              'Hikers Who Ended Their Hike',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _StoppedHikersList(roomId: room.id, service: _service),
            const _OfflineStopRelayCard(),
          ],
          const _OfflineSosRelayCard(),
          const SizedBox(height: 16),
          _HikeRoomPolicyCard(
            roomId: room.id,
            service: _service,
            isGuide: _isGuide,
          ),
          const SizedBox(height: 22),
          if (_isGuide && room.status == HikeRoomStatus.waiting)
            FilledButton.icon(
              onPressed: _submitting ? null : () => _startRoom(room.id),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Hike Session'),
            ),
          if (room.status == HikeRoomStatus.active) ...[
            // Hikers must agree to the Tour Guide Policy terms (checkbox in
            // _HikeRoomPolicyCard above) before they can start; the guide
            // isn't gated since the policy is written for hikers.
            StreamBuilder<HikeRoomParticipant?>(
              stream: _isGuide
                  ? null
                  : _service.watchCurrentParticipant(room.id),
              builder: (context, snapshot) {
                final accepted =
                    _isGuide || snapshot.data?.policyAcceptedAt != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          (_submitting || _openingHikingMode || !accepted)
                          ? null
                          : () => _openHikingMode(room),
                      icon: const Icon(Icons.hiking_rounded),
                      label: const Text('START HIKING'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF53D97A),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                    if (!accepted)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Agree to the Terms and Conditions in the Tour Guide Policy to start hiking.',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                  ],
                );
              },
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
          if (room.status == HikeRoomStatus.active) ...[
            // One SOS button for both paths — it uses whichever is
            // available (internet, and the Heltec when connected) at the
            // same time, the same way Hiking Mode's SOS does.
            FilledButton.icon(
              onPressed: _submitting ? null : () => _sendSos(room.id),
              icon: const Icon(Icons.sos_rounded),
              label: const Text('Send SOS'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!_isGuide && room.status == HikeRoomStatus.waiting)
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _leaveRoom(room.id),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Leave Room'),
            ),
          // Ending a hike now happens from Hiking Mode's End Hike (with a
          // reason) — this only shows the result: what was sent, and
          // whether the guide has seen it, over the internet OR the device.
          if (!_isGuide && room.status == HikeRoomStatus.active)
            StreamBuilder<HikeRoomParticipant?>(
              stream: _service.watchCurrentParticipant(room.id),
              builder: (context, snapshot) {
                final me = snapshot.data;
                if (me?.stopReason == null) return const SizedBox.shrink();
                return ListenableBuilder(
                  listenable: HeltecBleService.instance,
                  builder: (context, _) {
                    final seen =
                        me!.stopAcknowledged ||
                        HeltecBleService.instance.stopAcknowledgedOverLoraFor(
                          me.name,
                          since: me.stoppedAt,
                        );
                    return Card(
                      color: seen
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      child: ListTile(
                        leading: Icon(
                          seen ? Icons.done_all_rounded : Icons.flag_rounded,
                          color: seen ? Colors.greenAccent : Colors.orange,
                        ),
                        title: const Text('You ended your hike'),
                        subtitle: Text(
                          seen
                              ? '${me.stopReason} — your guide has seen this'
                              : '${me.stopReason} — waiting for your guide to see this',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SharedRouteMap extends StatelessWidget {
  const _SharedRouteMap({required this.room, this.service, this.roomId});

  final HikeRoom room;

  /// When set, pulls live SOS pins onto the map for every participant —
  /// the internet-sourced ones from Firestore and the offline one from
  /// [HeltecBleService]'s LoRa relay. Anyone in the room can be the one
  /// who needs help, hiker or guide, so this isn't role-restricted.
  final HikeRoomService? service;
  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final points = room.routePoints
        .map((point) => ll.LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final baseMarkers = <fm.Marker>[
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

    Widget buildMap(List<fm.Marker> sosMarkers) {
      return SizedBox(
        height: 300,
        child: OfflineMapWidget(
          initialLatitude: points.first.latitude,
          initialLongitude: points.first.longitude,
          initialZoom: 14,
          markers: [...baseMarkers, ...sosMarkers],
          polylines: [
            fm.Polyline(
              points: points,
              color: const Color(0xFF53D97A),
              strokeWidth: 5,
            ),
          ],
          showScaleLayer: false,
        ),
      );
    }

    Widget mapArea;
    final svc = service;
    final id = roomId;
    if (svc != null && id != null) {
      mapArea = StreamBuilder<List<RoomSosEvent>>(
        stream: svc.watchSosEvents(id),
        builder: (context, sosSnapshot) {
          final internetSosMarkers = (sosSnapshot.data ?? const [])
              .where((event) => event.status != 'acknowledged')
              .map(
                (event) => fm.Marker(
                  point: ll.LatLng(event.latitude, event.longitude),
                  width: 42,
                  height: 42,
                  child: const Icon(
                    Icons.sos_rounded,
                    color: Colors.redAccent,
                    size: 34,
                  ),
                ),
              )
              .toList();

          return ListenableBuilder(
            listenable: HeltecBleService.instance,
            builder: (context, _) {
              final ble = HeltecBleService.instance;
              final relayLat = ble.lastRelayLatitude;
              final relayLon = ble.lastRelayLongitude;
              final offlineSosMarkers = <fm.Marker>[
                // No GPS fix yet on the sender's device means lat/lon are
                // meaningless placeholders — don't plot a pin at all.
                if (ble.lastRelayHasFix && relayLat != null && relayLon != null)
                  fm.Marker(
                    point: ll.LatLng(relayLat, relayLon),
                    width: 42,
                    height: 42,
                    child: const Icon(
                      Icons.settings_input_antenna_rounded,
                      color: Colors.deepOrangeAccent,
                      size: 34,
                    ),
                  ),
              ];
              return buildMap([...internetSosMarkers, ...offlineSosMarkers]);
            },
          );
        },
      );
    } else {
      mapArea = buildMap(const []);
    }

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
          mapArea,
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
  const _HeltecStatusCard({
    this.guideName,
    this.mountainName,
    this.isGuide = false,
    this.service,
    this.roomId,
  });

  /// When set, sent to the device's OLED right after a successful connect
  /// so it can show hike context even with no one looking at the phone.
  final String? guideName;
  final String? mountainName;

  /// True when the current user is this room's tour guide — picks whether
  /// the device gets [HeltecBleService.sendGuideInfo] (mountain + hiker
  /// count) or [HeltecBleService.sendHikerInfo] (guide name + mountain).
  final bool isGuide;

  /// Only needed when [isGuide] is true, to look up the live participant
  /// count at the moment of connecting.
  final HikeRoomService? service;
  final String? roomId;

  Future<void> _connect() async {
    final ble = HeltecBleService.instance;
    await ble.connect(isGuide: isGuide);
    if (!ble.isConnected) return;

    final mountain = mountainName;
    if (mountain == null) return;

    if (isGuide) {
      final svc = service;
      final id = roomId;
      if (svc == null || id == null) return;
      final participants = await svc.watchParticipants(id).first;
      await ble.sendGuideInfo(
        mountainName: mountain,
        participantCount: participants.length,
      );
    } else {
      final guide = guideName;
      if (guide == null) return;
      await ble.sendHikerInfo(guideName: guide, mountainName: mountain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = HeltecBleService.instance;
    return ListenableBuilder(
      listenable: ble,
      builder: (context, _) {
        final connected = ble.isConnected;
        final subtitle = connected
            ? (ble.lastFixAt != null
                  ? 'Last location: ${ble.lastLatitude!.toStringAsFixed(6)}, '
                        '${ble.lastLongitude!.toStringAsFixed(6)}'
                  : 'Connected. Waiting for a GPS fix from the device.')
            : (ble.lastError ??
                  'Room and internet SOS are working. Connect a Heltec device to enable offline radio SOS.');
        return Card(
          color: connected
              ? Colors.green.withValues(alpha: 0.12)
              : Colors.orange.withValues(alpha: 0.12),
          child: ListTile(
            leading: Icon(
              connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_disabled_rounded,
              color: connected ? Colors.greenAccent : Colors.orange,
            ),
            title: Text(
              connected
                  ? 'Heltec device: Connected'
                  : 'Heltec device: Not connected',
            ),
            subtitle: Text(subtitle),
            trailing: connected
                ? null
                : TextButton(
                    onPressed: ble.isScanning ? null : _connect,
                    child: Text(ble.isScanning ? 'Scanning...' : 'Connect'),
                  ),
          ),
        );
      },
    );
  }
}

/// Shows an SOS relayed to THIS phone's Heltec over LoRa from another
/// hiker's Heltec — sourced entirely from [HeltecBleService], never from
/// Firestore, since this is exactly the path meant to work with zero
/// internet/cellular signal. Sits alongside [_SosList] (the internet path)
/// rather than replacing it.
class _OfflineSosRelayCard extends StatelessWidget {
  const _OfflineSosRelayCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HeltecBleService.instance,
      builder: (context, _) {
        final ble = HeltecBleService.instance;
        final name = ble.lastRelaySenderName;
        final lat = ble.lastRelayLatitude;
        final lon = ble.lastRelayLongitude;
        final at = ble.lastRelayAt;
        if (name == null || lat == null || lon == null) {
          return const SizedBox.shrink();
        }
        final minutesAgo = at == null
            ? null
            : DateTime.now().difference(at).inMinutes;
        final hasFix = ble.lastRelayHasFix;
        final reason = ble.lastRelayReason;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Card(
            color: Colors.red.withValues(alpha: 0.18),
            child: ListTile(
              leading: const Icon(Icons.sos_rounded, color: Colors.redAccent),
              title: Text('$name sent SOS — Offline (LoRa relay)'),
              subtitle: Text(
                '${reason == null ? '' : 'Reason: $reason\n'}'
                '${hasFix ? '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}' : 'Location unavailable — sender device had no GPS fix yet'}\n'
                '${minutesAgo == null ? 'Just now' : '$minutesAgo min ago'} • no internet used',
              ),
              isThreeLine: true,
            ),
          ),
        );
      },
    );
  }
}

class _OfflineStopRelayCard extends StatelessWidget {
  const _OfflineStopRelayCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HeltecBleService.instance,
      builder: (context, _) {
        final ble = HeltecBleService.instance;
        final name = ble.lastStopRelaySenderName;
        final reason = ble.lastStopRelayReason;
        final at = ble.lastStopRelayAt;
        if (name == null || reason == null) {
          return const SizedBox.shrink();
        }
        final minutesAgo = at == null
            ? null
            : DateTime.now().difference(at).inMinutes;
        final acknowledged = ble.stopAckSentFor(name);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Card(
            color: acknowledged
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.orange.withValues(alpha: 0.18),
            child: ListTile(
              leading: Icon(
                acknowledged ? Icons.done_all_rounded : Icons.flag_rounded,
                color: acknowledged ? Colors.greenAccent : Colors.orange,
              ),
              title: Text('$name ended their hike — Offline (LoRa relay)'),
              subtitle: Text(
                '$reason\n'
                '${minutesAgo == null ? 'Just now' : '$minutesAgo min ago'} • no internet used',
              ),
              isThreeLine: true,
              trailing: acknowledged
                  ? const Text('ACKNOWLEDGED')
                  : FilledButton(
                      onPressed: () => _acknowledgeEndedHike(
                        context,
                        // Heard only over LoRa — the online list above
                        // covers the internet side for this same hiker.
                        service: null,
                        roomId: null,
                        participantId: null,
                        hikerName: name,
                      ),
                      child: const Text('Acknowledge'),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Static conduct guidance shown inside an active Hike Room — what a hiker
/// is expected to do, what they must not do, and what the app actually
/// lets them do here. Collapsed by default so it doesn't bury the live
/// status cards above it; a hiker opens it when they actually want to
/// check something.
class _HikeRoomPolicyCard extends StatelessWidget {
  const _HikeRoomPolicyCard({
    required this.roomId,
    required this.service,
    required this.isGuide,
  });

  final String roomId;
  final HikeRoomService service;

  /// The Terms & Conditions checkbox is only shown to hikers — the guide
  /// still sees the policy itself but isn't asked to agree to it.
  final bool isGuide;

  static const List<String> _dos = [
    "Follow the Tour Guide's instructions throughout the hike.",
    "Stay with the group — don't get far ahead or fall far behind.",
    'Use End Hike in Hiking Mode (with a reason) if you need to stop — never just disappear from the group.',
    'Connect your Heltec device if you have one, especially where signal is weak.',
    "Respect the turnaround time the guide sets.",
    'Tell the guide right away if you feel unwell, before it gets worse.',
    'Practice Leave No Trace — pack out everything you bring in.',
  ];

  static const List<String> _donts = [
    'Do not use SOS unless it is a real emergency.',
    'Do not take shortcuts or leave the approved trail.',
    'Do not leave the group without telling the guide.',
    'Do not camp or sleep at the summit unless explicitly allowed.',
    'Do not leave trash on the mountain.',
    'Do not drink alcohol or smoke at the peak/summit area.',
  ];

  static const List<String> _canDoHere = [
    "View the Tour Guide's shared route map.",
    'See the list of hikers and the guide in this room.',
    'Connect a Heltec device to enable offline features.',
    'Send SOS — over the internet, or over the device if there is no signal.',
    'End Hike with a reason — your guide is told over the internet and/or the device, and you stay in the room.',
    'Tap START HIKING once the guide starts the hike, for live GPS tracking.',
    'Leave the room — only before the hike has started.',
    'See your own stop status, and whether the guide has acknowledged it.',
  ];

  @override
  Widget build(BuildContext context) {
    final policy = Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.policy_rounded),
          title: const Text('Tour Guide Policy'),
          subtitle: const Text('Rules, and what you can do here'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _policySection(
              context,
              "Do's",
              _dos,
              Icons.check_circle_outline_rounded,
              Colors.green,
            ),
            const SizedBox(height: 14),
            _policySection(
              context,
              "Don'ts",
              _donts,
              Icons.cancel_outlined,
              Colors.redAccent,
            ),
            const SizedBox(height: 14),
            _policySection(
              context,
              'What You Can Do Here',
              _canDoHere,
              Icons.touch_app_rounded,
              Colors.blueAccent,
            ),
          ],
        ),
      ),
    );

    if (isGuide) return policy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        policy,
        StreamBuilder<HikeRoomParticipant?>(
          stream: service.watchCurrentParticipant(roomId),
          builder: (context, snapshot) {
            final accepted = snapshot.data?.policyAcceptedAt != null;
            return CheckboxListTile(
              value: accepted,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text(
                'I have read and agree to the Terms and Conditions of the '
                'Tour Guide Policy above.',
              ),
              onChanged: snapshot.data == null
                  ? null
                  : (value) async {
                      try {
                        await service.setPolicyAccepted(
                          roomId,
                          accepted: value ?? false,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not save your agreement: $error',
                            ),
                          ),
                        );
                      }
                    },
            );
          },
        ),
      ],
    );
  }

  Widget _policySection(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

/// [_HeltecStatusCard] only sends the guide's Heltec a hiker-count
/// snapshot at the moment it connects — without this, the OLED goes
/// stale the instant anyone joins or leaves afterward. This has no UI
/// of its own; it just keeps re-sending the current count over BLE
/// every time the live participant list actually changes.
class _GuideParticipantCountSync extends StatelessWidget {
  const _GuideParticipantCountSync({
    required this.mountainName,
    required this.service,
    required this.roomId,
  });

  final String mountainName;
  final HikeRoomService service;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HikeRoomParticipant>>(
      stream: service.watchParticipants(roomId),
      builder: (context, snapshot) {
        final participants = snapshot.data;
        final ble = HeltecBleService.instance;
        if (participants != null && ble.isConnected) {
          unawaited(
            ble.sendGuideInfo(
              mountainName: mountainName,
              participantCount: participants.length,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SosList extends StatelessWidget {
  const _SosList({
    required this.roomId,
    required this.service,
    required this.isGuide,
  });

  final String roomId;
  final HikeRoomService service;

  /// Only the room's guide can actually acknowledge an SOS — enforced
  /// server-side by firestore.rules, mirrored here so a hiker sees a
  /// plain status instead of a button that would just fail.
  final bool isGuide;

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
                      '${event.reason == null ? '' : 'Reason: ${event.reason}\n'}'
                      '${event.latitude.toStringAsFixed(6)}, ${event.longitude.toStringAsFixed(6)}',
                    ),
                    isThreeLine: event.reason != null,
                    trailing: acknowledged
                        ? const Text('ACKNOWLEDGED')
                        : !isGuide
                        ? const Text('PENDING')
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

/// Guide acknowledges a hiker's ended hike over the internet AND the
/// Heltec (whichever are available) at the same time, so the hiker learns
/// it was seen even when neither side has signal.
Future<void> _acknowledgeEndedHike(
  BuildContext context, {
  required HikeRoomService? service,
  required String? roomId,
  required String? participantId,
  required String hikerName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ble = HeltecBleService.instance;
  final sentByDevice = ble.isConnected
      ? await ble.sendStopAck(hikerName: hikerName)
      : false;

  var sentOnline = false;
  if (service != null && roomId != null && participantId != null) {
    try {
      // Bounded: an offline Firestore write never completes on its own,
      // and the device path above already covers no-signal.
      await service
          .acknowledgeStop(roomId, participantId)
          .timeout(const Duration(seconds: 10));
      sentOnline = true;
    } catch (error) {
      debugPrint('Could not acknowledge online: $error');
    }
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        sentOnline && sentByDevice
            ? '$hikerName was told you saw it — over the internet and your device.'
            : sentOnline
            ? '$hikerName was told you saw it.'
            : sentByDevice
            ? '$hikerName was told you saw it over your device (no internet).'
            : 'Could not reach $hikerName — no internet and no device connected.',
      ),
    ),
  );
}

class _StoppedHikersList extends StatelessWidget {
  const _StoppedHikersList({required this.roomId, required this.service});

  final String roomId;
  final HikeRoomService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HikeRoomParticipant>>(
      stream: service.watchStoppedParticipants(roomId),
      builder: (context, snapshot) {
        final stopped = snapshot.data ?? const [];
        if (stopped.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('Everyone is still on the trail'),
            ),
          );
        }
        return Column(
          children: stopped
              .map((participant) {
                final acknowledged = participant.stopAcknowledged;
                return Card(
                  color: acknowledged
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.18),
                  child: ListTile(
                    leading: Icon(
                      acknowledged
                          ? Icons.done_all_rounded
                          : Icons.pan_tool_rounded,
                      color: acknowledged ? Colors.greenAccent : Colors.orange,
                    ),
                    title: Text('${participant.name} ended their hike'),
                    subtitle: Text(participant.stopReason ?? ''),
                    trailing: acknowledged
                        ? const Text('ACKNOWLEDGED')
                        : FilledButton(
                            onPressed: () => _acknowledgeEndedHike(
                              context,
                              service: service,
                              roomId: roomId,
                              participantId: participant.userId,
                              hikerName: participant.name,
                            ),
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
