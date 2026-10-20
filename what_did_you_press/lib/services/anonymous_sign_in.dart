import 'package:firebase_auth/firebase_auth.dart';

Future<void>? _pendingSignIn;

/// Shared by every service so concurrent calls use one anonymous identity.
Future<void> ensureSignedIn(FirebaseAuth auth) async {
  if (auth.currentUser != null) return;
  final pending = _pendingSignIn ??= auth.signInAnonymously().then((_) {});
  try {
    await pending;
  } finally {
    if (identical(_pendingSignIn, pending)) _pendingSignIn = null;
  }
}
