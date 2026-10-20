# Firebase setup for developers

The team shares the Firebase project `what-did-you-press` on the free Spark
plan: Firestore, anonymous Auth, security rules and indexes. There are no Cloud
Functions. **The app uses the live project by default**; local emulators are
opt-in.

## Install once on each development machine

Install Flutter/Dart, Node.js, npm, and a JDK **21 or newer** for Firestore
emulation. Then:

```bash
npm install -g firebase-tools
```

From `CM-g03/`:

```bash
npm --prefix tests/firestore-rules ci
cd what_did_you_press
flutter pub get
```

Use the Firebase configuration included in the repository. **Do not run
`firebase init` on each clone**, create a new Firebase project, or download an
Admin SDK key. Local emulators do not require project membership. Log in with
your own account (`firebase login`) when deploying to the shared live project.

## Run against the live project

From `CM-g03/what_did_you_press/`:

```bash
flutter run -d DEVICE_ID
flutter build apk   # installable APK for the phones
```

Any phone with Internet access works; no computer is needed. Data appears in
the [Firebase console](https://console.firebase.google.com/project/what-did-you-press/firestore).

## Deploy rules and indexes

After changing `firestore.rules` or `firestore.indexes.json`, test them (see
[Firebase rooms](firebase-rooms.md)) and deploy from `CM-g03/`:

```bash
firebase deploy --project what-did-you-press --only firestore
```

New indexes take a few minutes to build; nearby-bomb queries fail until then.
Anonymous sign-in must be enabled once in the console under Authentication →
Sign-in method.

## Run locally with emulators

Terminal 1, from **`CM-g03/`**:

```bash
firebase emulators:start --project what-did-you-press --only auth,firestore
```

Terminal 2, from **`CM-g03/what_did_you_press/`**:

```bash
flutter run -d web-server --web-port 8085 --dart-define=USE_FIREBASE_EMULATORS=true
```

Open **http://localhost:8085** in your browser. Press **JOGAR → CRIAR**. The
six-digit code should appear in the lobby. Check the room under
**http://127.0.0.1:4000/firestore** and users under
**http://127.0.0.1:4000/auth**. Local data does not appear in the live console.

Use a private window or another browser for the second player, then enter the
code and press ENTRAR. Ordinary tabs share the signed-in identity, so they may
be treated as the same player. Both clients must reach the same emulator set.

Emulator ports are Auth **9099**, Firestore **8080**, and UI **4000**.
`main.dart` configures them after Firebase initialization. Web and desktop use
`127.0.0.1`; Android emulators use `10.0.2.2` automatically. Linux desktop is
not configured; use web or Android from a Linux computer.

For a physical Android phone, use your computer's LAN address:

```bash
flutter run -d DEVICE_ID --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

Replace that example address. The phone and computer must share a reachable
network. In the root `firebase.json`, set `host` to `0.0.0.0` for the auth and
firestore emulators to allow LAN access; the default bindings are loopback
only. Allow their ports through your local firewall if needed. Only expose
development emulators on a trusted local network.

Fully stop/restart Flutter and refresh the page after changing startup config.
Emulator state is temporary unless exported, for example with
`firebase emulators:export emulator-data --project what-did-you-press` while
running. Restore it with `--import=emulator-data` on the emulator start command.

## Troubleshooting

`permission-denied` means the rules rejected a write. Locally, the emulator
log names the failing rule line. The most common live cause is a phone clock
far off real time, since the app judges expiry with its own clock while the
rules use the server's. `operation-not-allowed` on sign-in means anonymous
Auth is disabled. A nearby-bombs query failing with `failed-precondition`
means the index is missing or still building.

Room behavior, limitations and rules tests are documented in
[Firebase rooms](firebase-rooms.md).
