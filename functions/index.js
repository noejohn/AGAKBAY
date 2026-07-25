const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

admin.initializeApp();

const db = admin.firestore();
const AUTH_ATTEMPT_LIMIT = 5;
const CODE_EXPIRY_MINUTES = 10;
const RESEND_COOLDOWN_SECONDS = 45;

function randomSixDigitCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashCode({ code, uid }) {
  return crypto
    .createHash("sha256")
    .update(`${uid}:${code}`)
    .digest("hex");
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
