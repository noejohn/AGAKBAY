// One-off admin script — NOT deployed as a Cloud Function.
// Creates (if needed) and grants the admin role to an account by email.
// Run locally with a service-account key (same setup as
// scripts/approveGuide.js), since firestore.rules never lets a client set
// role/accountType to "admin" — this script (via the Admin SDK, which
// bypasses rules) is the only path.
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/grantAdminRole.js <email> [password]
//
// [password] is only needed the first time, to create the Firebase Auth
// account for a brand-new admin (min 6 characters — Firebase's own
// requirement). If the account already exists, [password] is ignored;
// this script never changes an existing password.
const admin = require("firebase-admin");

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];
  if (!email) {
    console.error("Usage: node scripts/grantAdminRole.js <johnnoerubio@gmail.com> [admin123]");
    process.exit(1);
  }

  admin.initializeApp();

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      throw err;
    }
    if (!password) {
      console.error(`No account exists for ${email} yet — pass a password to create one.`);
      process.exit(1);
    }
    user = await admin.auth().createUser({ email, password, emailVerified: true });
  }

  await admin.firestore().collection("users").doc(user.uid).set(
    {
      role: "admin",
      accountType: "admin",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await admin.auth().setCustomUserClaims(user.uid, {
    role: "admin",
    accountType: "admin",
    guideVerified: null,
    admin: true,
  });

  console.log(`Granted admin to ${email} (uid: ${user.uid}).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
