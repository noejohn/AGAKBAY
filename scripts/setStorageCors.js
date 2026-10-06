// One-off admin script — NOT deployed as a Cloud Function.
// Allows the admin web dashboard's origin(s) to load images directly from
// Firebase Storage (Image.network in lib/admin/admin_dashboard_shell.dart)
// — government ID and certificate photos were failing to load there with
// no error shown, because Cloud Storage buckets have no CORS configuration
// by default, so the browser blocks a cross-origin admin.tunga-app-2026.
// web.app -> firebasestorage.googleapis.com read even though the request
// itself (with its embedded download token) is perfectly authorized.
//
// This does NOT touch Storage Security Rules or who can generate a
// download URL — it only tells the browser which origins are allowed to
// read the response once they already have a valid URL, same as sharing
// the raw link directly already allows.
//
// Run locally with a service-account key (same setup as
// scripts/grantAdminRole.js):
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/setStorageCors.js
const admin = require("firebase-admin");

// Add any other origin the admin dashboard is actually served from (a
// custom domain, a different local dev port, etc.).
const ALLOWED_ORIGINS = [
  "https://tunga-app-2026.web.app",
  "https://tunga-app-2026.firebaseapp.com",
  "http://localhost:3000",
  "http://localhost:5000",
];

// admin.initializeApp() alone doesn't know which bucket to use for a bare
// service-account credential (only inside Cloud Functions' own runtime is
// that inferred automatically) — has to be named explicitly here.
const STORAGE_BUCKET = "tunga-app-2026.firebasestorage.app";

async function main() {
  admin.initializeApp({ storageBucket: STORAGE_BUCKET });
  const bucket = admin.storage().bucket();

  await bucket.setCorsConfiguration([
    {
      origin: ALLOWED_ORIGINS,
      method: ["GET", "HEAD"],
      responseHeader: ["Content-Type"],
      maxAgeSeconds: 3600,
    },
  ]);

  console.log(`CORS configured on gs://${bucket.name} for:`);
  for (const origin of ALLOWED_ORIGINS) {
    console.log(`  - ${origin}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
