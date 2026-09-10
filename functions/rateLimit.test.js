const { enforceRateLimit } = require("./rateLimit");

describe("enforceRateLimit", () => {
  it("allows the call through when redis is null (fails open when unconfigured)", async () => {
    await expect(
      enforceRateLimit({ redis: null, key: "k", maxCalls: 1, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });

  it("allows the call through when redis.incr rejects (fails open on error)", async () => {
    const redis = { incr: jest.fn().mockRejectedValue(new Error("network error")) };

    await expect(
      enforceRateLimit({ redis, key: "k", maxCalls: 1, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });

  it("sets an expiry only on the first call in a window", async () => {
    const redis = { incr: jest.fn().mockResolvedValue(1), expire: jest.fn() };

    await enforceRateLimit({ redis, key: "k", maxCalls: 5, windowSeconds: 60 });

    expect(redis.expire).toHaveBeenCalledWith("k", 60);
  });

  it("does not reset the expiry on later calls in the same window", async () => {
    const redis = { incr: jest.fn().mockResolvedValue(2), expire: jest.fn() };

    await enforceRateLimit({ redis, key: "k", maxCalls: 5, windowSeconds: 60 });

    expect(redis.expire).not.toHaveBeenCalled();
  });

  it("allows calls at or under the limit", async () => {
    const redis = { incr: jest.fn().mockResolvedValue(5), expire: jest.fn() };

    await expect(
      enforceRateLimit({ redis, key: "k", maxCalls: 5, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });

  it("throws resource-exhausted once the count exceeds the limit", async () => {
    const redis = { incr: jest.fn().mockResolvedValue(6), expire: jest.fn() };

    await expect(
      enforceRateLimit({ redis, key: "k", maxCalls: 5, windowSeconds: 60 }),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
  });
});
