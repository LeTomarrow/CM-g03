# Firebase setup for developers

The team shares the Firebase project `what-did-you-press`. Each developer runs
their own local emulators. **The app currently uses emulators by default**;
starting Flutter alone is not enough to create rooms.

## Install once on each development machine

Install Flutter/Dart, Node.js **24** (matching `functions/package.json`), npm,
and a JDK **21 or newer** for Firestore emulation. Then:

```bash
npm install -g firebase-tools
```

From `CM-g03/`:

```bash
npm --prefix functions ci
cd what_did_you_press
flutter pub get
```

Use the Firebase configuration included in the repository. **Do not run `firebase init` on each
clone**, create a new Firebase project, or download an Admin SDK key.
Local emulators do not require project membership or billing. Log in with your
own account (`firebase login`) when accessing the shared live project.

## Run locally

Terminal 1, from **`CM-g03/`**:

```bash
npm --prefix functions run build
firebase emulators:start --project what-did-you-press --only auth,functions,firestore
```

Wait for all three emulators and the `europe-west1-createRoom` endpoint to be
ready. Leave the terminal running. After editing TypeScript, rebuild it; the
emulator runs compiled `functions/lib/`, not the `.ts` source directly.

Terminal 2, from **`CM-g03/what_did_you_press/`**:

```bash
flutter run -d web-server --web-port 8085
```

Open **http://localhost:8085** in your browser. Chrome is not required.
Press **JOGAR → CRIAR**. The returned six-digit code should appear in the lobby.
Check the room under **http://127.0.0.1:4000/firestore** and users under
**http://127.0.0.1:4000/auth**. Local data does not appear in the live console.

Use a private window or another browser for the second player, then enter the
code and press ENTRAR. Ordinary tabs share the signed-in identity, so they may
be treated as the same player. Both clients must reach the same emulator set.

Emulator ports are Auth **9099**, Functions **5001**, Firestore **8080**, and
UI **4000**. `main.dart` configures them after Firebase initialization. Web and
desktop use `127.0.0.1`; Android emulators use `10.0.2.2` automatically.
Linux desktop is not configured; use web or Android from a Linux computer.

For a physical Android phone, use your computer's LAN address:

```bash
flutter run -d DEVICE_ID --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

Replace that example address. The phone and computer must share a reachable
network. In the root `firebase.json`, set `host` to `0.0.0.0` for auth,
functions and firestore emulators to allow LAN access; the default bindings
are loopback only. Allow their ports through your local firewall if needed.
Only expose development emulators on a trusted local network.

Fully stop/restart Flutter and refresh the page after changing startup config.
Emulator state is temporary unless exported, for example with
`firebase emulators:export emulator-data --project what-did-you-press` while
running. Restore it with `--import=emulator-data` on the emulator start command.

## Logs and troubleshooting

For local calls, check the emulator terminal and UI logs. Successful operations
log `Room created`, `Room joined`, or `Room deletion completed`. For live calls:

```bash
firebase functions:log --project what-did-you-press --only createRoom
```

Live logs are also available through the Functions dashboard and Google Cloud
Logs Explorer. See [Firebase logging](https://firebase.google.com/docs/functions/writing-and-viewing-logs).

An `internal` message alone does not identify the cause. In the browser Network
panel, local create requests should target
`http://127.0.0.1:5001/what-did-you-press/europe-west1/createRoom`.
If they target live Firebase, restart the app with emulator mode enabled.
If connection is refused, check emulator startup, host and ports. If the
endpoint responds with an error, inspect its terminal log. Sign-in failures
can happen before any function call. No live log entries are expected for
local requests.

Room behavior, limitations and integration checks are documented in
[Firebase rooms](firebase-rooms.md).
