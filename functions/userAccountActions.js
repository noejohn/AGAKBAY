const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

// User-owned hike data is stored under hike_rooms, not users/{uid}. Remove
// their SOS event details and membership, and end any room they guide so
// other participants are not left in a live room without its guide.
async function deleteUserHikeRecords(db, uid) {
  const [sosEvents, participants, sosNotifications, rooms] = await Promise.all([
    db.collectionGroup("sos_events").where("senderId", "==", uid).get(),
    db.collectionGroup("participants").where("userId", "==", uid).get(),
    db.collection("notifications")
      .where("type", "==", "sos")
      .where("senderId", "==", uid)
      .get(),
    db.collection("hike_rooms").get(),
  ]);

  const writesByPath = new Map();
  const queueUpdate = (ref, data) => writesByPath.set(ref.path, { ref, data });
  const queueDelete = (ref) => writesByPath.set(ref.path, { ref, delete: true });

  for (const doc of sosEvents.docs) queueDelete(doc.ref);
  for (const doc of sosNotifications.docs) {
    queueDelete(doc.ref);
  }
  for (const doc of sosEvents.docs) {
    const roomId = doc.ref.parent.parent?.id;
    if (roomId) {
      queueDelete(db.collection("notifications").doc(`sos_${roomId}_${doc.id}`));
    }
  }

  // Close rooms led by this user, finish memberships for the remaining
  // participants, and clear their active-room pointers.
  for (const room of rooms.docs) {
    const targetParticipantRef = room.ref.collection("participants").doc(uid);
    const targetParticipant = await targetParticipantRef.get();
    if (targetParticipant.exists) queueDelete(targetParticipantRef);
    if (room.data().guideId !== uid) continue;
    queueUpdate(room.ref, {
      status: "ended",
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      autoEndedReason: "guide_account_deleted",
    });
    const roomParticipants = await room.ref.collection("participants").get();
    for (const participant of roomParticipants.docs) {
      const participantData = participant.data();
      if (participantData.userId === uid || participant.id === uid) {
        queueDelete(participant.ref);
        continue;
      }
      if ((participantData.membershipStatus || "active") === "active") {
        queueUpdate(participant.ref, {
          membershipStatus: "room_ended",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const participantUserRef = db.collection("users").doc(participant.id);
        const participantUser = await participantUserRef.get();
        if (participantUser.exists) {
          queueUpdate(participantUserRef, {
            activeHikeRoomId: admin.firestore.FieldValue.delete(),
          });
        }
      }
    }
  }

  // Remove the deleted user's participant rows from rooms led by other users.
  for (const participant of participants.docs) {
    const roomRef = participant.ref.parent.parent;
    if (!roomRef) continue;
    const room = rooms.docs.find((doc) => doc.ref.path === roomRef.path);
    if (room?.data().guideId === uid) continue;
    queueDelete(participant.ref);
  }

  for (const room of rooms.docs) {
    queueDelete(room.ref.collection("sos_cooldowns").doc(uid));
  }

  const writes = [...writesByPath.values()];

  for (let offset = 0; offset < writes.length; offset += 450) {
    const batch = db.batch();
    for (const write of writes.slice(offset, offset + 450)) {
      if (write.delete) batch.delete(write.ref);
      else batch.update(write.ref, write.data);
    }
    await batch.commit();
  }
}

exports.cleanupOrphanedSosEvents = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const db = admin.firestore();
    const [events, anonymizedEvents] = await Promise.all([
      db.collectionGroup("sos_events").where("senderId", "!=", "").get(),
      db.collectionGroup("sos_events").where("senderName", "==", "user").get(),
    ]);

    const candidates = new Map();
    for (const event of events.docs) candidates.set(event.ref.path, event);
    // Older account deletion code anonymized senderName and removed senderId.
    for (const event of anonymizedEvents.docs) {
      if (!event.data().senderId) candidates.set(event.ref.path, event);
    }

    const senderIds = [...new Set([...candidates.values()]
      .map((event) => event.data().senderId)
      .filter((uid) => typeof uid === "string" && uid))];
    const profileExists = new Map();
    for (let offset = 0; offset < senderIds.length; offset += 400) {
      const batchIds = senderIds.slice(offset, offset + 400);
      const profiles = await db.getAll(...batchIds.map((uid) => db.collection("users").doc(uid)));
      profiles.forEach((profile) => profileExists.set(profile.id, profile.exists));
    }

    const orphaned = [...candidates.values()].filter((event) => {
      const uid = event.data().senderId;
      return !uid || profileExists.get(uid) === false;
    });
    const notifications = new Map();
    for (const event of orphaned) {
      const roomId = event.ref.parent.parent?.id;
      if (roomId) {
        const notificationRef = db.collection("notifications").doc(`sos_${roomId}_${event.id}`);
        notifications.set(notificationRef.path, notificationRef);
      }
    }

    const notificationRefs = [...notifications.values()];
    const existingNotificationRefs = [];
    for (let offset = 0; offset < notificationRefs.length; offset += 400) {
      const snapshots = await db.getAll(...notificationRefs.slice(offset, offset + 400));
      snapshots.forEach((snapshot) => {
        if (snapshot.exists) existingNotificationRefs.push(snapshot.ref);
      });
    }

    const refsToDelete = [
      ...orphaned.map((event) => event.ref),
      ...existingNotificationRefs,
    ];
    for (let offset = 0; offset < refsToDelete.length; offset += 450) {
      const batch = db.batch();
      for (const ref of refsToDelete.slice(offset, offset + 450)) batch.delete(ref);
      await batch.commit();
    }

    return {
      deletedSosEvents: orphaned.length,
      deletedSosNotifications: existingNotificationRefs.length,
    };
  },
);

exports.manageUserAccount = onCall(
  { timeoutSeconds: 120, memory: "256MiB" },
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

    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }
    const profile = userSnap.data() || {};
    const isAdmin = profile.adminAccess === true || profile.role === "admin" || profile.accountType === "admin";

    let target;
    try {
      target = await auth.getUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
      if (action !== "delete") {
        // Suspend/restore/revoke need a live sign-in account to act on.
        // This one has none — either it was already removed on the Auth
        // side, or this Firestore doc was created without one — so only
        // deleting the leftover profile data makes sense here.
        throw new HttpsError(
          "failed-precondition",
          "This profile has no sign-in account — it can only be deleted, not suspended or restored.",
        );
      }
      await deleteUserHikeRecords(db, uid);
      await db.collection("admin_actions").add({
        adminId: request.auth.uid,
        adminEmail: request.auth.token.email || null,
        action: "delete_user_account",
        targetId: uid,
        targetEmail: profile.email || null,
        targetName: profile.fullName || profile.displayName || null,
        previousStatus: isAdmin ? "admin" : "standard",
        newStatus: "deleted",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await db.recursiveDelete(userRef);
      return { action, status: "deleted" };
    }

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
        adminEmail: request.auth.token.email || null,
        action: "delete_user_account",
        targetId: uid,
        targetEmail: profile.email || null,
        targetName: profile.fullName || profile.displayName || null,
        previousStatus: isAdmin ? "admin" : "standard",
        newStatus: "deleted",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await deleteUserHikeRecords(db, uid);
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
      adminEmail: request.auth.token.email || null,
      action,
      targetId: uid,
      targetEmail: profile.email || null,
      targetName: profile.fullName || profile.displayName || null,
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
        adminEmail: request.auth.token.email || null,
        action: "create_admin",
        targetId: createdUser.uid,
        targetEmail: email,
        targetName: fullName,
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
