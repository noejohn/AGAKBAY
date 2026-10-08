const { HttpsError } = require("firebase-functions/v2/https");
const { normalizeMountainName } = require("./mountainNames");

function isTourismAdmin(auth) {
  return auth?.token?.admin === true &&
    (auth.token.adminRole === undefined ||
      auth.token.adminRole === "tourism_admin");
}

function assertTourismAdmin(auth) {
  if (!isTourismAdmin(auth)) {
    throw new HttpsError("permission-denied", "Tourism Admin access required.");
  }
}

function assertMountainHead(auth) {
  const mountainName = auth?.token?.managedMountainName;
  if (
    auth?.token?.admin !== true ||
    auth.token.adminRole !== "mountain_head" ||
    typeof mountainName !== "string" ||
    !mountainName.trim()
  ) {
    throw new HttpsError(
      "permission-denied",
      "Mountain Head access for an assigned mountain is required.",
    );
  }
  return mountainName.trim();
}

function normalizeMountainNames(value) {
  if (Array.isArray(value)) {
    return value
      .filter((name) => typeof name === "string")
      .map(normalizeMountainName)
      .filter(Boolean);
  }
  if (typeof value !== "string") return [];
  return value
    .split(/[,;\n]/)
    .map(normalizeMountainName)
    .filter(Boolean);
}

module.exports = {
  assertMountainHead,
  assertTourismAdmin,
  isTourismAdmin,
  normalizeMountainNames,
};
