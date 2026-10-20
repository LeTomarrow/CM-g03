# Firebase setup for developers

The team shares the Firebase project `what-did-you-press`. Each developer runs
their own local emulators. **The app currently uses emulators by default**;
starting Flutter alone is not enough to create rooms.

## What goes in Git

| Commit | Purpose |
| --- | --- |
| Root `firebase.json` | Functions, rules, emulator ports and deployment configuration |
| `firestore.rules`, `firestore.indexes.json` | Shared database access policy and indexes |
| `functions/src/`, package manifests and lockfile | Backend source and reproducible dependencies |
| `what_did_you_press/firebase.json` | FlutterFire platform mappings |
| `what_did_you_press/lib/firebase_options.dart` | Shared client project configuration |
| `what_did_you_press/android/app/google-services.json` | Android Firebase client configuration |
| `GoogleService-Info.plist` if iOS is added | Apple Firebase client configuration |
| Flutter `pubspec.yaml` and `pubspec.lock` | Client dependencies |
| `.firebaserc` if added | Project aliases; project IDs are not secrets |

Firebase client API keys and app IDs identify the project; they do not grant
Admin SDK access. This team keeps those files committed so every clone points
to the same project. Access is enforced by Authentication, Firestore rules and
backend authorization, not by hiding client configuration. See
[Firebase API keys](https://firebase.google.com/docs/projects/api-keys).

Ignore logs, `.firebase/`, emulator exports, `node_modules/`, compiled Functions
output, Flutter build output, local `.env` files and `.secret.local`. The ignore
files cover these. Use the ignored `emulator-data/` directory for local exports.
An `.env.example` may contain placeholder values and can be committed.

Never commit service account private keys, CLI login tokens, signing keys or
TURN/provider secrets. Common credential filenames are ignored as a safeguard;
arbitrarily named credentials still need review. No service account key is
needed for the local emulator workflow. For live Functions, use runtime
credentials and Secret Manager for future backend secrets. See the
[Firebase security checklist](https://firebase.google.com/support/guides/security-checklist).
Ignoring an already tracked file does not remove it from Git or its history.
If a private key was committed, revoke it; adding an ignore rule is insufficient.

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

Keep the committed Firebase configuration. **Do not run `firebase init` on each
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

## Configure a new platform or a different project

This is not needed for an ordinary clone. Run it when intentionally changing
the registered platforms or project:

```bash
dart pub global activate flutterfire_cli
firebase login
cd what_did_you_press
flutterfire configure --project what-did-you-press
```

Run `cd` from the repository root. In Fish, make the CLI available with
`fish_add_path $HOME/.pub-cache/bin`. In Bash, add
`export PATH="$PATH:$HOME/.pub-cache/bin"` to `~/.bashrc` and reload it.

Android is for phones/emulators; web is for browser tests; Windows is only
needed for Windows desktop tests. Current web and Windows options share a
Firebase web registration. Review generated changes before committing them.
`main.dart` already initializes Firebase; do not paste another initialization.

## Shared live project: set up once, not per developer

A project maintainer invites teammates using **Project settings → Users and
permissions**. Each teammate uses their own Google account.

In the shared Firebase console, enable **Authentication → Anonymous**, and
create a **Standard Cloud Firestore** database with ID **`(default)`**. Choose
a European location such as `europe-west1` (Belgium) or `eur3` (Europe).
Database location is independent of Functions and cannot be changed in place.
Room functions and the Dart caller use **`europe-west1`**.

Deploying Cloud Functions requires the **Blaze billing plan**. Without it,
continue with local emulators. A maintainer with deployment permissions can
deploy from **`CM-g03/`**, using the root backend `firebase.json`:

```bash
firebase deploy --project what-did-you-press --only functions,firestore:rules,firestore:indexes
```

The nested Flutter `firebase.json` has no deployment targets. Once deployment
succeeds, explicitly switch a client to live Firebase:

```bash
flutter run -d web-server --web-port 8085 --dart-define=USE_FIREBASE_EMULATORS=false
```

Check live documents under **Firebase Console → Firestore Database → Data →
rooms**. The collection is created by the first successful create operation.
Do not open database access rules to troubleshoot; the functions use the Admin
SDK and validate writes, while room reads require membership.

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
