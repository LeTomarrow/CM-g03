import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/services/game_protocol.dart';

final gameControllerProvider =
    NotifierProvider.autoDispose<GameController, GameState>(GameController.new);

/// MVI controller: external inputs become state transitions, while transport
/// and the isolate remain implementation details of this class.
class GameController extends Notifier<GameState> {
  BombEngine? _engine;
  StreamSubscription<BombEngineState>? _engineSubscription;
  RoomService? _roomService;
  int _revision = 0;
  int? _lastPublishedSecond;
  int _lastRemoteRevision = -1;
  StreamSubscription<GameMessage>? _remoteSubscription;

  @override
  GameState build() {
    ref.onDispose(() {
      _engineSubscription?.cancel();
      _remoteSubscription?.cancel();
      _engine?.dispose();
    });
    return GameState.initial();
  }

  Future<void> start({
    required int moduleCount,
    RoomService? roomService,
    bool authority = true,
  }) async {
    if (state.started) return;
    _roomService = roomService;
    if (!authority) {
      state = state.copyWith(started: true);
      if (roomService != null) {
        _remoteSubscription = roomService.gameMessages.listen((message) {
          if (message.type == 'snapshot') _applyRemoteSnapshot(message);
        });
      }
      return;
    }
    final engine = await BombEngine.start(
      duration: const Duration(minutes: 5),
      moduleCount: moduleCount,
      maxStrikes: 3,
    );
    if (!ref.mounted) {
      await engine.dispose();
      return;
    }
    _engine = engine;
    state = state.copyWith(
      started: true,
      loadout: BombLoadout.generate(
        seed: DateTime.now().microsecondsSinceEpoch,
        moduleCount: moduleCount,
      ),
    );
    _engineSubscription = engine.states.listen(_onEngineState);
  }

  void _applyRemoteSnapshot(GameMessage message) {
    if (!ref.mounted || message.revision <= _lastRemoteRevision) return;
    final payload = message.payload;
    final modules = payload['modules'];
    final seed = payload['seed'];
    if (modules is! List || seed is! int) return;
    _lastRemoteRevision = message.revision;
    final loadout = BombLoadout.fromJson(seed: seed, json: modules);
    state = state.copyWith(
      timeLeft: Duration(milliseconds: payload['timeLeftMs'] as int),
      strikes: payload['strikes'] as int,
      status: BombEngineStatus.values.byName(payload['status'] as String),
      loadout: loadout,
    );
  }

  void solveModule(int index) {
    _dispatch(SolveModuleRequested(index));
  }

  void registerStrike(int index) {
    _dispatch(StrikeRequested(index));
  }

  void _onEngineState(BombEngineState next) {
    _dispatch(EngineStateReceived(next));
  }

  void _dispatch(GameEvent event) {
    switch (event) {
      case SolveModuleRequested(:final index):
        _engine?.solveModule(index);
      case StrikeRequested(:final index):
        _engine?.registerStrike(index);
      case EngineStateReceived(:final state):
        _reduce(state);
    }
  }

  void _reduce(BombEngineState next) {
    if (!ref.mounted) return;
    final modules = [
      for (var index = 0; index < state.loadout.modules.length; index++)
        state.loadout.modules[index].copyWith(
          status: next.solvedModules.contains(index)
              ? ModuleStatus.solved
              : ModuleStatus.pending,
          failureCount: next.failureCounts[index] ?? 0,
        ),
    ];
    state = state.copyWith(
      timeLeft: next.timeLeft,
      strikes: next.strikes,
      status: next.status,
      loadout: state.loadout.copyWith(modules: modules),
    );
    final service = _roomService;
    final second = next.timeLeft.inSeconds;
    if (service == null ||
        (_lastPublishedSecond == second &&
            next.status == BombEngineStatus.running)) {
      return;
    }
    _lastPublishedSecond = second;
    unawaited(
      service.sendGameMessage(
        type: 'snapshot',
        revision: _revision++,
        payload: {
          'timeLeftMs': next.timeLeft.inMilliseconds,
          'strikes': next.strikes,
          'solvedModules': next.solvedModules.toList(),
          'status': next.status.name,
          'seed': state.loadout.seed,
          'modules': state.loadout.toJson(),
        },
      ),
    );
  }
}
