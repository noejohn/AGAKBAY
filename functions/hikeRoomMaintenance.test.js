const mockRoomGet = jest.fn();
const mockNotificationSet = jest.fn();

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn((name) => {
        if (name === "hike_rooms") {
          return { doc: jest.fn(() => ({ get: mockRoomGet })) };
        }
        if (name === "users") {
          return {
            doc: jest.fn(() => ({
              collection: jest.fn(() => ({
                doc: jest.fn(() => ({ set: mockNotificationSet })),
              })),
            })),
          };
        }
        throw new Error(`Unexpected collection in test: ${name}`);
      }),
    })),
    { FieldValue: { serverTimestamp: jest.fn(() => "SERVER_TIMESTAMP") } },
  ),
}));

const { notifyGuideOfStoppedHiker } = require("./hikeRoomMaintenance");

const callTrigger = (before, after, params = { roomId: "room-1", participantId: "hiker-1" }) =>
  notifyGuideOfStoppedHiker.run({
    data: {
      before: { data: () => before },
      after: { data: () => after },
    },
    params,
  });

beforeEach(() => {
  jest.clearAllMocks();
  mockRoomGet.mockResolvedValue({
    exists: true,
    data: () => ({ guideId: "guide-1" }),
  });
});

it("notifies the guide when a participant transitions into 'stopped'", async () => {
  await callTrigger(
    { membershipStatus: "active" },
    { membershipStatus: "stopped", name: "Juan", stopReason: "Twisted my ankle" },
  );

  expect(mockNotificationSet).toHaveBeenCalledWith(
    expect.objectContaining({
      type: "hiker_stopped",
      title: "Juan can't continue",
      body: "Twisted my ankle",
      roomId: "room-1",
      participantId: "hiker-1",
      read: false,
    }),
    { merge: true },
  );
});

it("does nothing when the participant was already 'stopped' before this update", async () => {
  await callTrigger(
    { membershipStatus: "stopped" },
    { membershipStatus: "stopped", name: "Juan", stopReason: "still stopped" },
  );

  expect(mockNotificationSet).not.toHaveBeenCalled();
});

it("does nothing when the update isn't a transition into 'stopped'", async () => {
  await callTrigger(
    { membershipStatus: "active" },
    { membershipStatus: "active", latitude: 7.01 },
  );

  expect(mockNotificationSet).not.toHaveBeenCalled();
});

it("does nothing when the room no longer exists", async () => {
  mockRoomGet.mockResolvedValue({ exists: false });

  await callTrigger(
    { membershipStatus: "active" },
    { membershipStatus: "stopped", name: "Juan", stopReason: "tired" },
  );

  expect(mockNotificationSet).not.toHaveBeenCalled();
});

it("does nothing when the guide somehow stops themself", async () => {
  mockRoomGet.mockResolvedValue({
    exists: true,
    data: () => ({ guideId: "guide-1" }),
  });

  await callTrigger(
    { membershipStatus: "active" },
    { membershipStatus: "stopped", name: "Guide", stopReason: "n/a" },
    { roomId: "room-1", participantId: "guide-1" },
  );

  expect(mockNotificationSet).not.toHaveBeenCalled();
});
