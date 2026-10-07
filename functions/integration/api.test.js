// API route tests: each test calls a real Cloud Function endpoint over HTTP
// (exactly like the Flutter app does) and checks both the HTTP response AND
// what actually ended up in the Firestore database — all inside the local
// Firebase Emulator, never the live project. Run with `npm run test:api`.
const admin = require("firebase-admin");
const { db, resetEmulator, createSignedInUser, callApi } = require("./emulator");

const now = () => admin.firestore.Timestamp.now();

async function seedActiveRoom({ roomId, guideUid, hikerUids }) {
  await db.collection("hike_rooms").doc(roomId).set({
    status: "active",
    guideId: guideUid,
    roomCode: "123456",
    mountainName: "Mount Apo",
  });
  for (const uid of [guideUid, ...hikerUids]) {
    await db.collection("hike_rooms").doc(roomId)
      .collection("participants").doc(uid)
      .set({ userId: uid, membershipStatus: "active" });
    await db.collection("users").doc(uid)
      .set({ fullName: uid === guideUid ? "Guide Gina" : "Hiker Juan", activeHikeRoomId: roomId });
  }
}

beforeEach(async () => {
  await resetEmulator();
});

describe("POST sendSosEvent", () => {
  test("401 UNAUTHENTICATED when not signed in", async () => {
    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 7.0, longitude: 125.0, reason: "Lost",
    });
    expect(res.status).toBe(401);
    expect(res.body.error.status).toBe("UNAUTHENTICATED");
  });

  test("400 INVALID_ARGUMENT for an impossible latitude", async () => {
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 999, longitude: 125.0, reason: "Lost",
    }, hiker.idToken);
    expect(res.status).toBe(400);
    expect(res.body.error.status).toBe("INVALID_ARGUMENT");
  });

  test("400 FAILED_PRECONDITION when the room has not started", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });
    await db.collection("hike_rooms").doc("room-1").update({ status: "waiting" });

    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 7.0, longitude: 125.0, reason: "Lost",
    }, hiker.idToken);
    expect(res.status).toBe(400);
    expect(res.body.error.status).toBe("FAILED_PRECONDITION");
  });

  test("400 FAILED_PRECONDITION when the caller is not in the room", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const outsider = await createSignedInUser("outsider@test.com", "Outsider");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [] });

    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 7.0, longitude: 125.0, reason: "Lost",
    }, outsider.idToken);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/not in this room/i);
  });

  test("200 OK writes the SOS (with reason) to the database", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });

    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 7.1855, longitude: 125.6515, reason: "Accident",
    }, hiker.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.sent).toBe(true);

    const event = await db.collection("hike_rooms").doc("room-1")
      .collection("sos_events").doc(res.body.result.eventId).get();
    expect(event.exists).toBe(true);
    expect(event.data()).toMatchObject({
      senderId: hiker.uid,
      senderName: "Hiker Juan",
      latitude: 7.1855,
      longitude: 125.6515,
      reason: "Accident",
      status: "sent",
    });
  });

  test("400 FAILED_PRECONDITION on a second SOS within the 30s cooldown", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });
    const body = { roomId: "room-1", latitude: 7.0, longitude: 125.0, reason: "Lost" };

    const first = await callApi("sendSosEvent", body, hiker.idToken);
    const second = await callApi("sendSosEvent", body, hiker.idToken);

    expect(first.status).toBe(200);
    expect(second.status).toBe(400);
    expect(second.body.error.message).toMatch(/wait/i);
  });
});

describe("POST sendNearbySos (solo hike)", () => {
  test("401 UNAUTHENTICATED when not signed in", async () => {
    const res = await callApi("sendNearbySos", { latitude: 7.0, longitude: 125.0 });
    expect(res.status).toBe(401);
  });

  test("200 OK notifies only fresh hikers within 5 km, nearest first", async () => {
    const solo = await createSignedInUser("solo@test.com", "Solo Sam");
    const near = await createSignedInUser("near@test.com", "Near Nina");
    const far = await createSignedInUser("far@test.com", "Far Fred");
    const stale = await createSignedInUser("stale@test.com", "Stale Stan");
    await db.collection("users").doc(solo.uid).set({ fullName: "Solo Sam" });

    // ~110 m away, ~22 km away, and close but last seen an hour ago.
    await db.collection("hiker_presence").doc(near.uid)
      .set({ latitude: 7.001, longitude: 125.0, updatedAt: now() });
    await db.collection("hiker_presence").doc(far.uid)
      .set({ latitude: 7.2, longitude: 125.0, updatedAt: now() });
    await db.collection("hiker_presence").doc(stale.uid).set({
      latitude: 7.0005,
      longitude: 125.0,
      updatedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000),
    });

    const res = await callApi("sendNearbySos", {
      latitude: 7.0, longitude: 125.0, reason: "Lost", trailName: "Mount Apo",
    }, solo.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.notifiedCount).toBe(1);

    const nearAlerts = await db.collection("users").doc(near.uid)
      .collection("notifications").get();
    expect(nearAlerts.size).toBe(1);
    expect(nearAlerts.docs[0].data()).toMatchObject({
      nearbySos: true,
      senderName: "Solo Sam",
      reason: "Lost",
      read: false,
    });

    const farAlerts = await db.collection("users").doc(far.uid)
      .collection("notifications").get();
    const staleAlerts = await db.collection("users").doc(stale.uid)
      .collection("notifications").get();
    expect(farAlerts.size).toBe(0);
    expect(staleAlerts.size).toBe(0);
  });
});

describe("POST endHikeRoom", () => {
  test("401 UNAUTHENTICATED when not signed in", async () => {
    const res = await callApi("endHikeRoom", { roomId: "room-1" });
    expect(res.status).toBe(401);
  });

  test("400 INVALID_ARGUMENT without a roomId", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const res = await callApi("endHikeRoom", {}, guide.idToken);
    expect(res.status).toBe(400);
    expect(res.body.error.status).toBe("INVALID_ARGUMENT");
  });

  test("404 NOT_FOUND for a room that does not exist", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const res = await callApi("endHikeRoom", { roomId: "missing" }, guide.idToken);
    expect(res.status).toBe(404);
  });

  test("403 PERMISSION_DENIED when a hiker tries to end the room", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });

    const res = await callApi("endHikeRoom", { roomId: "room-1" }, hiker.idToken);
    expect(res.status).toBe(403);

    const room = await db.collection("hike_rooms").doc("room-1").get();
    expect(room.data().status).toBe("active");
  });

  test("200 OK ends the room and releases every participant", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });

    const res = await callApi("endHikeRoom", { roomId: "room-1" }, guide.idToken);
    expect(res.status).toBe(200);
    expect(res.body.result.success).toBe(true);

    const room = await db.collection("hike_rooms").doc("room-1").get();
    expect(room.data().status).toBe("ended");

    const participant = await db.collection("hike_rooms").doc("room-1")
      .collection("participants").doc(hiker.uid).get();
    expect(participant.data().membershipStatus).toBe("room_ended");

    const hikerProfile = await db.collection("users").doc(hiker.uid).get();
    expect(hikerProfile.data().activeHikeRoomId).toBeUndefined();
  });
});
