import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/services/game_protocol.dart';

/// Every input of the game, dispatched through `GameController.dispatch`.
/// Views send intents; the controller itself feeds engine and peer events.
sealed class GameEvent {
  const GameEvent();
}

// ── Operator intents ────────────────────────────────────────────────────────

/// The operator opened a module; the manual follows it.
final class ModuleOpened extends GameEvent {
  const ModuleOpened(this.index);
  final int index;
}

final class ModuleClosed extends GameEvent {
  const ModuleClosed();
}

final class SolveModuleRequested extends GameEvent {
  const SolveModuleRequested(this.index);
  final int index;
}

final class StrikeRequested extends GameEvent {
  const StrikeRequested(this.index);
  final int index;
}

/// Live drawing while the stroke is in progress (rate limited).
final class DrawingChanged extends GameEvent {
  const DrawingChanged(this.strokes);
  final List<Stroke> strokes;
}

/// A finished stroke, sent immediately.
final class DrawingCompleted extends GameEvent {
  const DrawingCompleted(this.strokes);
  final List<Stroke> strokes;
}

/// Tells the partner the game is over. `reason` is `game_finished` or why the
/// local player left (e.g. `operator_left`).
final class GameEndAnnounced extends GameEvent {
  const GameEndAnnounced({required this.defused, required this.reason});
  final bool defused;
  final String reason;
}

// ── Manual intents ──────────────────────────────────────────────────────────

/// The manual points the operator to a module.
final class ManualFocusRequested extends GameEvent {
  const ManualFocusRequested(this.index);
  final int index;
}

final class HackLaunched extends GameEvent {
  const HackLaunched(this.hack);
  final String hack;
}

final class HackCountered extends GameEvent {
  const HackCountered();
}

// ── Both players ────────────────────────────────────────────────────────────

final class PlayerNameSet extends GameEvent {
  const PlayerNameSet(this.name);
  final String name;
}

// ── System events (not sent by views) ───────────────────────────────────────

final class EngineStateReceived extends GameEvent {
  const EngineStateReceived(this.state);
  final BombEngineState state;
}

final class RemoteMessageReceived extends GameEvent {
  const RemoteMessageReceived(this.message);
  final GameMessage message;
}
