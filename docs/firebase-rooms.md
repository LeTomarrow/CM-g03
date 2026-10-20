# Firebase rooms

For installation, emulator setup, deployment, and logs, see
[Firebase setup](firebase-setup.md). Every developer should start there.

## Room API

There are no Cloud Functions (the project stays on the free Spark plan). The
app writes to Firestore in transactions and `firestore.rules` enforces every
invariant, using only server timestamps. A room has one host and one guest.
The six-digit code is also its document ID in `rooms`; anyone signed in can
read a room by code, nobody can list them. Joining is atomic and repeatable
for existing members. Only the host can delete a room. Joins are rejected
after one hour; expiry does not delete the document automatically.

```dart
final rooms = RoomService(); // import services/room_service.dart
final created = await rooms.createRoom(); // signs in anonymously if needed
print(created.code); // show this to the other player

// On the other device:
final joined = await rooms.joinRoom('123456'); // use the actual displayed code
final subscription = rooms.watchRoom(joined.roomId).listen(
  (room) {
    // Render room.guestUid / room.status; null means the room is gone.
  },
  onError: (Object error) {
    // Handle connectivity errors in the lobby.
  },
);
// Cancel the subscription when leaving the session.
await subscription.cancel();

// On the host device:
await rooms.deleteRoom(created.roomId);
```

Expected failures throw `RoomException` (`notFound`, `full`, `expired`).
A write the rules reject throws `FirebaseException` with `permission-denied`.
Invalid local codes throw `ArgumentError`. Auth and network errors also
propagate to the caller.

The lobby's CRIAR button calls createRoom and displays the returned six-digit
code. ENTRAR joins by code. A Firestore listener updates both player slots.
Loading and errors are shown in the lobby; repeated create/join clicks are
blocked while a request is running or a room is active. COMEÇAR requires both
slots to be occupied, but still opens the local game screens independently.
Role selection remains local. Guest leaving, shared game start, WebRTC
signaling and game synchronization are not implemented. Leaving the lobby
cancels its listener but does not delete the room or free a guest slot.
`ready` only means that both room slots are occupied.

## Open-world bombs

The MUNDO screen (`features/world/`) uses `BombService`. `plantBomb` stores a
bomb at the caller's GPS position for 24 hours in one of three slots per
player (`bombs/{uid}_0..2`), which caps live bombs. `claimBomb` locks the bomb
for 10 minutes and, in the same transaction, creates a normal room (with
`bombId`) hosted by the operator; the manual joins it with the code through
the lobby. `resolveBomb` records `defused`, `exploded` or `abandoned`
(re-arms it); only the claimer may do so. The 50 m claim radius is checked
only on the client, since the rules cannot see GPS. Expected failures throw
`BombException`. Nearby bombs are read with geohash range queries, which need
the index in `firestore.indexes.json`.

## Security rules checks

Run from the repository root:

```bash
npm --prefix tests/firestore-rules ci
firebase emulators:exec --project demo-wdyp-rules --only firestore 'npm --prefix tests/firestore-rules test'
```

This uses an isolated local demo project. Each test repeats the writes the
services make and checks what the rules allow: room creation and joining,
expiry, host-only deletion, bomb slots, claims, leases and resolution. It
does not test the Flutter UI.
