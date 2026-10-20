# Firebase rooms

For installation, emulator setup, deployment, and logs, see
[Firebase setup](firebase-setup.md). Every developer should start there.

## Room API

Functions run in `europe-west1` (Belgium). A room has one host and one guest.
The six-digit code is also its document ID in `rooms`. Joining is atomic and
repeatable for existing members. Only the host can delete a room. Joins are
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
blocked while a request is running or a room is active. COMEÇAR requires both
slots to be occupied, but still opens the local game screens independently.
Role selection remains local. Guest leaving, shared game start, WebRTC
signaling and game synchronization are not implemented. Leaving the lobby
cancels its listener but does not delete the room or free a guest slot.
`ready` only means that both room slots are occupied.

## Backend integration checks

Run from the repository root:

```bash
npm --prefix functions run build
firebase emulators:exec --project demo-wdyp-rooms --only firestore 'node functions/test/rooms.cjs'
```

This uses an isolated local demo project and checks authentication, concurrent
joins, repeat joins, expiry, and host-only deletion. It does not test browser
network access or the Flutter UI.
