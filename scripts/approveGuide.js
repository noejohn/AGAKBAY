// One-off admin script — NOT deployed as a Cloud Function.
// Run locally with a service-account key after the firestore.rules
// lockdown ships, since that lockdown makes `guideVerified` permanently
// un-settable from the client — this is the only path left to approve one.
//
// Setup: download a service-account key from Firebase Console → Project
// Settings → Service Accounts, save it locally (gitignored, never commit
// it), then:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/approveGuide.js <uid>
const admin = require("firebase-admin");

async function main() {
  const uid = process.argv[2];
  if (!uid) {
    console.error("Usage: node scripts/approveGuide.js <uid>");
    process.exit(1);
  }

  admin.initializeApp();

  const userRef = admin.firestore().collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    console.error(`No users/${uid} document found.`);
    process.exit(1);
  }
  const data = snap.data();

  await userRef.update({
    guideVerified: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await admin.auth().setCustomUserClaims(uid, {
    role: data.role || "tour_guide",
    accountType: data.accountType || "tour_guide",
    guideVerified: true,
  });

  console.log(`Approved ${uid} as a verified tour guide.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
