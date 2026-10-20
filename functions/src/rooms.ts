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
        hostRole: "defuser",
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
    if (room.status === "playing") {
      throw new HttpsError("failed-precondition", "Game already started.");
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

// Keep the document so both listeners receive the start and final roles.
// A playing room is closed to all join requests, including existing members.
export const startGame = onCall({region: "europe-west1"}, async (request) => {
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
    const room = snapshot.data();
    if (!room) throw new HttpsError("not-found", "Room not found.");
    if (room.hostUid !== uid) {
      throw new HttpsError("permission-denied", "Only the host can start.");
    }
    // A retried start must not change the original start time.
    if (room.status === "playing") return;
    if (room.expiresAt.toMillis() <= Date.now() ||
        room.status !== "ready" || !room.guestUid) {
      throw new HttpsError("failed-precondition", "Room is not ready.");
    }
    transaction.update(ref, {
      status: "playing",
      startedAt: Timestamp.now(),
    });
  });
  info("Game started; room closed to joins", {operation: "startGame"});
  return {started: true};
});

export const switchRoles = onCall({region: "europe-west1"}, async (request) => {
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
    const room = snapshot.data();
    if (!room) throw new HttpsError("not-found", "Room not found.");
    if (room.hostUid !== uid && room.guestUid !== uid) {
      throw new HttpsError("permission-denied", "Only members can swap roles.");
    }
    if (room.expiresAt.toMillis() <= Date.now() ||
        !["waiting", "ready"].includes(room.status)) {
      throw new HttpsError("failed-precondition", "Room is no longer open.");
    }
    transaction.update(ref, {
      hostRole: room.hostRole === "manual" ? "defuser" : "manual",
    });
  });
  return {switched: true};
});
