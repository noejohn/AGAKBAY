const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");

// A guide's device refreshes guideLastActiveAt every ~60s while a room is
// active and their app is in the foreground (HikeRoomScreen.sendGuideHeartbeat).
// Leaving the room screen through the app's own back button/gesture is
// already caught client-side (PopScope forces the same end-room flow as the
// explicit "End Room" button) — this timeout is the backstop for the cases
// that can't signal cleanly on their own: a crashed/force-killed app, a dead
// battery, or the guide just never coming back.
const STALE_AFTER_MS = 15 * 60 * 1000;

async function closeAbandonedRoom(db, roomDoc) {
  const batch = db.batch();
  batch.update(roomDoc.ref, {
    status: "ended",
    endedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    autoEndedReason: "guide_inactive",
  });

  const participants = await roomDoc.ref.collection("participants").get();
  for (const participant of participants.docs) {
    if ((participant.data().membershipStatus || "active") !== "active") continue;
    batch.update(db.collection("users").doc(participant.id), {
      activeHikeRoomId: admin.firestore.FieldValue.delete(),
    });
    batch.update(participant.ref, {
      membershipStatus: "room_ended",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  batch.set(db.collection("admin_actions").doc(), {
    action: "auto_close_abandoned_room",
    targetId: roomDoc.id,
    previousStatus: "active",
    newStatus: "ended",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
}

exports.closeAbandonedHikeRooms = onSchedule(
  { schedule: "every 5 minutes", timeoutSeconds: 120, memory: "256MiB" },
  async () => {
    const db = admin.firestore();
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - STALE_AFTER_MS);
    const staleRooms = await db.collection("hike_rooms")
      .where("status", "==", "active")
      .where("guideLastActiveAt", "<", cutoff)
      .get();

    for (const roomDoc of staleRooms.docs) {
      try {
        await closeAbandonedRoom(db, roomDoc);
      } catch (error) {
        console.error(`Could not auto-close hike room ${roomDoc.id}:`, error);
      }
    }

    return null;
  },
);
