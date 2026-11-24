import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/features/game/game_state.dart';

/// Pure state transitions of the game. They never send, schedule or touch the
/// engine; GameController runs those effects. Each reducer returns the same
/// instance when it ignores its input, so callers can detect "no change".

/// Authoritative isolate state → rendered state (operator only).
GameState reduceEngineState(GameState state, BombEngineState next) {
  final modules = [
    for (var index = 0; index < state.loadout.modules.length; index++)
      state.loadout.modules[index].copyWith(
        status: next.solvedModules.contains(index)
            ? ModuleStatus.solved
            : ModuleStatus.pending,
        failureCount: next.failureCounts[index] ?? 0,
      ),
  ];
  return state.copyWith(
    timeLeft: next.timeLeft,
    strikes: next.strikes,
    status: next.status,
    loadout: state.loadout.copyWith(modules: modules),
  );
}

/// Whether solved modules, strikes or failures differ (time is ignored).
bool scoreChanged(BombEngineState a, BombEngineState b) {
  if (a.strikes != b.strikes ||
      a.solvedModules.length != b.solvedModules.length ||
      !a.solvedModules.containsAll(b.solvedModules) ||
      a.failureCounts.length != b.failureCounts.length) {
    return true;
  }
  return a.failureCounts.entries.any(
    (entry) => b.failureCounts[entry.key] != entry.value,
  );
}

/// Payload of a `snapshot` message, the inverse of [reduceSnapshot].
Map<String, dynamic> encodeSnapshot(GameState state, BombEngineState next) => {
  'timeLeftMs': next.timeLeft.inMilliseconds,
  'strikes': next.strikes,
  'solvedModules': next.solvedModules.toList(),
  'status': next.status.name,
  'seed': state.loadout.seed,
  'modules': state.loadout.toJson(),
};

/// Operator snapshot → manual state. Ignored after the session ended.
GameState reduceSnapshot(GameState state, Map<String, dynamic> payload) {
  if (state.connectionNotice != null) return state;
  final modules = payload['modules'];
  final seed = payload['seed'];
  final timeLeftMs = payload['timeLeftMs'];
  final strikes = payload['strikes'];
  final status = BombEngineStatus.values.asNameMap()[payload['status']];
  if (modules is! List ||
      seed is! int ||
      timeLeftMs is! int ||
      strikes is! int ||
      status == null) {
    return state;
  }
  return state.copyWith(
    timeLeft: Duration(milliseconds: timeLeftMs),
    strikes: strikes,
    status: status,
    loadout: BombLoadout.fromJson(seed: seed, json: modules),
  );
}

/// `ended` from the partner (or injected by the transport on disconnect).
///
/// A finished game sets its final status. A departure only marks the session
/// as ended: without an engine the result is `abandoned` right away, while the
/// operator keeps its status until the engine confirms the abandonment.
/// A notice already shown, or a finished bomb, is never replaced by a
/// departure.
GameState reduceEnded(
  GameState state,
  Map<String, dynamic> payload, {
  required bool hasEngine,
}) {
  final reason = payload['reason'];
  if (state.connectionNotice != null ||
      (state.status != BombEngineStatus.running && reason != 'game_finished')) {
    return state;
  }
  final finished = reason == 'game_finished'
      ? BombEngineStatus.values.asNameMap()[payload['status']]
      : null;
  return state.copyWith(
    status: finished ?? (hasEngine ? state.status : BombEngineStatus.abandoned),
    connectionNotice: switch (reason) {
      'game_finished' =>
        finished == BombEngineStatus.defused
            ? 'A bomba foi desarmada.'
            : 'A bomba explodiu.',
      'opponent_left' => 'O outro jogador saiu da sala.',
      'operator_left' => 'O operador saiu da sala.',
      'connection_lost' => 'A ligação ao outro jogador foi perdida.',
      _ => 'A sessão foi encerrada.',
    },
  );
}

/// `hack` and `command` messages.
GameState reducePeerCommand(
  GameState state,
  String type,
  Map<String, dynamic> payload,
) {
  if (type == 'hack') {
    // The operator launches attacks; the manual reports the counter-attack.
    final countered = payload['countered'];
    if (countered != null) {
      return countered == state.activeHack
          ? state.copyWith(clearHack: true)
          : state;
    }
    final hack = payload['hack'];
    return hack is String ? state.copyWith(activeHack: hack) : state;
  }
  if (type != 'command') return state;
  final command = payload['command'];
  if (command == 'presence') {
    final away = payload['away'];
    return away is bool ? state.copyWith(partnerAway: away) : state;
  }
  if (command == 'player_name') {
    final name = payload['name'];
    return name is String && name.isNotEmpty
        ? state.copyWith(partnerName: name)
        : state;
  }
  if (!state.started || command != 'module_focus') return state;
  final index = payload['moduleIndex'];
  final fromOperator = payload['source'] == 'defuser';
  if (fromOperator && index == null) {
    return state.copyWith(clearActiveModule: true);
  }
  if (index is! int || index < 0 || index >= state.loadout.modules.length) {
    return state;
  }
  return fromOperator
      ? state.copyWith(activeModule: index)
      : state.copyWith(manualFocus: index);
}
