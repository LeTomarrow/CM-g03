// Run with the Firestore emulator; never run against a live project.
const assert = require("node:assert/strict");
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Start the Firestore emulator before running this test.");
}
const {plantBomb, claimBomb, resolveBomb} = require("../lib/index.js");
const {encodeGeohash, distanceMeters} = require("../lib/geo.js");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const request = (uid, data = {}) => ({auth: uid ? {uid} : undefined, data});
const rejects = (operation, code) => assert.rejects(operation, {code});

// Faculty of Sciences, Lisbon; NEAR is ~11 m away, FAR is ~1.1 km away.
const HERE = {lat: 38.7569, lng: -9.1569};
const NEAR = {lat: 38.7570, lng: -9.1569};
const FAR = {lat: 38.7669, lng: -9.1569};

async function main() {
  assert.equal(encodeGeohash({lat: 57.64911, lng: 10.40744}, 11),
    "u4pruydqqvj");
  assert.ok(Math.abs(distanceMeters(HERE, FAR) - 1112) < 5);

  await rejects(plantBomb.run(request(null, HERE)), "unauthenticated");
  await rejects(plantBomb.run(request("planter", {lat: 91, lng: 0})),
    "invalid-argument");
  await rejects(claimBomb.run(request("op", {bombId: "../x", ...HERE})),
    "invalid-argument");

  const db = getFirestore();
  const created = [];
  try {
    for (let i = 0; i < 3; i++) {
      created.push((await plantBomb.run(request("planter", HERE))).bombId);
    }
    await rejects(plantBomb.run(request("planter", HERE)),
      "resource-exhausted");
    const [bombId, otherId] = created;
    const ref = db.collection("bombs").doc(bombId);
    const bomb = (await ref.get()).data();
    assert.equal(bomb.status, "armed");
    assert.equal(bomb.active, true);
    assert.equal(bomb.geohash, encodeGeohash(HERE));

    await rejects(claimBomb.run(request("planter", {bombId, ...HERE})),
      "permission-denied");
    await rejects(claimBomb.run(request("op-a", {bombId, ...FAR})),
      "failed-precondition");

    const attempts = await Promise.allSettled([
      claimBomb.run(request("op-a", {bombId, ...NEAR})),
      claimBomb.run(request("op-b", {bombId, ...NEAR})),
    ]);
    const won = attempts.filter((r) => r.status === "fulfilled");
    assert.equal(won.length, 1);
    const rejected = attempts.find((r) => r.status === "rejected");
    assert.equal(rejected.reason.code, "failed-precondition");
    const claim = won[0].value;
    created.push(`room:${claim.roomId}`);
    const winner = (await ref.get()).get("claimedBy");
    const loser = winner === "op-a" ? "op-b" : "op-a";

    const room = (await db.collection("rooms").doc(claim.roomId).get()).data();
    assert.equal(room.hostUid, winner);
    assert.equal(room.bombId, bombId);
    assert.equal(room.status, "waiting");
    assert.deepEqual(
      await claimBomb.run(request(winner, {bombId, ...NEAR})), claim);

    await rejects(resolveBomb.run(request(winner, {bombId, outcome: "x"})),
      "invalid-argument");
    await rejects(resolveBomb.run(request(loser, {
      bombId, outcome: "defused",
    })), "permission-denied");

    await resolveBomb.run(request(winner, {bombId, outcome: "abandoned"}));
    assert.equal((await ref.get()).get("status"), "armed");

    const second = await claimBomb.run(request(loser, {bombId, ...NEAR}));
    created.push(`room:${second.roomId}`);
    await ref.update({claimExpiresAt: Timestamp.fromMillis(0)});
    const third = await claimBomb.run(request(winner, {bombId, ...NEAR}));
    created.push(`room:${third.roomId}`);
    await rejects(resolveBomb.run(request(loser, {
      bombId, outcome: "defused",
    })), "permission-denied");

    assert.deepEqual(
      await resolveBomb.run(request(winner, {bombId, outcome: "defused"})),
      {status: "defused"});
    const resolved = (await ref.get()).data();
    assert.equal(resolved.active, false);
    assert.equal(resolved.resolvedBy, winner);
    await rejects(claimBomb.run(request(loser, {bombId, ...NEAR})),
      "failed-precondition");

    await db.collection("bombs").doc(otherId).update({
      expiresAt: Timestamp.fromMillis(0),
    });
    await rejects(claimBomb.run(request("op-a", {bombId: otherId, ...NEAR})),
      "failed-precondition");
    // Expired bombs no longer count towards the planting limit.
    created.push((await plantBomb.run(request("planter", HERE))).bombId);

    const nearby = await db.collection("bombs")
      .where("active", "==", true)
      .where("geohash", ">=", encodeGeohash(HERE, 5))
      .where("geohash", "<", `${encodeGeohash(HERE, 5)}~`)
      .get();
    assert.ok(nearby.docs.every((doc) => doc.id !== bombId));
    assert.ok(nearby.docs.some((doc) => doc.id === created[2]));
    console.log("Bomb integration checks passed.");
  } finally {
    await Promise.all(created.map((id) => id.startsWith("room:") ?
      db.collection("rooms").doc(id.slice(5)).delete() :
      db.collection("bombs").doc(id).delete()));
    await db.terminate();
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
