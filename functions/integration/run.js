// Runs the API route tests inside the Firebase Emulator, then makes sure
// the Firestore emulator (a Java process) is really gone. On Windows,
// `firebase emulators:exec` often leaves it running on port 8080, so the
// NEXT run fails with "Could not start Firestore Emulator, port taken".
const { spawnSync, execSync } = require("node:child_process");

const FIRESTORE_PORT = 8080;

function stopLeftoverFirestoreEmulator() {
  if (process.platform !== "win32") return;
  try {
    const output = execSync(`netstat -ano -p tcp | findstr :${FIRESTORE_PORT}`, {
      encoding: "utf8",
    });
    const pids = new Set(
      output.split(/\r?\n/)
        .filter((line) => line.includes("LISTENING"))
        .map((line) => line.trim().split(/\s+/).pop())
        .filter(Boolean),
    );
    for (const pid of pids) {
      // Only ever stop a Java process — that's what the Firestore emulator
      // is; anything else on this port is left alone.
      const name = execSync(`tasklist /FI "PID eq ${pid}" /FO CSV /NH`, {
        encoding: "utf8",
      });
      if (name.toLowerCase().startsWith("\"java")) {
        execSync(`taskkill /PID ${pid} /F`, { stdio: "ignore" });
        console.log(`Stopped leftover Firestore emulator (PID ${pid}).`);
      }
    }
  } catch {
    // Nothing listening on the port — nothing to clean up.
  }
}

stopLeftoverFirestoreEmulator();
const result = spawnSync(
  "firebase",
  [
    "emulators:exec",
    "--only", "auth,firestore,functions",
    "--project", "tunga-app-2026",
    "\"npx jest --config integration/jest.config.js --runInBand\"",
  ],
  { stdio: "inherit", shell: true },
);
stopLeftoverFirestoreEmulator();
process.exit(result.status ?? 1);
