import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum HikeRoomStatus { waiting, active, ended }

class HikeRoomRoutePoint {
  const HikeRoomRoutePoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  Map<String, double> toMap() => <String, double>{
    'lat': latitude,
    'lon': longitude,
  };
}

class HikeRoom {
  const HikeRoom({
    required this.id,
    required this.code,
    required this.mountainName,
    required this.guideId,
    required this.guideName,
    required this.status,
    required this.mountainLatitude,
    required this.mountainLongitude,
    required this.routeName,
    required this.jumpOffLabel,
    required this.routePoints,
    this.mountainPlaceId = '',
    this.routeAssetPath = '',
  });

  final String id;
  final String code;
  final String mountainName;
  final String guideId;
  final String guideName;
  final HikeRoomStatus status;
  final double mountainLatitude;
  final double mountainLongitude;
  final String mountainPlaceId;
  final String routeName;
  final String jumpOffLabel;
  final String routeAssetPath;
  final List<HikeRoomRoutePoint> routePoints;

  factory HikeRoom.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawStatus = data['status']?.toString() ?? 'waiting';
    return HikeRoom(
      id: snapshot.id,
      code: data['roomCode']?.toString() ?? '',
      mountainName: data['mountainName']?.toString() ?? 'Unnamed hike',
      guideId: data['guideId']?.toString() ?? '',
      guideName: data['guideName']?.toString() ?? 'Tour Guide',
      status: HikeRoomStatus.values.firstWhere(
        (status) => status.name == rawStatus,
        orElse: () => HikeRoomStatus.waiting,
      ),
      mountainLatitude: (data['mountainLatitude'] as num?)?.toDouble() ?? 0,
      mountainLongitude: (data['mountainLongitude'] as num?)?.toDouble() ?? 0,
      mountainPlaceId: data['mountainPlaceId']?.toString() ?? '',
      routeName: data['routeName']?.toString() ?? 'Shared trail route',
      jumpOffLabel: data['jumpOffLabel']?.toString() ?? '',
      routeAssetPath: data['routeAssetPath']?.toString() ?? '',
      routePoints: _decodeRoutePoints(data['routePoints']),
    );
  }

  static List<HikeRoomRoutePoint> _decodeRoutePoints(dynamic raw) {
    if (raw is! List) return const <HikeRoomRoutePoint>[];
    final points = <HikeRoomRoutePoint>[];
    for (final item in raw) {
      if (item is GeoPoint) {
        points.add(HikeRoomRoutePoint(item.latitude, item.longitude));
      } else if (item is Map) {
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          points.add(HikeRoomRoutePoint(lat, lon));
        }
      }
    }
    return points;
  }
}

class HikeRoomParticipant {
  const HikeRoomParticipant({
    required this.userId,
    required this.name,
    required this.role,
    required this.deviceStatus,
    required this.activityStatus,
  });

  final String userId;
  final String name;
  final String role;
  final String deviceStatus;
  final String activityStatus;

  factory HikeRoomParticipant.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return HikeRoomParticipant(
      userId: snapshot.id,
      name: data['name']?.toString() ?? 'Hiker',
      role: data['role']?.toString() ?? 'hiker',
      deviceStatus: data['deviceStatus']?.toString() ?? 'not_connected',
      activityStatus: data['activityStatus']?.toString() ?? 'in_room',
    );
  }
}

class RoomSosEvent {
  const RoomSosEvent({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String senderName;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime? createdAt;

  factory RoomSosEvent.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestamp = data['createdAt'];
    return RoomSosEvent(
      id: snapshot.id,
      senderId: data['senderId']?.toString() ?? '',
      senderName: data['senderName']?.toString() ?? 'Hiker',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      status: data['status']?.toString() ?? 'sent',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

class HikeRoomService {
  HikeRoomService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Random _random = Random.secure();

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in.');
    }
    return user;
  }

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  DocumentReference<Map<String, dynamic>> _roomRef(String roomId) =>
      _firestore.collection('hike_rooms').doc(roomId);

  Future<Map<String, dynamic>> getCurrentUserProfile() async {
    final snapshot = await _userRef(_user.uid).get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  String accountTypeFromProfile(Map<String, dynamic> profile) {
    final rawValue =
        profile['accountType']?.toString() ??
        profile['role']?.toString() ??
        'hiker';
    final normalized = rawValue.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    if (normalized == 'tourguide' || normalized == 'guide') {
      return 'tour_guide';
    }
    return normalized;
  }

  Future<HikeRoom?> getActiveRoom() async {
    final profile = await getCurrentUserProfile();
    final roomId = profile['activeHikeRoomId']?.toString() ?? '';
    if (roomId.isEmpty) return null;
    final snapshot = await _roomRef(roomId).get();
    if (!snapshot.exists) {
      await _userRef(
        _user.uid,
      ).update({'activeHikeRoomId': FieldValue.delete()});
      return null;
    }
    final room = HikeRoom.fromSnapshot(snapshot);
    if (room.status == HikeRoomStatus.ended) {
      await _userRef(
        _user.uid,
      ).update({'activeHikeRoomId': FieldValue.delete()});
      return null;
    }
    return room;
  }

  Stream<HikeRoom?> watchRoom(String roomId) {
    return _roomRef(roomId).snapshots().map(
      (snapshot) => snapshot.exists ? HikeRoom.fromSnapshot(snapshot) : null,
    );
  }

  Stream<String> watchCurrentMembership(String roomId) {
    return _roomRef(roomId)
        .collection('participants')
        .doc(_user.uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? (snapshot.data()?['membershipStatus']?.toString() ?? 'active')
              : 'removed',
        );
  }

  Stream<List<HikeRoomParticipant>> watchParticipants(String roomId) {
    return _roomRef(roomId)
        .collection('participants')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where(
                (doc) =>
                    (doc.data()['membershipStatus']?.toString() ?? 'active') ==
                    'active',
              )
              .map(HikeRoomParticipant.fromSnapshot)
              .toList(growable: false),
        );
  }

  Stream<List<RoomSosEvent>> watchSosEvents(String roomId) {
    return _roomRef(roomId)
        .collection('sos_events')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(RoomSosEvent.fromSnapshot)
              .toList(growable: false),
        );
  }

  Future<HikeRoom> createRoom({
    required String mountainName,
    required String mountainPlaceId,
    required double mountainLatitude,
    required double mountainLongitude,
    required String routeName,
    required String jumpOffLabel,
    required String routeAssetPath,
    required List<HikeRoomRoutePoint> routePoints,
  }) async {
    final user = _user;
    final profile = await getCurrentUserProfile();
    if (accountTypeFromProfile(profile) != 'tour_guide') {
      throw StateError('Only Tour Guide accounts can create rooms.');
    }
    if ((profile['activeHikeRoomId']?.toString() ?? '').isNotEmpty) {
      throw StateError('Close or leave your current room first.');
    }

    final cleanMountain = mountainName.trim();
    if (cleanMountain.isEmpty) {
      throw ArgumentError('Enter the mountain or hike name.');
    }
    if (routePoints.length < 2) {
      throw ArgumentError(
        'Select a mapped trail route before creating a room.',
      );
    }
    final code = await _generateUniqueCode();
    final roomRef = _firestore.collection('hike_rooms').doc();
    final guideName = _displayName(profile);
    final batch = _firestore.batch();
    batch.set(roomRef, {
      'roomCode': code,
      'mountainName': cleanMountain,
      'mountainPlaceId': mountainPlaceId,
      'mountainLatitude': mountainLatitude,
      'mountainLongitude': mountainLongitude,
      'routeName': routeName.trim().isEmpty
          ? 'Shared trail route'
          : routeName.trim(),
      'jumpOffLabel': jumpOffLabel,
      'routeAssetPath': routeAssetPath,
      'routePoints': routePoints.map((point) => point.toMap()).toList(),
      'guideId': user.uid,
      'guideName': guideName,
      'status': HikeRoomStatus.waiting.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(roomRef.collection('participants').doc(user.uid), {
      'userId': user.uid,
      'name': guideName,
      'role': 'tour_guide',
      'deviceStatus': 'not_connected',
      'membershipStatus': 'active',
      'activityStatus': 'in_room',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userRef(user.uid), {'activeHikeRoomId': roomRef.id});
    await batch.commit();
    final snapshot = await roomRef.get();
    return HikeRoom.fromSnapshot(snapshot);
  }

  Future<HikeRoom> joinRoom(String code) async {
    final user = _user;
    final profile = await getCurrentUserProfile();
    if (accountTypeFromProfile(profile) != 'hiker') {
      throw StateError('Only Hiker accounts can join a guide room.');
    }
    if ((profile['activeHikeRoomId']?.toString() ?? '').isNotEmpty) {
      throw StateError('Leave your current room first.');
    }
    final cleanCode = code.replaceAll(RegExp(r'\D'), '');
    if (cleanCode.length != 6) {
      throw ArgumentError('Enter the 6-digit room code.');
    }
    final query = await _firestore
        .collection('hike_rooms')
        .where('roomCode', isEqualTo: cleanCode)
        .limit(1)
        .get();
    if (query.docs.isEmpty) throw StateError('Room code not found.');
    final room = HikeRoom.fromSnapshot(query.docs.first);
    if (room.status != HikeRoomStatus.waiting) {
      throw StateError('This room is no longer accepting hikers.');
    }
    final batch = _firestore.batch();
    batch.set(_roomRef(room.id).collection('participants').doc(user.uid), {
      'userId': user.uid,
      'name': _displayName(profile),
      'role': 'hiker',
      'deviceStatus': 'not_connected',
      'membershipStatus': 'active',
      'activityStatus': 'in_room',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userRef(user.uid), {'activeHikeRoomId': room.id});
    batch.update(_roomRef(room.id), {
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return room;
  }

  Future<void> startRoom(String roomId) => _setRoomStatus(
    roomId,
    HikeRoomStatus.active,
    timestampField: 'startedAt',
  );

  Future<void> endRoom(String roomId) =>
      _setRoomStatus(roomId, HikeRoomStatus.ended, timestampField: 'endedAt');

  Future<void> _setRoomStatus(
    String roomId,
    HikeRoomStatus status, {
    required String timestampField,
  }) async {
    final room = HikeRoom.fromSnapshot(await _roomRef(roomId).get());
    if (room.guideId != _user.uid) {
      throw StateError('Only the room guide can change the hike status.');
    }
    await _roomRef(roomId).update({
      'status': status.name,
      timestampField: FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (status == HikeRoomStatus.ended) {
      final participants = await _roomRef(
        roomId,
      ).collection('participants').get();
      final batch = _firestore.batch();
      for (final participant in participants.docs) {
        if ((participant.data()['membershipStatus']?.toString() ?? 'active') !=
            'active') {
          continue;
        }
        batch.update(_userRef(participant.id), {
          'activeHikeRoomId': FieldValue.delete(),
        });
        batch.update(participant.reference, {
          'membershipStatus': 'room_ended',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> leaveRoom(String roomId) async {
    final room = HikeRoom.fromSnapshot(await _roomRef(roomId).get());
    if (room.guideId == _user.uid) {
      throw StateError('The guide must end the room instead of leaving it.');
    }
    final batch = _firestore.batch();
    batch.update(_roomRef(roomId).collection('participants').doc(_user.uid), {
      'membershipStatus': 'left',
      'leftAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userRef(_user.uid), {
      'activeHikeRoomId': FieldValue.delete(),
    });
    batch.update(_roomRef(roomId), {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> kickParticipant(String roomId, String participantId) async {
    final room = HikeRoom.fromSnapshot(await _roomRef(roomId).get());
    if (room.guideId != _user.uid) {
      throw StateError('Only the Tour Guide can remove participants.');
    }
    if (participantId == room.guideId) {
      throw StateError('The Tour Guide cannot be removed from the room.');
    }
    final participantRef = _roomRef(
      roomId,
    ).collection('participants').doc(participantId);
    final participant = await participantRef.get();
    if (!participant.exists ||
        (participant.data()?['membershipStatus']?.toString() ?? 'active') !=
            'active') {
      throw StateError('This participant is no longer in the room.');
    }
    final batch = _firestore.batch();
    batch.update(participantRef, {
      'membershipStatus': 'removed',
      'removedBy': _user.uid,
      'removedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userRef(participantId), {
      'activeHikeRoomId': FieldValue.delete(),
    });
    batch.update(_roomRef(roomId), {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> setCurrentParticipantHiking(
    String roomId, {
    required bool isHiking,
  }) async {
    final participantRef = _roomRef(
      roomId,
    ).collection('participants').doc(_user.uid);
    final participant = await participantRef.get();
    if (!participant.exists ||
        (participant.data()?['membershipStatus']?.toString() ?? 'active') !=
            'active') {
      throw StateError('You are not an active participant in this room.');
    }
    await participantRef.update({
      'activityStatus': isHiking ? 'hiking' : 'in_room',
      isHiking ? 'hikingStartedAt' : 'returnedToRoomAt':
          FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendSos({
    required String roomId,
    required double latitude,
    required double longitude,
    String transport = 'internet',
  }) async {
    final profile = await getCurrentUserProfile();
    final room = HikeRoom.fromSnapshot(await _roomRef(roomId).get());
    if (room.status != HikeRoomStatus.active) {
      throw StateError('The guide has not started this hike room.');
    }
    final participant = await _roomRef(
      roomId,
    ).collection('participants').doc(_user.uid).get();
    if (!participant.exists ||
        (participant.data()?['membershipStatus']?.toString() ?? 'active') !=
            'active') {
      throw StateError('You are not in this room.');
    }
    await _roomRef(roomId).collection('sos_events').add({
      'roomId': roomId,
      'roomCode': room.code,
      'senderId': _user.uid,
      'senderName': _displayName(profile),
      'latitude': latitude,
      'longitude': longitude,
      'transport': transport,
      'status': 'sent',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acknowledgeSos(String roomId, String eventId) async {
    final room = HikeRoom.fromSnapshot(await _roomRef(roomId).get());
    if (room.guideId != _user.uid) {
      throw StateError('Only the Tour Guide can acknowledge an SOS.');
    }
    await _roomRef(roomId).collection('sos_events').doc(eventId).update({
      'status': 'acknowledged',
      'acknowledgedBy': _user.uid,
      'acknowledgedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> _generateUniqueCode() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = (100000 + _random.nextInt(900000)).toString();
      final existing = await _firestore
          .collection('hike_rooms')
          .where('roomCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    throw StateError('Unable to generate a room code. Try again.');
  }

  String _displayName(Map<String, dynamic> profile) {
    final fullName = profile['fullName']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final displayName = _user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    return _user.email?.split('@').first ?? 'Hiker';
  }
}
