const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

// Solo SOS — a hiker with no Hike Room (so no Tour Guide listening) still
// needs SOMEONE to hear them. This finds the hikers physically closest to
// them right now, using the hiker_presence docs every phone in Hiking Mode
// keeps fresh (see _HikingModeScreenState._publishPresence in main.dart),
// and drops an SOS into each of their in-app notifications. Their Hiking
// Mode screen listens for exactly these and pops an alert + map pin.

// Presence older than this is treated as "not out hiking anymore" — Hiking
// Mode refreshes it every ~1 minute while open.
const PRESENCE_FRESH_MS = 15 * 60 * 1000;
const NEARBY_RADIUS_METERS = 5000;
const MAX_NEARBY_HIKERS = 5;
const SOLO_SOS_COOLDOWN_SECONDS = 30;
const SOS_REASON_MAX_LENGTH = 60;

function isFiniteInRange(value, min, max) {
  return Number.isFinite(value) && value >= min && value <= max;
}

/** Great-circle distance in meters between two lat/lng points. */
function haversineMeters(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadius = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(a));
}

/**
 * Picks the closest fresh hikers to (lat, lng), excluding the sender.
 * presences: [{ uid, latitude, longitude, updatedAtMs }]
 */
function pickNearbyHikers(presences, { senderId, latitude, longitude, nowMs }) {
  return presences
    .filter((p) => p.uid !== senderId)
    .filter((p) => isFiniteInRange(p.latitude, -90, 90) &&
      isFiniteInRange(p.longitude, -180, 180))
    .filter((p) => nowMs - p.updatedAtMs <= PRESENCE_FRESH_MS)
    .map((p) => ({
      ...p,
      distanceMeters: haversineMeters(latitude, longitude, p.latitude, p.longitude),
    }))
    .filter((p) => p.distanceMeters <= NEARBY_RADIUS_METERS)
    .sort((a, b) => a.distanceMeters - b.distanceMeters)
    .slice(0, MAX_NEARBY_HIKERS);
}

function formatDistance(meters) {
  return meters < 1000 ?
    `${Math.round(meters)} m` :
    `${(meters / 1000).toFixed(1)} km`;
}

const sendNearbySos = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const auth = request.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const uid = auth.uid;
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    const reason = String(request.data?.reason ?? "").trim()
      .slice(0, SOS_REASON_MAX_LENGTH);
    const trailName = String(request.data?.trailName ?? "").trim().slice(0, 80);

    if (!isFiniteInRange(latitude, -90, 90)) {
      throw new HttpsError("invalid-argument", "Invalid latitude.");
    }
    if (!isFiniteInRange(longitude, -180, 180)) {
      throw new HttpsError("invalid-argument", "Invalid longitude.");
    }

    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const cooldownRef = db.collection("solo_sos_cooldowns").doc(uid);
    const cooldownSnap = await cooldownRef.get();
    const nextAllowedAt = cooldownSnap.data()?.nextAllowedAt;
    if (nextAllowedAt && nextAllowedAt.toMillis() > now.toMillis()) {
      const waitSeconds = Math.ceil(
        (nextAllowedAt.toMillis() - now.toMillis()) / 1000,
      );
      throw new HttpsError(
        "failed-precondition",
        `Please wait ${waitSeconds}s before sending another SOS.`,
      );
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const fullName = String(userSnap.data()?.fullName ?? "").trim();
    const authName = String(auth.token?.name ?? "").trim();
    const emailLocalPart = String(auth.token?.email ?? "").split("@")[0];
    const senderName = fullName || authName || emailLocalPart || "A hiker";

    // Single-field range query — no composite index needed. Distance is
    // filtered in memory; the number of people hiking at once is small.
    const freshSince = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - PRESENCE_FRESH_MS,
    );
    const presenceSnap = await db.collection("hiker_presence")
      .where("updatedAt", ">=", freshSince)
      .get();
    const presences = presenceSnap.docs.map((doc) => ({
      uid: doc.id,
      latitude: Number(doc.data().latitude),
      longitude: Number(doc.data().longitude),
      updatedAtMs: doc.data().updatedAt?.toMillis?.() ?? 0,
    }));
    const nearby = pickNearbyHikers(presences, {
      senderId: uid,
      latitude,
      longitude,
      nowMs: now.toMillis(),
    });

    const eventRef = db.collection("solo_sos_events").doc();
    const batch = db.batch();
    batch.set(eventRef, {
      senderId: uid,
      senderName,
      latitude,
      longitude,
      reason: reason || null,
      trailName: trailName || null,
      notifiedHikerIds: nearby.map((h) => h.uid),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    for (const hiker of nearby) {
      batch.set(
        db.collection("users").doc(hiker.uid)
          .collection("notifications").doc(`nearby_sos_${eventRef.id}`),
        {
          type: "sos",
          nearbySos: true,
          title: `SOS nearby: ${senderName}`,
          body: `${reason || "Needs help"} — about ` +
            `${formatDistance(hiker.distanceMeters)} from you` +
            `${trailName ? ` on ${trailName}` : ""}.`,
          reason: reason || null,
          senderId: uid,
          senderName,
          latitude,
          longitude,
          distanceMeters: Math.round(hiker.distanceMeters),
          soloSosEventId: eventRef.id,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      );
    }
    batch.set(cooldownRef, {
      nextAllowedAt: admin.firestore.Timestamp.fromMillis(
        now.toMillis() + SOLO_SOS_COOLDOWN_SECONDS * 1000,
      ),
    });
    await batch.commit();

    return {
      sent: true,
      notifiedCount: nearby.length,
      nearestMeters: nearby.length ? Math.round(nearby[0].distanceMeters) : null,
    };
  },
);

module.exports = {
  sendNearbySos,
  haversineMeters,
  pickNearbyHikers,
  PRESENCE_FRESH_MS,
  NEARBY_RADIUS_METERS,
  MAX_NEARBY_HIKERS,
};
