const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

// Called from the Admin Web dashboard's Tour Guide Verification page.
// Gated on the `admin` custom claim (mirrored by exchangeAuth0Token from
// Firestore's role field — see functions/auth0Exchange.js) rather than
// any client-supplied flag, since firestore.rules never lets a client
// write "admin" onto their own doc (see firestore.rules' users/{userId}
// create rule).
exports.reviewTourGuideApplication = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const targetUid = request.data?.uid;
    const decision = request.data?.decision;
    if (typeof targetUid !== "string" || !targetUid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    if (decision !== "approve" && decision !== "reject") {
      throw new HttpsError("invalid-argument", "decision must be 'approve' or 'reject'.");
    }

    const db = admin.firestore();
    const userRef = db.collection("users").doc(targetUid);
    const snap = await userRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "No user profile found.");
    }
    const data = snap.data();
    if (data.accountType !== "tour_guide" || data.guideVerified !== false) {
      throw new HttpsError(
        "failed-precondition",
        "This account has no pending tour guide application.",
      );
    }

    const approved = decision === "approve";
    // Rejecting drops the account back to hiker rather than leaving it in
    // limbo — matches the AGAKBAY admin-plan's "kapag rejected, mananatiling
    // Hiker ang account" rule, and re-declaring as tour_guide later just
    // starts a fresh application.
    const update = approved
      ? { guideVerified: true }
      : { role: "hiker", accountType: "hiker", guideVerified: null };
    await userRef.update({
      ...update,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const claims = approved
      ? { role: "tour_guide", accountType: "tour_guide", guideVerified: true, admin: false }
      : { role: "hiker", accountType: "hiker", guideVerified: null, admin: false };
    await admin.auth().setCustomUserClaims(targetUid, claims);

    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      action: approved ? "approve_tour_guide" : "reject_tour_guide",
      targetId: targetUid,
      previousStatus: "pending",
      newStatus: approved ? "approved" : "rejected",
      reason: typeof request.data?.reason === "string" ? request.data.reason : null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { decision };
  },
);
