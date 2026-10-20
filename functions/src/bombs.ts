import {info} from "firebase-functions/logger";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {distanceMeters, encodeGeohash, parseCoordinates} from "./geo";
import {newRoomData, randomRoomCode, ROOM_CREATE_ATTEMPTS} from "./rooms";

export const BOMB_LIFETIME_MS = 24 * 60 * 60 * 1000;
export const CLAIM_LEASE_MS = 10 * 60 * 1000;
export const CLAIM_RADIUS_METERS = 50;
export const MAX_ACTIVE_BOMBS = 3;

const OUTCOMES = ["defused", "exploded", "abandoned"];

/**
 * Rejects unauthenticated calls.
 * @param {{uid: string} | undefined} auth Callable auth context.
 * @return {string} Caller UID.
 */
function requireUid(auth: {uid: string} | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  return auth.uid;
}

/**
 * Validates an auto-generated Firestore document ID.
 * @param {unknown} bombId Candidate ID from the client.
 * @return {string} The same ID.
 */
function requireBombId(bombId: unknown): string {
  if (typeof bombId !== "string" || !/^[A-Za-z0-9]{20}$/.test(bombId)) {
    throw new HttpsError("invalid-argument", "Invalid bomb ID.");
  }
  return bombId;
}

export const plantBomb = onCall({region: "europe-west1"}, async (request) => {
  const uid = requireUid(request.auth);
  const point = parseCoordinates(request.data);
  if (!point) throw new HttpsError("invalid-argument", "Invalid location.");
  const db = getFirestore();
  const bombs = db.collection("bombs");
  const ref = bombs.doc();
  await db.runTransaction(async (transaction) => {
    const now = Timestamp.now();
    const planted = await transaction.get(bombs
      .where("plantedBy", "==", uid)
      .where("active", "==", true));
    const live = planted.docs.filter((doc) =>
      doc.get("expiresAt").toMillis() > now.toMillis());
    if (live.length >= MAX_ACTIVE_BOMBS) {
      throw new HttpsError("resource-exhausted", "Too many active bombs.");
    }
    transaction.create(ref, {
      lat: point.lat,
      lng: point.lng,
      geohash: encodeGeohash(point),
      plantedBy: uid,
      status: "armed",
      active: true,
      claimedBy: null,
      roomId: null,
      claimExpiresAt: null,
      createdAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + BOMB_LIFETIME_MS),
    });
  });
  info("Bomb planted", {operation: "plantBomb"});
  return {bombId: ref.id};
});

export const claimBomb = onCall({region: "europe-west1"}, async (request) => {
  const uid = requireUid(request.auth);
  const bombId = requireBombId(request.data?.bombId);
  const point = parseCoordinates(request.data);
  if (!point) throw new HttpsError("invalid-argument", "Invalid location.");
  const db = getFirestore();
  const bombRef = db.collection("bombs").doc(bombId);
  for (let attempt = 0; attempt < ROOM_CREATE_ATTEMPTS; attempt++) {
    const code = randomRoomCode();
    const roomRef = db.collection("rooms").doc(code);
    const roomId = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(bombRef);
      const bomb = snapshot.data();
      if (!bomb) throw new HttpsError("not-found", "Bomb not found.");
      const now = Date.now();
      if (!bomb.active || bomb.expiresAt.toMillis() <= now) {
        throw new HttpsError("failed-precondition", "Bomb is gone.");
      }
      if (bomb.plantedBy === uid) {
        throw new HttpsError("permission-denied", "You planted this bomb.");
      }
      const leased = bomb.status === "claimed" &&
        bomb.claimExpiresAt.toMillis() > now;
      // Claiming again with the same identity returns the existing room.
      if (leased && bomb.claimedBy === uid) return bomb.roomId as string;
      if (leased) {
        throw new HttpsError("failed-precondition", "Bomb is being defused.");
      }
      const distance = distanceMeters(point, {lat: bomb.lat, lng: bomb.lng});
      if (distance > CLAIM_RADIUS_METERS) {
        throw new HttpsError("failed-precondition", "Too far from the bomb.");
      }
      const room = await transaction.get(roomRef);
      if (room.exists) return null;
      transaction.create(roomRef, newRoomData(code, uid, bombId));
      transaction.update(bombRef, {
        status: "claimed",
        claimedBy: uid,
        roomId: code,
        claimExpiresAt: Timestamp.fromMillis(now + CLAIM_LEASE_MS),
      });
      return code;
    });
    if (roomId) {
      info("Bomb claimed", {operation: "claimBomb"});
      return {roomId, code: roomId};
    }
  }
  throw new HttpsError("resource-exhausted", "Try claiming the bomb again.");
});

export const resolveBomb = onCall({region: "europe-west1"}, async (request) => {
  const uid = requireUid(request.auth);
  const bombId = requireBombId(request.data?.bombId);
  const outcome = request.data?.outcome;
  if (!OUTCOMES.includes(outcome)) {
    throw new HttpsError("invalid-argument", "Invalid outcome.");
  }
  const ref = getFirestore().collection("bombs").doc(bombId);
  await getFirestore().runTransaction(async (transaction) => {
    const bomb = (await transaction.get(ref)).data();
    if (!bomb) throw new HttpsError("not-found", "Bomb not found.");
    // An expired lease still counts until another pair claims the bomb.
    if (bomb.status !== "claimed" || bomb.claimedBy !== uid) {
      throw new HttpsError("permission-denied", "You are not defusing it.");
    }
    if (outcome === "abandoned") {
      transaction.update(ref, {
        status: "armed",
        claimedBy: null,
        roomId: null,
        claimExpiresAt: null,
      });
      return;
    }
    transaction.update(ref, {
      status: outcome,
      active: false,
      claimExpiresAt: null,
      resolvedBy: uid,
      resolvedAt: Timestamp.now(),
    });
  });
  info("Bomb resolved", {operation: "resolveBomb", outcome});
  return {status: outcome === "abandoned" ? "armed" : outcome};
});
