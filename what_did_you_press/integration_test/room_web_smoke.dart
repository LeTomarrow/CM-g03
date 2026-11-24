// Browser smoke entry point: builds two real peer services using separate
// Firebase apps/identities. Requires local Auth :9199 and Firestore :8180.
import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/services/room_service.dart';

@JS('roomSmokeResult')
external set smokeResult(JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Testing peers...'))));
  RoomService? host;
  RoomService? guest;
  StreamSubscription<Room?>? hostSub;
  StreamSubscription<Room?>? guestSub;
  try {
    const options = FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:123:web:456',
      messagingSenderId: '123',
      projectId: 'demo-wdyp-signaling',
    );
    final hostApp = await Firebase.initializeApp(options: options);
    final guestApp = await Firebase.initializeApp(
      name: 'guest',
      options: options,
    );
    Future<RoomService> service(FirebaseApp app) async {
      final auth = FirebaseAuth.instanceFor(app: app);
      final db = FirebaseFirestore.instanceFor(app: app);
      await auth.useAuthEmulator('127.0.0.1', 9199);
      db.useFirestoreEmulator('127.0.0.1', 8180);
      return RoomService(auth: auth, firestore: db);
    }

    host = await service(hostApp);
    guest = await service(guestApp);
    final room = await host.createRoom();
    final joined = await guest.joinRoom(room.code);
    Room? hostState;
    Room? guestState;
    Object? failure;
    hostSub = host
        .watchRoom(room.roomId)
        .listen((r) => hostState = r, onError: (Object e) => failure = e);
    guestSub = guest
        .watchRoom(joined.roomId)
        .listen((r) => guestState = r, onError: (Object e) => failure = e);
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!condition()) {
        if (failure != null) throw failure!;
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'Timed out: ${hostState?.status}/${guestState?.status}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await waitFor(
      () => hostState?.status == 'ready' && guestState?.status == 'ready',
    );
    await guest.switchRoles(room.roomId);
    await waitFor(
      () =>
          hostState?.hostRole == PlayerRole.manual &&
          guestState?.hostRole == PlayerRole.manual,
    );
    await host.switchRoles(room.roomId);
    await waitFor(
      () =>
          hostState?.hostRole == PlayerRole.defuser &&
          guestState?.hostRole == PlayerRole.defuser,
    );
    await host.startGame(room.roomId);
    await waitFor(
      () => hostState?.status == 'playing' && guestState?.status == 'playing',
    );
    final mailbox = await FirebaseFirestore.instance
        .collection('rooms')
        .doc(room.roomId)
        .get(const GetOptions(source: Source.server));
    if (mailbox.exists) throw StateError('Signaling room was not deleted');
    smokeResult =
        'PASS: connected, roles swapped both ways, shared start, mailbox deleted'
            .toJS;
  } catch (error, stack) {
    smokeResult = 'FAIL: $error\n$stack'.toJS;
  } finally {
    await hostSub?.cancel();
    await guestSub?.cancel();
    await host?.close();
    await guest?.close();
  }
}
