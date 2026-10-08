const crypto = require("node:crypto");
const admin = require("firebase-admin");
require("./emulatorAdminFix");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { getRedisClient, weatherCacheKey } = require("./redisCache");
const { enforceRateLimit } = require("./rateLimit");
const { exchangeAuth0Token } = require("./auth0Exchange");
const {
  reviewTourGuideApplication,
  recommendAdminReview,
} = require("./adminActions");
const {
  manageUserAccount,
  createAdminAccount,
  refreshAdminClaims,
  cleanupOrphanedSosEvents,
  getDeletedSosSenderIds,
} = require("./userAccountActions");
const {
  updateParticipantBluetoothStatus,
  renameBluetoothDevice,
} = require("./bluetoothActivity");
const {
  closeAbandonedHikeRooms,
  notifyGuideOfStoppedHiker,
} = require("./hikeRoomMaintenance");
const { endHikeRoom } = require("./endHikeRoom");
const { backfillAuditLogNames } = require("./auditLogMaintenance");
const { reviewTrailSubmission } = require("./trailReview");
const { sanitizeRoutePoints } = require("./routePoints");
const { sendNearbySos } = require("./nearbySos");

admin.initializeApp();

exports.exchangeAuth0Token = exchangeAuth0Token;
exports.reviewTourGuideApplication = reviewTourGuideApplication;
exports.recommendAdminReview = recommendAdminReview;
exports.manageUserAccount = manageUserAccount;
exports.createAdminAccount = createAdminAccount;
exports.refreshAdminClaims = refreshAdminClaims;
exports.cleanupOrphanedSosEvents = cleanupOrphanedSosEvents;
exports.getDeletedSosSenderIds = getDeletedSosSenderIds;
exports.updateParticipantBluetoothStatus = updateParticipantBluetoothStatus;
exports.renameBluetoothDevice = renameBluetoothDevice;
exports.closeAbandonedHikeRooms = closeAbandonedHikeRooms;
exports.notifyGuideOfStoppedHiker = notifyGuideOfStoppedHiker;
exports.endHikeRoom = endHikeRoom;
exports.backfillAuditLogNames = backfillAuditLogNames;
exports.reviewTrailSubmission = reviewTrailSubmission;
exports.sanitizeRoutePoints = sanitizeRoutePoints;
exports.sendNearbySos = sendNearbySos;

const db = admin.firestore();
const AUTH_ATTEMPT_LIMIT = 5;
const CODE_EXPIRY_MINUTES = 10;
const RESEND_COOLDOWN_SECONDS = 45;

function randomSixDigitCode() {
  // crypto.randomInt (not Math.random) — this code gates email
  // verification, so it needs to be unpredictable to an attacker, not
  // just uniformly distributed.
  return String(crypto.randomInt(100000, 1000000));
}
exports.randomSixDigitCode = randomSixDigitCode;

function hashCode({ code, uid }) {
  return crypto
    .createHash("sha256")
    .update(`${uid}:${code}`)
    .digest("hex");
}
exports.hashCode = hashCode;

async function sendEmailWithResend({ to, code }) {
  const apiKey = process.env.RESEND_API_KEY;
  const fromEmail = process.env.VERIFICATION_FROM_EMAIL;

  if (!apiKey || !fromEmail) {
    throw new HttpsError(
      "failed-precondition",
      "Email provider is not configured. Set RESEND_API_KEY and VERIFICATION_FROM_EMAIL secrets.",
    );
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [to],
      subject: "Your Agakbay verification code",
      html: `<div style="font-family:Arial,sans-serif;">
        <h2>Agakbay Email Verification</h2>
        <p>Your verification code is:</p>
        <p style="font-size:32px;font-weight:700;letter-spacing:4px;">${code}</p>
        <p>This code expires in ${CODE_EXPIRY_MINUTES} minutes.</p>
      </div>`,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new HttpsError(
      "internal",
      `Email send failed (${response.status}). ${body}`,
    );
  }
}

exports.sendEmailVerificationCode = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: ["RESEND_API_KEY", "VERIFICATION_FROM_EMAIL"] },
  async (request) => {
    const auth = request.auth;
    if (!auth?.uid || !auth.token?.email) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const uid = auth.uid;
    const email = auth.token.email;
    const verificationRef = db.collection("email_verifications").doc(uid);
    const now = admin.firestore.Timestamp.now();
    const existing = await verificationRef.get();
    if (existing.exists) {
      const resendAt = existing.data()?.resendAt;
      if (resendAt && resendAt.toMillis() > now.toMillis()) {
        const waitSeconds = Math.ceil((resendAt.toMillis() - now.toMillis()) / 1000);
        throw new HttpsError(
          "failed-precondition",
          `Please wait ${waitSeconds}s before requesting a new code.`,
        );
      }
    }

    const code = randomSixDigitCode();
    const codeHash = hashCode({ code, uid });
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + CODE_EXPIRY_MINUTES * 60 * 1000,
    );
    const resendAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + RESEND_COOLDOWN_SECONDS * 1000,
    );

    await verificationRef.set(
      {
        uid,
        email,
        codeHash,
        attempts: 0,
        expiresAt,
        resendAt,
        createdAt: existing.exists ? existing.data()?.createdAt ?? now : now,
        updatedAt: now,
      },
      { merge: true },
    );

    await sendEmailWithResend({ to: email, code });

    return {
      sent: true,
      expiresInSeconds: CODE_EXPIRY_MINUTES * 60,
      resendInSeconds: RESEND_COOLDOWN_SECONDS,
    };
  },
);

exports.verifyEmailCode = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const auth = request.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const code = String(request.data?.code ?? "").trim();
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Code must be 6 digits.");
    }

    const uid = auth.uid;
    const verificationRef = db.collection("email_verifications").doc(uid);
    const snapshot = await verificationRef.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "No verification code found.");
    }

    const data = snapshot.data();
    const now = admin.firestore.Timestamp.now();
    const expiresAt = data?.expiresAt;
    const attempts = Number(data?.attempts ?? 0);

    if (!expiresAt || expiresAt.toMillis() < now.toMillis()) {
      throw new HttpsError("deadline-exceeded", "Verification code has expired.");
    }
    if (attempts >= AUTH_ATTEMPT_LIMIT) {
      throw new HttpsError(
        "permission-denied",
        "Too many failed attempts. Please request a new code.",
      );
    }

    const inputHash = hashCode({ code, uid });
    if (inputHash !== data?.codeHash) {
      await verificationRef.set(
        {
          attempts: attempts + 1,
          updatedAt: now,
        },
        { merge: true },
      );
      throw new HttpsError("invalid-argument", "Incorrect verification code.");
    }

    await admin.auth().updateUser(uid, { emailVerified: true });
    await db.collection("users").doc(uid).set(
      {
        emailVerified: true,
        emailVerifiedCustom: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await verificationRef.delete();

    return { verified: true };
  },
);

const SOS_COOLDOWN_SECONDS = 30;
// "Others: " plus the app's 40-character note limit, with some slack.
const SOS_REASON_MAX_LENGTH = 60;

function isFiniteNumberInRange(value, min, max) {
  const num = Number(value);
  return Number.isFinite(num) && num >= min && num <= max;
}
exports.isFiniteNumberInRange = isFiniteNumberInRange;

exports.sendSosEvent = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const auth = request.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const uid = auth.uid;
    const roomId = String(request.data?.roomId ?? "").trim();
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    const transport = String(request.data?.transport ?? "internet");
    // "Lost", "Accident", "Others" or "Others: <note>" from the app's SOS
    // reason picker. Optional so an older app build still gets through —
    // an SOS must never be rejected just for missing context.
    const reason = String(request.data?.reason ?? "").trim()
      .slice(0, SOS_REASON_MAX_LENGTH);

    if (!roomId) {
      throw new HttpsError("invalid-argument", "roomId is required.");
    }
    if (!isFiniteNumberInRange(latitude, -90, 90)) {
      throw new HttpsError("invalid-argument", "Invalid latitude.");
    }
    if (!isFiniteNumberInRange(longitude, -180, 180)) {
      throw new HttpsError("invalid-argument", "Invalid longitude.");
    }

    const roomRef = db.collection("hike_rooms").doc(roomId);
    const cooldownRef = roomRef.collection("sos_cooldowns").doc(uid);
    const now = admin.firestore.Timestamp.now();

    const cooldownSnap = await cooldownRef.get();
    if (cooldownSnap.exists) {
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
    }

    // Re-verify room/membership server-side — the client already checks
    // this for a fast, friendly error, but only this check is trustworthy;
    // a modified client could otherwise skip straight to writing an event.
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists || roomSnap.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "The guide has not started this hike room.",
      );
    }
    const room = roomSnap.data();

    const participantRef = roomRef.collection("participants").doc(uid);
    const participantSnap = await participantRef.get();
    const membershipStatus = participantSnap.data()?.membershipStatus ?? "active";
    // A hiker who stopped remains in the room while returning and must still
    // be able to send an SOS.
    if (
      !participantSnap.exists ||
      !["active", "stopped"].includes(membershipStatus)
    ) {
      throw new HttpsError("failed-precondition", "You are not in this room.");
    }

    // Same fallback order as _displayName() in hike_room_service.dart:
    // profile fullName, then Auth displayName, then the email's local
    // part, then a generic label.
    const userSnap = await db.collection("users").doc(uid).get();
    const fullName = String(userSnap.data()?.fullName ?? "").trim();
    const authName = String(auth.token?.name ?? "").trim();
    const emailLocalPart = String(auth.token?.email ?? "").split("@")[0];
    const senderName = fullName || authName || emailLocalPart || "Hiker";

    const eventRef = roomRef.collection("sos_events").doc();
    const batch = db.batch();
    batch.set(eventRef, {
      roomId,
      roomCode: room?.roomCode ?? "",
      mountainName: room?.mountainName ?? "",
      senderId: uid,
      senderName,
      latitude,
      longitude,
      reason: reason || null,
      transport,
      status: "sent",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(cooldownRef, {
      nextAllowedAt: admin.firestore.Timestamp.fromMillis(
        now.toMillis() + SOS_COOLDOWN_SECONDS * 1000,
      ),
    });
    const auditRef = db.collection("admin_actions")
      .doc(`sos_sent_${roomId}_${eventRef.id}`);
    batch.set(auditRef, {
      action: "send_sos",
      actorId: uid,
      actorName: senderName,
      targetId: roomId,
      targetName: `Hike Room ${room.roomCode || roomId}`,
      roomId,
      roomCode: room.roomCode || roomId,
      newStatus: "sent",
      notifyAdmins: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return { sent: true, eventId: eventRef.id };
  },
);

exports.onSosEventCreated = onDocumentCreated(
  {
    document: "hike_rooms/{roomId}/sos_events/{eventId}",
    region: "asia-southeast1",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const snapshot = event.data;

    if (!snapshot) {
      return;
    }

    const data = snapshot.data() || {};

    const roomId = event.params.roomId;
    const eventId = event.params.eventId;

    const eventRef = db.collection("hike_rooms").doc(roomId)
      .collection("sos_events").doc(eventId);
    const notificationRef = db.collection("notifications")
      .doc(`sos_${roomId}_${eventId}`);

    // Account deletion removes the source event and its notification. Check
    // the source inside the same transaction so a delayed create trigger
    // cannot recreate a notification after cleanup.
    await db.runTransaction(async (transaction) => {
      const [eventSnap, notificationSnap] = await Promise.all([
        transaction.get(eventRef),
        transaction.get(notificationRef),
      ]);
      if (!eventSnap.exists || notificationSnap.exists) return;
      const currentEvent = eventSnap.data() || {};
      const senderName = String(currentEvent.senderName || "Hiker");
      const roomCode = String(currentEvent.roomCode || roomId);
      const reason = String(currentEvent.reason || "").trim();
      transaction.create(notificationRef, {
        type: "sos",
        title: "SOS Emergency Alert",
        message: reason ?
          `${senderName} has triggered an SOS (${reason}) in hike room ${roomCode}.` :
          `${senderName} has triggered an SOS in hike room ${roomCode}.`,
        reason: reason || null,
        isRead: false,
        roomId,
        eventId,
        mountainName: String(currentEvent.mountainName || data.mountainName || ""),
        senderId: String(data.senderId || ""),
        senderName,
        latitude: Number(data.latitude),
        longitude: Number(data.longitude),
        transport: String(data.transport || "internet"),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);

async function writeOperationalAudit(event, action, fields) {
  const eventId = String(event.id).replace(/[^A-Za-z0-9_-]/g, "_");
  const auditRef = db.collection("admin_actions")
    .doc(`event_${action}_${eventId}`);
  await db.runTransaction(async (transaction) => {
    const auditSnapshot = await transaction.get(auditRef);
    if (auditSnapshot.exists) return;
    transaction.create(auditRef, {
      action,
      ...fields,
      notifyAdmins: false,
      createdAt: event.time
        ? admin.firestore.Timestamp.fromDate(new Date(event.time))
        : admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

exports.onSosEventAcknowledged = onDocumentUpdated(
  {
    document: "hike_rooms/{roomId}/sos_events/{eventId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after ||
        before.status === "acknowledged" ||
        after.status !== "acknowledged") return;

    const roomId = event.params.roomId;
    const roomSnapshot = await db.collection("hike_rooms").doc(roomId).get();
    const room = roomSnapshot.data() || {};
    await writeOperationalAudit(event, "acknowledge_sos", {
      actorId: after.acknowledgedBy || room.guideId || "",
      actorName: room.guideName || "Tour Guide",
      targetId: after.senderId || event.params.eventId,
      targetName: after.senderName || "Hiker",
      roomId,
      roomCode: room.roomCode || roomId,
      previousStatus: before.status || "sent",
      newStatus: after.status,
    });
  },
);

exports.onHikeRoomCreated = onDocumentCreated(
  {
    document: "hike_rooms/{roomId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const room = event.data?.data();
    if (!room) return;
    await writeOperationalAudit(event, "create_hike_room", {
      actorId: room.guideId || "",
      actorName: room.guideName || "Tour Guide",
      targetId: event.params.roomId,
      targetName: room.mountainName || "Hike Room",
      roomId: event.params.roomId,
      roomCode: room.roomCode || "",
      newStatus: room.status || "waiting",
    });
  },
);

exports.onHikeRoomStatusChanged = onDocumentUpdated(
  {
    document: "hike_rooms/{roomId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const action = after.status === "active"
      ? "start_hike_room"
      : after.status === "ended" && !after.autoEndedReason
        ? "end_hike_room"
        : null;
    if (!action) return;

    await writeOperationalAudit(event, action, {
      actorId: after.guideId || "",
      actorName: after.guideName || "Tour Guide",
      targetId: event.params.roomId,
      targetName: after.mountainName || "Hike Room",
      roomId: event.params.roomId,
      roomCode: after.roomCode || "",
      previousStatus: before.status || "",
      newStatus: after.status,
    });
  },
);

exports.onHikeRoomParticipantCreated = onDocumentCreated(
  {
    document: "hike_rooms/{roomId}/participants/{participantId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const participant = event.data?.data();
    if (!participant || participant.role !== "hiker") return;
    const roomId = event.params.roomId;
    const roomSnapshot = await db.collection("hike_rooms").doc(roomId).get();
    const room = roomSnapshot.data() || {};
    await writeOperationalAudit(event, "join_hike_room", {
      actorId: participant.userId || event.params.participantId,
      actorName: participant.name || "Hiker",
      targetId: roomId,
      targetName: `Hike Room ${room.roomCode || roomId}`,
      roomId,
      roomCode: room.roomCode || roomId,
      newStatus: "active",
    });
  },
);

exports.onHikeRoomParticipantUpdated = onDocumentUpdated(
  {
    document: "hike_rooms/{roomId}/participants/{participantId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const roomId = event.params.roomId;
    const roomSnapshot = await db.collection("hike_rooms").doc(roomId).get();
    const room = roomSnapshot.data() || {};
    const participantId = after.userId || event.params.participantId;

    if (before.membershipStatus !== after.membershipStatus) {
      let action;
      let actorId;
      let actorName;
      if (after.membershipStatus === "left") {
        action = "leave_hike_room";
        actorId = participantId;
        actorName = after.name || "Hiker";
      } else if (after.membershipStatus === "removed") {
        action = "remove_hike_participant";
        actorId = after.removedBy || room.guideId || "";
        actorName = room.guideName || "Tour Guide";
      }
      if (action) {
        await writeOperationalAudit(event, action, {
          actorId,
          actorName,
          targetId: participantId,
          targetName: after.name || "Hiker",
          roomId,
          roomCode: room.roomCode || roomId,
          previousStatus: before.membershipStatus || "active",
          newStatus: after.membershipStatus,
        });
      }
    }

    if (before.activityStatus !== after.activityStatus) {
      const action = after.activityStatus === "hiking"
        ? "start_hiking"
        : after.activityStatus === "in_room"
          ? "return_to_room"
          : null;
      if (action) {
        await writeOperationalAudit(event, action, {
          actorId: participantId,
          actorName: after.name || "Hiker",
          targetId: roomId,
          targetName: `Hike Room ${room.roomCode || roomId}`,
          roomId,
          roomCode: room.roomCode || roomId,
          previousStatus: before.activityStatus || "",
          newStatus: after.activityStatus,
        });
      }
    }
  },
);

function weatherCodeFromGoogleCondition(conditionType) {
  const type = String(conditionType || "").toUpperCase();
  if (type.includes("THUNDER")) return 95;
  if (type.includes("HEAVY") && type.includes("RAIN")) return 65;
  if (type.includes("SHOWERS")) return type.includes("HEAVY") ? 82 : 80;
  if (type.includes("RAIN")) return 63;
  if (type.includes("DRIZZLE")) return 53;
  if (type.includes("SNOW") || type.includes("ICE")) return 71;
  if (type.includes("FOG") || type.includes("HAZE")) return 45;
  if (type.includes("CLOUD")) return type.includes("PARTLY") ? 2 : 3;
  if (type.includes("CLEAR") || type.includes("SUNNY")) return 0;
  return 3;
}
exports.weatherCodeFromGoogleCondition = weatherCodeFromGoogleCondition;

function isWetWeatherCode(weatherCode) {
  return (
    (weatherCode >= 51 && weatherCode <= 67) ||
    (weatherCode >= 71 && weatherCode <= 86) ||
    weatherCode >= 95
  );
}
exports.isWetWeatherCode = isWetWeatherCode;

// Same thresholds as weather_service.dart's _hikeWeatherRisk — this is now
// the single source of truth; the Dart copy is deleted once the client
// calls this function instead of classifying the raw API response itself.
function hikeWeatherRisk({
  weatherCode,
  rainChancePercent,
  precipitationMm,
  windSpeedKmh,
}) {
  const rainChance = rainChancePercent ?? 0;
  const precipitation = precipitationMm ?? 0;
  const windSpeed = windSpeedKmh ?? 0;
  const stormy = weatherCode >= 95;
  const heavyRain = weatherCode === 65 || weatherCode === 67 || weatherCode === 82;

  if (
    stormy ||
    heavyRain ||
    rainChance >= 80 ||
    precipitation >= 20 ||
    windSpeed >= 45
  ) {
    return "unsafe";
  }
  if (
    isWetWeatherCode(weatherCode) ||
    weatherCode === 3 ||
    rainChance >= 50 ||
    precipitation >= 5 ||
    windSpeed >= 30
  ) {
    return "caution";
  }
  return "good";
}
exports.hikeWeatherRisk = hikeWeatherRisk;

async function buildWeatherSnapshot({ latitude, longitude, redis, fetchFn }) {
  const cacheKey = weatherCacheKey(latitude, longitude);
  if (redis) {
    const cached = await redis.get(cacheKey).catch(() => null);
    if (cached) {
      return cached;
    }
  }

  const apiKey = process.env.WEATHER_API_KEY;
  if (!apiKey) {
    throw new HttpsError(
      "failed-precondition",
      "Weather provider is not configured. Set the WEATHER_API_KEY secret.",
    );
  }

  const url = new URL("https://weather.googleapis.com/v1/currentConditions:lookup");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("location.latitude", latitude.toFixed(6));
  url.searchParams.set("location.longitude", longitude.toFixed(6));

  let decoded;
  try {
    const response = await fetchFn(url, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) {
      // Never log `url` here — it carries the API key as a query param.
      const bodySnippet = await response.text().catch(() => "");
      console.error(
        `Weather API returned ${response.status}: ${bodySnippet.slice(0, 300)}`,
      );
      return null;
    }
    decoded = await response.json();
  } catch (error) {
    console.error("Weather API request failed:", error);
    return null;
  }
  if (!decoded || typeof decoded !== "object") {
    return null;
  }

  const conditionMap = decoded.weatherCondition;
  const conditionType =
    conditionMap && typeof conditionMap === "object" ? conditionMap.type : "";
  const weatherCode = weatherCodeFromGoogleCondition(conditionType);

  const precipitationMap = decoded.precipitation;
  const probabilityMap =
    precipitationMap && typeof precipitationMap === "object"
      ? precipitationMap.probability
      : null;
  const qpfMap =
    precipitationMap && typeof precipitationMap === "object"
      ? precipitationMap.qpf
      : null;
  const windMap = decoded.wind;

  const risk = hikeWeatherRisk({
    weatherCode,
    rainChancePercent:
      probabilityMap && typeof probabilityMap === "object"
        ? Number(probabilityMap.percent)
        : undefined,
    precipitationMm:
      qpfMap && typeof qpfMap === "object" ? Number(qpfMap.quantity) : undefined,
    windSpeedKmh:
      windMap && typeof windMap === "object" ? Number(windMap.speed) : undefined,
  });

  const descriptionMap =
    conditionMap && typeof conditionMap === "object" ? conditionMap.description : null;
  const descriptionText =
    descriptionMap && typeof descriptionMap === "object"
      ? String(descriptionMap.text || "").trim()
      : "";
  const fallbackHeadline = {
    unsafe: "Rough weather is rolling in near you",
    caution: "Weather looks a bit unsettled near you",
    good: "Clear skies near you",
  }[risk];

  const snapshot = {
    isSevere: risk === "unsafe",
    isCaution: risk === "caution",
    isSunny: risk === "good" && weatherCode <= 2,
    headline: descriptionText || fallbackHeadline,
  };

  if (redis) {
    // 10-minute TTL; a write failure should never fail the user-facing
    // request, so this is fire-and-forget from the caller's perspective.
    await redis.set(cacheKey, snapshot, { ex: 600 }).catch(() => {});
  }

  return snapshot;
}
exports.buildWeatherSnapshot = buildWeatherSnapshot;

exports.fetchWeatherSnapshot = onCall(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: ["WEATHER_API_KEY", "UPSTASH_REDIS_REST_URL", "UPSTASH_REDIS_REST_TOKEN"],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    if (!isFiniteNumberInRange(latitude, -90, 90)) {
      throw new HttpsError("invalid-argument", "Invalid latitude.");
    }
    if (!isFiniteNumberInRange(longitude, -180, 180)) {
      throw new HttpsError("invalid-argument", "Invalid longitude.");
    }

    const redis = getRedisClient();
    await enforceRateLimit({
      redis,
      key: `ratelimit:fetchWeatherSnapshot:${request.auth.uid}`,
      maxCalls: 30,
      windowSeconds: 60,
    });

    return buildWeatherSnapshot({ latitude, longitude, redis, fetchFn: fetch });
  },
);

// Only records the submission for admin review — publishing to
// mountain_trails, notifying the submitter, and notifying other hikers all
// now happen in reviewTrailSubmission (trailReview.js), gated on an actual
// admin decision from the Trail Verification page. This trigger used to
// auto-publish and flip the doc's status off "pending" within seconds of
// upload, which meant the admin dashboard's "pending" list emptied itself
// before anyone could review anything — it only records + alerts admins now.
exports.onTrailSubmissionCreated = onDocumentCreated(
  {
    document: "trail_submissions/{submissionId}",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const submissionId = event.params.submissionId;
    const data = snapshot.data() || {};
    const mountainKey = String(data.mountainKey || "").trim();
    const mountainName = String(data.mountainName || "").trim();
    const trailName = String(data.trailName || mountainName || "Unnamed trail").trim();
    const submitterUid = String(data.submittedBy || "").trim();

    let submitterName = String(data.submitterName || data.authorName || "").trim();
    if (submitterUid) {
      const submitterSnap = await db.collection("users").doc(submitterUid).get();
      const submitter = submitterSnap.data() || {};
      submitterName = submitterName || String(
        submitter.fullName || submitter.username || submitter.email || "",
      ).trim();
    }
    submitterName = submitterName || "Unknown user";

    // Use deterministic IDs so a retried Firestore event cannot create
    // duplicate audit rows or admin notifications.
    const auditRef = db.collection("admin_actions").doc(`trail_submission_${submissionId}`);
    const notificationRef = db.collection("notifications").doc(`trail_submission_${submissionId}`);
    await db.runTransaction(async (transaction) => {
      const [auditSnap, notificationSnap] = await Promise.all([
        transaction.get(auditRef),
        transaction.get(notificationRef),
      ]);
      if (!auditSnap.exists) {
        transaction.create(auditRef, {
          action: "submit_trail_route",
          targetId: submissionId,
          trailName,
          mountainName,
          mountainKey,
          submittedBy: submitterUid,
          submitterName,
          previousStatus: null,
          newStatus: "received",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      if (!notificationSnap.exists) {
        transaction.create(notificationRef, {
          type: "trail_submission",
          title: "New Trail Route Submission",
          message: `${submitterName} submitted ${trailName} for ${mountainName || "a mountain"}.`,
          trailSubmissionId: submissionId,
          mountainKey,
          mountainName,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });
  },
);

// Every audit record also becomes an in-app admin notification. Trail
// submission notifications are created with the audit row above so their
// message includes the submitter and trail name; this trigger handles all
// other admin actions and safely tolerates Firestore event retries.
exports.onAdminActionCreated = onDocumentCreated(
  {
    document: "admin_actions/{actionId}",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data() || {};
    if (data.notifyAdmins === false) return;
    const actionId = event.params.actionId;
    const action = String(data.action || "admin_action");
    const notificationId = action === "submit_trail_route"
      ? `trail_submission_${data.targetId || actionId}`
      : `admin_action_${actionId}`;
    const notificationRef = db.collection("notifications").doc(notificationId);
    const actionLabels = {
      create_admin: "Created an admin account",
      approve_tour_guide: "Approved a tour guide",
      reject_tour_guide: "Rejected a tour guide",
      revoke_admin: "Revoked admin access",
      suspend: "Suspended an account",
      restore: "Restored an account",
      delete_user_account: "Deleted a user account",
      cleanup_orphaned_sos_events: "Removed SOS alerts from deleted users",
      rename_bluetooth_device: "Renamed a Bluetooth device",
      submit_trail_route: "Received a trail route submission",
      approve_trail_submission: "Approved a trail submission",
      reject_trail_submission: "Rejected a trail submission",
      auto_close_abandoned_room: "Auto-closed an abandoned hike room",
    };
    const label = actionLabels[action] || action.replaceAll("_", " ");
    const target = String(
      data.trailName || data.mountainName || data.targetName || data.targetId || "",
    ).trim();
    let actor = String(
      data.submitterName || data.adminName || data.adminEmail || data.actorEmail ||
      data.adminId || data.submittedBy ||
      (action === "auto_close_abandoned_room" ? "System" : "An administrator"),
    ).trim();
    if (data.adminId && !data.adminName) {
      const adminProfile = await db.collection("users").doc(String(data.adminId)).get();
      const profile = adminProfile.data() || {};
      let adminName = profile.fullName || profile.displayName || profile.name;
      if (!adminName) {
        try {
          const authUser = await admin.auth().getUser(String(data.adminId));
          adminName = authUser.displayName;
        } catch (_) {
          // Keep the email/uid fallback when the Auth account has no name.
        }
      }
      actor = String(adminName || actor).trim();
    }

    await db.runTransaction(async (transaction) => {
      const notificationSnap = await transaction.get(notificationRef);
      if (notificationSnap.exists) return;
      transaction.create(notificationRef, {
        type: "admin_action",
        title: action === "submit_trail_route"
          ? "New Trail Route Submission"
          : "Admin Activity",
        message: `${actor}: ${label}${target ? ` — ${target}` : ""}.`,
        actionId,
        action,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);

// Keep a distinct name: the deployed onCommunityCommentCreated function is
// an HTTPS endpoint, and Firebase cannot change a function's trigger type.
exports.notifyOnCommunityCommentCreated = onDocumentCreated(
  {
    document: "community_posts/{postId}/comments/{commentId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const { postId } = event.params;
    const comment = snapshot.data() || {};
    const commenterUid = String(comment.authorId || "").trim();
    if (!commenterUid) {
      return;
    }

    const postSnap = await db.collection("community_posts").doc(postId).get();
    if (!postSnap.exists) {
      return;
    }
    const post = postSnap.data() || {};
    const postAuthorId = String(post.authorId || "").trim();
    if (!postAuthorId || postAuthorId === commenterUid) {
      return;
    }

    const commenterName = String(comment.authorName || "").trim() || "Someone";
    const preview = String(comment.content || "").trim();
    const truncated =
      preview.length > 80 ? `${preview.slice(0, 80)}...` : preview;
    const body = truncated
      ? `${commenterName} commented: "${truncated}"`
      : `${commenterName} commented on your post.`;

    await db
      .collection("users")
      .doc(postAuthorId)
      .collection("notifications")
      .add({
        type: "comment",
        title: "New comment on your post",
        body,
        postId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  },
);

async function notifyCommunityLike(event, isCommentLike) {
  const snapshot = event.data;
  if (!snapshot) {
    return;
  }

  const { postId, commentId, likerId: pathLikerId } = event.params;
  const likerId = String(snapshot.data()?.userId || pathLikerId || "").trim();
  if (!likerId) {
    return;
  }

  const postSnap = await db.collection("community_posts").doc(postId).get();
  if (!postSnap.exists) {
    return;
  }

  let recipientId = String(postSnap.data()?.authorId || "").trim();
  if (isCommentLike) {
    const commentSnap = await db
      .collection("community_posts")
      .doc(postId)
      .collection("comments")
      .doc(commentId)
      .get();
    if (!commentSnap.exists) {
      return;
    }
    recipientId = String(commentSnap.data()?.authorId || "").trim();
  }
  if (!recipientId || recipientId === likerId) {
    return;
  }

  const notificationRef = db
    .collection("users")
    .doc(recipientId)
    .collection("notifications")
    .doc(event.id);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(notificationRef);
    if (existing.exists) {
      return;
    }
    transaction.create(notificationRef, {
      type: "like",
      title: isCommentLike ? "Your comment got a like" : "Your post got a like",
      body: isCommentLike
        ? "Someone liked your comment."
        : "Someone liked your post.",
      postId,
      ...(isCommentLike ? { commentId } : {}),
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

exports.notifyOnCommunityPostLiked = onDocumentCreated(
  {
    document: "community_posts/{postId}/likes/{likerId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  (event) => notifyCommunityLike(event, false),
);

exports.notifyOnCommunityCommentLiked = onDocumentCreated(
  {
    document: "community_posts/{postId}/comments/{commentId}/likes/{likerId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  (event) => notifyCommunityLike(event, true),
);
