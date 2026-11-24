import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/services/game_protocol.dart';
import 'package:what_did_you_press/services/game_transport.dart';

class _GameRoom implements GameTransport {
  final messages = StreamController<GameMessage>.broadcast();
  final sentTypes = <String>[];

  @override
  Stream<bool> get linkStatus => const Stream.empty();

  @override
  Stream<GameMessage> get gameMessages => messages.stream;

  @override
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload = const {},
  }) async {
    sentTypes.add(type);
  }

  void end(String reason) => messages.add(
    GameMessage(
      session: 'test',
      type: 'ended',
      revision: 1,
      payload: {'reason': reason},
    ),
  );
}

void main() {
  test('abandonment stops engine updates and rejects later inputs', () async {
    final engine = await BombEngine.start(
      duration: const Duration(minutes: 5),
      moduleCount: 2,
    );
    addTearDown(engine.dispose);
    final states = <BombEngineState>[];
    final subscription = engine.states.listen(states.add);
    addTearDown(subscription.cancel);
    final abandoned = engine.states.firstWhere(
      (state) => state.status == BombEngineStatus.abandoned,
    );
    engine.abandon();
    final terminal = await abandoned.timeout(const Duration(seconds: 5));
    final count = states.length;
    engine.solveModule(0);
    engine.registerStrike(0);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(states, hasLength(count));
    expect(terminal.strikes, 0);
    expect(terminal.solvedModules, isEmpty);
    expect(terminal.timeLeft, greaterThan(Duration.zero));
  });

  test(
    'a final snapshot still allows the manual to receive the result',
    () async {
      final room = _GameRoom();
      final container = ProviderContainer();
      final subscription = container.listen(gameControllerProvider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await room.messages.close();
      });
      await container
          .read(gameControllerProvider.notifier)
          .start(moduleCount: 2, transport: room, authority: false);
      final initial = container.read(gameControllerProvider);
      room.messages.add(
        GameMessage(
          session: 'test',
          type: 'snapshot',
          revision: 1,
          payload: {
            'timeLeftMs': 10000,
            'strikes': 0,
            'status': 'defused',
            'seed': initial.loadout.seed,
            'modules': initial.loadout.toJson(),
          },
        ),
      );
      room.messages.add(
        const GameMessage(
          session: 'test',
          type: 'ended',
          revision: 2,
          payload: {'reason': 'game_finished', 'status': 'defused'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(gameControllerProvider).status,
        BombEngineStatus.defused,
      );
      expect(
        container.read(gameControllerProvider).connectionNotice,
        'A bomba foi desarmada.',
      );
      room.end('connection_lost');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(gameControllerProvider).status,
        BombEngineStatus.defused,
      );
    },
  );

  for (final reason in ['opponent_left', 'connection_lost']) {
    test(
      '$reason abandons the operator and stops publishing snapshots',
      () async {
        final room = _GameRoom();
        final container = ProviderContainer();
        final subscription = container.listen(
          gameControllerProvider,
          (_, _) {},
        );
        addTearDown(() async {
          subscription.close();
          container.dispose();
          await room.messages.close();
        });
        final controller = container.read(gameControllerProvider.notifier);
        await controller.start(moduleCount: 2, transport: room);
        final abandoned = Completer<void>();
        final listener = container.listen(gameControllerProvider, (_, next) {
          if (next.status == BombEngineStatus.abandoned &&
              !abandoned.isCompleted) {
            abandoned.complete();
          }
        });
        addTearDown(listener.close);
        room.end(reason);
        await abandoned.future.timeout(const Duration(seconds: 5));
        final terminal = container.read(gameControllerProvider);
        final sent = room.sentTypes.length;
        room.end(reason);
        await controller.dispatch(const SolveModuleRequested(0));
        await controller.dispatch(const StrikeRequested(0));
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(
          container.read(gameControllerProvider).status,
          BombEngineStatus.abandoned,
        );
        expect(
          container.read(gameControllerProvider).timeLeft,
          terminal.timeLeft,
        );
        expect(room.sentTypes, hasLength(sent));
        expect(terminal.connectionNotice, isNotNull);
      },
    );
  }
}
