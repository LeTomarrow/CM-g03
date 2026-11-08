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
    this.activeModule,
    this.connectionNotice,
    this.playerName = 'Operador',
    this.partnerName = 'Parceiro',
    this.activeHack,
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
  final int? activeModule;
  final String? connectionNotice;
  final String playerName;
  final String partnerName;
  final String? activeHack;
  final bool started;

  GameState copyWith({
    Duration? timeLeft,
    int? strikes,
    BombEngineStatus? status,
    bool? started,
    BombLoadout? loadout,
    int? manualFocus,
    String? connectionNotice,
    int? activeModule,
    bool clearActiveModule = false,
    String? playerName,
    String? partnerName,
    String? activeHack,
    bool clearHack = false,
  }) => GameState(
    timeLeft: timeLeft ?? this.timeLeft,
    strikes: strikes ?? this.strikes,
    status: status ?? this.status,
    started: started ?? this.started,
    loadout: loadout ?? this.loadout,
    manualFocus: manualFocus ?? this.manualFocus,
    connectionNotice: connectionNotice ?? this.connectionNotice,
    activeModule: clearActiveModule ? null : activeModule ?? this.activeModule,
    playerName: playerName ?? this.playerName,
    partnerName: partnerName ?? this.partnerName,
    activeHack: clearHack ? null : activeHack ?? this.activeHack,
  );
}
