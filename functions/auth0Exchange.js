const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { createRemoteJWKSet, jwtVerify } = require("jose");
const { getRedisClient } = require("./redisCache");
const { enforceRateLimit } = require("./rateLimit");

// AUTH0_DOMAIN / AUTH0_CLIENT_ID are not secrets (they're public per
// OAuth/OIDC for a native/PKCE client) — set them as plain env vars via a
// functions/.env file (gitignored, not committed) or `firebase functions:config`,
// e.g.:
//   AUTH0_DOMAIN=your-tenant.us.auth0.com
//   AUTH0_CLIENT_ID=your_auth0_client_id
let _jwks = null;
function getJwks() {
  if (_jwks) {
    return _jwks;
  }
  const domain = process.env.AUTH0_DOMAIN;
  if (!domain) {
    throw new HttpsError(
      "failed-precondition",
      "Auth0 is not configured. Set the AUTH0_DOMAIN env var.",
    );
  }
  _jwks = createRemoteJWKSet(new URL(`https://${domain}/.well-known/jwks.json`));
  return _jwks;
}

async function verifyAuth0IdToken(idToken) {
  const domain = process.env.AUTH0_DOMAIN;
  const clientId = process.env.AUTH0_CLIENT_ID;
  if (!domain || !clientId) {
    throw new HttpsError(
      "failed-precondition",
      "Auth0 is not configured. Set the AUTH0_DOMAIN and AUTH0_CLIENT_ID env vars.",
    );
  }
  const { payload } = await jwtVerify(idToken, getJwks(), {
    issuer: `https://${domain}/`,
    audience: clientId,
  });
  return payload;
}
exports.verifyAuth0IdToken = verifyAuth0IdToken;

// Reuses the existing Firebase uid when this email already has a Firebase
// Auth account (covers both password-migrated and Google-signed-in users —
// matched by email, not Auth0's `sub`, since a user's Auth0 identity is
// brand new regardless of which method they originally signed up with on
// the Firebase side). Only creates a new Firebase user when no match exists.
async function resolveFirebaseUid({ email, displayName }) {
  try {
    const existing = await admin.auth().getUserByEmail(email);
    return { uid: existing.uid, isNew: false };
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      throw err;
    }
    const created = await admin.auth().createUser({
      email,
      emailVerified: true,
      displayName,
    });
    return { uid: created.uid, isNew: true };
  }
}
exports.resolveFirebaseUid = resolveFirebaseUid;

// Mirrors the signup doc shape from AuthDatabaseService.signUpUser /
// signInWithGoogle (lib/services/auth_database_service.dart) for a
// brand-new Auth0-only account. Defaults to 'hiker' since there's no
// hiker/guide question during the Google/Auth0 redirect itself — the app
// asks that separately right after sign-in via setInitialAccountType,
// gated by accountTypeConfirmed so it can only ever run once per account.
async function bootstrapNewUserDoc({ db, uid, email, displayName }) {
  const emailLocalPart = email.split("@")[0];
  const fullName = displayName?.trim() || emailLocalPart;
  const usersRef = db.collection("users").doc(uid);
  await usersRef.set({
    uid,
    fullName,
    username: emailLocalPart,
    email,
    accountType: "hiker",
    role: "hiker",
    guideVerified: null,
    accountTypeConfirmed: false,
    emailVerified: true,
    verificationMethod: "auth0",
    onboardingComplete: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await usersRef.collection("public").doc("profile").set({ fullName });
}
exports.bootstrapNewUserDoc = bootstrapNewUserDoc;

exports.exchangeAuth0Token = onCall(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: ["UPSTASH_REDIS_REST_URL", "UPSTASH_REDIS_REST_TOKEN"],
  },
  async (request) => {
    const idToken = request.data?.idToken;
    if (typeof idToken !== "string" || !idToken) {
      throw new HttpsError("invalid-argument", "Missing Auth0 idToken.");
    }

    let payload;
    try {
      payload = await verifyAuth0IdToken(idToken);
    } catch (err) {
      if (err instanceof HttpsError) {
        throw err;
      }
      throw new HttpsError("unauthenticated", "Invalid or expired Auth0 token.");
    }

    const email = payload.email;
    if (!email || payload.email_verified !== true) {
      throw new HttpsError("failed-precondition", "Auth0 account email is not verified.");
    }

    // Keyed by email, not uid — this runs before a Firebase uid is resolved,
    // and email is the actual identity being exchanged repeatedly if abused.
    await enforceRateLimit({
      redis: getRedisClient(),
      key: `ratelimit:exchangeAuth0Token:${email}`,
      maxCalls: 10,
      windowSeconds: 60,
    });

    const db = admin.firestore();
    const { uid, isNew } = await resolveFirebaseUid({ email, displayName: payload.name });

    let role = "hiker";
    let accountType = "hiker";
    let guideVerified = null;
    if (isNew) {
      await bootstrapNewUserDoc({ db, uid, email, displayName: payload.name });
    } else {
      const snap = await db.collection("users").doc(uid).get();
      const data = snap.data() || {};
      role = data.role || "hiker";
      accountType = data.accountType || "hiker";
      guideVerified = data.guideVerified ?? null;
    }

    // setCustomUserClaims must happen before createCustomToken: it's what
    // persists the role across future silent token refreshes. A custom
    // claim passed only as createCustomToken's additionalClaims would
    // otherwise silently vanish after the token's first refresh (~1 hour).
    // `admin` is a boolean mirror of role === "admin" so Firestore rules
    // and Cloud Functions can gate on `request.auth.token.admin` directly
    // instead of a string comparison — the role is only ever granted via
    // scripts/grantAdminRole.js (Admin SDK), never through a client write.
    await admin.auth().setCustomUserClaims(uid, {
      role,
      accountType,
      guideVerified,
      admin: role === "admin",
    });
    const firebaseCustomToken = await admin.auth().createCustomToken(uid);

    return { firebaseCustomToken, isNewUser: isNew };
  },
);

