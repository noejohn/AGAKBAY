const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { MAIL_SECRETS, sendAdminResetCodeEmail } = require("./mailer");
const { enforceRateLimit } = require("./rateLimit");
const { getRedisClient } = require("./redisCache");

// "Forgot password?" for the Admin Dashboard: email -> 6-digit code ->
// new password. Admin accounts only. Codes are stored hashed, expire after
// CODE_TTL_MINUTES, and lock after MAX_ATTEMPTS wrong guesses. Neither step
// ever reveals whether an email belongs to an admin account.
const REGION = "asia-southeast1";
const CODE_TTL_MINUTES = 10;
const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_SECONDS = 60;
// Same answer for every email, admin or not, so this can't be used to
// discover who the admins are.
const GENERIC_SENT_MESSAGE =
  "If that email belongs to an admin account, a reset code has been sent.";
const INVALID_CODE_MESSAGE = "That code is invalid or has expired. Request a new one.";

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** Same rules as the mobile sign-up's password strength check. */
function passwordProblem(password) {
  if (typeof password !== "string" || password.length < 8) {
    return "Password must be at least 8 characters.";
  }
  if (password.length > 128) return "Password is too long.";
  if (!/[0-9]/.test(password)) return "Password must include a number.";
  if (!/[^A-Za-z0-9]/.test(password)) {
    return "Password must include a special character.";
  }
  return null;
}

function hashCode(code, uid) {
  return crypto.createHash("sha256").update(`${uid}:${code}`).digest("hex");
}

function codesMatch(code, uid, storedHash) {
  const actual = Buffer.from(hashCode(code, uid), "hex");
  const expected = Buffer.from(String(storedHash || ""), "hex");
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

// Keyed by a hash of the email, so the raw address isn't a document ID.
function resetDocRef(db, email) {
  const id = crypto.createHash("sha256").update(email).digest("hex");
  return db.collection("admin_password_resets").doc(id);
}

async function findAdminByEmail(auth, email) {
  try {
    const user = await auth.getUserByEmail(email);
    if (user.disabled || user.customClaims?.admin !== true) return null;
    return user;
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

const requestAdminPasswordReset = onCall(
  { region: REGION, timeoutSeconds: 30, memory: "256MiB", secrets: MAIL_SECRETS },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    if (!isValidEmail(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }
    await enforceRateLimit({
      redis: getRedisClient(),
      key: `ratelimit:adminPasswordReset:${email}`,
      maxCalls: 5,
      windowSeconds: 15 * 60,
    });

    const db = admin.firestore();
    const user = await findAdminByEmail(admin.auth(), email);
    if (!user) return { message: GENERIC_SENT_MESSAGE };

    const ref = resetDocRef(db, email);
    const existing = await ref.get();
    const lastSentMs = existing.data()?.sentAt?.toMillis?.() ?? 0;
    if (Date.now() - lastSentMs < RESEND_COOLDOWN_SECONDS * 1000) {
      // A code was just sent — don't spam their inbox, same answer.
      return { message: GENERIC_SENT_MESSAGE };
    }

    const code = String(crypto.randomInt(100000, 1000000));
    await ref.set({
      uid: user.uid,
      codeHash: hashCode(code, user.uid),
      attempts: 0,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + CODE_TTL_MINUTES * 60 * 1000,
      ),
    });
    try {
      await sendAdminResetCodeEmail({
        to: email,
        code,
        expiresInMinutes: CODE_TTL_MINUTES,
      });
    } catch (error) {
      await ref.delete().catch(() => {});
      if (error instanceof HttpsError) throw error;
      console.error("requestAdminPasswordReset: email failed", error?.message || error);
      throw new HttpsError("unavailable", "Could not send the reset code. Try again shortly.");
    }
    return { message: GENERIC_SENT_MESSAGE };
  },
);

const confirmAdminPasswordReset = onCall(
  { region: REGION, timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    const code = String(request.data?.code ?? "").trim();
    const newPassword = request.data?.newPassword;
    if (!isValidEmail(email) || !/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", INVALID_CODE_MESSAGE);
    }
    const problem = passwordProblem(newPassword);
    if (problem) throw new HttpsError("invalid-argument", problem);

    const db = admin.firestore();
    const auth = admin.auth();
    const ref = resetDocRef(db, email);

    // Checked and counted inside a transaction so parallel guesses can't
    // slip past the attempt limit.
    const uid = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return null;
      const data = snapshot.data();
      const expired = (data.expiresAt?.toMillis?.() ?? 0) < Date.now();
      if (expired || (data.attempts ?? 0) >= MAX_ATTEMPTS) {
        transaction.delete(ref);
        return null;
      }
      if (!codesMatch(code, data.uid, data.codeHash)) {
        transaction.update(ref, { attempts: (data.attempts ?? 0) + 1 });
        return null;
      }
      transaction.delete(ref);
      return data.uid;
    });
    if (!uid) throw new HttpsError("invalid-argument", INVALID_CODE_MESSAGE);

    // Re-check: the account could have been suspended or had admin access
    // removed after the code was sent.
    const user = await auth.getUser(uid);
    if (user.disabled || user.customClaims?.admin !== true) {
      throw new HttpsError("invalid-argument", INVALID_CODE_MESSAGE);
    }

    // Receiving the code proves they control this inbox, so the email also
    // counts as verified (the dashboard requires a verified email).
    await auth.updateUser(uid, { password: newPassword, emailVerified: true });
    // Signs out every existing session — someone who had the old password
    // is kicked out too.
    await auth.revokeRefreshTokens(uid);
    try {
      await db.collection("admin_actions").add({
        adminId: uid,
        adminEmail: email,
        action: "admin_password_reset",
        targetId: uid,
        targetEmail: email,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error("confirmAdminPasswordReset: audit log failed", error);
    }
    return { reset: true };
  },
);

module.exports = {
  requestAdminPasswordReset,
  confirmAdminPasswordReset,
  passwordProblem,
  hashCode,
  codesMatch,
  normalizeEmail,
  GENERIC_SENT_MESSAGE,
  INVALID_CODE_MESSAGE,
};
