import {info} from "firebase-functions/logger";
import {randomInt} from "node:crypto";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

export const ROOM_CREATE_ATTEMPTS = 10;

/**
 * Picks a candidate room code; callers must check that it is unused.
 * @return {string} Six-digit code, also used as the document ID.
 */
export function randomRoomCode(): string {
  return randomInt(100000, 1000000).toString();
}

/**
 * Builds a new waiting room document.
 * @param {string} code Six-digit room code.
 * @param {string} hostUid Creator of the room.
 * @param {string | null} bombId Open-world bomb the room plays, if any.
 * @return {object} Firestore document data.
 */
export function newRoomData(code: string, hostUid: string,
  bombId: string | null = null) {
  const now = Timestamp.now();
  return {
    code,
    hostUid,
    guestUid: null,
    status: "waiting",
    bombId,
    createdAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + 60 * 60 * 1000),
  };
}

export const createRoom = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  for (let attempt = 0; attempt < ROOM_CREATE_ATTEMPTS; attempt++) {
    const code = randomRoomCode();
    const ref = db.collection("rooms").doc(code);
    const created = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);
      if (existing.exists) return false;
      transaction.create(ref, newRoomData(code, uid));
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
