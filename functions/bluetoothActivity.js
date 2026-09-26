const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

exports.updateParticipantBluetoothStatus = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");

    const roomId = request.data?.roomId;
    const deviceId = request.data?.deviceId;
    const deviceName = typeof request.data?.deviceName === "string"
      ? request.data.deviceName.trim()
      : "";
    const deviceStatus = request.data?.deviceStatus;
    if (typeof roomId !== "string" || !roomId || roomId.length > 128 ||
        typeof deviceId !== "string" || !deviceId || deviceId.length > 200 ||
        !["connected", "disconnected"].includes(deviceStatus) ||
        deviceName.length > 80) {
      throw new HttpsError("invalid-argument", "Invalid room or device details.");
    }

    const db = admin.firestore();
    const participantRef = db.collection("hike_rooms").doc(roomId)
      .collection("participants").doc(uid);
    const [roomSnap, participantSnap] = await Promise.all([
      db.collection("hike_rooms").doc(roomId).get(),
      participantRef.get(),
    ]);
    if (!roomSnap.exists || !participantSnap.exists ||
        (deviceStatus === "connected" && roomSnap.data()?.status !== "active") ||
        (participantSnap.data()?.membershipStatus || "active") !== "active") {
      throw new HttpsError("failed-precondition", "An active hike room membership is required.");
    }

    const previous = participantSnap.data() || {};
    const nextName = deviceName || previous.deviceName || "Heltec device";
    const changed = previous.deviceId !== deviceId ||
      previous.deviceName !== nextName || previous.deviceStatus !== deviceStatus;
    if (!changed) return { recorded: false };

    const deviceKey = Buffer.from(deviceId, "utf8").toString("base64url");
    const deviceRef = db.collection("bluetooth_devices").doc(deviceKey);
    const activityRef = deviceRef.collection("activity").doc();
    const deviceSnap = await deviceRef.get();
    const displayName = deviceSnap.data()?.displayName || nextName;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const statusChanged = previous.deviceStatus !== deviceStatus || previous.deviceId !== deviceId;
    const eventType = statusChanged ? deviceStatus : "device_changed";
    const batch = db.batch();
    const participantUpdate = {
      deviceId,
      deviceName: nextName,
      displayName,
      deviceStatus,
      updatedAt: now,
    };
    if (deviceStatus === "connected") participantUpdate.lastBluetoothAt = now;
    batch.update(participantRef, participantUpdate);
    batch.set(deviceRef, {
      deviceId,
      deviceName: nextName,
      lastStatus: deviceStatus,
      lastRoomId: roomId,
      lastRoomCode: roomSnap.data()?.roomCode || roomId,
      lastParticipantId: uid,
      lastParticipantName: previous.name || "Hiker",
      lastActivityAt: now,
      updatedAt: now,
    }, { merge: true });
    batch.set(activityRef, {
      deviceId,
      deviceName: nextName,
      eventType,
      deviceStatus,
      roomId,
      roomCode: roomSnap.data()?.roomCode || roomId,
      participantId: uid,
      participantName: previous.name || "Hiker",
      occurredAt: now,
    });
    await batch.commit();
    return { recorded: true, eventId: activityRef.id };
  },
);

exports.renameBluetoothDevice = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }
    const deviceId = request.data?.deviceId;
    const displayName = typeof request.data?.displayName === "string"
      ? request.data.displayName.trim()
      : "";
    if (typeof deviceId !== "string" || !deviceId ||
        !displayName || displayName.length > 80) {
      throw new HttpsError("invalid-argument", "A device ID and name are required.");
    }

    const db = admin.firestore();
    const deviceKey = Buffer.from(deviceId, "utf8").toString("base64url");
    const deviceRef = db.collection("bluetooth_devices").doc(deviceKey);
    const deviceSnap = await deviceRef.get();
    if (!deviceSnap.exists) {
      throw new HttpsError("not-found", "Bluetooth device not found.");
    }
    const previousName = deviceSnap.data()?.displayName || deviceSnap.data()?.deviceName;
    await deviceRef.update({
      displayName,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection("admin_actions").add({
      adminId: request.auth.uid,
      action: "rename_bluetooth_device",
      targetId: deviceKey,
      previousStatus: previousName || null,
      newStatus: displayName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { displayName };
  },
);
