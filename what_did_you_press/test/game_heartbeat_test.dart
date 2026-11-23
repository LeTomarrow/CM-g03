import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/services/game_protocol.dart';
import 'package:what_did_you_press/services/game_transport.dart';

class _Room implements GameTransport {
  final messages = StreamController<GameMessage>.broadcast();
  final sent = <GameMessage>[];

  @override
  Stream<GameMessage> get gameMessages => messages.stream;

  @override
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload = const {},
  }) async {
    sent.add(
      GameMessage(
        session: 'test',
        type: type,
        revision: revision,
        payload: payload,
      ),
    );
  }

  void receive(String type, [Map<String, dynamic> payload = const {}]) =>
      messages.add(
        GameMessage(session: 'test', type: type, revision: 1, payload: payload),
      );

  int get pings => sent.where((message) => message.type == 'ping').length;
}

void main() {
  late _Room room;
  late ProviderContainer container;

  GameState state() => container.read(gameControllerProvider);
  GameController controller() =>
      container.read(gameControllerProvider.notifier);

  Future<void> wait(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> startManual(WidgetTester tester) async {
    room = _Room();
    container = ProviderContainer();
    container.listen(gameControllerProvider, (_, _) {});
    await controller().start(moduleCount: 3, transport: room, authority: false);
  }

  /// Must run inside the test body: testWidgets rejects pending timers.
  Future<void> stop(WidgetTester tester) async {
    container.dispose();
    await room.messages.close();
    await tester.pump();
  }

  testWidgets('pings every second', (tester) async {
    await startManual(tester);
    await wait(tester, 3);
    expect(room.pings, 3);
    await stop(tester);
  });

  testWidgets('a silent partner is flagged and cleared by any message', (
    tester,
  ) async {
    await startManual(tester);
    await wait(tester, GameController.silenceWarningTicks - 1);
    expect(state().partnerSilent, isFalse);
    await wait(tester, 1);
    expect(state().partnerSilent, isTrue);
    expect(state().linkWarning, isNotNull);

    room.receive('ping');
    await tester.pump();
    expect(state().partnerSilent, isFalse);
    expect(state().linkWarning, isNull);
    await stop(tester);
  });

  testWidgets('a long silence ends the session as a lost connection', (
    tester,
  ) async {
    await startManual(tester);
    await wait(tester, GameController.silenceLimitTicks);
    expect(state().status, BombEngineStatus.abandoned);
    expect(state().connectionNotice, 'A ligação ao outro jogador foi perdida.');
    expect(state().linkWarning, isNull);

    final pings = room.pings;
    await wait(tester, 3);
    expect(room.pings, pings);
    await stop(tester);
  });

  testWidgets('regular pings keep the session alive', (tester) async {
    await startManual(tester);
    for (var i = 0; i < GameController.silenceLimitTicks + 5; i++) {
      room.receive('ping');
      await tester.pump(const Duration(seconds: 1));
    }
    expect(state().status, BombEngineStatus.running);
    expect(state().partnerSilent, isFalse);
    await stop(tester);
  });

  testWidgets('leaving the app is announced and shown to the partner', (
    tester,
  ) async {
    await startManual(tester);
    await controller().dispatch(const AppLifecycleChanged(foreground: false));
    final presence = room.sent.lastWhere((m) => m.type == 'command');
    expect(presence.payload, {'command': 'presence', 'away': true});

    room.receive('command', {'command': 'presence', 'away': true});
    await tester.pump();
    expect(state().partnerAway, isTrue);
    expect(state().linkWarning, contains('saiu da app'));

    room.receive('command', {'command': 'presence', 'away': false});
    await tester.pump();
    expect(state().partnerAway, isFalse);
    await stop(tester);
  });
}
