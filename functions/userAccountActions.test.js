jest.mock("firebase-admin", () => ({
  auth: jest.fn(),
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: jest.fn() },
  }),
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn((options, handler) => ({ run: handler })),
  HttpsError: class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  },
}));

const admin = require("firebase-admin");
const {
  findDeletedSosSenderIds,
  getDeletedSosSenderIds,
  writeSosCleanupAudit,
} = require("./userAccountActions");

it("identifies deleted SOS senders using Firebase Auth, not missing profiles", async () => {
  const docs = [
    { data: () => ({ senderId: "active-user" }) },
    { data: () => ({ senderId: "deleted-user" }) },
    { data: () => ({ senderId: "deleted-user" }) },
    { data: () => ({ senderId: "" }) },
    { data: () => ({ senderId: null }) },
  ];
  const getUsers = jest.fn().mockResolvedValue({
    notFound: [{ uid: "deleted-user" }],
  });

  const deletedIds = await findDeletedSosSenderIds(
    {},
    { getUsers },
    docs,
  );

  expect(getUsers).toHaveBeenCalledWith([
    { uid: "active-user" },
    { uid: "deleted-user" },
  ]);
  expect([...deletedIds]).toEqual(["deleted-user"]);
});

it("requires admin access and returns deleted SOS sender IDs", async () => {
  await expect(
    getDeletedSosSenderIds.run({ auth: { token: { admin: false } } }),
  ).rejects.toMatchObject({ code: "permission-denied" });

  const get = jest.fn().mockResolvedValue({
    docs: [{ data: () => ({ senderId: "deleted-user" }) }],
  });
  admin.firestore.mockReturnValue({
    collectionGroup: jest.fn(() => ({ get })),
  });
  const getUsers = jest.fn().mockResolvedValue({
    notFound: [{ uid: "deleted-user" }],
  });
  admin.auth.mockReturnValue({ getUsers });

  await expect(
    getDeletedSosSenderIds.run({ auth: { token: { admin: true } } }),
  ).resolves.toEqual({ senderIds: ["deleted-user"] });
  expect(get).toHaveBeenCalled();
});

it("writes the SOS cleanup audit entry and admin notification together", async () => {
  const writes = [];
  const auditRef = { id: "cleanup-action-1" };
  const notificationRef = { id: "admin_action_cleanup-action-1" };
  const batch = {
    set: jest.fn((ref, data) => writes.push({ ref, data })),
    commit: jest.fn().mockResolvedValue(),
  };
  const collection = jest.fn((name) => ({
    doc: jest.fn((id) => {
      if (name === "admin_actions") return auditRef;
      return id ? notificationRef : undefined;
    }),
  }));
  const db = { collection, batch: jest.fn(() => batch) };
  const auth = {
    uid: "admin-uid",
    token: { admin: true, email: "admin@example.com", name: "Admin User" },
  };

  await writeSosCleanupAudit(db, auth, {
    deletedSosEvents: 3,
    deletedSosNotifications: 2,
  });

  expect(batch.set).toHaveBeenCalledTimes(2);
  expect(writes[0]).toMatchObject({
    ref: auditRef,
    data: {
      action: "cleanup_orphaned_sos_events",
      adminId: "admin-uid",
      adminEmail: "admin@example.com",
      deletedSosEvents: 3,
      deletedSosNotifications: 2,
      notifyAdmins: false,
    },
  });
  expect(writes[1]).toMatchObject({
    ref: notificationRef,
    data: {
      type: "admin_action",
      title: "Admin Activity",
      actionId: "cleanup-action-1",
      action: "cleanup_orphaned_sos_events",
      isRead: false,
    },
  });
  expect(writes[1].data.message).toContain("Admin User");
  expect(writes[1].data.message).toContain("Removed 3 SOS alerts and 2 notifications.");
  expect(batch.commit).toHaveBeenCalledTimes(1);
});
