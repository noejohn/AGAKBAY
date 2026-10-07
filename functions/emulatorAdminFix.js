// Works around a Firebase Functions EMULATOR bug — a no-op in production.
//
// The emulator wraps the firebase-admin module in a Proxy and re-binds
// `admin.firestore` (an arrow function in firebase-admin v12) on every
// access. Binding a function drops its static members, so inside the
// emulator `admin.firestore.FieldValue` / `.Timestamp` are undefined and
// every function using them crashes — even though the exact same code works
// when deployed. Only `npm run test:api` / `firebase emulators:start` hit
// this.
//
// Fix: give `admin.firestore` back a regular (non-arrow) function that still
// calls the original and carries FieldValue, Timestamp, etc. The emulator's
// Proxy returns regular functions as-is instead of re-binding them.
const admin = require("firebase-admin");

if (process.env.FUNCTIONS_EMULATOR === "true" && !admin.firestore.FieldValue) {
  const firestoreTypes = require("firebase-admin/firestore");
  const original = admin.firestore;
  const firestore = function firestore(app) {
    return original(app);
  };
  Object.assign(firestore, firestoreTypes);
  Object.defineProperty(admin, "firestore", {
    value: firestore,
    configurable: true,
    writable: true,
  });
}
