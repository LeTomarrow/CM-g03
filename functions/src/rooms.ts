import {info} from "firebase-functions/logger";
import {randomInt} from "node:crypto";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

export const createRoom = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = randomInt(100000, 1000000).toString();
    const ref = db.collection("rooms").doc(code);
    const created = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);
      if (existing.exists) return false;
      const now = Timestamp.now();
      transaction.create(ref, {
        code,
        hostUid: uid,
        guestUid: null,
        status: "waiting",
        createdAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + 60 * 60 * 1000),
      });
      return true;
    });
    if (created) {
      info("Room created", {operation: "createRoom"});
      return {roomId: code, code};
    }
  }
  throw new HttpsError("resource-exhausted", "Try creating a room again.");
});

export const joinRoom = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = request.auth.uid;
  const code = request.data?.code;
  if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Enter a six-digit code.");
  }
  const ref = getFirestore().collection("rooms").doc(code);
  await getFirestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const room = snapshot.data();
    if (!room) throw new HttpsError("not-found", "Room not found.");
    if (room.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "Room expired.");
    }
    // Joining again with the same identity is safe.
    if (room.hostUid === uid || room.guestUid === uid) return;
    if (room.guestUid !== null || room.status !== "waiting") {
      throw new HttpsError("failed-precondition", "Room is full.");
    }
    transaction.update(ref, {guestUid: uid, status: "ready"});
  });
  info("Room joined", {operation: "joinRoom"});
  return {roomId: code, code};
});

export const deleteRoom = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = request.auth.uid;
  const roomId = request.data?.roomId;
  if (typeof roomId !== "string" || !/^\d{6}$/.test(roomId)) {
    throw new HttpsError("invalid-argument", "Invalid room ID.");
  }
  const ref = getFirestore().collection("rooms").doc(roomId);
  await getFirestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    if (snapshot.get("hostUid") !== uid) {
      throw new HttpsError("permission-denied", "Only the host can delete it.");
    }
    transaction.delete(ref);
  });
  info("Room deletion completed", {operation: "deleteRoom"});
  return {deleted: true};
});
