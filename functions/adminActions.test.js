const mockAppDocGet = jest.fn();
const mockAppDocUpdate = jest.fn();
const mockUserDocUpdate = jest.fn();
const mockCollectionAdd = jest.fn();
const mockNotificationAdd = jest.fn();
const mockSetCustomUserClaims = jest.fn();

jest.mock("firebase-admin", () => ({
  auth: jest.fn(() => ({
    setCustomUserClaims: mockSetCustomUserClaims,
  })),
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn((name) => {
        if (name === "tour_guide_applications") {
          return { doc: jest.fn(() => ({ get: mockAppDocGet, update: mockAppDocUpdate })) };
        }
        if (name === "users") {
          return {
            doc: jest.fn(() => ({
              update: mockUserDocUpdate,
              collection: jest.fn(() => ({ add: mockNotificationAdd })),
            })),
          };
        }
        if (name === "admin_actions") {
          return { add: mockCollectionAdd };
        }
        throw new Error(`Unexpected collection in test: ${name}`);
      }),
    })),
    { FieldValue: { serverTimestamp: jest.fn(() => "SERVER_TIMESTAMP") } },
  ),
}));

const { reviewTourGuideApplication } = require("./adminActions");

const adminAuth = { uid: "admin-uid", token: { admin: true } };
const callHandler = (data, auth = adminAuth) => reviewTourGuideApplication.run({ data, auth });

beforeEach(() => {
  jest.clearAllMocks();
});

it("rejects when the caller lacks the admin claim", async () => {
  await expect(
    callHandler(
      { applicationId: "app-1", decision: "approve" },
      { uid: "hiker-uid", token: { admin: false } },
    ),
  ).rejects.toMatchObject({ code: "permission-denied" });
  expect(mockAppDocGet).not.toHaveBeenCalled();
});

it("rejects when not signed in at all", async () => {
  await expect(
    callHandler({ applicationId: "app-1", decision: "approve" }, null),
  ).rejects.toMatchObject({ code: "permission-denied" });
});

it("rejects an invalid decision value", async () => {
  await expect(callHandler({ applicationId: "app-1", decision: "maybe" })).rejects.toThrow(
    /approve.*reject/,
  );
});

it("rejects when the application doesn't exist", async () => {
  mockAppDocGet.mockResolvedValue({ exists: false });

  await expect(callHandler({ applicationId: "ghost-app", decision: "approve" })).rejects.toThrow(
    /No application/,
  );
});

it("rejects when the application has already been reviewed", async () => {
  mockAppDocGet.mockResolvedValue({
    exists: true,
    data: () => ({ uid: "guide-1", status: "approved" }),
  });

  await expect(callHandler({ applicationId: "app-1", decision: "approve" })).rejects.toThrow(
    /already been reviewed/,
  );
  expect(mockAppDocUpdate).not.toHaveBeenCalled();
});

describe("approve", () => {
  beforeEach(() => {
    mockAppDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ uid: "guide-1", status: "pending" }),
    });
  });

  it("marks the application approved and promotes the account to verified tour_guide", async () => {
    const result = await callHandler({ applicationId: "app-1", decision: "approve" });

    expect(mockAppDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ status: "approved", reviewedBy: "admin-uid" }),
    );
    expect(mockUserDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        role: "tour_guide",
        accountType: "tour_guide",
        guideVerified: true,
      }),
    );
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("guide-1", {
      role: "tour_guide",
      accountType: "tour_guide",
      guideVerified: true,
      admin: false,
    });
    expect(result).toEqual({ decision: "approve" });
  });

  it("writes an audit log entry", async () => {
    await callHandler({ applicationId: "app-1", decision: "approve", reason: "looks good" });

    expect(mockCollectionAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        adminId: "admin-uid",
        action: "approve_tour_guide",
        targetId: "guide-1",
        previousStatus: "pending",
        newStatus: "approved",
        reason: "looks good",
      }),
    );
  });

  it("notifies the applicant of the approval", async () => {
    await callHandler({ applicationId: "app-1", decision: "approve" });

    expect(mockNotificationAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "guide_application",
        title: "Tour Guide Application Approved!",
        read: false,
      }),
    );
  });
});

describe("reject", () => {
  beforeEach(() => {
    mockAppDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ uid: "guide-2", status: "pending" }),
    });
  });

  it("marks the application rejected without touching the user's account", async () => {
    const result = await callHandler({ applicationId: "app-2", decision: "reject" });

    expect(mockAppDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ status: "rejected", reviewedBy: "admin-uid" }),
    );
    expect(mockUserDocUpdate).not.toHaveBeenCalled();
    expect(mockSetCustomUserClaims).not.toHaveBeenCalled();
    expect(result).toEqual({ decision: "reject" });
  });

  it("writes an audit log entry with no reason when none is given", async () => {
    await callHandler({ applicationId: "app-2", decision: "reject" });

    expect(mockCollectionAdd).toHaveBeenCalledWith(
      expect.objectContaining({ action: "reject_tour_guide", newStatus: "rejected", reason: null }),
    );
  });

  it("notifies the applicant of the rejection, including the reason when given", async () => {
    await callHandler({ applicationId: "app-2", decision: "reject", reason: "ID unreadable" });

    expect(mockNotificationAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "guide_application",
        title: "Tour Guide Application Update",
        body: expect.stringContaining("ID unreadable"),
        read: false,
      }),
    );
  });
});
