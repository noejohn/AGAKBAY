const {
  haversineMeters,
  pickNearbyHikers,
  PRESENCE_FRESH_MS,
  MAX_NEARBY_HIKERS,
} = require("./nearbySos");

describe("haversineMeters", () => {
  test("is zero for the same point", () => {
    expect(haversineMeters(7.0, 125.0, 7.0, 125.0)).toBe(0);
  });

  test("is about 111 km per degree of latitude", () => {
    const meters = haversineMeters(7.0, 125.0, 8.0, 125.0);
    expect(meters).toBeGreaterThan(110000);
    expect(meters).toBeLessThan(112000);
  });
});

describe("pickNearbyHikers", () => {
  const nowMs = 1_000_000_000;
  const sender = { senderId: "me", latitude: 7.0, longitude: 125.0, nowMs };
  const fresh = (uid, latitude, longitude) => ({
    uid,
    latitude,
    longitude,
    updatedAtMs: nowMs,
  });

  test("sorts by distance and excludes the sender", () => {
    const result = pickNearbyHikers([
      fresh("far", 7.02, 125.0),
      fresh("me", 7.0, 125.0),
      fresh("near", 7.001, 125.0),
    ], sender);
    expect(result.map((h) => h.uid)).toEqual(["near", "far"]);
  });

  test("drops hikers outside the radius", () => {
    // ~11 km away.
    const result = pickNearbyHikers([fresh("away", 7.1, 125.0)], sender);
    expect(result).toEqual([]);
  });

  test("drops stale presence", () => {
    const result = pickNearbyHikers([{
      uid: "stale",
      latitude: 7.001,
      longitude: 125.0,
      updatedAtMs: nowMs - PRESENCE_FRESH_MS - 1,
    }], sender);
    expect(result).toEqual([]);
  });

  test("drops invalid coordinates", () => {
    const result = pickNearbyHikers([fresh("bad", NaN, 125.0)], sender);
    expect(result).toEqual([]);
  });

  test("caps the number of hikers notified", () => {
    const many = Array.from({ length: MAX_NEARBY_HIKERS + 3 }, (_, i) =>
      fresh(`h${i}`, 7.0 + i * 0.0005, 125.0));
    expect(pickNearbyHikers(many, sender)).toHaveLength(MAX_NEARBY_HIKERS);
  });
});
