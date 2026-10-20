// Run with the Firestore emulator; never run against a live project.
// Each helper mirrors a write made by lib/services/*_service.dart.
const {readFileSync} = require("node:fs");
const path = require("node:path");
const {after, before, beforeEach, describe, test} = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const firebase = require("firebase/compat/app").default;
require("firebase/compat/firestore");

const {FieldValue, Timestamp} = firebase.firestore;
const LONG_AGO = Timestamp.fromMillis(0);
const GEOHASH = "eycs0p8eu";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();
const admin = (action) =>
  env.withSecurityRulesDisabled((context) => action(context.firestore()));

const roomData = (code, hostUid, bombId = null) => ({
  code,
  hostUid,
  guestUid: null,
  status: "waiting",
  bombId,
  createdAt: FieldValue.serverTimestamp(),
});

const bombData = (uid, overrides = {}) => ({
  lat: 38.7569,
  lng: -9.1569,
  geohash: GEOHASH,
  plantedBy: uid,
  status: "armed",
  active: true,
  claimedBy: null,
  roomId: null,
  claimedAt: null,
  createdAt: FieldValue.serverTimestamp(),
  ...overrides,
});

const createRoom = (uid, code, data = roomData(code, uid)) =>
  db(uid).collection("rooms").doc(code).set(data);

const joinRoom = (uid, code, extra = {}) => db(uid).collection("rooms")
  .doc(code).update({guestUid: uid, status: "ready", ...extra});

const plant = (uid, slot = 0, data = bombData(uid)) =>
  db(uid).collection("bombs").doc(`${uid}_${slot}`).set(data);

const claim = (uid, bombId, code, {withRoom = true, roomBombId} = {}) => {
  const firestore = db(uid);
  return firestore.runTransaction(async (transaction) => {
    const bombRef = firestore.collection("bombs").doc(bombId);
    await transaction.get(bombRef);
    if (withRoom) {
      transaction.set(firestore.collection("rooms").doc(code),
        roomData(code, uid, roomBombId ?? bombId));
    }
    transaction.update(bombRef, {
      status: "claimed",
      claimedBy: uid,
      roomId: code,
      claimedAt: FieldValue.serverTimestamp(),
    });
  });
};

const abandon = (uid, bombId) => db(uid).collection("bombs").doc(bombId)
  .update({status: "armed", claimedBy: null, roomId: null, claimedAt: null});

const resolve = (uid, bombId, status, extra = {}) => db(uid)
  .collection("bombs").doc(bombId).update({
    status,
    active: false,
    resolvedBy: uid,
    resolvedAt: FieldValue.serverTimestamp(),
    ...extra,
  });

const age = (collection, id, fields) =>
  admin((firestore) => firestore.collection(collection).doc(id).update(fields));

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Start the Firestore emulator before running this test.");
  }
  env = await initializeTestEnvironment({
    projectId: "demo-wdyp-rules",
    firestore: {
      rules: readFileSync(
        path.join(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
});

beforeEach(() => env.clearFirestore());
after(() => env.cleanup());

describe("rooms", () => {
  test("only signed-in players create well-formed rooms", async () => {
    await assertFails(anonymous().collection("rooms").doc("123456")
      .set(roomData("123456", "host")));
    await assertFails(createRoom("host", "12345"));
    await assertFails(createRoom("host", "123456",
      roomData("123456", "someone-else")));
    await assertFails(createRoom("host", "123456",
      {...roomData("123456", "host"), status: "ready"}));
    await assertFails(createRoom("host", "123456",
      {...roomData("123456", "host"), createdAt: Timestamp.now()}));
    await assertFails(createRoom("host", "123456",
      {...roomData("123456", "host"), extra: true}));
    await assertSucceeds(createRoom("host", "123456"));
    // An existing code cannot be taken over.
    await assertFails(createRoom("thief", "123456"));
  });

  test("rooms are readable by code but not listable", async () => {
    await createRoom("host", "123456");
    await assertSucceeds(db("stranger").collection("rooms").doc("123456")
      .get());
    await assertFails(anonymous().collection("rooms").doc("123456").get());
    await assertFails(db("stranger").collection("rooms").get());
  });

  test("exactly one guest joins an open room", async () => {
    await createRoom("host", "123456");
    await assertFails(joinRoom("host", "123456"));
    await assertFails(joinRoom("guest", "123456", {hostUid: "guest"}));
    await assertFails(db("guest").collection("rooms").doc("123456")
      .update({guestUid: "other", status: "ready"}));
    await assertSucceeds(joinRoom("guest", "123456"));
    await assertFails(joinRoom("late", "123456"));
  });

  test("expired rooms cannot be joined", async () => {
    await createRoom("host", "123456");
    await age("rooms", "123456", {createdAt: LONG_AGO});
    await assertFails(joinRoom("guest", "123456"));
  });

  test("only the host deletes a room", async () => {
    await createRoom("host", "123456");
    await joinRoom("guest", "123456");
    const room = (uid) => db(uid).collection("rooms").doc("123456");
    await assertFails(room("guest").delete());
    await assertSucceeds(room("host").delete());
  });

  test("a bomb room needs a matching claim", async () => {
    await assertFails(createRoom("op", "123456",
      roomData("123456", "op", "planter_0")));
  });
});

describe("bombs", () => {
  test("players plant only valid bombs in their three slots", async () => {
    await assertFails(anonymous().collection("bombs").doc("planter_0")
      .set(bombData("planter")));
    await assertFails(db("other").collection("bombs").doc("planter_0")
      .set(bombData("other")));
    await assertFails(plant("planter", 3));
    await assertFails(plant("planter", 0, bombData("planter", {lat: 91})));
    await assertFails(plant("planter", 0,
      bombData("planter", {geohash: "aaaaaaaaa"})));
    await assertFails(plant("planter", 0,
      bombData("planter", {status: "claimed"})));
    await assertFails(plant("planter", 0,
      bombData("planter", {createdAt: Timestamp.now()})));
    for (const slot of [0, 1, 2]) {
      await assertSucceeds(plant("planter", slot));
    }
  });

  test("a slot is reused only after its bomb is gone", async () => {
    await plant("planter", 0);
    await assertFails(plant("planter", 0));
    await age("bombs", "planter_0", {createdAt: LONG_AGO});
    await assertSucceeds(plant("planter", 0));
    await claim("op", "planter_0", "111111");
    await resolve("op", "planter_0", "defused");
    await assertSucceeds(plant("planter", 0));
  });

  test("the map is readable by signed-in players", async () => {
    await plant("planter", 0);
    const nearby = (firestore) => firestore.collection("bombs")
      .where("active", "==", true)
      .where("geohash", ">=", GEOHASH.slice(0, 5))
      .where("geohash", "<", `${GEOHASH.slice(0, 5)}~`)
      .get();
    await assertSucceeds(nearby(db("op")));
    await assertFails(nearby(anonymous()));
  });

  test("one pair claims a bomb, with its room", async () => {
    await plant("planter", 0);
    await assertFails(claim("planter", "planter_0", "111111"));
    await assertFails(claim("op", "planter_0", "111111", {withRoom: false}));
    await assertFails(claim("op", "planter_0", "111111",
      {roomBombId: "planter_1"}));
    await assertSucceeds(claim("op", "planter_0", "111111"));
    await assertFails(claim("rival", "planter_0", "222222"));

    await age("bombs", "planter_0", {claimedAt: LONG_AGO});
    await assertSucceeds(claim("rival", "planter_0", "222222"));
    await assertFails(resolve("op", "planter_0", "defused"));
  });

  test("dead bombs cannot be claimed", async () => {
    await plant("planter", 0);
    await age("bombs", "planter_0", {createdAt: LONG_AGO});
    await assertFails(claim("op", "planter_0", "111111"));
  });

  test("only the claimer abandons or resolves", async () => {
    await plant("planter", 0);
    await claim("op", "planter_0", "111111");
    await assertFails(abandon("rival", "planter_0"));
    await assertSucceeds(abandon("op", "planter_0"));

    await claim("op", "planter_0", "222222");
    await assertFails(resolve("rival", "planter_0", "defused"));
    await assertFails(resolve("op", "planter_0", "armed"));
    await assertFails(resolve("op", "planter_0", "defused", {lat: 0}));
    await assertFails(resolve("op", "planter_0", "defused",
      {resolvedAt: Timestamp.now()}));
    await assertSucceeds(resolve("op", "planter_0", "exploded"));
    await assertFails(resolve("op", "planter_0", "defused"));
    await assertFails(claim("rival", "planter_0", "333333"));
  });

  test("nobody deletes bombs", async () => {
    await plant("planter", 0);
    await assertFails(db("planter").collection("bombs").doc("planter_0")
      .delete());
  });
});
