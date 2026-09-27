const mockSubmissionGet = jest.fn();
const mockSubmissionUpdate = jest.fn();
const mockMountainTrailSet = jest.fn();
const mockNotificationAdd = jest.fn();
const mockAuditAdd = jest.fn();
const mockLeaderboardGet = jest.fn();
const mockBatchSet = jest.fn();
const mockBatchCommit = jest.fn();

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn((name) => {
        if (name === "trail_submissions") {
          return { doc: jest.fn(() => ({ get: mockSubmissionGet, update: mockSubmissionUpdate })) };
        }
        if (name === "mountain_trails") {
          return { doc: jest.fn(() => ({ set: mockMountainTrailSet })) };
        }
        if (name === "users") {
          return {
            doc: jest.fn(() => ({
              collection: jest.fn(() => ({
                add: mockNotificationAdd,
                doc: jest.fn(() => "NOTIFICATION_DOC_REF"),
              })),
            })),
          };
        }
        if (name === "admin_actions") {
          return { add: mockAuditAdd };
        }
        if (name === "leaderboard") {
          return { where: jest.fn(() => ({ get: mockLeaderboardGet })) };
        }
        throw new Error(`Unexpected collection in test: ${name}`);
      }),
      batch: jest.fn(() => ({ set: mockBatchSet, commit: mockBatchCommit })),
    })),
    { FieldValue: { serverTimestamp: jest.fn(() => "SERVER_TIMESTAMP") } },
  ),
}));

const { reviewTrailSubmission } = require("./trailReview");

const adminAuth = { uid: "admin-uid", token: { admin: true, email: "admin@agakbay.ph" } };
const callHandler = (data, auth = adminAuth) => reviewTrailSubmission.run({ data, auth });

beforeEach(() => {
  jest.clearAllMocks();
  mockLeaderboardGet.mockResolvedValue({ empty: true, forEach: jest.fn() });
});

it("rejects when the caller lacks the admin claim", async () => {
  await expect(
    callHandler(
      { submissionId: "sub-1", decision: "approve" },
      { uid: "hiker-uid", token: { admin: false } },
    ),
  ).rejects.toMatchObject({ code: "permission-denied" });
  expect(mockSubmissionGet).not.toHaveBeenCalled();
});

it("rejects an invalid decision value", async () => {
  await expect(callHandler({ submissionId: "sub-1", decision: "maybe" })).rejects.toThrow(
    /approve.*reject/,
  );
});

it("rejects when the submission doesn't exist", async () => {
  mockSubmissionGet.mockResolvedValue({ exists: false });

  await expect(callHandler({ submissionId: "ghost", decision: "approve" })).rejects.toThrow(
    /No trail submission/,
  );
});

it("rejects when the submission has already been reviewed", async () => {
  mockSubmissionGet.mockResolvedValue({
    exists: true,
    data: () => ({ status: "approved" }),
  });

  await expect(callHandler({ submissionId: "sub-1", decision: "approve" })).rejects.toThrow(
    /already been reviewed/,
  );
  expect(mockSubmissionUpdate).not.toHaveBeenCalled();
});

describe("approve", () => {
  beforeEach(() => {
    mockSubmissionGet.mockResolvedValue({
      exists: true,
      data: () => ({
        status: "pending",
        submittedBy: "hiker-1",
        mountainKey: "mt-apo",
        mountainName: "Mt. Apo",
        trailName: "Mt. Apo Summit Trail",
        routePoints: [
          { lat: 7.0, lon: 125.27 },
          { lat: 7.01, lon: 125.28 },
        ],
      }),
    });
  });

  it("marks the submission approved and publishes to mountain_trails", async () => {
    const result = await callHandler({ submissionId: "sub-1", decision: "approve" });

    expect(mockSubmissionUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ status: "approved", reviewedBy: "admin-uid" }),
    );
    expect(mockMountainTrailSet).toHaveBeenCalledWith(
      expect.objectContaining({
        mountainKey: "mt-apo",
        status: "verified",
        trailName: "Mt. Apo Summit Trail",
      }),
      { merge: true },
    );
    expect(result).toEqual({ decision: "approve" });
  });

  it("notifies the submitter of the approval", async () => {
    await callHandler({ submissionId: "sub-1", decision: "approve" });

    expect(mockNotificationAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "trail",
        title: "Trail Submission Approved!",
        read: false,
      }),
    );
  });

  it("notifies other hikers who've done that mountain, excluding the submitter", async () => {
    mockLeaderboardGet.mockResolvedValue({
      empty: false,
      forEach: (cb) => {
        cb({ id: "hiker-1" }); // the submitter — must be skipped
        cb({ id: "hiker-2" });
      },
    });

    await callHandler({ submissionId: "sub-1", decision: "approve" });

    expect(mockBatchSet).toHaveBeenCalledTimes(1);
    expect(mockBatchSet).toHaveBeenCalledWith(
      "NOTIFICATION_DOC_REF",
      expect.objectContaining({ type: "trail", title: "New trail recorded" }),
    );
    expect(mockBatchCommit).toHaveBeenCalled();
  });

  it("writes an audit log entry", async () => {
    await callHandler({ submissionId: "sub-1", decision: "approve" });

    expect(mockAuditAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        adminId: "admin-uid",
        adminEmail: "admin@agakbay.ph",
        action: "approve_trail_submission",
        targetId: "sub-1",
        previousStatus: "pending",
        newStatus: "approved",
      }),
    );
  });

  it("does not publish when there are fewer than 2 route points", async () => {
    mockSubmissionGet.mockResolvedValue({
      exists: true,
      data: () => ({
        status: "pending",
        submittedBy: "hiker-1",
        mountainKey: "mt-apo",
        mountainName: "Mt. Apo",
        routePoints: [{ lat: 7.0, lon: 125.27 }],
      }),
    });

    await callHandler({ submissionId: "sub-1", decision: "approve" });

    expect(mockMountainTrailSet).not.toHaveBeenCalled();
  });
});

describe("reject", () => {
  beforeEach(() => {
    mockSubmissionGet.mockResolvedValue({
      exists: true,
      data: () => ({
        status: "pending",
        submittedBy: "hiker-2",
        mountainKey: "mt-apo",
        mountainName: "Mt. Apo",
        trailName: "Mt. Apo Summit Trail",
        routePoints: [
          { lat: 7.0, lon: 125.27 },
          { lat: 7.01, lon: 125.28 },
        ],
      }),
    });
  });

  it("marks the submission rejected without publishing anything", async () => {
    const result = await callHandler({ submissionId: "sub-2", decision: "reject" });

    expect(mockSubmissionUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ status: "rejected", reviewedBy: "admin-uid" }),
    );
    expect(mockMountainTrailSet).not.toHaveBeenCalled();
    expect(result).toEqual({ decision: "reject" });
  });

  it("notifies the submitter of the rejection, including the reason when given", async () => {
    await callHandler({ submissionId: "sub-2", decision: "reject", reason: "GPS points look off" });

    expect(mockNotificationAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "trail",
        title: "Trail Submission Update",
        body: expect.stringContaining("GPS points look off"),
        read: false,
      }),
    );
  });

  it("does not notify other hikers", async () => {
    await callHandler({ submissionId: "sub-2", decision: "reject" });

    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  it("writes an audit log entry with no reason when none is given", async () => {
    await callHandler({ submissionId: "sub-2", decision: "reject" });

    expect(mockAuditAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "reject_trail_submission",
        newStatus: "rejected",
        reason: null,
      }),
    );
  });
});
