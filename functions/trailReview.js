const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { sanitizeRoutePoints } = require("./routePoints");

async function notifyHikersOfNewTrail(db, { mountainKey, mountainName, submitterUid }) {
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

// Called from the Admin Web dashboard's Trail Verification page. Publishing
// to mountain_trails and every notification here only ever happens after an
// actual admin decision — onTrailSubmissionCreated (functions/index.js) just
// records the submission and alerts admins that something is waiting.
exports.reviewTrailSubmission = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const submissionId = request.data?.submissionId;
    const decision = request.data?.decision;
    if (typeof submissionId !== "string" || !submissionId) {
      throw new HttpsError("invalid-argument", "submissionId is required.");
    }
    if (decision !== "approve" && decision !== "reject") {
      throw new HttpsError("invalid-argument", "decision must be 'approve' or 'reject'.");
    }

    const db = admin.firestore();
    const submissionRef = db.collection("trail_submissions").doc(submissionId);
    const snap = await submissionRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "No trail submission found.");
    }
    const submission = snap.data() || {};
    if (submission.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "This submission has already been reviewed.",
      );
    }

    const approved = decision === "approve";
    const submitterUid = String(submission.submittedBy || "").trim();
    const mountainKey = String(submission.mountainKey || "").trim();
    const mountainName = String(submission.mountainName || "").trim();
    const trailName = String(submission.trailName || mountainName || "Unnamed trail").trim();
    const reason = typeof request.data?.reason === "string" ? request.data.reason : null;

    await submissionRef.update({
      status: approved ? "approved" : "rejected",
      reviewedBy: request.auth.uid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewNote: reason,
    });

    if (approved) {
      const routePoints = sanitizeRoutePoints(submission.routePoints);
      if (mountainKey && routePoints.length >= 2) {
        const stations = Array.isArray(submission.stations)
          ? submission.stations.map((name) => String(name).trim()).filter(Boolean)
          : [];
        await db.collection("mountain_trails").doc(mountainKey).set(
          {
            mountainKey,
            status: "verified",
            routePoints,
            trailName,
            stations,
            recordedAt: submission.recordedAt || null,
            source: "community_recorded",
            generatedFromSubmissionId: submissionId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    if (submitterUid) {
      await db.collection("users").doc(submitterUid).collection("notifications").add({
        type: "trail",
        title: approved ? "Trail Submission Approved!" : "Trail Submission Update",
        body: approved
          ? `Your trail route for ${trailName} has been approved and published.`
          : reason
            ? `Your trail submission for ${trailName} was not approved: ${reason}`
            : `Your trail submission for ${trailName} was not approved this time.`,
        mountainKey: mountainKey || null,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (approved && mountainKey) {
        await notifyHikersOfNewTrail(db, {
          mountainKey,
          mountainName: trailName || mountainName,
          submitterUid,
        });
      }
    }

    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: approved ? "approve_trail_submission" : "reject_trail_submission",
      targetId: submissionId,
      trailName,
      mountainName,
      previousStatus: "pending",
      newStatus: approved ? "approved" : "rejected",
      reason,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { decision };
  },
);
