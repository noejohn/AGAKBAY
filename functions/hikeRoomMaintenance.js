const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");

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

  const stillPresent = new Set(["active", "stopped"]);
  const participants = await roomDoc.ref.collection("participants").get();
  for (const participant of participants.docs) {
    if (!stillPresent.has(participant.data().membershipStatus || "active")) continue;
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

function sameTimestamp(a, b) {
  if (!a || !b) return a === b;
  if (typeof a.isEqual === "function") return a.isEqual(b);
  return String(a) === String(b);
}

// A hiker ending their hike from Hiking Mode (with a reason) writes straight
// onto their own participant doc (HikeRoomService.stopHiking) — firestore.rules lets them
// update that doc, but never lets them write into the guide's own
// notifications collection. This bridges the two with the Admin SDK, the
// same shape as every other cross-user notification in this app.
exports.notifyGuideOfStoppedHiker = onDocumentUpdated(
  {
    document: "hike_rooms/{roomId}/participants/{participantId}",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    // Notify on the transition INTO "stopped", or on a NEW end-hike message
    // (stoppedAt changes — a hiker can start hiking again and end again) —
    // not on every other edit to this participant doc (e.g. a location
    // update).
    if (after.membershipStatus !== "stopped") return;
    const isNewStop = before.membershipStatus !== "stopped" ||
      !sameTimestamp(before.stoppedAt, after.stoppedAt);
    if (!isNewStop) return;

    const { roomId, participantId } = event.params;
    const db = admin.firestore();
    const roomSnap = await db.collection("hike_rooms").doc(roomId).get();
    if (!roomSnap.exists) return;
    const guideId = String(roomSnap.data()?.guideId || "").trim();
    if (!guideId || guideId === participantId) return;

    const hikerName = String(after.name || "A hiker").trim();
    const reason = String(after.stopReason || "").trim();

    // Deterministic ID so a retried Firestore event can't double-notify.
    await db
      .collection("users")
      .doc(guideId)
      .collection("notifications")
      .doc(`hiker_stopped_${roomId}_${participantId}`)
      .set(
        {
          type: "hiker_stopped",
          title: `${hikerName} ended their hike`,
          body: reason || `${hikerName} ended their hike and may need help.`,
          roomId,
          participantId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  },
);
