import 'package:what_did_you_press/features/game/bomb_engine.dart';

/// Immutable state rendered by both bomb views.
class GameState {
  const GameState({
    required this.timeLeft,
    required this.strikes,
    required this.solvedModules,
    required this.status,
    this.started = false,
  });

  factory GameState.initial() => const GameState(
    timeLeft: Duration(minutes: 5),
    strikes: 0,
    solvedModules: <int>{},
    status: BombEngineStatus.running,
  );

  final Duration timeLeft;
  final int strikes;
  final Set<int> solvedModules;
  final BombEngineStatus status;
  final bool started;

  GameState copyWith({
    Duration? timeLeft,
    int? strikes,
    Set<int>? solvedModules,
    BombEngineStatus? status,
    bool? started,
  }) => GameState(
    timeLeft: timeLeft ?? this.timeLeft,
    strikes: strikes ?? this.strikes,
    solvedModules: solvedModules ?? this.solvedModules,
    status: status ?? this.status,
    started: started ?? this.started,
  );
}
