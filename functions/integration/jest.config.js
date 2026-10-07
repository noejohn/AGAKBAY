// API route tests — run through `npm run test:api`, which starts the
// Firebase Emulator (Auth, Firestore, Functions) first and stops it after.
module.exports = {
  rootDir: "..",
  testEnvironment: "node",
  testMatch: ["<rootDir>/integration/**/*.test.js"],
  // Each test calls real HTTP endpoints on the emulator.
  testTimeout: 30000,
};
