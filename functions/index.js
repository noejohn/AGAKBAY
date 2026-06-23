const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

admin.initializeApp();

const db = admin.firestore();
const AUTH_ATTEMPT_LIMIT = 5;
const CODE_EXPIRY_MINUTES = 10;
const RESEND_COOLDOWN_SECONDS = 45;
const EARTH_RADIUS_METERS = 6371000;

function randomSixDigitCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashCode({ code, uid }) {
  return crypto
    .createHash("sha256")
    .update(`${uid}:${code}`)
    .digest("hex");
}

function toRadians(value) {
  return (value * Math.PI) / 180;
}

function distanceMeters(a, b) {
  const lat1 = Number(a.lat);
  const lon1 = Number(a.lon);
  const lat2 = Number(b.lat);
  const lon2 = Number(b.lon);
  if (
    !Number.isFinite(lat1) ||
    !Number.isFinite(lon1) ||
    !Number.isFinite(lat2) ||
    !Number.isFinite(lon2)
  ) {
    return 0;
  }
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const x =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
  return EARTH_RADIUS_METERS * c;
}

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

function routeLengthMeters(points) {
  if (!Array.isArray(points) || points.length < 2) {
    return 0;
  }
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += distanceMeters(points[i - 1], points[i]);
  }
  return total;
}

function scoreSubmission(data) {
  const routePoints = sanitizeRoutePoints(data.routePoints);
  if (routePoints.length < 20) {
    return { score: 0, routePoints, reason: "too_few_route_points" };
  }
  const trackPoints = Array.isArray(data.trackPoints) ? data.trackPoints : [];
  const trackCount = trackPoints.length;
  if (trackCount < 20) {
    return { score: 0, routePoints, reason: "too_few_track_points" };
  }

  const routeMeters = routeLengthMeters(routePoints);
  if (routeMeters < 1200) {
    return { score: 0, routePoints, reason: "route_too_short" };
  }

  let score = 0;
  const rawQuality = Number(data.qualityScore);
  if (Number.isFinite(rawQuality)) {
    score += Math.max(0, Math.min(1, rawQuality)) * 0.35;
  }
  if (routeMeters >= 3000) score += 0.1;
  if (routeMeters >= 7000) score += 0.1;
  if (Number(data.durationSeconds) >= 3600) score += 0.1;
  if (Number(data.elevationGainMasl) >= 300) score += 0.1;
  if (data.reachedSummit === true) score += 0.15;
  if (trackCount >= 100) score += 0.1;
  if (trackCount >= 250) score += 0.1;

  const normalized = Math.max(0, Math.min(1, score));
  return { score: normalized, routePoints, reason: "ok" };
}

function pickBestRoute(submissions) {
  const sorted = [...submissions].sort((a, b) => b.score - a.score);
  return sorted[0] || null;
}

function deriveTrailStatus({ submissionCount, avgScore }) {
  if (submissionCount >= 8 && avgScore >= 0.72) {
    return "verified";
  }
  if (submissionCount >= 3 && avgScore >= 0.55) {
    return "provisional";
  }
  return "none";
}

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
      await snapshot.ref.set(
        {
          status: "rejected",
          rejectionReason: "missing_mountain_key",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const evaluation = scoreSubmission(data);
    if (evaluation.score < 0.45) {
      await snapshot.ref.set(
        {
          status: "rejected",
          rejectionReason: evaluation.reason,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          normalizedScore: evaluation.score,
        },
        { merge: true },
      );
      return;
    }

    await snapshot.ref.set(
      {
        status: "accepted",
        normalizedScore: evaluation.score,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const submissionsSnap = await db
      .collection("trail_submissions")
      .where("mountainKey", "==", mountainKey)
      .limit(120)
      .get();

    const accepted = [];
    submissionsSnap.forEach((doc) => {
      const item = doc.data();
      const status = String(item.status || "").toLowerCase();
      if (status !== "accepted" && status !== "included") {
        return;
      }
      const scored = scoreSubmission(item);
      if (scored.score < 0.45 || scored.routePoints.length < 20) {
        return;
      }
      accepted.push({
        id: doc.id,
        score: scored.score,
        routePoints: scored.routePoints,
      });
    });

    if (accepted.length === 0) {
      return;
    }

    const best = pickBestRoute(accepted);
    if (!best) {
      return;
    }

    const avgScore =
      accepted.reduce((sum, item) => sum + item.score, 0) / accepted.length;
    const status = deriveTrailStatus({
      submissionCount: accepted.length,
      avgScore,
    });

    const sourceStatus = status === "verified" ? "community_verified" : "community_provisional";

    await db.collection("mountain_trails").doc(mountainKey).set(
      {
        mountainKey,
        status,
        qualityScore: Number(avgScore.toFixed(4)),
        submissionCount: accepted.length,
        routePoints: best.routePoints,
        source: sourceStatus,
        generatedFromSubmissionId: submissionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const includedRefs = accepted.slice(0, 12).map((item) =>
      db.collection("trail_submissions").doc(item.id)
    );
    const batch = db.batch();
    for (const ref of includedRefs) {
      batch.set(
        ref,
        {
          status: "included",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
  },
);
