import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';

/// Immutable state rendered by both bomb views.
class GameState {
  const GameState({
    required this.timeLeft,
    required this.strikes,
    required this.status,
    required this.loadout,
    this.manualFocus,
    this.started = false,
  });

  factory GameState.initial() => GameState(
    timeLeft: Duration(minutes: 5),
    strikes: 0,
    status: BombEngineStatus.running,
    loadout: BombLoadout.generate(seed: 0),
  );

  final Duration timeLeft;
  final int strikes;
  final BombEngineStatus status;
  final BombLoadout loadout;
  final int? manualFocus;
  final bool started;

  GameState copyWith({
    Duration? timeLeft,
    int? strikes,
    BombEngineStatus? status,
    bool? started,
    BombLoadout? loadout,
    int? manualFocus,
  }) => GameState(
    timeLeft: timeLeft ?? this.timeLeft,
    strikes: strikes ?? this.strikes,
    status: status ?? this.status,
    started: started ?? this.started,
    loadout: loadout ?? this.loadout,
    manualFocus: manualFocus ?? this.manualFocus,
  );
}
