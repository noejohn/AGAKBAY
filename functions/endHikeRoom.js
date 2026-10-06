const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

async function endHikeRoomForGuide(db, roomId, guideId) {
  const roomRef = db.collection("hike_rooms").doc(roomId);
  const roomSnapshot = await roomRef.get();
  if (!roomSnapshot.exists) {
    throw new HttpsError("not-found", "This hike room no longer exists.");
  }
  if (roomSnapshot.data().guideId !== guideId) {
    throw new HttpsError("permission-denied", "Only the Tour Guide can end this room.");
  }

  const participants = await roomRef.collection("participants").get();
  const userSnapshots = await Promise.all(participants.docs.map((participant) =>
    db.collection("users").doc(participant.id).get(),
  ));
  const pendingWrites = [];

  const stillPresent = new Set(["active", "stopped"]);
  for (let index = 0; index < participants.docs.length; index++) {
    const participant = participants.docs[index];
    const data = participant.data();
    if (stillPresent.has(data.membershipStatus || "active")) {
      pendingWrites.push({
        ref: participant.ref,
        data: {
          membershipStatus: "room_ended",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }

    const userRef = db.collection("users").doc(participant.id);
    const userSnapshot = userSnapshots[index];
    if (userSnapshot.exists && userSnapshot.data().activeHikeRoomId === roomId) {
      pendingWrites.push({
        ref: userRef,
        data: {
          activeHikeRoomId: admin.firestore.FieldValue.delete(),
        },
      });
    }
  }

  // Keep each batch below Firestore's 500-write limit. The room remains open
  // until every participant has been detached, so a retry can finish cleanup.
  for (let offset = 0; offset < pendingWrites.length; offset += 450) {
    const batch = db.batch();
    for (const write of pendingWrites.slice(offset, offset + 450)) {
      batch.update(write.ref, write.data);
    }
    await batch.commit();
  }

  await roomRef.update({
    status: "ended",
    endedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

exports.endHikeRoom = onCall(async (request) => {
  const guideId = request.auth?.uid;
  if (!guideId) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const roomId = request.data?.roomId?.toString().trim();
  if (!roomId) {
    throw new HttpsError("invalid-argument", "roomId is required.");
  }

  try {
    await endHikeRoomForGuide(admin.firestore(), roomId, guideId);
    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error(`Could not end hike room ${roomId}:`, error);
    throw new HttpsError("internal", "Could not end the room for all hikers. Please retry.");
  }
});

exports.endHikeRoomForGuide = endHikeRoomForGuide;
