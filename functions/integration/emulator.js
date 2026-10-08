// Helpers for API route tests against the local Firebase Emulator.
// Nothing here can touch the live project: the Admin SDK is pointed at the
// emulator through FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST,
// which `firebase emulators:exec` sets before the tests start.
const admin = require("firebase-admin");

const PROJECT_ID = "tunga-app-2026";
const REGION = "us-central1";
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error(
    "Emulator not detected — run these through `npm run test:api`, never " +
      "directly, so they can't hit the live database.",
  );
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

/** Wipes every document and every account in the emulator. */
async function resetEmulator() {
  await fetch(
    `http://${FIRESTORE_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  await fetch(`http://${AUTH_HOST}/emulator/v1/projects/${PROJECT_ID}/accounts`, {
    method: "DELETE",
  });
}

/** Creates an emulator account and returns { uid, idToken } for it. */
async function createSignedInUser(email, displayName, customClaims) {
  const password = "test-password-123";
  const user = await admin.auth().createUser({ email, password, displayName });
  if (customClaims) {
    await admin.auth().setCustomUserClaims(user.uid, customClaims);
  }
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  return { uid: user.uid, idToken: body.idToken };
}

/**
 * Calls a callable Cloud Function exactly the way the Flutter app does:
 * an HTTP POST with { data } and the user's ID token. Returns the HTTP
 * status plus the parsed body ({ result } on success, { error } on failure).
 */
async function callApi(name, data, idToken) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/${name}`,
    { method: "POST", headers, body: JSON.stringify({ data }) },
  );
  return { status: response.status, body: await response.json() };
}

module.exports = {
  admin,
  db,
  resetEmulator,
  createSignedInUser,
  callApi,
};
