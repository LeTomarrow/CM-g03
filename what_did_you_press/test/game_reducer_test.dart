import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/features/game/game_reducer.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/features/lobby_controller.dart';
import 'package:what_did_you_press/services/bomb_service.dart';

GameState _started() => GameState.initial().copyWith(
  started: true,
  loadout: BombLoadout.generate(seed: 42, moduleCount: 3),
);

void main() {
  group('reduceEngineState', () {
    test('marks solved modules and failure counts from the engine', () {
      final next = reduceEngineState(
        _started(),
        const BombEngineState(
          timeLeft: Duration(seconds: 90),
          strikes: 1,
          solvedModules: {1},
          failureCounts: {0: 1},
          status: BombEngineStatus.running,
        ),
      );
      expect(next.timeLeft, const Duration(seconds: 90));
      expect(next.strikes, 1);
      expect(next.loadout.modules[1].solved, isTrue);
      expect(next.loadout.modules[0].failureCount, 1);
    });
  });

  group('reduceSnapshot', () {
    test('round-trips the operator snapshot on the manual', () {
      final operator = _started();
      const engine = BombEngineState(
        timeLeft: Duration(seconds: 30),
        strikes: 2,
        solvedModules: {},
        failureCounts: {},
        status: BombEngineStatus.running,
      );
      final manual = reduceSnapshot(
        GameState.initial(),
        encodeSnapshot(operator, engine),
      );
      expect(manual.timeLeft, const Duration(seconds: 30));
      expect(manual.strikes, 2);
      expect(manual.loadout.seed, 42);
      expect(manual.loadout.modules, hasLength(3));
    });

    test('ignores malformed payloads and snapshots after the session', () {
      final state = GameState.initial();
      expect(identical(reduceSnapshot(state, {'seed': 'x'}), state), isTrue);
      final ended = state.copyWith(connectionNotice: 'fim');
      expect(identical(reduceSnapshot(ended, {}), ended), isTrue);
    });
  });

  group('reduceEnded', () {
    test('a departure abandons a player without an engine', () {
      final next = reduceEnded(GameState.initial(), {
        'reason': 'opponent_left',
      }, hasEngine: false);
      expect(next.status, BombEngineStatus.abandoned);
      expect(next.connectionNotice, 'O outro jogador saiu da sala.');
    });

    test('the operator waits for the engine to confirm abandonment', () {
      final next = reduceEnded(GameState.initial(), {
        'reason': 'connection_lost',
      }, hasEngine: true);
      expect(next.status, BombEngineStatus.running);
      expect(next.connectionNotice, isNotNull);
    });

    test('a departure never replaces a finished result', () {
      final finished = reduceEnded(GameState.initial(), {
        'reason': 'game_finished',
        'status': 'defused',
      }, hasEngine: false);
      expect(finished.status, BombEngineStatus.defused);
      final after = reduceEnded(finished, {
        'reason': 'connection_lost',
      }, hasEngine: false);
      expect(identical(after, finished), isTrue);
    });

    test('an unknown final status does not throw', () {
      final next = reduceEnded(GameState.initial(), {
        'reason': 'game_finished',
        'status': 'bogus',
      }, hasEngine: false);
      expect(next.status, BombEngineStatus.abandoned);
    });
  });

  group('reducePeerCommand', () {
    test('module focus is bounded and depends on the source', () {
      final state = _started();
      final manual = reducePeerCommand(state, 'command', {
        'command': 'module_focus',
        'moduleIndex': 2,
        'source': 'manual',
      });
      expect(manual.manualFocus, 2);
      final opened = reducePeerCommand(state, 'command', {
        'command': 'module_focus',
        'moduleIndex': 1,
        'source': 'defuser',
      });
      expect(opened.activeModule, 1);
      final closed = reducePeerCommand(opened, 'command', {
        'command': 'module_focus',
        'moduleIndex': null,
        'source': 'defuser',
      });
      expect(closed.activeModule, isNull);
      final outOfRange = reducePeerCommand(state, 'command', {
        'command': 'module_focus',
        'moduleIndex': 9,
        'source': 'manual',
      });
      expect(identical(outOfRange, state), isTrue);
    });

    test('partner name and hacks update the state', () {
      final named = reducePeerCommand(GameState.initial(), 'command', {
        'command': 'player_name',
        'name': 'Sentinela',
      });
      expect(named.partnerName, 'Sentinela');
      final hacked = reducePeerCommand(named, 'hack', {'hack': 'glitch'});
      expect(hacked.activeHack, 'glitch');
    });
  });

  test('a partner who left re-arms the world bomb instead of exploding it', () {
    expect(worldOutcomeFor(BombEngineStatus.abandoned), BombOutcome.abandoned);
    expect(worldOutcomeFor(BombEngineStatus.defused), BombOutcome.defused);
    expect(worldOutcomeFor(BombEngineStatus.exploded), BombOutcome.exploded);
  });
}
