const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { assertTourismAdmin } = require("./adminAuthorization");
const { canonicalizeDavaoMountainName } = require("./mountainNames");
const { MAIL_SECRETS, sendAdminWelcomeEmail } = require("./mailer");

exports.refreshAdminClaims = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to verify admin access.");
    }

    let phase = "read-admin-profile";
    try {
      const db = admin.firestore();
      const profileSnap = await db.collection("users").doc(uid).get();
      if (!profileSnap.exists) {
        throw new HttpsError("permission-denied", "No admin profile was found.");
      }

      const profile = profileSnap.data() || {};
      if (
        profile.adminAccess !== true &&
        profile.role !== "admin" &&
        profile.accountType !== "admin"
      ) {
        throw new HttpsError("permission-denied", "Admin access is not enabled.");
      }

      const adminRole = profile.adminRole || "tourism_admin";
      if (!["tourism_admin", "mountain_head"].includes(adminRole)) {
        throw new HttpsError("failed-precondition", "Unsupported admin role.");
      }

      const managedMountainName = typeof profile.managedMountainName === "string"
        ? profile.managedMountainName.trim()
        : "";
      if (adminRole === "mountain_head" && !managedMountainName) {
        throw new HttpsError(
          "failed-precondition",
          "This Mountain Head account has no assigned mountain.",
        );
      }

      phase = "read-auth-user";
      const auth = admin.auth();
      const userRecord = await auth.getUser(uid);
      const claims = {
        ...(userRecord.customClaims || {}),
        admin: true,
        role: "admin",
        accountType: "admin",
        adminRole,
      };
      if (adminRole === "mountain_head") {
        claims.managedMountainName = managedMountainName;
      } else {
        delete claims.managedMountainName;
      }
      phase = "write-custom-claims";
      await auth.setCustomUserClaims(uid, claims);

      return { adminRole, managedMountainName: managedMountainName || null };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("refreshAdminClaims failed", {
        uid,
        phase,
        code: error?.code || null,
        message: error?.message || String(error),
      });
      throw new HttpsError(
        "internal",
        `Admin role refresh failed during ${phase}. Check Cloud Function logs.`,
      );
    }
  },
);

// User-owned hike data is stored under hike_rooms, not users/{uid}. Remove
// their SOS event details and membership, and end any room they guide so
// other participants are not left in a live room without its guide.
// Runs `worker` over `items` with at most `limit` in flight at once — every
// item used to be awaited one after another, so deletion time grew with
// every hike room ever created.
async function forEachConcurrently(items, limit, worker) {
  for (let offset = 0; offset < items.length; offset += limit) {
    await Promise.all(items.slice(offset, offset + limit).map(worker));
  }
}

async function deleteUserHikeRecords(db, uid) {
  // Only this user's SOS notifications — not the whole collection.
  const [sosNotifications, rooms] = await Promise.all([
    db.collection("notifications").where("senderId", "==", uid).get(),
    db.collection("hike_rooms").get(),
  ]);

  const writesByPath = new Map();
  const queueUpdate = (ref, data) => writesByPath.set(ref.path, { ref, data });
  const queueDelete = (ref) => writesByPath.set(ref.path, { ref, delete: true });

  for (const notification of sosNotifications.docs) {
    if (notification.data().type === "sos") queueDelete(notification.ref);
  }

  // Walk rooms directly so deletion does not depend on collection-group
  // indexes for participant or SOS sender fields — but check them in
  // parallel, and only read the SOS events this user actually sent.
  await forEachConcurrently(rooms.docs, 20, async (room) => {
    const targetParticipantRef = room.ref.collection("participants").doc(uid);
    const [targetParticipant, sosEvents] = await Promise.all([
      targetParticipantRef.get(),
      room.ref.collection("sos_events").where("senderId", "==", uid).get(),
    ]);
    if (targetParticipant.exists) queueDelete(targetParticipantRef);

    for (const event of sosEvents.docs) {
      queueDelete(event.ref);
      queueDelete(
        db.collection("notifications").doc(`sos_${room.id}_${event.id}`),
      );
    }

    queueDelete(room.ref.collection("sos_cooldowns").doc(uid));
    if (room.data().guideId !== uid) return;

    queueUpdate(room.ref, {
      status: "ended",
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      autoEndedReason: "guide_account_deleted",
    });
    const roomParticipants = await room.ref.collection("participants").get();
    await Promise.all(roomParticipants.docs.map(async (participant) => {
      const participantData = participant.data();
      if (participantData.userId === uid || participant.id === uid) {
        queueDelete(participant.ref);
        return;
      }
      if ((participantData.membershipStatus || "active") !== "active") return;
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
    }));
  });

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

async function deletePrivateUserData(db, uid, storage = admin.storage()) {
  const applications = await db.collection("tour_guide_applications")
    .where("uid", "==", uid)
    .get();

  for (let offset = 0; offset < applications.docs.length; offset += 450) {
    const batch = db.batch();
    for (const application of applications.docs.slice(offset, offset + 450)) {
      batch.delete(application.ref);
    }
    await batch.commit();
  }

  const bucket = storage.bucket();
  await Promise.all([
    bucket.deleteFiles({ prefix: `profile_photos/${uid}/` }),
    bucket.deleteFiles({ prefix: `tour_guide_applications/${uid}/` }),
  ]);
}

exports.deletePrivateUserData = deletePrivateUserData;

async function findDeletedSosSenderIds(db, auth, eventDocs) {
  const docs = eventDocs ?? (await db.collectionGroup("sos_events").get()).docs;
  const senderIds = [...new Set(docs
    .map((event) => event.data().senderId)
    .filter((uid) => typeof uid === "string" && uid))];

  // A missing profile alone does not mean its owner deleted their account.
  // Use Firebase Authentication as the source of truth.
  const deletedSenderIds = new Set();
  for (let offset = 0; offset < senderIds.length; offset += 100) {
    const batchIds = senderIds.slice(offset, offset + 100);
    const result = await auth.getUsers(batchIds.map((uid) => ({ uid })));
    for (const missingUser of result.notFound) {
      if (missingUser.uid) deletedSenderIds.add(missingUser.uid);
    }
  }
  return deletedSenderIds;
}

exports.findDeletedSosSenderIds = findDeletedSosSenderIds;

async function writeSosCleanupAudit(db, auth, counts) {
  const auditRef = db.collection("admin_actions").doc();
  const notificationRef = db.collection("notifications")
    .doc(`admin_action_${auditRef.id}`);
  const action = "cleanup_orphaned_sos_events";
  const adminName = auth.token?.name || auth.token?.email || auth.uid;
  const message = `${adminName}: Cleaned up deleted users' SOS alerts — ` +
    `Removed ${counts.deletedSosEvents} SOS alerts and ` +
    `${counts.deletedSosNotifications} notifications.`;
  const createdAt = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(auditRef, {
    adminId: auth.uid,
    adminEmail: auth.token?.email || null,
    action,
    targetName: "Deleted users' SOS alerts",
    deletedSosEvents: counts.deletedSosEvents,
    deletedSosNotifications: counts.deletedSosNotifications,
    createdAt,
    notifyAdmins: false,
  });
  batch.set(notificationRef, {
    type: "admin_action",
    title: "Admin Activity",
    message,
    actionId: auditRef.id,
    action,
    isRead: false,
    createdAt,
  });
  await batch.commit();
}

exports.writeSosCleanupAudit = writeSosCleanupAudit;

async function deleteUserAccount({
  db,
  auth,
  request,
  uid,
  profile,
  userRef,
  isAdmin,
  deleteAuthUser,
  cleanupHikeData = deleteUserHikeRecords,
  cleanupPrivateData = deletePrivateUserData,
}) {
  let phase = "write-audit-log";
  try {
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

    // The sign-in account goes FIRST: it frees the email for a new sign-up
    // and locks the person out immediately. If any cleanup step below then
    // fails or times out, the leftover profile can simply be deleted again
    // (manageUserAccount handles a profile with no sign-in account).
    if (deleteAuthUser) {
      phase = "delete-auth-account";
      try {
        await auth.deleteUser(uid);
      } catch (error) {
        if (error.code !== "auth/user-not-found") throw error;
      }
    }

    phase = "clean-up-hike-data";
    await cleanupHikeData(db, uid);

    phase = "delete-private-user-data";
    await cleanupPrivateData(db, uid);

    phase = "delete-firestore-profile";
    await db.recursiveDelete(userRef);
    return { action: "delete", status: "deleted" };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("manageUserAccount delete failed", {
      uid,
      adminUid: request.auth.uid,
      phase,
      code: error?.code || null,
      message: error?.message || String(error),
    });
    throw new HttpsError(
      "internal",
      `Account deletion failed during ${phase}. Check Cloud Function logs.`,
    );
  }
}

exports.deleteUserAccount = deleteUserAccount;

exports.getDeletedSosSenderIds = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    assertTourismAdmin(request.auth);

    const deletedSenderIds = await findDeletedSosSenderIds(
      admin.firestore(),
      admin.auth(),
    );
    return { senderIds: [...deletedSenderIds] };
  },
);

exports.cleanupOrphanedSosEvents = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    assertTourismAdmin(request.auth);

    const db = admin.firestore();
    const events = await db.collectionGroup("sos_events").get();
    const deletedSenderIds = await findDeletedSosSenderIds(
      db,
      admin.auth(),
      events.docs,
    );

    const orphaned = events.docs.filter((event) => {
      const data = event.data();
      const senderId = data.senderId?.toString() ?? "";
      return deletedSenderIds.has(senderId) ||
          (!senderId && data.senderName?.toString().trim().toLowerCase() === "user");
    });
    const notifications = new Map();
    for (const event of orphaned) {
      const roomId = event.ref.parent.parent?.id;
      if (roomId) {
        const notificationRef = db.collection("notifications").doc(`sos_${roomId}_${event.id}`);
        notifications.set(notificationRef.path, notificationRef);
      }
    }

    // Also remove any older SOS notification for a deleted sender, including
    // notifications whose event was already removed in an earlier cleanup.
    for (const uid of deletedSenderIds) {
      const senderNotifications = await db.collection("notifications")
        .where("senderId", "==", uid)
        .get();
      for (const notification of senderNotifications.docs) {
        if (notification.data().type === "sos") {
          notifications.set(notification.ref.path, notification.ref);
        }
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

    const deletedSosEvents = orphaned.length;
    const deletedSosNotifications = existingNotificationRefs.length;
    await writeSosCleanupAudit(db, request.auth, {
      deletedSosEvents,
      deletedSosNotifications,
    });

    return {
      deletedSosEvents,
      deletedSosNotifications,
    };
  },
);

// Same region as the Firestore database (asia-southeast1). Running these in
// the default us-central1 made every one of their many sequential database
// reads cross the Pacific and back — the main reason Delete and Suspend were
// so slow. The admin dashboard calls them through this region too
// (_adminFunctions in lib/admin/admin_dashboard_shell.dart).
const ADMIN_FUNCTIONS_REGION = "asia-southeast1";

exports.manageUserAccount = onCall(
  { timeoutSeconds: 300, memory: "512MiB", region: ADMIN_FUNCTIONS_REGION },
  async (request) => {
    assertTourismAdmin(request.auth);

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
    // Profile and sign-in account are independent — fetch both at once.
    const [userSnap, targetResult] = await Promise.all([
      userRef.get(),
      auth.getUser(uid).then(
        (user) => ({ user }),
        (error) => ({ error }),
      ),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }
    const profile = userSnap.data() || {};
    const isAdmin = profile.adminAccess === true ||
      profile.role === "admin" ||
      profile.accountType === "admin";

    const target = targetResult.user;
    if (targetResult.error) {
      const error = targetResult.error;
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
      return deleteUserAccount({
        db,
        auth,
        request,
        uid,
        profile,
        userRef,
        isAdmin,
        deleteAuthUser: false,
      });
    }

    if (["revoke_admin", "suspend", "delete"].includes(action) && isAdmin) {
      const [markedAdmins, legacyAdmins, legacyAccountTypeAdmins] = await Promise.all([
        db.collection("users").where("adminAccess", "==", true).get(),
        db.collection("users").where("role", "==", "admin").get(),
        db.collection("users").where("accountType", "==", "admin").get(),
      ]);
      const admins = new Map([
        ...markedAdmins.docs,
        ...legacyAdmins.docs,
        ...legacyAccountTypeAdmins.docs,
      ].map((doc) => [doc.id, doc.data()]));
      const activeAdminsRemaining = [...admins.entries()].filter(
        ([adminUid, data]) => adminUid !== uid &&
          data.adminRole !== "mountain_head" &&
          data.accountSuspended !== true,
      ).length;
      if (activeAdminsRemaining === 0 && profile.accountSuspended !== true) {
        throw new HttpsError("failed-precondition", "You cannot remove, suspend, or delete the last admin.");
      }
    }

    if (action === "delete") {
      return deleteUserAccount({
        db,
        auth,
        request,
        uid,
        profile,
        userRef,
        isAdmin,
        deleteAuthUser: true,
      });
    }

    const claims = { ...(target.customClaims || {}) };
    const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    let previousStatus;
    let newStatus;

    if (action === "revoke_admin") {
      claims.admin = false;
      delete claims.adminRole;
      delete claims.managedMountainName;
      claims.role = profile.accountType && profile.accountType !== "admin"
        ? profile.accountType
        : "hiker";
      updates.adminAccess = false;
      updates.adminRole = admin.firestore.FieldValue.delete();
      updates.managedMountainName = admin.firestore.FieldValue.delete();
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

    // Profile update and audit entry don't depend on each other.
    await Promise.all([userRef.update(updates), db.collection("admin_actions").add({
      adminId: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action,
      targetId: uid,
      targetEmail: profile.email || null,
      targetName: profile.fullName || profile.displayName || null,
      previousStatus,
      newStatus,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    })]);

    return { action, status: newStatus };
  },
);

exports.createAdminAccount = onCall(
  {
    timeoutSeconds: 60,
    memory: "256MiB",
    region: ADMIN_FUNCTIONS_REGION,
    secrets: MAIL_SECRETS,
  },
  async (request) => {
    assertTourismAdmin(request.auth);

    const adminRole = request.data?.adminRole;
    if (!["tourism_admin", "mountain_head"].includes(adminRole)) {
      throw new HttpsError(
        "invalid-argument",
        "Choose either Tourism Admin or Mountain Head.",
      );
    }
    const requestedMountainName = request.data?.managedMountainName;
    const managedMountainName = adminRole === "mountain_head"
      ? canonicalizeDavaoMountainName(requestedMountainName)
      : null;
    if (adminRole === "mountain_head" && !managedMountainName) {
      throw new HttpsError(
        "invalid-argument",
        "Choose a managed mountain from the Davao Region list.",
      );
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
    let sendingEmail = false;
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
        adminRole,
        ...(adminRole === "mountain_head" ? { managedMountainName } : {}),
        guideVerified: null,
      };
      await db.collection("users").doc(createdUser.uid).set({
        uid: createdUser.uid,
        email,
        fullName,
        displayName: fullName,
        username: email.split("@")[0],
        role: "admin",
        accountType: "admin",
        adminRole,
        ...(adminRole === "mountain_head" ? { managedMountainName } : {}),
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
      await auth.setCustomUserClaims(createdUser.uid, claims);
      // The one-time "set your password" link goes ONLY to the new admin's
      // own inbox. It used to be returned to (and shown on the screen of)
      // the admin who created the account — anyone who saw or copied it
      // could have set the password and taken the account over.
      const setupLink = await auth.generatePasswordResetLink(email);
      sendingEmail = true;
      await sendAdminWelcomeEmail({
        to: email,
        fullName,
        adminRole,
        managedMountainName,
        setupLink,
      });
      sendingEmail = false;
      // The email is already in their inbox at this point, so an audit-log
      // hiccup must not roll back (and invalidate) the account it describes.
      try {
        await db.collection("admin_actions").add({
          adminId: request.auth.uid,
          adminEmail: request.auth.token.email || null,
          action: "create_admin",
          targetId: createdUser.uid,
          targetEmail: email,
          targetName: fullName,
          previousStatus: null,
          newStatus: adminRole,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error("createAdminAccount: audit log write failed", error);
      }
      return {
        uid: createdUser.uid,
        email,
        adminRole,
        managedMountainName: adminRole === "mountain_head"
          ? managedMountainName
          : null,
        emailSent: true,
      };
    } catch (error) {
      // Roll the account back so the same email can simply be tried again.
      if (createdUser) {
        await auth.deleteUser(createdUser.uid).catch(() => {});
        await db.collection("users").doc(createdUser.uid).delete().catch(() => {});
      }
      if (error instanceof HttpsError) throw error;
      if (error.code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "An account already uses this email.");
      }
      if (sendingEmail) {
        console.error("createAdminAccount: welcome email failed", {
          code: error?.code || null,
          message: error?.message || String(error),
        });
        throw new HttpsError(
          "unavailable",
          "The account was not created because the welcome email could not be sent. Check the email address and try again.",
        );
      }
      throw new HttpsError("internal", "Could not create the admin account.");
    }
  },
);
