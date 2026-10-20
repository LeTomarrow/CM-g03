# Firebase rooms

For installation, emulator setup, deployment, and logs, see
[Firebase setup](firebase-setup.md). Every developer should start there.

## Room API

Functions run in `europe-west1` (Belgium). A room has one host and one guest.
The six-digit code is also its document ID in `rooms`. Joining is atomic and
repeatable for existing members while the room is open. Only the host can delete a room. Joins are
rejected after one hour; expiry does not delete the document automatically.

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
    // A deleted room can cause permission-denied because membership vanished.
    // Handle closure and other connectivity errors in the lobby.
  },
);
// Cancel the subscription when leaving the session.
await subscription.cancel();

// On the host device:
await rooms.deleteRoom(created.roomId);
```

Catch `FirebaseFunctionsException` around operations and show a suitable UI
message for `not-found`, `failed-precondition`, `permission-denied`, and
`unauthenticated`. Invalid local codes throw `ArgumentError`. Auth and network
errors also propagate to the caller. Keep the same service instance per app.

The lobby's CRIAR button calls createRoom and displays the returned six-digit
code. ENTRAR joins by code. A Firestore listener updates both player slots.
Loading and errors are shown in the lobby; repeated create/join clicks are
blocked while a request is running or a room is active.

Either member can press TROCAR PAPÉIS before start. `switchRoles(roomId)`
transactionally toggles `hostRole` (`defuser` or `manual`); the guest always
has the opposite role. Both screens display the stored roles and mark the
local player with `(tu)`. Older rooms without hostRole default to host=defuser.

Only the host can press COMEÇAR, and both players must be in the room.
`startGame(roomId)` atomically changes `ready` to `playing` and sets startedAt.
This closes the room to new joins, including repeat joins by members, and
freezes the roles. The document is retained so both listeners receive the
start event and navigate once to their assigned screen; it is not deleted.
Repeated host start requests are safe and preserve the original start time.

Guest leaving, WebRTC signaling and gameplay synchronization are not yet
implemented. Shared lobby start opens each phone's local game; it does not
synchronize puzzles or timers. Leaving the lobby cancels its listener but does
not delete the room or free a guest slot. `ready` means both slots are occupied.
Rebuild Functions before using the new endpoints in the emulator; for live
Firebase, deploy the updated Functions first.

## Backend integration checks

Run from the repository root:

```bash
npm --prefix functions run build
firebase emulators:exec --project demo-wdyp-rooms --only firestore 'node functions/test/rooms.cjs'
```

This uses an isolated local demo project and checks authentication, concurrent
joins, repeat joins, expiry, host-only deletion and start, shared role swaps,
start/swap races, role locking, and join rejection after start. It does not test browser
network access or the Flutter UI.
