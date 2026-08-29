// firebase-admin is mocked because requiring the real module tries to
// initialize actual Firebase credentials, which don't exist in a plain
// test environment — these tests only exercise pure helper functions
// that don't touch Firestore/Auth at all.
jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  firestore: Object.assign(jest.fn(), {
    Timestamp: { now: jest.fn(), fromMillis: jest.fn() },
    FieldValue: { serverTimestamp: jest.fn() },
  }),
  auth: jest.fn(),
}));

const {
  randomSixDigitCode,
  hashCode,
  sanitizeRoutePoints,
  isFiniteNumberInRange,
  weatherCodeFromGoogleCondition,
  isWetWeatherCode,
  hikeWeatherRisk,
} = require("./index");

describe("randomSixDigitCode", () => {
  it("returns a 6-digit numeric string", () => {
    for (let i = 0; i < 20; i += 1) {
      expect(randomSixDigitCode()).toMatch(/^\d{6}$/);
    }
  });

  it("produces varied values, not a constant", () => {
    const values = new Set(Array.from({ length: 20 }, randomSixDigitCode));
    expect(values.size).toBeGreaterThan(1);
  });
});

describe("hashCode", () => {
  it("is deterministic for the same input", () => {
    const a = hashCode({ code: "123456", uid: "user1" });
    const b = hashCode({ code: "123456", uid: "user1" });
    expect(a).toBe(b);
  });

  it("differs when the code differs", () => {
    const a = hashCode({ code: "123456", uid: "user1" });
    const b = hashCode({ code: "654321", uid: "user1" });
    expect(a).not.toBe(b);
  });

  it("differs when the uid differs", () => {
    const a = hashCode({ code: "123456", uid: "user1" });
    const b = hashCode({ code: "123456", uid: "user2" });
    expect(a).not.toBe(b);
  });

  it("returns a 64-character hex string (SHA-256)", () => {
    expect(hashCode({ code: "123456", uid: "user1" })).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("sanitizeRoutePoints", () => {
  it("returns an empty array for non-array input", () => {
    expect(sanitizeRoutePoints(null)).toEqual([]);
    expect(sanitizeRoutePoints(undefined)).toEqual([]);
    expect(sanitizeRoutePoints("not an array")).toEqual([]);
  });

  it("keeps valid points and rounds to 7 decimal places", () => {
    const result = sanitizeRoutePoints([{ lat: 6.98781234567, lon: 125.2731234567 }]);
    expect(result).toEqual([{ lat: 6.9878123, lon: 125.2731235 }]);
  });

  it("drops points with out-of-range coordinates", () => {
    const result = sanitizeRoutePoints([
      { lat: 200, lon: 0 },
      { lat: 0, lon: -200 },
      { lat: 10, lon: 20 },
    ]);
    expect(result).toEqual([{ lat: 10, lon: 20 }]);
  });

  it("drops malformed entries without throwing", () => {
    const result = sanitizeRoutePoints([null, "bad", 42, { lat: "abc", lon: 1 }, { lat: 1, lon: 2 }]);
    expect(result).toEqual([{ lat: 1, lon: 2 }]);
  });
});

describe("isFiniteNumberInRange", () => {
  it("accepts numbers within range", () => {
    expect(isFiniteNumberInRange(10, 0, 20)).toBe(true);
    expect(isFiniteNumberInRange("10", 0, 20)).toBe(true);
  });

  it("rejects out-of-range, non-numeric, and non-finite values", () => {
    expect(isFiniteNumberInRange(30, 0, 20)).toBe(false);
    expect(isFiniteNumberInRange("abc", 0, 20)).toBe(false);
    expect(isFiniteNumberInRange(undefined, 0, 20)).toBe(false);
    expect(isFiniteNumberInRange(Infinity, 0, 20)).toBe(false);
  });
});

describe("weatherCodeFromGoogleCondition", () => {
  it.each([
    ["THUNDERSTORM", 95],
    ["HEAVY_RAIN", 65],
    ["HEAVY_SHOWERS", 82],
    ["LIGHT_SHOWERS", 80],
    ["RAIN", 63],
    ["DRIZZLE", 53],
    ["SNOW", 71],
    ["ICE", 71],
    ["FOG", 45],
    ["HAZE", 45],
    ["PARTLY_CLOUDY", 2],
    ["CLOUDY", 3],
    ["CLEAR", 0],
    ["SUNNY", 0],
    ["", 3],
    ["SOME_UNKNOWN_CONDITION", 3],
  ])("maps %s to weather code %i", (condition, expected) => {
    expect(weatherCodeFromGoogleCondition(condition)).toBe(expected);
  });
});

describe("isWetWeatherCode", () => {
  it.each([51, 65, 67, 71, 82, 86, 95, 99])("treats code %i as wet", (code) => {
    expect(isWetWeatherCode(code)).toBe(true);
  });

  it.each([0, 1, 2, 3, 45, 50, 87, 94])("treats code %i as not wet", (code) => {
    expect(isWetWeatherCode(code)).toBe(false);
  });
});

describe("hikeWeatherRisk", () => {
  it("flags a thunderstorm as unsafe", () => {
    expect(hikeWeatherRisk({ weatherCode: 95 })).toBe("unsafe");
  });

  it("flags heavy rain as unsafe", () => {
    expect(hikeWeatherRisk({ weatherCode: 65 })).toBe("unsafe");
  });

  it("flags a high rain chance as unsafe even with a clear code", () => {
    expect(hikeWeatherRisk({ weatherCode: 0, rainChancePercent: 85 })).toBe("unsafe");
  });

  it("flags heavy wind as unsafe", () => {
    expect(hikeWeatherRisk({ weatherCode: 0, windSpeedKmh: 50 })).toBe("unsafe");
  });

  it("flags a wet-but-not-severe code as caution", () => {
    expect(hikeWeatherRisk({ weatherCode: 53 })).toBe("caution");
  });

  it("flags a moderate rain chance as caution", () => {
    expect(hikeWeatherRisk({ weatherCode: 0, rainChancePercent: 60 })).toBe("caution");
  });

  it("treats clear, calm conditions as good", () => {
    expect(
      hikeWeatherRisk({
        weatherCode: 0,
        rainChancePercent: 5,
        precipitationMm: 0,
        windSpeedKmh: 10,
      }),
    ).toBe("good");
  });
});
