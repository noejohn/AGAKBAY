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

  test("200 OK lets a hiker who ended their hike send SOS without rejoining", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });
    await db.collection("hike_rooms").doc("room-1")
      .collection("participants").doc(hiker.uid)
      .update({ membershipStatus: "stopped", stopReason: "Too tired" });

    const res = await callApi("sendSosEvent", {
      roomId: "room-1", latitude: 7.1855, longitude: 125.6515, reason: "Accident",
    }, hiker.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.sent).toBe(true);

    const participant = await db.collection("hike_rooms").doc("room-1")
      .collection("participants").doc(hiker.uid).get();
    expect(participant.data().membershipStatus).toBe("stopped");

    const event = await db.collection("hike_rooms").doc("room-1")
      .collection("sos_events").doc(res.body.result.eventId).get();
    expect(event.exists).toBe(true);
    expect(event.data()).toMatchObject({
      senderId: hiker.uid,
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

describe("POST submitIncidentReport", () => {
  test("the acknowledged room guide can report a qualifying SOS to the Mountain Head", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    const hiker = await createSignedInUser("hiker@test.com", "Hiker Juan");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [hiker.uid] });
    await db.collection("users").doc("mountain-head-1").set({
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await db.collection("hike_rooms").doc("room-1")
      .collection("sos_events").doc("sos-1").set({
        senderId: hiker.uid,
        senderName: "Hiker Juan",
        reason: "Accident",
        latitude: 7.0,
        longitude: 125.0,
        status: "acknowledged",
        acknowledgedBy: guide.uid,
      });

    const res = await callApi("submitIncidentReport", {
      reportId: "incident_api_test_1",
      roomId: "room-1",
      eventId: "sos-1",
      guideNotes: "Guide checked the location and contacted rescue.",
    }, guide.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.sent).toBe(true);
    const report = await db.collection("incident_reports")
      .doc("incident_api_test_1").get();
    expect(report.data()).toMatchObject({
      guideId: guide.uid,
      eventId: "sos-1",
      // The room says "Mount Apo"; submitIncidentReport stores the official
      // Davao list spelling (canonicalizeDavaoMountainName in mountainNames.js).
      mountainName: "Mt. Apo",
      category: "Accident",
      hikerName: "Hiker Juan",
      guideNotes: "Guide checked the location and contacted rescue.",
      status: "submitted",
    });
    const notifications = await db.collection("notifications")
      .where("reportId", "==", "incident_api_test_1").get();
    expect(notifications.size).toBe(1);
    expect(notifications.docs[0].data()).toMatchObject({
      type: "incident_report",
      mountainName: "Mt. Apo",
      guideNotes: "Guide checked the location and contacted rescue.",
    });
  });

  test("the room guide can queue a received LoRa SOS report without an SOS document", async () => {
    const guide = await createSignedInUser("guide@test.com", "Guide Gina");
    await seedActiveRoom({ roomId: "room-1", guideUid: guide.uid, hikerUids: [] });
    await db.collection("users").doc("mountain-head-1").set({
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });

    const res = await callApi("submitIncidentReport", {
      reportId: "incident_lora_123",
      roomId: "room-1",
      source: "lora",
      hikerName: "Hiker Juan",
      reason: "Accident",
      latitude: 7.0,
      longitude: 125.0,
      guideNotes: "Received and acknowledged over LoRa.",
    }, guide.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.mountainHeadsNotified).toBe(1);
    const report = await db.collection("incident_reports")
      .doc("incident_lora_123").get();
    expect(report.data()).toMatchObject({
      guideId: guide.uid,
      source: "lora_relay_unverified",
      eventId: null,
      category: "Accident",
      hikerName: "Hiker Juan",
    });
  });
});

describe("POST updateIncidentReportStatus", () => {
  function seedIncidentReport(mountainName = "Mount Apo") {
    return db.collection("incident_reports").doc("incident_status_test").set({
      guideId: "guide-1",
      mountainName,
      status: "submitted",
      guideNotes: "Initial report details.",
    });
  }

  test("the assigned Mountain Head can acknowledge the report", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();

    const res = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "acknowledge",
    }, head.idToken);

    expect(res.status).toBe(200);
    expect(res.body.result.status).toBe("acknowledged");
    const report = await db.collection("incident_reports")
      .doc("incident_status_test").get();
    expect(report.data()).toMatchObject({
      status: "acknowledged",
      acknowledgedBy: head.uid,
      acknowledgedByName: "Head Helen",
    });
    const notification = await db.collection("users").doc("guide-1")
      .collection("notifications")
      .doc("incident_report_incident_status_test_acknowledged").get();
    expect(notification.data()).toMatchObject({
      type: "incident_report_status",
      reportId: "incident_status_test",
      status: "acknowledged",
    });
  });

  test("the assigned Mountain Head can advance the report through all three statuses", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();

    const acknowledge = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "acknowledge",
    }, head.idToken);
    expect(acknowledge.body.result.status).toBe("acknowledged");

    const respondersSent = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "send_responders",
    }, head.idToken);
    expect(respondersSent.body.result.status).toBe("responders_sent");

    const responded = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "resolve",
    }, head.idToken);

    expect(responded.status).toBe(200);
    expect(responded.body.result.status).toBe("responded");
    const report = await db.collection("incident_reports")
      .doc("incident_status_test").get();
    expect(report.data()).toMatchObject({
      status: "responded",
      respondedBy: head.uid,
      respondersSentBy: head.uid,
      acknowledgedBy: head.uid,
    });
    for (const status of [
      "acknowledged",
      "responders_sent",
      "responded",
    ]) {
      const notification = await db.collection("users").doc("guide-1")
        .collection("notifications")
        .doc(`incident_report_incident_status_test_${status}`).get();
      expect(notification.data()).toMatchObject({
        type: "incident_report_status",
        reportId: "incident_status_test",
        status,
      });
    }
  });

  test("a Mountain Head cannot skip the responders-sent status", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();

    const res = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "resolve",
    }, head.idToken);

    expect(res.status).toBe(400);
    const report = await db.collection("incident_reports")
      .doc("incident_status_test").get();
    expect(report.data().status).toBe("submitted");
  });

  // ADM-UT-004: "the selected action updates the report status only once".
  function guideStatusNotifications() {
    return db.collection("users").doc("guide-1").collection("notifications")
      .where("reportId", "==", "incident_status_test").get();
  }

  test("ADM-UT-004: pressing the same action twice updates the status only once", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();
    const body = { reportId: "incident_status_test", action: "acknowledge" };

    const first = await callApi("updateIncidentReportStatus", body, head.idToken);
    const afterFirst = (await db.collection("incident_reports")
      .doc("incident_status_test").get()).data();
    const second = await callApi("updateIncidentReportStatus", body, head.idToken);
    const afterSecond = (await db.collection("incident_reports")
      .doc("incident_status_test").get()).data();

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(second.body.result.status).toBe("acknowledged");
    // The second press changed nothing: same timestamp, same details.
    expect(afterSecond.acknowledgedAt.isEqual(afterFirst.acknowledgedAt)).toBe(true);
    expect(afterSecond.guideNotes).toBe("Initial report details.");
    expect((await guideStatusNotifications()).size).toBe(1);
  });

  test("ADM-UT-004: two simultaneous presses still update the status only once", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();
    const body = { reportId: "incident_status_test", action: "acknowledge" };

    const results = await Promise.all([
      callApi("updateIncidentReportStatus", body, head.idToken),
      callApi("updateIncidentReportStatus", body, head.idToken),
    ]);

    expect(results.map((res) => res.status)).toEqual([200, 200]);
    const report = (await db.collection("incident_reports")
      .doc("incident_status_test").get()).data();
    expect(report.status).toBe("acknowledged");
    expect((await guideStatusNotifications()).size).toBe(1);
  });

  test("ADM-UT-004: an earlier action can't be re-applied once the report has moved on", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport();
    for (const action of ["acknowledge", "send_responders"]) {
      await callApi("updateIncidentReportStatus", {
        reportId: "incident_status_test", action,
      }, head.idToken);
    }

    const res = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test", action: "acknowledge",
    }, head.idToken);

    expect(res.status).toBe(400);
    const report = (await db.collection("incident_reports")
      .doc("incident_status_test").get()).data();
    expect(report.status).toBe("responders_sent");
  });

  test("a Mountain Head cannot update a report for another mountain", async () => {
    const head = await createSignedInUser("head@test.com", "Head Helen", {
      admin: true,
      adminRole: "mountain_head",
      managedMountainName: "Mount Apo",
    });
    await seedIncidentReport("Mount Talomo");

    const res = await callApi("updateIncidentReportStatus", {
      reportId: "incident_status_test",
      action: "acknowledge",
    }, head.idToken);

    expect(res.status).toBe(403);
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

// ADM-UT-003: account changes made from the admin dashboard
// (manageUserAccount, asia-southeast1) land on the intended account — in
// both Firebase Authentication and the Firestore profile — and nowhere else.
describe("POST manageUserAccount (ADM-UT-003)", () => {
  const ADMIN_REGION = "asia-southeast1";

  async function seedTourismAdminAndTarget() {
    const tourismAdmin = await createSignedInUser("tourism@test.com", "Tourism Tina", {
      admin: true,
      role: "admin",
      adminRole: "tourism_admin",
    });
    await db.collection("users").doc(tourismAdmin.uid).set({
      fullName: "Tourism Tina",
      email: "tourism@test.com",
      role: "admin",
      accountType: "admin",
      adminRole: "tourism_admin",
      adminAccess: true,
    });
    const target = await createSignedInUser("target@test.com", "Target Hiker");
    await db.collection("users").doc(target.uid).set({
      fullName: "Target Hiker",
      email: "target@test.com",
      role: "hiker",
      accountType: "hiker",
    });
    const bystander = await createSignedInUser("bystander@test.com", "Bystander");
    await db.collection("users").doc(bystander.uid).set({
      fullName: "Bystander",
      email: "bystander@test.com",
      role: "hiker",
      accountType: "hiker",
    });
    return { tourismAdmin, target, bystander };
  }

  test("Suspend: disables only the chosen account and records it", async () => {
    const { tourismAdmin, target, bystander } = await seedTourismAdminAndTarget();

    const res = await callApi("manageUserAccount", {
      uid: target.uid, action: "suspend",
    }, tourismAdmin.idToken, ADMIN_REGION);

    expect(res.status).toBe(200);
    expect(res.body.result).toMatchObject({ action: "suspend", status: "suspended" });
    expect((await admin.auth().getUser(target.uid)).disabled).toBe(true);
    expect((await db.collection("users").doc(target.uid).get()).data().accountSuspended)
      .toBe(true);
    // Nobody else was touched.
    expect((await admin.auth().getUser(bystander.uid)).disabled).toBe(false);
    const audit = await db.collection("admin_actions")
      .where("targetId", "==", target.uid).get();
    expect(audit.docs.map((doc) => doc.data())).toEqual(expect.arrayContaining([
      expect.objectContaining({
        action: "suspend", adminId: tourismAdmin.uid, newStatus: "suspended",
      }),
    ]));
  });

  test("Restore: re-enables a suspended account", async () => {
    const { tourismAdmin, target } = await seedTourismAdminAndTarget();
    await callApi("manageUserAccount", { uid: target.uid, action: "suspend" },
      tourismAdmin.idToken, ADMIN_REGION);

    const res = await callApi("manageUserAccount", {
      uid: target.uid, action: "restore",
    }, tourismAdmin.idToken, ADMIN_REGION);

    expect(res.status).toBe(200);
    expect(res.body.result.status).toBe("active");
    expect((await admin.auth().getUser(target.uid)).disabled).toBe(false);
    expect((await db.collection("users").doc(target.uid).get()).data().accountSuspended)
      .toBe(false);
  });

  test("Revoke admin: removes admin access from that admin only", async () => {
    const { tourismAdmin } = await seedTourismAdminAndTarget();
    const head = await createSignedInUser("head@test.com", "Head Hank", {
      admin: true, role: "admin", adminRole: "mountain_head", managedMountainName: "Mt. Apo",
    });
    await db.collection("users").doc(head.uid).set({
      fullName: "Head Hank", role: "admin", accountType: "admin",
      adminRole: "mountain_head", managedMountainName: "Mt. Apo", adminAccess: true,
    });

    const res = await callApi("manageUserAccount", {
      uid: head.uid, action: "revoke_admin",
    }, tourismAdmin.idToken, ADMIN_REGION);

    expect(res.status).toBe(200);
    expect((await admin.auth().getUser(head.uid)).customClaims).toMatchObject({ admin: false });
    const profile = (await db.collection("users").doc(head.uid).get()).data();
    expect(profile.adminAccess).toBe(false);
    expect(profile.adminRole).toBeUndefined();
    // The acting admin keeps their own access.
    expect((await admin.auth().getUser(tourismAdmin.uid)).customClaims.admin).toBe(true);
  });

  test("Delete: removes the account and profile, and the email can sign up again", async () => {
    const { tourismAdmin, target } = await seedTourismAdminAndTarget();

    const res = await callApi("manageUserAccount", {
      uid: target.uid, action: "delete",
    }, tourismAdmin.idToken, ADMIN_REGION);

    expect(res.status).toBe(200);
    expect(res.body.result.status).toBe("deleted");
    await expect(admin.auth().getUser(target.uid))
      .rejects.toMatchObject({ code: "auth/user-not-found" });
    expect((await db.collection("users").doc(target.uid).get()).exists).toBe(false);
    // The same email is free for a brand-new account.
    const reused = await admin.auth().createUser({
      email: "target@test.com", password: "New#pass2026",
    });
    expect(reused.uid).not.toBe(target.uid);
  });

  test("403 PERMISSION_DENIED when a non-admin tries, and nothing changes", async () => {
    const { target, bystander } = await seedTourismAdminAndTarget();

    const res = await callApi("manageUserAccount", {
      uid: target.uid, action: "suspend",
    }, bystander.idToken, ADMIN_REGION);

    expect(res.status).toBe(403);
    expect((await admin.auth().getUser(target.uid)).disabled).toBe(false);
  });

  test("400 FAILED_PRECONDITION when an admin tries to restrict their own account", async () => {
    const { tourismAdmin } = await seedTourismAdminAndTarget();

    const res = await callApi("manageUserAccount", {
      uid: tourismAdmin.uid, action: "suspend",
    }, tourismAdmin.idToken, ADMIN_REGION);

    expect(res.status).toBe(400);
    expect((await admin.auth().getUser(tourismAdmin.uid)).disabled).toBe(false);
  });
});
