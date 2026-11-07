import 'package:what_did_you_press/features/game/bomb_engine.dart';

sealed class GameEvent {
  const GameEvent();
}

final class SolveModuleRequested extends GameEvent {
  const SolveModuleRequested(this.index);
  final int index;
}

final class StrikeRequested extends GameEvent {
  const StrikeRequested();
}

final class EngineStateReceived extends GameEvent {
  const EngineStateReceived(this.state);
  final BombEngineState state;
}
