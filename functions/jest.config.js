// Default `npm test`: fast unit tests only. The API route tests under
// integration/ need the Firebase Emulator running, so they have their own
// config and script (`npm run test:api`).
module.exports = {
  testEnvironment: "node",
  testPathIgnorePatterns: ["/node_modules/", "/integration/"],
};
