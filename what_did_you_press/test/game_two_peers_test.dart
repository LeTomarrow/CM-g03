import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/services/game_protocol.dart';
import 'package:what_did_you_press/services/game_transport.dart';

/// One end of an in-memory DataChannel. Messages cross as encoded text, so the
/// real protocol validation runs on every hop.
class _Link implements GameTransport {
  final _incoming = StreamController<GameMessage>.broadcast();
  late _Link peer;
  bool connected = true;

  @override
  Stream<bool> get linkStatus => const Stream.empty();

  @override
  Stream<GameMessage> get gameMessages => _incoming.stream;

  @override
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload = const {},
  }) async {
    if (!connected) throw StateError('peer gone');
    final text = GameMessage(
      session: 'test',
      type: type,
      revision: revision,
      payload: payload,
    ).encode();
    peer._incoming.add(GameMessage.decode(text, 'test'));
  }

  /// What the transport injects when the DataChannel drops.
  void dropConnection() {
    connected = false;
    peer.connected = false;
    _incoming.add(
      const GameMessage(
        session: 'test',
        type: 'ended',
        revision: 0,
        payload: {'reason': 'connection_lost'},
      ),
    );
  }

  Future<void> close() => _incoming.close();
}

/// A player: its own ProviderContainer, like a separate device.
class _Peer {
  _Peer(this.link) {
    _subscription = container.listen(gameControllerProvider, (_, _) {});
  }

  final _Link link;
  final container = ProviderContainer();
  late final ProviderSubscription<GameState> _subscription;

  GameController get controller =>
      container.read(gameControllerProvider.notifier);
  GameState get state => container.read(gameControllerProvider);

  Future<GameState> waitFor(bool Function(GameState state) test) {
    if (test(state)) return Future.value(state);
    final done = Completer<GameState>();
    late final ProviderSubscription<GameState> sub;
    sub = container.listen(gameControllerProvider, (_, next) {
      if (test(next) && !done.isCompleted) {
        done.complete(next);
        sub.close();
      }
    });
    return done.future.timeout(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    _subscription.close();
    container.dispose();
    await link.close();
  }
}

/// Lets the in-memory messages and the listeners that react to them run.
Future<void> _deliver() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Peer operator;
  late _Peer manual;

  setUp(() async {
    final a = _Link();
    final b = _Link();
    a.peer = b;
    b.peer = a;
    operator = _Peer(a);
    manual = _Peer(b);
    await manual.controller.start(
      moduleCount: 3,
      transport: b,
      authority: false,
    );
    await operator.controller.start(moduleCount: 3, transport: a);
  });

  tearDown(() async {
    await operator.dispose();
    await manual.dispose();
  });

  test('the manual replicates the operator loadout and timer', () async {
    final replica = await manual.waitFor(
      (state) => state.loadout.seed == operator.state.loadout.seed,
    );
    expect(
      replica.loadout.modules.map((module) => module.type),
      operator.state.loadout.modules.map((module) => module.type),
    );
    expect(replica.timeLeft, lessThanOrEqualTo(const Duration(minutes: 5)));
    expect(replica.status, BombEngineStatus.running);
  });

  test(
    'solves and strikes reach the manual without waiting a second',
    () async {
      await manual.waitFor(
        (s) => s.loadout.seed == operator.state.loadout.seed,
      );

      operator.controller.dispatch(const SolveModuleRequested(0));
      await operator.waitFor((s) => s.loadout.modules[0].solved);
      await _deliver();
      expect(manual.state.loadout.modules[0].solved, isTrue);

      operator.controller.dispatch(const StrikeRequested(1));
      await operator.waitFor((s) => s.strikes == 1);
      await _deliver();
      expect(manual.state.strikes, 1);
      expect(manual.state.loadout.modules[1].failureCount, 1);
    },
  );

  test('a stale snapshot never rolls the manual back', () async {
    await manual.waitFor((s) => s.loadout.seed == operator.state.loadout.seed);
    operator.controller.dispatch(const StrikeRequested(0));
    await manual.waitFor((s) => s.strikes == 1);

    manual.link._incoming.add(
      GameMessage(
        session: 'test',
        type: 'snapshot',
        revision: 0,
        payload: {
          'timeLeftMs': 300000,
          'strikes': 0,
          'solvedModules': const <int>[],
          'status': 'running',
          'seed': operator.state.loadout.seed,
          'modules': operator.state.loadout.toJson(),
        },
      ),
    );
    await _deliver();
    expect(manual.state.strikes, 1);
  });

  test('module focus is mirrored in both directions', () async {
    await manual.waitFor((s) => s.loadout.seed == operator.state.loadout.seed);

    operator.controller.dispatch(const ModuleOpened(2));
    await manual.waitFor((s) => s.activeModule == 2);
    manual.controller.dispatch(const ManualFocusRequested(1));
    await operator.waitFor((s) => s.manualFocus == 1);

    operator.controller.dispatch(const ModuleClosed());
    await manual.waitFor((s) => s.activeModule == null);
  });

  test('defusing every module ends the game on both sides', () async {
    await manual.waitFor((s) => s.loadout.seed == operator.state.loadout.seed);
    for (var index = 0; index < 3; index++) {
      operator.controller.dispatch(SolveModuleRequested(index));
    }
    await operator.waitFor((s) => s.status == BombEngineStatus.defused);
    await manual.waitFor((s) => s.status == BombEngineStatus.defused);

    await operator.controller.dispatch(
      const GameEndAnnounced(defused: true, reason: 'game_finished'),
    );
    final result = await manual.waitFor((s) => s.connectionNotice != null);
    expect(result.connectionNotice, 'A bomba foi desarmada.');
  });

  test('a dropped connection abandons both players', () async {
    await manual.waitFor((s) => s.loadout.seed == operator.state.loadout.seed);
    operator.link.dropConnection();
    manual.link.dropConnection();

    await operator.waitFor((s) => s.status == BombEngineStatus.abandoned);
    final replica = await manual.waitFor(
      (s) => s.status == BombEngineStatus.abandoned,
    );
    expect(replica.connectionNotice, 'A ligação ao outro jogador foi perdida.');
    expect(
      operator.state.connectionNotice,
      'A ligação ao outro jogador foi perdida.',
    );
  });
}
