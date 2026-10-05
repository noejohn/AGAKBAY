// One-off admin script — NOT deployed as a Cloud Function.
// Read-only Firestore browser for the terminal (same service-account
// setup as scripts/approveGuide.js). It never writes anything.
//
//   node scripts/readFirestore.js                      list top-level collections
//   node scripts/readFirestore.js users                list docs in a collection (first 20)
//   node scripts/readFirestore.js users 50             ...with a custom limit
//   node scripts/readFirestore.js users/<docId>        print one document + its subcollections
//   node scripts/readFirestore.js users/<docId>/trips  subcollections work the same way
const admin = require("firebase-admin");

async function main() {
  const path = process.argv[2];
  const limit = Number(process.argv[3]) || 20;

  admin.initializeApp();
  const db = admin.firestore();

  if (!path) {
    const collections = await db.listCollections();
    console.log("Top-level collections:");
    collections.forEach((c) => console.log(`  ${c.id}`));
    return;
  }

  const segments = path.split("/").filter(Boolean);
  if (segments.length % 2 === 1) {
    const snap = await db.collection(path).limit(limit).get();
    console.log(`${path}: showing ${snap.size} doc(s) (limit ${limit})\n`);
    snap.forEach((doc) => {
      console.log(`--- ${doc.id}`);
      console.log(JSON.stringify(doc.data(), null, 2));
    });
    return;
  }

  const ref = db.doc(path);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`No ${path} document found.`);
    process.exit(1);
  }
  console.log(JSON.stringify(snap.data(), null, 2));
  const subcollections = await ref.listCollections();
  if (subcollections.length) {
    console.log("\nSubcollections:");
    subcollections.forEach((c) => console.log(`  ${path}/${c.id}`));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
