const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

exports.manageUserAccount = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const uid = request.data?.uid;
    const action = request.data?.action;
    if (typeof uid !== "string" || !uid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    if (!["revoke_admin", "suspend", "restore", "delete"].includes(action)) {
      throw new HttpsError("invalid-argument", "Unsupported account action.");
    }
    if (uid === request.auth.uid) {
      throw new HttpsError("failed-precondition", "You cannot restrict your own admin account.");
    }

    const auth = admin.auth();
    const db = admin.firestore();
    let target;
    try {
      target = await auth.getUser(uid);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        throw new HttpsError("not-found", "Authentication account not found.");
      }
      throw error;
    }

    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }
    const profile = userSnap.data() || {};
    const isAdmin = profile.adminAccess === true || profile.role === "admin" || profile.accountType === "admin";

    if (["revoke_admin", "suspend", "delete"].includes(action) && isAdmin) {
      const markedAdmins = await db.collection("users").where("adminAccess", "==", true).get();
      const legacyAdmins = await db.collection("users").where("role", "==", "admin").get();
      const legacyAccountTypeAdmins = await db.collection("users").where("accountType", "==", "admin").get();
      const admins = new Map([
        ...markedAdmins.docs,
        ...legacyAdmins.docs,
        ...legacyAccountTypeAdmins.docs,
      ].map((doc) => [doc.id, doc.data()]));
      const activeAdminsRemaining = [...admins.entries()].filter(
        ([adminUid, data]) => adminUid !== uid && data.accountSuspended !== true,
      ).length;
      if (activeAdminsRemaining === 0 && profile.accountSuspended !== true) {
        throw new HttpsError("failed-precondition", "You cannot remove, suspend, or delete the last admin.");
      }
    }

    if (action === "delete") {
      await db.collection("admin_actions").add({
        adminId: request.auth.uid,
        action: "delete_user_account",
        targetId: uid,
        previousStatus: isAdmin ? "admin" : "standard",
        newStatus: "deleted",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await auth.deleteUser(uid);
      await db.recursiveDelete(userRef);
      return { action, status: "deleted" };
    }

    const claims = { ...(target.customClaims || {}) };
    const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    let previousStatus;
    let newStatus;

    if (action === "revoke_admin") {
      claims.admin = false;
      claims.role = profile.accountType && profile.accountType !== "admin"
        ? profile.accountType
        : "hiker";
      updates.adminAccess = false;
      updates.role = profile.accountType && profile.accountType !== "admin"
        ? profile.accountType
        : "hiker";
      if (profile.accountType === "admin") updates.accountType = "hiker";
      previousStatus = isAdmin ? "admin" : "standard";
      newStatus = "standard";
      await auth.setCustomUserClaims(uid, claims);
    } else {
      const suspend = action === "suspend";
      await auth.updateUser(uid, { disabled: suspend });
      if (suspend) await auth.revokeRefreshTokens(uid);
      updates.accountSuspended = suspend;
      previousStatus = target.disabled ? "suspended" : "active";
      newStatus = suspend ? "suspended" : "active";
    }

    await userRef.update(updates);
    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      action,
      targetId: uid,
      previousStatus,
      newStatus,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { action, status: newStatus };
  },
);

exports.createAdminAccount = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const email = typeof request.data?.email === "string"
      ? request.data.email.trim().toLowerCase()
      : "";
    const fullName = typeof request.data?.fullName === "string"
      ? request.data.fullName.trim()
      : "";
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }
    if (!fullName) {
      throw new HttpsError("invalid-argument", "Full name is required.");
    }

    const auth = admin.auth();
    const db = admin.firestore();
    let createdUser;
    try {
      createdUser = await auth.createUser({
        email,
        displayName: fullName,
        emailVerified: false,
        disabled: false,
      });
      const claims = {
        admin: true,
        role: "admin",
        accountType: "admin",
        guideVerified: null,
      };
      await auth.setCustomUserClaims(createdUser.uid, claims);
      await db.collection("users").doc(createdUser.uid).set({
        uid: createdUser.uid,
        email,
        fullName,
        displayName: fullName,
        username: email.split("@")[0],
        role: "admin",
        accountType: "admin",
        adminAccess: true,
        accountSuspended: false,
        guideVerified: null,
        emailVerified: false,
        accountTypeConfirmed: true,
        onboardingComplete: true,
        verificationMethod: "admin_created",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const resetLink = await auth.generatePasswordResetLink(email);
      await db.collection("admin_actions").add({
        adminId: request.auth.uid,
        action: "create_admin",
        targetId: createdUser.uid,
        previousStatus: null,
        newStatus: "admin",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { uid: createdUser.uid, email, resetLink };
    } catch (error) {
      if (createdUser) {
        await auth.deleteUser(createdUser.uid).catch(() => {});
        await db.collection("users").doc(createdUser.uid).delete().catch(() => {});
      }
      if (error instanceof HttpsError) throw error;
      if (error.code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "An account already uses this email.");
      }
      throw new HttpsError("internal", "Could not create the admin account.");
    }
  },
);
