const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getRedisClient, weatherCacheKey } = require("./redisCache");
const { enforceRateLimit } = require("./rateLimit");
const { exchangeAuth0Token, setInitialAccountType } = require("./auth0Exchange");

admin.initializeApp();

exports.exchangeAuth0Token = exchangeAuth0Token;
exports.setInitialAccountType = setInitialAccountType;

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

function sanitizeRoutePoints(points) {
  if (!Array.isArray(points)) {
    return [];
  }
  const cleaned = [];
  for (const point of points) {
    if (!point || typeof point !== "object") {
      continue;
    }
    const lat = Number(point.lat);
    const lon = Number(point.lon);
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lon) ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180
    ) {
      continue;
    }
    cleaned.push({
      lat: Number(lat.toFixed(7)),
      lon: Number(lon.toFixed(7)),
    });
  }
  return cleaned;
}
exports.sanitizeRoutePoints = sanitizeRoutePoints;

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
    if (
      !participantSnap.exists ||
      (participantSnap.data()?.membershipStatus ?? "active") !== "active"
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
      senderId: uid,
      senderName,
      latitude,
      longitude,
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
    await batch.commit();

    return { sent: true, eventId: eventRef.id };
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
    if (!mountainKey) {
      return;
    }

    const routePoints = sanitizeRoutePoints(data.routePoints);

    await snapshot.ref.set(
      {
        status: "included",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (routePoints.length < 2) {
      return;
    }

    const trailName = String(data.trailName || data.mountainName || "").trim();
    const stations = Array.isArray(data.stations)
      ? data.stations.map((name) => String(name).trim()).filter(Boolean)
      : [];

    await db.collection("mountain_trails").doc(mountainKey).set(
      {
        mountainKey,
        status: "verified",
        routePoints,
        trailName,
        stations,
        recordedAt: data.recordedAt || null,
        source: "community_recorded",
        generatedFromSubmissionId: submissionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await notifyHikersOfNewTrail({
      mountainKey,
      mountainName: trailName || String(data.mountainName || "").trim(),
      submitterUid: String(data.submittedBy || ""),
    });
  },
);

async function notifyHikersOfNewTrail({ mountainKey, mountainName, submitterUid }) {
  const displayName = mountainName || "a nearby mountain";
  const hikersSnap = await db
    .collection("leaderboard")
    .where("completedTrailKeys", "array-contains", mountainKey)
    .get();

  if (hikersSnap.empty) {
    return;
  }

  const batch = db.batch();
  let notifyCount = 0;
  hikersSnap.forEach((doc) => {
    const uid = doc.id;
    if (!uid || uid === submitterUid) {
      return;
    }
    const notificationRef = db
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .doc();
    batch.set(notificationRef, {
      type: "trail",
      title: "New trail recorded",
      body: `Someone recorded a trail for ${displayName}. Check it out!`,
      mountainKey,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    notifyCount += 1;
  });

  if (notifyCount > 0) {
    await batch.commit();
  }
}

exports.onCommunityCommentCreated = onDocumentCreated(
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
