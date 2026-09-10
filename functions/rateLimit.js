const { HttpsError } = require("firebase-functions/v2/https");

// Fixed-window counter via Redis INCR/EXPIRE: the window starts on the
// first call for a given key and resets windowSeconds after that first
// call, not on every subsequent hit. `redis` is dependency-injected (see
// getRedisClient in redisCache.js) so this stays unit-testable without a
// real Redis connection, and — same as buildWeatherSnapshot's cache — a
// null/failing redis client fails OPEN rather than blocking real users,
// since this is a defense-in-depth layer, not the only control.
async function enforceRateLimit({ redis, key, maxCalls, windowSeconds }) {
  if (!redis) {
    return;
  }
  let count;
  try {
    count = await redis.incr(key);
    if (count === 1) {
      await redis.expire(key, windowSeconds);
    }
  } catch {
    return;
  }
  if (count > maxCalls) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please wait a moment and try again.",
    );
  }
}
exports.enforceRateLimit = enforceRateLimit;
