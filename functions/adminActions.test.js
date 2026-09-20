const mockDocGet = jest.fn();
const mockDocUpdate = jest.fn();
const mockCollectionAdd = jest.fn();
const mockSetCustomUserClaims = jest.fn();

jest.mock("firebase-admin", () => ({
  auth: jest.fn(() => ({
    setCustomUserClaims: mockSetCustomUserClaims,
  })),
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn((name) => ({
        doc: jest.fn(() => ({
          get: mockDocGet,
          update: mockDocUpdate,
        })),
        add: mockCollectionAdd,
        __name: name,
      })),
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
    callHandler({ uid: "guide-1", decision: "approve" }, { uid: "hiker-uid", token: { admin: false } }),
  ).rejects.toMatchObject({ code: "permission-denied" });
  expect(mockDocGet).not.toHaveBeenCalled();
});

it("rejects when not signed in at all", async () => {
  await expect(callHandler({ uid: "guide-1", decision: "approve" }, null)).rejects.toMatchObject({
    code: "permission-denied",
  });
});

it("rejects an invalid decision value", async () => {
  await expect(callHandler({ uid: "guide-1", decision: "maybe" })).rejects.toThrow(
    /approve.*reject/,
  );
});

it("rejects when the target user doc doesn't exist", async () => {
  mockDocGet.mockResolvedValue({ exists: false });

  await expect(callHandler({ uid: "ghost-uid", decision: "approve" })).rejects.toThrow(
    /No user profile/,
  );
});

it("rejects when the account has no pending application", async () => {
  mockDocGet.mockResolvedValue({
    exists: true,
    data: () => ({ accountType: "hiker", guideVerified: null }),
  });

  await expect(callHandler({ uid: "hiker-1", decision: "approve" })).rejects.toThrow(
    /no pending tour guide application/,
  );
  expect(mockDocUpdate).not.toHaveBeenCalled();
});

describe("approve", () => {
  beforeEach(() => {
    mockDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ accountType: "tour_guide", guideVerified: false }),
    });
  });

  it("sets guideVerified true and mirrors verified tour_guide claims", async () => {
    const result = await callHandler({ uid: "guide-1", decision: "approve" });

    expect(mockDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ guideVerified: true }),
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
    await callHandler({ uid: "guide-1", decision: "approve", reason: "looks good" });

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
});

describe("reject", () => {
  beforeEach(() => {
    mockDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ accountType: "tour_guide", guideVerified: false }),
    });
  });

  it("drops the account back to hiker instead of leaving it in limbo", async () => {
    const result = await callHandler({ uid: "guide-2", decision: "reject" });

    expect(mockDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ role: "hiker", accountType: "hiker", guideVerified: null }),
    );
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("guide-2", {
      role: "hiker",
      accountType: "hiker",
      guideVerified: null,
      admin: false,
    });
    expect(result).toEqual({ decision: "reject" });
  });

  it("writes an audit log entry with no reason when none is given", async () => {
    await callHandler({ uid: "guide-2", decision: "reject" });

    expect(mockCollectionAdd).toHaveBeenCalledWith(
      expect.objectContaining({ action: "reject_tour_guide", newStatus: "rejected", reason: null }),
    );
  });
});
