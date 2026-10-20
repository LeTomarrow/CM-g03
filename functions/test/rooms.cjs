// Run with the Firestore emulator; never run against a live project.
const assert = require("node:assert/strict");
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Start the Firestore emulator before running this test.");
}
const {createRoom, joinRoom, deleteRoom} = require("../lib/index.js");
const {getFirestore} = require("firebase-admin/firestore");
const request = (uid, data = {}) => ({auth: uid ? {uid} : undefined, data});
const rejects = (operation, code) => assert.rejects(operation, {code});

async function main() {
  await rejects(createRoom.run(request(null)), "unauthenticated");
  await rejects(joinRoom.run(request(null)), "unauthenticated");
  await rejects(deleteRoom.run(request(null)), "unauthenticated");
  await rejects(joinRoom.run(request("guest", {code: "../bad"})),
    "invalid-argument");
  const room = await createRoom.run(request("host"));
  const ref = getFirestore().collection("rooms").doc(room.roomId);
  try {
    assert.match(room.code, /^\d{6}$/);
    const attempts = await Promise.allSettled([
      joinRoom.run(request("guest-a", {code: room.code})),
      joinRoom.run(request("guest-b", {code: room.code})),
    ]);
    assert.equal(attempts.filter((r) => r.status === "fulfilled").length, 1);
    const rejected = attempts.find((r) => r.status === "rejected");
    assert.equal(rejected.reason.code, "failed-precondition");
    const state = (await ref.get()).data();
    assert.equal(state.status, "ready");
    assert.equal(state.hostUid, "host");
    await joinRoom.run(request(state.guestUid, {code: room.code}));
    await rejects(deleteRoom.run(request(state.guestUid, {
      roomId: room.roomId,
    })), "permission-denied");
    await ref.update({expiresAt: require("firebase-admin/firestore")
      .Timestamp.fromMillis(0)});
    await rejects(joinRoom.run(request("other", {code: room.code})),
      "failed-precondition");
    await deleteRoom.run(request("host", {roomId: room.roomId}));
    assert.equal((await ref.get()).exists, false);
    await deleteRoom.run(request("host", {roomId: room.roomId}));
    await rejects(joinRoom.run(request("guest", {code: room.code})),
      "not-found");
    console.log("Room integration checks passed.");
  } finally {
    await ref.delete();
    await getFirestore().terminate();
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
