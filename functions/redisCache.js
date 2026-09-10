const { Redis } = require("@upstash/redis");

let _client = null;

// Returns null when the secrets aren't configured — callers must treat a
// null client as "cache disabled", not as an error, so weather lookups
// keep working even before/without Upstash being set up.
function getRedisClient() {
  if (_client) {
    return _client;
  }
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    return null;
  }
  _client = new Redis({ url, token });
  return _client;
}
exports.getRedisClient = getRedisClient;

function weatherCacheKey(latitude, longitude) {
  return `weather:${latitude.toFixed(2)}:${longitude.toFixed(2)}`;
}
exports.weatherCacheKey = weatherCacheKey;
