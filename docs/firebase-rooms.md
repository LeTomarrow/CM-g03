# Rooms: Firestore signaling and client protocol

Room logic now lives in Dart. There are no Cloud Functions or callable
endpoints. Firestore is a mailbox used to find a peer and exchange WebRTC
connection information. After connection, lobby messages use a reliable,
ordered WebRTC DataChannel named `room-v1`.

## Responsibilities

- `services/room_service.dart`: anonymous sign-in, code reservation/claim,
  Firestore signaling, WebRTC transport, cleanup, and the existing lobby API.
- `services/room_protocol.dart`: small, testable client state machine and JSON
  format. The host coordinates decisions; it need not be the operator.
- `features/lobby.dart`: displays the service stream and sends user actions.
- `firestore.rules`: permits only valid membership and signaling writes.

The host creates a random six-digit code with a transaction that checks for
collisions. A guest claims the empty guest slot in another transaction. Two
simultaneous guests cannot both claim it. A 128-bit random `session` identifies
that particular connection even if a code is reused later. Both clients sign
in anonymously; use separate browser profiles/private windows to test them.

## Firestore document

```text
rooms/{sixDigitCode}
  version: 1
  session: random 32-character hexadecimal string
  hostUid: creator's authenticated UID
  guestUid: null, then the admitted guest's UID
  createdAt: server timestamp
  expiresAt: timestamp, approximately one hour later
  offer: null, then { type: "offer", sdp: "..." }
  answer: null, then { type: "answer", sdp: "..." }
  hostCandidates: [ { candidate, sdpMid, sdpMLineIndex }, ... ]
  guestCandidates: [ { candidate, sdpMid, sdpMLineIndex }, ... ]
```

These fields describe discovery and signaling, not gameplay. There is no
Firestore `hostRole`, `status`, game timer, puzzle state or start endpoint.
Candidates live inside the document (at most 128 per peer), so deleting the
room does not leave orphan candidate subcollections. SDP is limited to 64 KiB.

The host creates the DataChannel and offer. The guest applies the offer and
publishes an answer. Both apply the other peer's ICE candidates only after
setting their remote description. Snapshot processing is serialized so an
offer cannot be applied twice while an async operation is in progress.

Exact document reads are allowed to authenticated users who know/guess the
code; this is necessary for joining and collision checking. Collection listing
is denied. The six-digit code is an invitation, not a strong secret. Do not
store private gameplay/profile data here. Rules enforce immutable identity and
session, one guest, one SDP per sender, and append-only own ICE candidates.
Only the host can delete the document. Expired rooms reject joins/signaling;
there is no background cleanup job. Existing pre-migration rooms are not valid
version-1 signaling documents; create a new room after upgrading both clients.

## Local room state

`watchRoom()` now emits local room state, combining admitted member IDs and
peer messages. The lobby can keep using the same subscription API:

```dart
final rooms = RoomService();
final connection = await rooms.createRoom(); // guest uses joinRoom(code)
final subscription = rooms.watchRoom(connection.roomId).listen(
  (room) { /* display role and connection state */ },
  onError: (Object error) { /* display error / allow a new connection */ },
);
```

Phases are `waiting → ready → starting → playing`, or `closed` on failure.
A claimed guest slot does not mean ready: the DataChannel must actually open.
A host may choose its role while waiting. Once connected, either player can
request a swap; only the host changes canonical state. The guest's role is
always the opposite of `hostRole`, so the roles cannot accidentally match.

## DataChannel protocol, version 1

Every message is UTF-8 JSON (maximum 2 KiB):

```json
{
  "version": 1,
  "session": "0123456789abcdef0123456789abcdef",
  "type": "state",
  "revision": 2,
  "hostRole": "manual"
}
```

`hostRole` is `defuser` or `manual`. Only the host increments `revision` and
publishes authoritative state. Sender identity comes from the established
peer connection, never a UID supplied in a message. Invalid versions, roles,
sessions, message types and stale states are ignored/rejected.

| Type | Sender → receiver | Meaning |
| --- | --- | --- |
| `hello` | guest → host | DataChannel is open; send current roles |
| `state` | host → guest | Apply current revision and roles; lobby is ready |
| `swap` | guest → host | Request a swap of the revision the guest has seen |
| `prepare` | host → guest | Freeze these roles and prepare to start |
| `ack` | guest → host | Confirm this exact prepared revision and role |
| `start` | host → guest | Enter the game with those prepared roles |
| `closed` | either → other | Session is ending |

For a host swap, the host changes its local role, increments revision and sends
`state`. For a guest swap, the guest sends `swap`; the host applies it only if
its revision matches and then broadcasts `state`. This avoids replaying stale
swap requests. Role changes cannot be applied while starting or playing.

## Start and deletion

1. Host presses COMEÇAR. A connected guest is required.
2. Host freezes the roles, increments revision and sends `prepare`.
3. Guest stores the prepared roles, detaches its Firestore listener and sends
   `ack` for that revision. It does not enter the game yet.
4. Host waits up to 10 seconds for matching `ack`, detaches its listener and
   deletes the Firestore signaling document with a session-checked transaction.
5. Host sends `start`. Both enter the screen corresponding to their local role.

Deleting a room by itself never means start. Only a valid `start` following
`prepare` does. If acknowledgement/deletion fails, the host reports failure
and restores lobby state. The guest times out if start never arrives. As with
any two-device protocol, a broken connection during the final exchange may
leave one device ahead; failures require a new room rather than claiming both
started successfully.

The DataChannel is retained while the game screen is active and closed when
that route is disposed. Closing a host lobby removes its mailbox; leaving as a
guest notifies the host and ends the peer session. Guest slots are not recycled
in place: create a fresh room to avoid mixing old SDP and ICE with a new peer.
Network failure is reported; automatic ICE restart/reconnection is not included.

Gameplay transport is exposed by `RoomService.gameMessages` and
`sendGameMessage()`. These messages use a separate scope, session and revision
from the lobby protocol, and are never persisted in Firestore. The defuser is
the gameplay authority: `features/game/bomb_engine.dart` runs its timer,
strikes and solved-module set in a Dart isolate. `BombPage` publishes compact
authoritative snapshots over the DataChannel; the manual should render those
snapshots and send only input/command messages. It must not run a second timer
or decide results locally.

## Current scope

Create, join, close/delete, shared role changes, host-only shared start and
signaling cleanup and the authoritative bomb transport are implemented. The
module-specific puzzle rules and the manual's snapshot consumer are still the
next implementation step. They belong on the peer transport, not in Firestore
gameplay writes.

STUN helps find routes; TURN is needed when direct connectivity fails. The app
accepts `WEBRTC_STUN_URL` (defaults to Google's public STUN), `WEBRTC_TURN_URL`,
`WEBRTC_TURN_USERNAME`, and `WEBRTC_TURN_CREDENTIAL` as Dart defines. No TURN
service is provisioned. Use only temporary/scoped TURN credentials for testing;
Dart defines are compiled into the app and cannot hide provider secrets.
Firestore/Auth can run on Spark within quotas; TURN is a separate service.

## Open-world bombs

The MUNDO screen (`features/world/`) uses `services/bomb_service.dart` and
the phone's GPS (`geolocator`). Bombs are ordinary Firestore documents:

```text
bombs/{uid}_{0..2}      one of three slots per player, which caps live bombs
  lat, lng, geohash     position; geohash (9 chars) powers nearby queries
  plantedBy             planter's UID
  status                armed | claimed | defused | exploded
  active                false once defused or exploded
  claimedBy, claimedAt  current claim; the lease lasts 10 minutes
  createdAt             server timestamp; the bomb lives 24 hours
  resolvedBy, resolvedAt  set when defused or exploded
```

A player within 50 m claims a bomb (a transaction checks it is free), then
the lobby opens in bomb mode: it creates an ordinary room automatically, the
claimer hosts as operator and roles are locked (`RoomService.rolesLocked`).
The manual joins with the code as usual. When `BombPage` ends, the host
records `defused` or `exploded`; leaving the lobby before starting re-arms the
bomb. Rules enforce slots, server-timestamped lifetimes, one claimer per
lease, and that only the claimer resolves. The 50 m radius is checked only on
the client, since rules cannot see GPS. Nearby bombs are read with geohash
range queries over the cell and its neighbours, which need the composite
index in `firestore.indexes.json` (deployed with the rules).

## Checks

Dart protocol/game tests, from `what_did_you_press/`:

```bash
flutter test
flutter analyze
```

Firestore rule tests, from the repository root:

```bash
npm --prefix tools/firebase-tests ci
firebase emulators:exec --project demo-wdyp-signaling --only firestore 'npm --prefix tools/firebase-tests test'
```

These test claims, unauthorized writes, signaling ownership, expiration,
protocol revisions, frozen roles and start ordering. `bombs.test.mjs` covers
bomb slots, claims, leases and resolution. Test two real browser
profiles/devices for network reachability and relay requirements too.

A real-browser smoke entry point is available at
`what_did_you_press/integration_test/room_web_smoke.dart`. It uses an isolated
`demo-wdyp-signaling` project with Auth on 9199 and Firestore on 8180. Build
with `flutter build web --debug --target integration_test/room_web_smoke.dart`,
serve `build/web` on localhost, and inspect `globalThis.roomSmokeResult` in the
browser console. It creates two independent Firebase app identities, opens real
peer connections, swaps roles both ways, starts, and verifies mailbox deletion.
It is a test entry point, not the normal app. Do not run database-clearing rule
tests concurrently against the same demo project.
