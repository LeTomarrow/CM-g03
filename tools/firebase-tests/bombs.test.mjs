import {readFile} from 'node:fs/promises';
import {after, before, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds}
  from '@firebase/rules-unit-testing';
import {doc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where,
  serverTimestamp, Timestamp} from 'firebase/firestore';

// Each helper mirrors a write made by lib/services/bomb_service.dart.
let env;
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Use the emulator');
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  env = await initializeTestEnvironment({projectId: 'demo-wdyp-bombs', firestore: {
    host, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  }});
});
beforeEach(async () => env.clearFirestore());
after(async () => env?.cleanup());

const GEOHASH = 'eycs0p8eu';
const LONG_AGO = Timestamp.fromMillis(0);
const db = (uid) => uid ? env.authenticatedContext(uid).firestore()
  : env.unauthenticatedContext().firestore();
const ref = (uid, id = 'planter_0') => doc(db(uid), 'bombs', id);
const data = (uid, overrides = {}) => ({lat: 38.7569, lng: -9.1569,
  geohash: GEOHASH, plantedBy: uid, status: 'armed', active: true,
  claimedBy: null, claimedAt: null, createdAt: serverTimestamp(), ...overrides});
const plant = (uid, slot = 0, value = data(uid)) =>
  setDoc(ref(uid, `${uid}_${slot}`), value);
const claim = (uid, extra = {}) => updateDoc(ref(uid), {status: 'claimed',
  claimedBy: uid, claimedAt: serverTimestamp(), ...extra});
const abandon = (uid) => updateDoc(ref(uid), {status: 'armed', claimedBy: null,
  claimedAt: null});
const resolve = (uid, status, extra = {}) => updateDoc(ref(uid), {status,
  active: false, resolvedBy: uid, resolvedAt: serverTimestamp(), ...extra});
const age = (fields) => env.withSecurityRulesDisabled((context) =>
  updateDoc(doc(context.firestore(), 'bombs', 'planter_0'), fields));

test('players plant only valid bombs in their three slots', async () => {
  await assertFails(setDoc(ref(null), data('planter')));
  await assertFails(setDoc(ref('other'), data('other')));
  await assertFails(plant('planter', 3));
  await assertFails(plant('planter', 0, data('planter', {lat: 91})));
  await assertFails(plant('planter', 0, data('planter', {geohash: 'aaaaaaaaa'})));
  await assertFails(plant('planter', 0, data('planter', {status: 'claimed'})));
  await assertFails(plant('planter', 0, data('planter', {createdAt: Timestamp.now()})));
  await assertFails(plant('planter', 0, data('planter', {roomId: null})));
  for (const slot of [0, 1, 2]) await assertSucceeds(plant('planter', slot));
});

test('a slot is reused only after its bomb is gone', async () => {
  await plant('planter');
  await assertFails(plant('planter'));
  await age({createdAt: LONG_AGO});
  await assertSucceeds(plant('planter'));
  await claim('op');
  await resolve('op', 'defused');
  await assertSucceeds(plant('planter'));
});

test('the map is readable by signed-in players only', async () => {
  await plant('planter');
  const nearby = (uid) => getDocs(query(collection(db(uid), 'bombs'),
    where('active', '==', true),
    where('geohash', '>=', GEOHASH.slice(0, 5)),
    where('geohash', '<', `${GEOHASH.slice(0, 5)}~`)));
  await assertSucceeds(nearby('op'));
  await assertFails(nearby(null));
});

test('one player claims a bomb until the lease expires', async () => {
  await plant('planter');
  await assertFails(claim('planter'));
  await assertFails(claim('op', {claimedAt: Timestamp.now()}));
  await assertFails(claim('op', {lat: 0}));
  await assertSucceeds(claim('op'));
  await assertFails(claim('rival'));
  await age({claimedAt: LONG_AGO});
  await assertSucceeds(claim('rival'));
  await assertFails(resolve('op', 'defused'));
});

test('dead bombs cannot be claimed', async () => {
  await plant('planter');
  await age({createdAt: LONG_AGO});
  await assertFails(claim('op'));
});

test('only the claimer abandons or resolves', async () => {
  await plant('planter');
  await claim('op');
  await assertFails(abandon('rival'));
  await assertSucceeds(abandon('op'));
  await claim('op');
  await assertFails(resolve('rival', 'defused'));
  await assertFails(resolve('op', 'armed'));
  await assertFails(resolve('op', 'defused', {lat: 0}));
  await assertFails(resolve('op', 'defused', {resolvedAt: Timestamp.now()}));
  await assertSucceeds(resolve('op', 'exploded'));
  await assertFails(resolve('op', 'defused'));
  await assertFails(claim('rival'));
});

test('nobody deletes bombs', async () => {
  await plant('planter');
  await assertFails(deleteDoc(ref('planter')));
});
