import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// An SOS from a nearby solo hiker, delivered by the sendNearbySos Cloud
/// Function into this user's own notifications.
class NearbySosAlert {
  const NearbySosAlert({
    required this.id,
    required this.senderName,
    required this.latitude,
    required this.longitude,
    required this.read,
    this.reason,
    this.distanceMeters,
    this.createdAt,
  });

  final String id;
  final String senderName;
  final double latitude;
  final double longitude;
  final bool read;
  final String? reason;
  final int? distanceMeters;
  final DateTime? createdAt;

  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return '';
    return meters < 1000
        ? '$meters m away'
        : '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  factory NearbySosAlert.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final createdAt = data['createdAt'];
    return NearbySosAlert(
      id: snapshot.id,
      senderName: data['senderName']?.toString() ?? 'A hiker',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      read: data['read'] == true,
      reason: data['reason']?.toString(),
      distanceMeters: (data['distanceMeters'] as num?)?.toInt(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

/// Solo-hike SOS: lets a hiker with no Hike Room reach the hikers closest
/// to them, and lets every hiker in Hiking Mode be one of those helpers.
class NearbySosService {
  NearbySosService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _presenceRef {
    final uid = _uid;
    return uid == null ? null : _firestore.collection('hiker_presence').doc(uid);
  }

  /// Shares this hiker's current location so a nearby solo SOS can find
  /// them. Only the Cloud Function can read it (see firestore.rules).
  Future<void> publishPresence({
    required double latitude,
    required double longitude,
  }) async {
    final ref = _presenceRef;
    if (ref == null) return;
    await ref.set({
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stops sharing location — called when Hiking Mode closes.
  Future<void> clearPresence() async {
    await _presenceRef?.delete();
  }

  /// Sends a solo SOS to the closest hikers. Returns how many were notified.
  Future<int> sendNearbySos({
    required double latitude,
    required double longitude,
    required String reason,
    String? trailName,
  }) async {
    try {
      final result = await _functions.httpsCallable('sendNearbySos').call<
        Map<String, dynamic>
      >({
        'latitude': latitude,
        'longitude': longitude,
        'reason': reason,
        'trailName': trailName,
      });
      return (result.data['notifiedCount'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'Unable to send SOS. Try again.');
    }
  }

  /// Nearby solo SOS alerts addressed to this user, newest first.
  Stream<List<NearbySosAlert>> watchNearbySosAlerts() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('nearbySos', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final alerts = snapshot.docs
              .map(NearbySosAlert.fromSnapshot)
              .toList(growable: false);
          alerts.sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
          return alerts;
        });
  }

  Future<void> markAlertRead(String alertId) async {
    final uid = _uid;
    if (uid == null) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(alertId)
        .update({'read': true});
  }
}
