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

jest.mock("./mailer", () => ({
  MAIL_SECRETS: [],
  sendAdminWelcomeEmail: jest.fn().mockResolvedValue(),
}));

const admin = require("firebase-admin");
const mailer = require("./mailer");
const {
  findDeletedSosSenderIds,
  deleteUserAccount,
  deletePrivateUserData,
  getDeletedSosSenderIds,
  refreshAdminClaims,
  createAdminAccount,
  writeSosCleanupAudit,
} = require("./userAccountActions");

it("requires an explicit admin role when creating an admin account", async () => {
  await expect(
    createAdminAccount.run({
      auth: { uid: "tourism-admin", token: { admin: true } },
      data: { email: "head@example.com", fullName: "Mountain Head" },
    }),
  ).rejects.toMatchObject({
    code: "invalid-argument",
    message: "Choose either Tourism Admin or Mountain Head.",
  });
});

it("persists and returns the selected Mountain Head role and mountain", async () => {
  let savedProfile;
  let savedClaims;
  const auth = {
    createUser: jest.fn().mockResolvedValue({ uid: "head-uid" }),
    setCustomUserClaims: jest.fn((_uid, claims) => {
      savedClaims = claims;
      return Promise.resolve();
    }),
    generatePasswordResetLink: jest.fn().mockResolvedValue("reset-link"),
    deleteUser: jest.fn(),
  };
  const db = {
    collection: jest.fn((name) => ({
      doc: jest.fn(() => ({
        set: jest.fn((profile) => {
          if (name === "users") savedProfile = profile;
          return Promise.resolve();
        }),
      })),
      add: jest.fn(),
    })),
  };
  admin.auth.mockReturnValue(auth);
  admin.firestore.mockReturnValue(db);

  await expect(
    createAdminAccount.run({
      auth: { uid: "tourism-admin", token: { admin: true } },
      data: {
        fullName: "Mountain Head",
        email: "head@example.com",
        adminRole: "mountain_head",
        managedMountainName: "mT apo",
      },
    }),
  ).resolves.toMatchObject({
    uid: "head-uid",
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
    emailSent: true,
  });
  expect(savedProfile).toMatchObject({
    role: "admin",
    accountType: "admin",
    adminAccess: true,
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
  });
  expect(savedClaims).toMatchObject({
    admin: true,
    role: "admin",
    accountType: "admin",
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
  });
  // The setup link goes to the new admin's inbox only...
  expect(mailer.sendAdminWelcomeEmail).toHaveBeenCalledWith(expect.objectContaining({
    to: "head@example.com",
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
    setupLink: "reset-link",
  }));
});

it("never returns the password setup link to the admin who created the account", async () => {
  admin.auth.mockReturnValue({
    createUser: jest.fn().mockResolvedValue({ uid: "new-uid" }),
    setCustomUserClaims: jest.fn().mockResolvedValue(),
    generatePasswordResetLink: jest.fn().mockResolvedValue("secret-setup-link"),
    deleteUser: jest.fn(),
  });
  admin.firestore.mockReturnValue({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({ set: jest.fn().mockResolvedValue() })),
      add: jest.fn().mockResolvedValue(),
    })),
  });

  const result = await createAdminAccount.run({
    auth: { uid: "tourism-admin", token: { admin: true } },
    data: { fullName: "New Admin", email: "new@example.com", adminRole: "tourism_admin" },
  });

  expect(JSON.stringify(result)).not.toContain("secret-setup-link");
});

it("rolls the account back when the welcome email cannot be sent", async () => {
  mailer.sendAdminWelcomeEmail.mockRejectedValueOnce(new Error("SMTP auth failed"));
  const deleteUser = jest.fn().mockResolvedValue();
  const deleteProfile = jest.fn().mockResolvedValue();
  admin.auth.mockReturnValue({
    createUser: jest.fn().mockResolvedValue({ uid: "new-uid" }),
    setCustomUserClaims: jest.fn().mockResolvedValue(),
    generatePasswordResetLink: jest.fn().mockResolvedValue("link"),
    deleteUser,
  });
  admin.firestore.mockReturnValue({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({
        set: jest.fn().mockResolvedValue(),
        delete: deleteProfile,
      })),
      add: jest.fn().mockResolvedValue(),
    })),
  });
  const consoleError = jest.spyOn(console, "error").mockImplementation(() => {});

  await expect(createAdminAccount.run({
    auth: { uid: "tourism-admin", token: { admin: true } },
    data: { fullName: "New Admin", email: "new@example.com", adminRole: "tourism_admin" },
  })).rejects.toMatchObject({ code: "unavailable" });

  expect(deleteUser).toHaveBeenCalledWith("new-uid");
  expect(deleteProfile).toHaveBeenCalled();
  consoleError.mockRestore();
});

it("deletes the sign-in account first (freeing the email), then hike and profile data", async () => {
  const order = [];
  const db = {
    collection: jest.fn(() => ({
      add: jest.fn(() => {
        order.push("audit");
      }),
    })),
    recursiveDelete: jest.fn(() => {
      order.push("profile");
    }),
  };
  const auth = {
    deleteUser: jest.fn(() => {
      order.push("auth");
    }),
  };
  const cleanupHikeData = jest.fn(() => {
    order.push("hikes");
  });
  const cleanupPrivateData = jest.fn(() => {
    order.push("private");
  });

  await expect(
    deleteUserAccount({
      db,
      auth,
      request: { auth: { uid: "admin-uid", token: {} } },
      uid: "target-uid",
      profile: {},
      userRef: {},
      isAdmin: false,
      deleteAuthUser: true,
      cleanupHikeData,
      cleanupPrivateData,
    }),
  ).resolves.toEqual({ action: "delete", status: "deleted" });
  expect(order).toEqual(["audit", "auth", "hikes", "private", "profile"]);
});

it("deletes guide applications and private storage files for the account", async () => {
  const batch = { delete: jest.fn(), commit: jest.fn().mockResolvedValue() };
  const applicationRef = { id: "application-1" };
  const where = jest.fn(() => ({
    get: jest.fn().mockResolvedValue({
      docs: [{ ref: applicationRef }],
    }),
  }));
  const db = {
    collection: jest.fn(() => ({ where })),
    batch: jest.fn(() => batch),
  };
  const deleteFiles = jest.fn().mockResolvedValue();
  const storage = {
    bucket: jest.fn(() => ({ deleteFiles })),
  };

  await deletePrivateUserData(db, "target-uid", storage);

  expect(where).toHaveBeenCalledWith("uid", "==", "target-uid");
  expect(batch.delete).toHaveBeenCalledWith(applicationRef);
  expect(batch.commit).toHaveBeenCalledTimes(1);
  expect(deleteFiles).toHaveBeenCalledTimes(2);
  expect(deleteFiles).toHaveBeenCalledWith({
    prefix: "profile_photos/target-uid/",
  });
  expect(deleteFiles).toHaveBeenCalledWith({
    prefix: "tour_guide_applications/target-uid/",
  });
});

it("reports the exact phase when profile deletion fails", async () => {
  const db = {
    collection: jest.fn(() => ({ add: jest.fn().mockResolvedValue() })),
    recursiveDelete: jest.fn().mockRejectedValue(
      Object.assign(new Error("Firestore unavailable"), {
        code: "unavailable",
      }),
    ),
  };
  const consoleError = jest.spyOn(console, "error").mockImplementation(() => {});

  await expect(
    deleteUserAccount({
      db,
      auth: { deleteUser: jest.fn().mockResolvedValue() },
      request: { auth: { uid: "admin-uid", token: {} } },
      uid: "target-uid",
      profile: {},
      userRef: {},
      isAdmin: false,
      deleteAuthUser: true,
      cleanupHikeData: jest.fn().mockResolvedValue(),
      cleanupPrivateData: jest.fn().mockResolvedValue(),
    }),
  ).rejects.toMatchObject({
    code: "internal",
    message: expect.stringContaining("delete-firestore-profile"),
  });
  expect(consoleError).toHaveBeenCalledWith(
    "manageUserAccount delete failed",
    expect.objectContaining({
      uid: "target-uid",
      phase: "delete-firestore-profile",
      code: "unavailable",
    }),
  );
  consoleError.mockRestore();
});

it("refreshes custom claims from the Mountain Head's trusted profile", async () => {
  const profile = {
    role: "admin",
    accountType: "admin",
    adminAccess: true,
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
  };
  admin.firestore.mockReturnValue({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({
        get: jest.fn().mockResolvedValue({
          exists: true,
          data: () => profile,
        }),
      })),
    })),
  });

  const setCustomUserClaims = jest.fn();
  admin.auth.mockReturnValue({
    getUser: jest.fn().mockResolvedValue({
      customClaims: { unrelatedClaim: "preserved" },
    }),
    setCustomUserClaims,
  });

  await expect(
    refreshAdminClaims.run({ auth: { uid: "head-uid" } }),
  ).resolves.toEqual({
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
  });
  expect(setCustomUserClaims).toHaveBeenCalledWith("head-uid", {
    unrelatedClaim: "preserved",
    admin: true,
    role: "admin",
    accountType: "admin",
    adminRole: "mountain_head",
    managedMountainName: "Mt. Apo",
  });
});

it("does not issue admin claims when the trusted profile is not an admin", async () => {
  admin.firestore.mockReturnValue({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({
        get: jest.fn().mockResolvedValue({
          exists: true,
          data: () => ({ role: "hiker", accountType: "hiker" }),
        }),
      })),
    })),
  });
  const setCustomUserClaims = jest.fn();
  admin.auth.mockReturnValue({ getUser: jest.fn(), setCustomUserClaims });

  await expect(
    refreshAdminClaims.run({ auth: { uid: "hiker-uid" } }),
  ).rejects.toMatchObject({ code: "permission-denied" });
  expect(setCustomUserClaims).not.toHaveBeenCalled();
});

it("reports the failing server phase when custom claim updates fail", async () => {
  admin.firestore.mockReturnValue({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({
        get: jest.fn().mockResolvedValue({
          exists: true,
          data: () => ({
            role: "admin",
            accountType: "admin",
            adminRole: "mountain_head",
            managedMountainName: "Mt. Apo",
          }),
        }),
      })),
    })),
  });
  admin.auth.mockReturnValue({
    getUser: jest.fn().mockResolvedValue({ customClaims: {} }),
    setCustomUserClaims: jest.fn().mockRejectedValue(
      Object.assign(new Error("permission denied by IAM"), {
        code: "auth/insufficient-permission",
      }),
    ),
  });
  const consoleError = jest.spyOn(console, "error").mockImplementation(() => {});

  await expect(
    refreshAdminClaims.run({ auth: { uid: "head-uid" } }),
  ).rejects.toMatchObject({
    code: "internal",
    message: expect.stringContaining("write-custom-claims"),
  });
  expect(consoleError).toHaveBeenCalledWith(
    "refreshAdminClaims failed",
    expect.objectContaining({
      uid: "head-uid",
      phase: "write-custom-claims",
      code: "auth/insufficient-permission",
    }),
  );
  consoleError.mockRestore();
});

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
