import {readFile} from 'node:fs/promises';
import {after, before, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds}
  from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs,
  runTransaction, serverTimestamp, Timestamp, arrayUnion} from 'firebase/firestore';

let env;
const projectId = 'demo-wdyp-signaling';
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Use the emulator');
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  env = await initializeTestEnvironment({projectId, firestore: {
    host, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  }});
});
beforeEach(async () => env.clearFirestore());
after(async () => env?.cleanup());
const db = (uid) => uid ? env.authenticatedContext(uid).firestore()
  : env.unauthenticatedContext().firestore();
const ref = (uid, code = '123456') => doc(db(uid), 'rooms', code);
const data = () => ({version: 1, session: 'a'.repeat(32), hostUid: 'host',
  guestUid: null, createdAt: serverTimestamp(),
  expiresAt: Timestamp.fromMillis(Date.now() + 3600000),
  offer: null, answer: null, hostCandidates: [], guestCandidates: []});
const candidate = {candidate: 'candidate:test', sdpMid: '0', sdpMLineIndex: 0};

test('create/get invitation, no anonymous access, listing or fake ownership', async () => {
  await assertFails(setDoc(ref(null), data()));
  await assertFails(setDoc(ref('guest'), data()));
  await assertFails(setDoc(ref('host', 'bad'), data()));
  await assertFails(setDoc(ref('host'), {...data(), hostRole: 'manual'}));
  await assertFails(setDoc(ref('host'), {...data(), expiresAt:
    Timestamp.fromMillis(Date.now() + 3 * 3600000)}));
  await assertSucceeds(getDoc(ref('host'))); // missing lookup for collision check
  await assertSucceeds(setDoc(ref('host'), data()));
  await assertSucceeds(getDoc(ref('guest')));
  await assertFails(getDoc(ref(null)));
  await assertFails(getDocs(collection(db('guest'), 'rooms')));
});

test('concurrent claims admit one guest, no slot hijack or game state writes', async () => {
  await setDoc(ref('host'), data());
  const claim = (uid) => {
    const store = db(uid);
    return runTransaction(store, async (tx) => {
    const target = doc(store, 'rooms', '123456');
    const snapshot = await tx.get(target);
    if (snapshot.data().guestUid) throw Error('Full');
    tx.update(target, {guestUid: uid});
    });
  };
  const attempts = await Promise.allSettled([claim('a'), claim('b')]);
  assert.equal(attempts.filter((r) => r.status === 'fulfilled').length, 1);
  await assertFails(updateDoc(ref('stranger'), {guestUid: 'stranger'}));
  await assertFails(updateDoc(ref('host'), {hostRole: 'manual'}));
  await assertFails(updateDoc(ref('host'), {status: 'playing'}));
  await assertFails(updateDoc(ref('host'), {session: 'b'.repeat(32)}));
});

test('only each peer may publish its own immutable SDP and append ICE', async () => {
  await setDoc(ref('host'), data());
  await updateDoc(ref('guest'), {guestUid: 'guest'});
  await assertFails(updateDoc(ref('guest'), {offer: {type: 'offer', sdp: 'sdp'}}));
  await assertSucceeds(updateDoc(ref('host'), {offer: {type: 'offer', sdp: 'sdp'}}));
  await assertFails(updateDoc(ref('host'), {offer: {type: 'offer', sdp: 'changed'}}));
  await assertFails(updateDoc(ref('host'), {answer: {type: 'answer', sdp: 'sdp'}}));
  await assertSucceeds(updateDoc(ref('guest'), {answer: {type: 'answer', sdp: 'sdp'}}));
  await assertSucceeds(updateDoc(ref('host'), {hostCandidates: arrayUnion(candidate)}));
  await assertSucceeds(updateDoc(ref('guest'), {guestCandidates: arrayUnion(candidate)}));
  await assertFails(updateDoc(ref('guest'), {hostCandidates: arrayUnion({...candidate,
    candidate: 'spoof'})}));
  await assertFails(updateDoc(ref('host'), {hostCandidates: []}));
  await assertFails(updateDoc(ref('guest'), {guestCandidates: arrayUnion({bad: true})}));
  await assertFails(deleteDoc(ref('guest')));
  await assertSucceeds(deleteDoc(ref('host')));
  assert.equal((await getDoc(ref('host'))).exists(), false);
});

test('expired rooms reject membership and signaling but host may clean up', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', '123456'), {...data(),
      expiresAt: Timestamp.fromMillis(0)});
  });
  await assertFails(updateDoc(ref('guest'), {guestUid: 'guest'}));
  await assertFails(updateDoc(ref('host'), {offer: {type: 'offer', sdp: 'sdp'}}));
  await assertSucceeds(deleteDoc(ref('host')));
});
