import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/core/drawing.dart';
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
  Timer? _drawingTimer;
  Map<String, dynamic>? _pendingDrawing;

  @override
  GameState build() {
    ref.onDispose(() {
      _engineSubscription?.cancel();
      _remoteSubscription?.cancel();
      _drawingTimer?.cancel();
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
    if (roomService != null) {
      _remoteSubscription = roomService.gameMessages.listen(_onGameMessage);
    }
    if (!authority) {
      state = state.copyWith(started: true);
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

  void sendModuleFocus(int index) {
    final service = _roomService;
    if (service == null) return;
    unawaited(
      service.sendGameMessage(
        type: 'command',
        revision: _revision++,
        payload: {
          'command': 'module_focus',
          'moduleIndex': index,
          'source': 'manual',
        },
      ),
    );
  }

  void publishPlayerName(String name) {
    final value = name.trim();
    if (value.isEmpty) return;
    state = state.copyWith(playerName: value);
    final service = _roomService;
    if (service == null) return;
    unawaited(service.sendGameMessage(
      type: 'command', revision: _revision++,
      payload: {'command': 'player_name', 'name': value},
    ));
  }

  void publishHack(String hack) {
    final service = _roomService;
    if (service == null) return;
    unawaited(service.sendGameMessage(
      type: 'hack', revision: _revision++, payload: {'hack': hack},
    ));
  }

  void clearHack() => state = state.copyWith(clearHack: true);

  void publishModuleFocus(int? index) {
    final service = _roomService;
    if (service == null) return;
    unawaited(
      service.sendGameMessage(
        type: 'command',
        revision: _revision++,
        payload: {
          'command': 'module_focus',
          'moduleIndex': index,
          'source': 'defuser',
        },
      ),
    );
  }

  Future<void> publishGameEnded(bool defused, {String reason = 'game_finished'}) async {
    final service = _roomService;
    if (service == null) return;
    await service.sendGameMessage(
      type: 'ended',
      revision: _revision++,
      payload: {
        'reason': reason,
        if (reason == 'game_finished') 'status': defused ? 'defused' : 'exploded',
      },
    );
  }

  /// Sends the defuser's drawing at a bounded rate. Drawing is presentation
  /// input, so it is not part of the authoritative bomb state.
  void publishDrawing(List<Stroke> strokes) {
    _pendingDrawing = {'mode': 'replace', 'strokes': _encodeDrawing(strokes)};
    if (_drawingTimer != null) return;
    _drawingTimer = Timer(const Duration(milliseconds: 100), () {
      _drawingTimer = null;
      final drawing = _pendingDrawing;
      _pendingDrawing = null;
      if (drawing == null || _roomService == null) return;
      _sendDrawingPayload(drawing);
    });
  }

  void publishDrawingSnapshot(List<Stroke> strokes) {
    _drawingTimer?.cancel();
    _drawingTimer = null;
    _pendingDrawing = null;
    _sendDrawingPayload({
      'mode': 'replace',
      'strokes': _encodeDrawing(strokes),
    });
  }

  void _sendDrawingPayload(Map<String, dynamic>? payload) {
    final service = _roomService;
    if (payload == null || service == null) return;
    unawaited(
      service.sendGameMessage(
        type: 'drawing',
        revision: _revision++,
        payload: payload,
      ),
    );
  }

  List<List<int>> _encodeStroke(Stroke stroke) {
    const maxPoints = 80;
    if (stroke.length <= maxPoints) {
      return [
        for (final point in stroke)
          [(point.dx * 1000).round(), (point.dy * 1000).round()],
      ];
    }
    return [
      for (var i = 0; i < maxPoints; i++)
        [
          (stroke[(i * (stroke.length - 1) / (maxPoints - 1)).round()].dx *
                  1000)
              .round(),
          (stroke[(i * (stroke.length - 1) / (maxPoints - 1)).round()].dy *
                  1000)
              .round(),
        ],
    ];
  }

  List<List<List<int>>> _encodeDrawing(List<Stroke> strokes) {
    var remaining = 800;
    final encoded = <List<List<int>>>[];
    for (final stroke in strokes) {
      if (remaining <= 0) break;
      final points = _encodeStroke(stroke).take(remaining).toList();
      encoded.add(points);
      remaining -= points.length;
    }
    return encoded;
  }

  void _onGameMessage(GameMessage message) {
    if (message.type == 'drawing') {
      _applyDrawingMessage(message.payload);
      return;
    }
    if (message.type == 'ended') {
      final reason = message.payload['reason'];
      if (state.connectionNotice != null) {
        return;
      }
      final status = message.payload['status'];
      state = state.copyWith(
        status: reason == 'game_finished' && status is String
            ? BombEngineStatus.values.byName(status)
            : BombEngineStatus.running,
        connectionNotice: switch (reason) {
          'game_finished' =>
            status == 'defused'
                ? 'A bomba foi desarmada.'
                : 'A bomba explodiu.',
          'opponent_left' => 'O outro jogador saiu da sala.',
          'operator_left' => 'O operador saiu da sala.',
          'connection_lost' => 'A ligação ao outro jogador foi perdida.',
          _ => 'A sessão foi encerrada.',
        },
      );
      return;
    }
    if (message.type == 'snapshot') {
      _applyRemoteSnapshot(message);
      return;
    }
    if (message.type == 'hack') {
      final hack = message.payload['hack'];
      if (hack is String) state = state.copyWith(activeHack: hack);
      return;
    }
    if (message.type != 'command') return;
    if (message.payload['command'] == 'player_name') {
      final name = message.payload['name'];
      if (name is String && name.isNotEmpty) {
        state = state.copyWith(partnerName: name);
      }
      return;
    }
    if (!state.started) return;
    if (message.payload['command'] != 'module_focus') return;
    final source = message.payload['source'];
    final index = message.payload['moduleIndex'];
    if (source == 'defuser') {
      if (index == null) {
        state = state.copyWith(clearActiveModule: true);
      } else if (index is int &&
          index >= 0 &&
          index < state.loadout.modules.length) {
        state = state.copyWith(activeModule: index);
      }
      return;
    }
    if (index is! int || index < 0 || index >= state.loadout.modules.length) {
      return;
    }
    state = state.copyWith(manualFocus: index);
  }

  void _applyDrawingMessage(Map<String, dynamic> payload) {
    final mode = payload['mode'];
    if (mode == 'replace') {
      final rawStrokes = payload['strokes'];
      if (rawStrokes is List) {
        liveDrawing.value = rawStrokes
            .whereType<List>()
            .map(_decodeStroke)
            .toList(growable: true);
      }
      return;
    }
    final index = payload['index'];
    final rawPoints = payload['points'];
    if (index is! int || rawPoints is! List || index < 0) return;
    final strokes = List<Stroke>.of(liveDrawing.value);
    while (strokes.length <= index) {
      strokes.add(<Offset>[]);
    }
    strokes[index] = _decodeStroke(rawPoints);
    liveDrawing.value = strokes;
  }

  Stroke _decodeStroke(dynamic rawPoints) => [
    for (final rawPoint in rawPoints.whereType<List>())
      if (rawPoint.length >= 2)
        Offset(
          (rawPoint[0] as num).toDouble() / 1000,
          (rawPoint[1] as num).toDouble() / 1000,
        ),
  ];

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
