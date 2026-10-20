# Firebase setup for developers

The team shares `what-did-you-press`. The app uses Firebase Authentication and
Cloud Firestore directly, with WebRTC carrying lobby messages. There are no
Cloud Functions, backend builds, or callable endpoints. The Firestore database
should be in Europe; database location is set in Firebase, not Dart.

## Install on each development machine

Install Flutter/Dart, Node.js/npm for the Firebase CLI, and JDK 21 or newer for
the Firestore emulator. Then:

```bash
npm install -g firebase-tools
```

From the repository root:

```bash
cd what_did_you_press
flutter pub get
```

Use the Firebase configuration already in the repository. Do not rerun
`firebase init`, create another project, or download an Admin SDK key.

## Run locally

Terminal 1, from **`CM-g03/`**:

```bash
firebase emulators:start --project what-did-you-press --only auth,firestore
```

Wait for both emulators to be ready. There is no Functions emulator or
TypeScript compilation step anymore. Restart an already-running emulator
suite after this migration to load the new access rules.

Terminal 2, from **`CM-g03/what_did_you_press/`**:

```bash
flutter run -d web-server --web-port 8085
```

Open **http://localhost:8085** in your browser. Chrome is not required. The app
uses emulators by default. Press JOGAR → CRIAR. Open a separate browser profile
or private window, enter the displayed code and press ENTRAR. Two ordinary tabs
usually share an anonymous identity and are not two separate players.

Check the signaling document at **http://127.0.0.1:4000/firestore**, and users
at **http://127.0.0.1:4000/auth**. Roles no longer appear in Firestore: they
travel directly through WebRTC. Wait for the lobby to report that the peer
connection is established before starting. Host start deletes the signaling
room after the guest acknowledges; both screens then open their assigned role.

Local ports: Auth **9099**, Firestore **8080**, Emulator UI **4000**, and web
app **8085** in the command above. The local data is not in the live console.
Fully restart Flutter and refresh the browser after startup changes.

For Android emulators, select the Android device in `flutter devices` and run
`flutter run -d DEVICE_ID`. Firebase host `10.0.2.2` is selected automatically;
web/desktop use `127.0.0.1`. Linux desktop Firebase is not configured; use web
or Android from Linux. Physical Android phones need a LAN override:

```bash
flutter run -d DEVICE_ID --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

Replace the address with your development computer's LAN address. Bind auth
and firestore emulator `host` values to `0.0.0.0` in root `firebase.json` for
LAN access, allow the ports through the firewall, and use a trusted network.
Remote browser tests need a secure origin (HTTPS) or localhost for WebRTC;
Android phones are the recommended physical-device target.

Emulator state is temporary. If useful, export to the ignored `emulator-data/`
folder while running:

```bash
firebase emulators:export emulator-data --project what-did-you-press
```

Restore with `--import=emulator-data` on the start command. Use fresh rooms
after the migration; old room documents have a different schema.

## Use live Firebase without Cloud Functions

The shared project needs Anonymous Authentication enabled and a default
Standard Firestore database. Spark's no-cost quotas apply; Functions billing
is not required for this design. From **`CM-g03/`**, a maintainer with access
must deploy the new rules before any client writes can work:

```bash
firebase login
firebase deploy --project what-did-you-press --only firestore:rules,firestore:indexes
```

From the Flutter folder, explicitly select live services:

```bash
flutter run -d web-server --web-port 8085 --dart-define=USE_FIREBASE_EMULATORS=false
```

This does not deploy an app or provision TURN. Firebase rules authorize the
initial room and signaling operations; peer room logic runs on the clients.
Deleted local source files do not remove any previously deployed Functions.
If someone deployed old Functions, a maintainer should remove those obsolete
endpoints separately in the Firebase/Google Cloud console.

## Troubleshooting

There are no Cloud Function logs to look for. Inspect browser Network/Console,
Flutter output, Emulator UI, and Firestore documents. Browser signaling uses
Firestore's SDK transport; there should be no `createRoom` HTTP endpoint call.

- Permission denied: ensure the new rules are loaded/deployed and Anonymous
  Auth is enabled for live Firebase.
- Connection refused: check that Auth and Firestore emulators are running and
  that the client is using the right host.
- Room created but peer connection fails: use two identities; verify both use
  the same project/emulator and room code. Wait for offer, answer and candidates
  in the signaling document. Restrictive networks can require a TURN relay.
- Lost connection/start timeout: close and create a new room. Automatic
  reconnection is not yet implemented.

The host's initial mailbox lasts up to about one hour but is not automatically
removed if the process crashes. Hosts clean up on normal exit and start. Rules
deny joins/signaling after expiry. There is no scheduled cleanup service.

See [room protocol and tests](firebase-rooms.md) for the message format,
start acknowledgement/deletion sequence, security model and test commands.
