const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

// Actions whose targetId is a users/{uid} doc — worth resolving to a name/
// email. Other actions (rename_bluetooth_device, submit_trail_route) either
// target something that isn't a user or already carry their own readable
// fields, so they're left alone here.
const USER_TARGET_ACTIONS = new Set([
  "create_admin",
  "approve_tour_guide",
  "reject_tour_guide",
  "revoke_admin",
  "suspend",
  "restore",
  "delete_user_account",
]);

// One-time cleanup for admin_actions documents written before adminEmail/
// targetEmail/targetName existed (see userAccountActions.js, adminActions.js,
// bluetoothActivity.js) — those older rows only ever stored raw uids, which
// read as meaningless strings in the Audit Logs table. Triggered from the
// dashboard's "Fix Older Records" button rather than a local script, since
// the person running this dashboard isn't set up to run node scripts with a
// service-account key.
exports.backfillAuditLogNames = onCall(
  { timeoutSeconds: 120, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const db = admin.firestore();
    const auth = admin.auth();
    const snap = await db.collection("admin_actions").get();

    const userCache = new Map();
    async function resolveUser(uid) {
      if (!uid) return {};
      if (userCache.has(uid)) return userCache.get(uid);
      let email = null;
      let name = null;
      try {
        const userSnap = await db.collection("users").doc(uid).get();
        if (userSnap.exists) {
          const data = userSnap.data() || {};
          email = data.email || null;
          name = data.fullName || data.displayName || null;
        }
      } catch (error) {
        console.error(`Could not read users/${uid} during audit backfill:`, error);
      }
      if (!email) {
        try {
          const authUser = await auth.getUser(uid);
          email = email || authUser.email || null;
          name = name || authUser.displayName || null;
        } catch (_) {
          // Auth account no longer exists (deleted/orphaned) — leave blank,
          // the row will keep showing the raw uid for this one.
        }
      }
      const result = { email, name };
      userCache.set(uid, result);
      return result;
    }

    let updated = 0;
    const batch = db.batch();
    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.adminEmail !== undefined && data.adminName !== undefined) continue;
      const updates = {};
      if (data.adminId) {
        const adminInfo = await resolveUser(data.adminId);
        updates.adminEmail = adminInfo.email;
        updates.adminName = adminInfo.name;
      }
      if (USER_TARGET_ACTIONS.has(data.action) && data.targetId) {
        const targetInfo = await resolveUser(data.targetId);
        updates.targetEmail = targetInfo.email;
        updates.targetName = targetInfo.name;
      }
      if (Object.keys(updates).length > 0) {
        batch.update(doc.ref, updates);
        updated += 1;
      }
    }
    if (updated > 0) await batch.commit();

    return { scanned: snap.size, updated };
  },
);
