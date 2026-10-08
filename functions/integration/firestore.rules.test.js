// Database security tests: each test acts as a specific user (hiker, guide,
// admin, or signed out) talking DIRECTLY to Firestore — the way the Flutter
// app does for everything that doesn't go through a Cloud Function — and
// checks that firestore.rules allows or blocks it. Runs inside the local
// Firestore emulator via `npm run test:api`; never touches the live project.
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  writeBatch,
  deleteField,
  deleteDoc,
  serverTimestamp,
  setLogLevel,
} = require("firebase/firestore");

// Every "CANNOT ..." test is SUPPOSED to be rejected with PERMISSION_DENIED
// — the client SDK would otherwise print a long warning for each one,
// burying the actual pass/fail results.
setLogLevel("silent");

const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "tunga-app-2026",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host,
      port: Number(port),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// --- Who is making the request --------------------------------------------
const asHiker = () => testEnv.authenticatedContext("hiker-1").firestore();
const asOtherHiker = () => testEnv.authenticatedContext("hiker-2").firestore();
const asGuide = () => testEnv.authenticatedContext("guide-1").firestore();
const asSignedOut = () => testEnv.unauthenticatedContext().firestore();
const asTourismAdmin = () => testEnv
  .authenticatedContext("admin-1", { admin: true, adminRole: "tourism_admin" })
  .firestore();

/** Writes starting data with the rules switched off (like the Admin SDK). */
async function seed(writes) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [docPath, data] of Object.entries(writes)) {
      await setDoc(doc(db, docPath), data);
    }
  });
}

const activeRoom = {
  "hike_rooms/room-1": { guideId: "guide-1", status: "active", mountainName: "Mount Apo" },
  "hike_rooms/room-1/participants/hiker-1": { userId: "hiker-1", membershipStatus: "active" },
  "hike_rooms/room-1/participants/hiker-2": { userId: "hiker-2", membershipStatus: "active" },
};

// ---------------------------------------------------------------------------
describe("users — profiles and roles", () => {
  beforeEach(() => seed({
    "users/hiker-1": { fullName: "Juan", accountType: "hiker" },
    "users/hiker-2": { fullName: "Maria", accountType: "hiker" },
    "users/guide-1": { fullName: "Gina", accountType: "tour_guide" },
  }));

  test("a hiker can read their own profile", async () => {
    await assertSucceeds(getDoc(doc(asHiker(), "users/hiker-1")));
  });

  test("a hiker CANNOT read another hiker's profile", async () => {
    await assertFails(getDoc(doc(asHiker(), "users/hiker-2")));
  });

  test("a hiker can read a tour guide's profile", async () => {
    await assertSucceeds(getDoc(doc(asHiker(), "users/guide-1")));
  });

  test("a signed-out visitor CANNOT read any profile", async () => {
    await assertFails(getDoc(doc(asSignedOut(), "users/hiker-1")));
  });

  test("a new user can create their own hiker profile (the app's real sign-up data)", async () => {
    // Same fields as AuthDatabaseService's sign-up write in
    // lib/services/auth_database_service.dart.
    const db = testEnv.authenticatedContext("new-hiker").firestore();
    await assertSucceeds(setDoc(doc(db, "users/new-hiker"), {
      uid: "new-hiker",
      fullName: "New Hiker",
      username: "newhiker",
      email: "new@test.com",
      accountType: "hiker",
      role: "hiker",
      guideVerified: null,
      emailVerified: false,
      verificationMethod: "link",
      onboardingComplete: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
  });

  test("a new user CANNOT sign up as admin", async () => {
    const db = testEnv.authenticatedContext("sneaky").firestore();
    await assertFails(setDoc(doc(db, "users/sneaky"), { accountType: "admin" }));
  });

  test("a new user CANNOT sneak admin access into their sign-up", async () => {
    const db = testEnv.authenticatedContext("sneaky").firestore();
    await assertFails(setDoc(doc(db, "users/sneaky"), {
      accountType: "hiker", role: "hiker", adminAccess: true,
    }));
    await assertFails(setDoc(doc(db, "users/sneaky"), {
      accountType: "hiker", role: "hiker", adminRole: "tourism_admin",
    }));
  });

  test("a new user CANNOT sign up directly as a tour guide", async () => {
    const db = testEnv.authenticatedContext("sneaky").firestore();
    await assertFails(setDoc(doc(db, "users/sneaky"), { accountType: "tour_guide" }));
  });

  test("a hiker can update their own contact details", async () => {
    await assertSucceeds(updateDoc(doc(asHiker(), "users/hiker-1"), {
      contactNumber: "09171234567",
      emergencyContactName: "Mama",
    }));
  });

  test("a hiker CANNOT promote themself to tour guide", async () => {
    await assertFails(updateDoc(doc(asHiker(), "users/hiker-1"), { accountType: "tour_guide" }));
  });

  test("a hiker CANNOT give themself an admin role", async () => {
    await assertFails(updateDoc(doc(asHiker(), "users/hiker-1"), { adminRole: "tourism_admin" }));
  });

  test("a hiker CANNOT edit someone else's profile", async () => {
    await assertFails(updateDoc(doc(asHiker(), "users/hiker-2"), { fullName: "Hacked" }));
  });

  test("a hiker CANNOT read someone else's notifications", async () => {
    await seed({ "users/hiker-2/notifications/n1": { title: "Private" } });
    await assertFails(getDoc(doc(asHiker(), "users/hiker-2/notifications/n1")));
  });
});

// ---------------------------------------------------------------------------
describe("hike_rooms — rooms and participants", () => {
  test("a hiker (no admin claim, e.g. email sign-up) can read a hike room", async () => {
    await seed(activeRoom);
    await assertSucceeds(getDoc(doc(asHiker(), "hike_rooms/room-1")));
  });

  test("a hiker with an explicit admin:false claim (Auth0 sign-in) can read a hike room", async () => {
    await seed(activeRoom);
    const db = testEnv.authenticatedContext("hiker-1", { admin: false }).firestore();
    await assertSucceeds(getDoc(doc(db, "hike_rooms/room-1")));
  });

  test("a signed-out visitor CANNOT read a hike room", async () => {
    await seed(activeRoom);
    await assertFails(getDoc(doc(asSignedOut(), "hike_rooms/room-1")));
  });

  test("a guide can create a room they own", async () => {
    await assertSucceeds(setDoc(doc(asGuide(), "hike_rooms/new-room"), {
      guideId: "guide-1", status: "waiting",
    }));
  });

  test("nobody can create a room under someone else's name", async () => {
    await assertFails(setDoc(doc(asHiker(), "hike_rooms/fake-room"), {
      guideId: "guide-1", status: "waiting",
    }));
  });

  test("the guide can start their own room", async () => {
    await seed({ "hike_rooms/room-1": { guideId: "guide-1", status: "waiting" } });
    await assertSucceeds(updateDoc(doc(asGuide(), "hike_rooms/room-1"), { status: "active" }));
  });

  test("the guide CANNOT end a room directly (must use the endHikeRoom API)", async () => {
    await seed(activeRoom);
    await assertFails(updateDoc(doc(asGuide(), "hike_rooms/room-1"), { status: "ended" }));
  });

  test("a hiker CANNOT change a room's status", async () => {
    await seed(activeRoom);
    await assertFails(updateDoc(doc(asHiker(), "hike_rooms/room-1"), { status: "waiting" }));
  });

  test("a hiker can join a room as themself", async () => {
    await seed({
      "hike_rooms/room-1": { guideId: "guide-1", status: "waiting" },
      "users/hiker-1": {
        contactNumber: "09171234567",
        emergencyContactName: "Emergency Contact",
        emergencyContactPhone: "09179876543",
      },
    });
    await assertSucceeds(setDoc(doc(asHiker(), "hike_rooms/room-1/participants/hiker-1"), {
      userId: "hiker-1", membershipStatus: "active",
    }));
  });

  test("a hiker CANNOT join a room without complete safety details", async () => {
    await seed({
      "hike_rooms/room-1": { guideId: "guide-1", status: "waiting" },
      "users/hiker-1": { contactNumber: "09171234567" },
    });
    await assertFails(setDoc(doc(asHiker(), "hike_rooms/room-1/participants/hiker-1"), {
      userId: "hiker-1", membershipStatus: "active",
    }));
  });

  test("a hiker CANNOT add someone else to a room", async () => {
    await seed({ "hike_rooms/room-1": { guideId: "guide-1", status: "waiting" } });
    await assertFails(setDoc(doc(asHiker(), "hike_rooms/room-1/participants/hiker-2"), {
      userId: "hiker-2", membershipStatus: "active",
    }));
  });

  test("a hiker can update their own participant record (e.g. end hike)", async () => {
    await seed(activeRoom);
    await assertSucceeds(updateDoc(doc(asHiker(), "hike_rooms/room-1/participants/hiker-1"), {
      membershipStatus: "stopped", stopReason: "Too tired",
    }));
  });

  test("a hiker CANNOT edit another hiker's participant record", async () => {
    await seed(activeRoom);
    await assertFails(updateDoc(doc(asHiker(), "hike_rooms/room-1/participants/hiker-2"), {
      membershipStatus: "kicked",
    }));
  });

  test.each(["active", "stopped"])(
    "the guide can remove a %s hiker and clear their room pointer atomically",
    async (membershipStatus) => {
      await seed({
        ...activeRoom,
        "hike_rooms/room-1/participants/hiker-2": {
          userId: "hiker-2",
          membershipStatus,
        },
        "users/hiker-2": {
          accountType: "hiker",
          activeHikeRoomId: "room-1",
        },
      });

      const db = asGuide();
      const batch = writeBatch(db);
      batch.update(doc(db, "hike_rooms/room-1/participants/hiker-2"), {
        membershipStatus: "removed",
        removedBy: "guide-1",
        removedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.update(doc(db, "users/hiker-2"), {
        activeHikeRoomId: deleteField(),
      });
      batch.update(doc(db, "hike_rooms/room-1"), {
        updatedAt: serverTimestamp(),
      });

      await assertSucceeds(batch.commit());
      const participant = await getDoc(
        doc(db, "hike_rooms/room-1/participants/hiker-2"),
      );
      expect(participant.data().membershipStatus).toBe("removed");
    },
  );
});

// ---------------------------------------------------------------------------
describe("sos_events — emergency alerts", () => {
  beforeEach(() => seed({
    ...activeRoom,
    "hike_rooms/room-1/sos_events/sos-1": {
      senderId: "hiker-1", latitude: 7.0, longitude: 125.0, status: "sent",
    },
  }));

  test("a hiker in the room can read its SOS alerts", async () => {
    await assertSucceeds(getDoc(doc(asOtherHiker(), "hike_rooms/room-1/sos_events/sos-1")));
  });

  test("a hiker CANNOT create an SOS directly (must use the sendSosEvent API)", async () => {
    await assertFails(setDoc(doc(asHiker(), "hike_rooms/room-1/sos_events/fake"), {
      senderId: "hiker-1", latitude: 7.0, longitude: 125.0, status: "sent",
    }));
  });

  test("the guide can acknowledge an SOS", async () => {
    await assertSucceeds(updateDoc(doc(asGuide(), "hike_rooms/room-1/sos_events/sos-1"), {
      status: "acknowledged", acknowledgedBy: "guide-1", acknowledgedAt: serverTimestamp(),
    }));
  });

  test("the guide CANNOT alter the SOS location", async () => {
    await assertFails(updateDoc(doc(asGuide(), "hike_rooms/room-1/sos_events/sos-1"), {
      latitude: 0,
    }));
  });

  test("a hiker CANNOT acknowledge an SOS", async () => {
    await assertFails(updateDoc(doc(asOtherHiker(), "hike_rooms/room-1/sos_events/sos-1"), {
      status: "acknowledged",
    }));
  });

  test("nobody can read the SOS cooldown records", async () => {
    await seed({ "hike_rooms/room-1/sos_cooldowns/hiker-1": { nextAllowedAt: 1 } });
    await assertFails(getDoc(doc(asHiker(), "hike_rooms/room-1/sos_cooldowns/hiker-1")));
  });
});

// ---------------------------------------------------------------------------
describe("hiker_presence — live location privacy", () => {
  test("a hiker can share their own location", async () => {
    await assertSucceeds(setDoc(doc(asHiker(), "hiker_presence/hiker-1"), {
      latitude: 7.0, longitude: 125.0, updatedAt: serverTimestamp(),
    }));
  });

  test("a hiker CANNOT read another hiker's location", async () => {
    await seed({ "hiker_presence/hiker-2": { latitude: 7.0, longitude: 125.0 } });
    await assertFails(getDoc(doc(asHiker(), "hiker_presence/hiker-2")));
  });

  test("a hiker CANNOT post a location for someone else", async () => {
    await assertFails(setDoc(doc(asHiker(), "hiker_presence/hiker-2"), {
      latitude: 7.0, longitude: 125.0, updatedAt: serverTimestamp(),
    }));
  });

  test("a hiker CANNOT attach extra data to their location", async () => {
    await assertFails(setDoc(doc(asHiker(), "hiker_presence/hiker-1"), {
      latitude: 7.0, longitude: 125.0, updatedAt: serverTimestamp(), name: "extra",
    }));
  });

  test("a hiker can stop sharing (delete) their own location", async () => {
    await seed({ "hiker_presence/hiker-1": { latitude: 7.0, longitude: 125.0 } });
    await assertSucceeds(deleteDoc(doc(asHiker(), "hiker_presence/hiker-1")));
  });
});

// ---------------------------------------------------------------------------
describe("tour guide applications and admin data", () => {
  test("a hiker can submit a pending tour guide application", async () => {
    await assertSucceeds(setDoc(doc(asHiker(), "tour_guide_applications/app-1"), {
      uid: "hiker-1", status: "pending",
    }));
  });

  test("a hiker CANNOT submit an already-approved application", async () => {
    await assertFails(setDoc(doc(asHiker(), "tour_guide_applications/app-1"), {
      uid: "hiker-1", status: "approved",
    }));
  });

  test("a hiker CANNOT approve their own application later", async () => {
    await seed({ "tour_guide_applications/app-1": { uid: "hiker-1", status: "pending" } });
    await assertFails(updateDoc(doc(asHiker(), "tour_guide_applications/app-1"), {
      status: "approved",
    }));
  });

  test("another hiker CANNOT read someone's application (contains a government ID)", async () => {
    await seed({ "tour_guide_applications/app-1": { uid: "hiker-1", status: "pending" } });
    await assertFails(getDoc(doc(asOtherHiker(), "tour_guide_applications/app-1")));
  });

  test("a hiker CANNOT read the admin audit log", async () => {
    await seed({ "admin_actions/a1": { action: "approve" } });
    await assertFails(getDoc(doc(asHiker(), "admin_actions/a1")));
  });

  test("a Tourism Admin can read the admin audit log", async () => {
    await seed({ "admin_actions/a1": { action: "approve" } });
    await assertSucceeds(getDoc(doc(asTourismAdmin(), "admin_actions/a1")));
  });
});

// ---------------------------------------------------------------------------
describe("community_posts", () => {
  const post = {
    authorId: "hiker-1", authorName: "Juan", content: "Great hike!",
    mountainName: "Mount Apo", likeCount: 0, commentCount: 0,
  };

  test("a hiker can create a post as themself", async () => {
    await assertSucceeds(setDoc(doc(asHiker(), "community_posts/p1"), post));
  });

  test("a hiker CANNOT post under someone else's name", async () => {
    await assertFails(setDoc(doc(asOtherHiker(), "community_posts/p1"), post));
  });

  test("another hiker can like a post (+1)", async () => {
    await seed({ "community_posts/p1": post });
    await assertSucceeds(updateDoc(doc(asOtherHiker(), "community_posts/p1"), { likeCount: 1 }));
  });

  test("another hiker CANNOT inflate the like count (+5)", async () => {
    await seed({ "community_posts/p1": post });
    await assertFails(updateDoc(doc(asOtherHiker(), "community_posts/p1"), { likeCount: 5 }));
  });

  test("another hiker CANNOT edit the post's content", async () => {
    await seed({ "community_posts/p1": post });
    await assertFails(updateDoc(doc(asOtherHiker(), "community_posts/p1"), { content: "Hacked" }));
  });

  test("another hiker CANNOT delete someone else's post", async () => {
    await seed({ "community_posts/p1": post });
    await assertFails(deleteDoc(doc(asOtherHiker(), "community_posts/p1")));
  });
});

// ---------------------------------------------------------------------------
describe("default deny", () => {
  test("any collection not listed in the rules is blocked", async () => {
    await assertFails(setDoc(doc(asHiker(), "random_collection/x"), { a: 1 }));
  });
});
