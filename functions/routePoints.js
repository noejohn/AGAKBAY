// Shared by index.js (submission intake) and trailReview.js (publish on
// approval) — kept in its own file so trailReview.js doesn't have to
// require index.js and risk a circular require.
function sanitizeRoutePoints(points) {
  if (!Array.isArray(points)) {
    return [];
  }
  const cleaned = [];
  for (const point of points) {
    if (!point || typeof point !== "object") {
      continue;
    }
    const lat = Number(point.lat);
    const lon = Number(point.lon);
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lon) ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180
    ) {
      continue;
    }
    cleaned.push({
      lat: Number(lat.toFixed(7)),
      lon: Number(lon.toFixed(7)),
    });
  }
  return cleaned;
}

module.exports = { sanitizeRoutePoints };
