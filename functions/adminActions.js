const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  assertTourismAdmin,
  assertMountainHead,
  normalizeMountainNames,
} = require("./adminAuthorization");
const { normalizeMountainName } = require("./mountainNames");

// Called from the Admin Web dashboard's Tour Guide Verification page.
// Gated on the `admin` custom claim (mirrored by exchangeAuth0Token from
// Firestore's role field — see functions/auth0Exchange.js) rather than
// any client-supplied flag, since firestore.rules never lets a client
// write "admin" onto their own doc (see firestore.rules' users/{userId}
// create rule).
//
// Reviews a tour_guide_applications doc (submitted via the mobile app's
// "Apply as Tour Guide" form). The applicant's users/{uid} doc is never
// touched by the application itself — it only changes here, on approval —
// so a rejected/pending applicant's account was never anything but a
// normal hiker the whole time; there's nothing to "revert" on rejection.
exports.reviewTourGuideApplication = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    assertTourismAdmin(request.auth);

    const applicationId = request.data?.applicationId;
    const decision = request.data?.decision;
    if (typeof applicationId !== "string" || !applicationId) {
      throw new HttpsError("invalid-argument", "applicationId is required.");
    }
    if (decision !== "approve" && decision !== "reject") {
      throw new HttpsError("invalid-argument", "decision must be 'approve' or 'reject'.");
    }

    const db = admin.firestore();
    const applicationRef = db.collection("tour_guide_applications").doc(applicationId);
    const snap = await applicationRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "No application found.");
    }
    const application = snap.data();
    if (application.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "This application has already been reviewed.",
      );
    }

    const approved = decision === "approve";
    const targetUid = application.uid;
    const reason = typeof request.data?.reason === "string" ? request.data.reason : null;

    await applicationRef.update({
      status: approved ? "approved" : "rejected",
      reviewedBy: request.auth.uid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewNote: reason,
    });

    if (approved) {
      const userRef = db.collection("users").doc(targetUid);
      const mountainNames = Array.isArray(application.mountainNames)
        ? application.mountainNames
          .filter((name) => typeof name === "string")
          .map((name) => name.trim())
          .filter(Boolean)
        : typeof application.mountainsHandled === "string"
          ? application.mountainsHandled
            .split(/[,;\n]/)
            .map((name) => name.trim())
            .filter(Boolean)
          : [];
      await userRef.update({
        role: "tour_guide",
        accountType: "tour_guide",
        guideVerified: true,
        mountainNames: [...new Set(mountainNames)],
        mountainsHandled: application.mountainsHandled || mountainNames.join(", "),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await admin.auth().setCustomUserClaims(targetUid, {
        role: "tour_guide",
        accountType: "tour_guide",
        guideVerified: true,
        admin: false,
      });
    }

    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: approved ? "approve_tour_guide" : "reject_tour_guide",
      targetId: targetUid,
      targetEmail: application.applicantEmail || null,
      targetName: application.fullName || null,
      previousStatus: "pending",
      newStatus: approved ? "approved" : "rejected",
      reason,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Same shape _createUserNotification writes client-side (lib/main.dart)
    // so the existing Notifications sheet renders this with no UI changes.
    await db.collection("users").doc(targetUid).collection("notifications").add({
      type: "guide_application",
      title: approved ? "Tour Guide Application Approved!" : "Tour Guide Application Update",
      body: approved
        ? "Congratulations! Your Tour Guide application has been approved. You can now create and manage Hike Rooms."
        : reason
          ? `Your Tour Guide application was not approved: ${reason}`
          : "Your Tour Guide application was not approved this time. You're welcome to apply again.",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { decision };
  },
);

exports.recommendAdminReview = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const managedMountainName = assertMountainHead(request.auth);
    const targetType = request.data?.targetType;
    const targetId = request.data?.targetId;
    const decision = request.data?.decision;
    const reason = typeof request.data?.reason === "string"
      ? request.data.reason.trim()
      : "";

    if (!["tour_guide_application", "trail_submission"].includes(targetType)) {
      throw new HttpsError("invalid-argument", "Unsupported review type.");
    }
    if (typeof targetId !== "string" || !targetId.trim()) {
      throw new HttpsError("invalid-argument", "targetId is required.");
    }
    if (!["approve", "reject"].includes(decision)) {
      throw new HttpsError("invalid-argument", "decision must be 'approve' or 'reject'.");
    }

    const db = admin.firestore();
    const collectionName = targetType === "tour_guide_application"
      ? "tour_guide_applications"
      : "trail_submissions";
    const targetRef = db.collection(collectionName).doc(targetId);
    const targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "The item to review was not found.");
    }
    const target = targetSnap.data() || {};
    if (target.status !== "pending") {
      throw new HttpsError("failed-precondition", "This item has already been reviewed.");
    }

    const assignedMountain = normalizeMountainName(managedMountainName);
    const mountainMatches = targetType === "trail_submission"
      ? normalizeMountainName(String(target.mountainName || "")) === assignedMountain
      : normalizeMountainNames(target.mountainNames ?? target.mountainsHandled)
        .includes(assignedMountain);
    if (!mountainMatches) {
      throw new HttpsError(
        "permission-denied",
        "This item is outside your managed mountain.",
      );
    }

    const recommendation = {
      decision,
      reason: reason || null,
      mountainName: managedMountainName,
      recommendedBy: request.auth.uid,
      recommendedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await targetRef.update({ mountainHeadRecommendation: recommendation });
    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: "mountain_head_recommendation",
      targetId,
      targetName: target.trailName || target.fullName || target.applicantEmail || targetId,
      mountainName: managedMountainName,
      recommendation: decision,
      reason: reason || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { decision, targetId };
  },
);
