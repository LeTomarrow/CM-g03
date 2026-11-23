import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/features/game/drawing_codec.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/game_reducer.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/services/game_protocol.dart';
import 'package:what_did_you_press/services/game_transport.dart';

final gameControllerProvider =
    NotifierProvider.autoDispose<GameController, GameState>(GameController.new);

/// MVI: every input — view intents, isolate state and peer messages — enters
/// as a [GameEvent] through [dispatch]. The pure reducers in game_reducer.dart
/// compute the next [GameState]; this class only runs the effects (engine
/// commands and transport messages).
class GameController extends Notifier<GameState> {
  /// Heartbeats without any message before the partner is shown as silent.
  static const silenceWarningTicks = 4;

  /// Heartbeats without any message before the session counts as lost.
  static const silenceLimitTicks = 15;

  BombEngine? _engine;
  StreamSubscription<BombEngineState>? _engineSubscription;
  GameTransport? _transport;
  StreamSubscription<GameMessage>? _remoteSubscription;
  StreamSubscription<bool>? _linkSubscription;
  int _revision = 0;
  BombEngineState? _lastPublished;
  int _lastRemoteRevision = -1;
  Timer? _drawingTimer;
  List<Stroke>? _pendingDrawing;
  Timer? _heartbeat;
  int _silentTicks = 0;

  @override
  GameState build() {
    ref.onDispose(() {
      _engineSubscription?.cancel();
      _remoteSubscription?.cancel();
      _linkSubscription?.cancel();
      _drawingTimer?.cancel();
      _heartbeat?.cancel();
      _engine?.dispose();
    });
    return GameState.initial();
  }

  /// Lifecycle, not an intent: connects the transport and, on the authority
  /// (operator), spawns the engine that owns time and score.
  Future<void> start({
    required int moduleCount,
    GameTransport? transport,
    bool authority = true,
  }) async {
    if (state.started) return;
    _transport = transport;
    _remoteSubscription = transport?.gameMessages.listen(
      (message) => dispatch(RemoteMessageReceived(message)),
    );
    _linkSubscription = transport?.linkStatus.listen(
      (up) => dispatch(LinkStatusChanged(up: up)),
    );
    if (transport != null) {
      _heartbeat = Timer.periodic(
        const Duration(seconds: 1),
        (_) => dispatch(const HeartbeatTick()),
      );
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
    // The partner may have left while the isolate was starting.
    if (!ref.mounted || state.status != BombEngineStatus.running) {
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
    _engineSubscription = engine.states.listen(
      (next) => dispatch(EngineStateReceived(next)),
    );
  }

  /// Single entry point. Completes when the event's effects were handed to
  /// the transport; only [GameEndAnnounced] reports a send failure.
  Future<void> dispatch(GameEvent event) async {
    if (!ref.mounted) return;
    switch (event) {
      case ModuleOpened(:final index):
        _focus(index, source: 'defuser');
      case ModuleClosed():
        _focus(null, source: 'defuser');
      case ManualFocusRequested(:final index):
        _focus(index, source: 'manual');
      case SolveModuleRequested(:final index):
        _engine?.solveModule(index);
      case StrikeRequested(:final index):
        _engine?.registerStrike(index);
      case PlayerNameSet(:final name):
        final value = name.trim();
        if (value.isEmpty) return;
        state = state.copyWith(playerName: value);
        _send('command', {'command': 'player_name', 'name': value});
      case AppLifecycleChanged(:final foreground):
        _send('command', {'command': 'presence', 'away': !foreground});
      case HackLaunched(:final hack):
        _send('hack', {'hack': hack});
      case HackCountered():
        state = state.copyWith(clearHack: true);
      case DrawingChanged(:final strokes):
        _throttleDrawing(strokes);
      case DrawingCompleted(:final strokes):
        _cancelDrawing();
        _send('drawing', {
          'mode': 'replace',
          'strokes': encodeDrawing(strokes),
        });
      case GameEndAnnounced(:final defused, :final reason):
        await _transport?.sendGameMessage(
          type: 'ended',
          revision: _revision++,
          payload: {
            'reason': reason,
            if (reason == 'game_finished')
              'status': defused ? 'defused' : 'exploded',
          },
        );
      case EngineStateReceived(state: final next):
        _onEngineState(next);
      case HeartbeatTick():
        _onHeartbeat();
      case LinkStatusChanged(:final up):
        if (state.connectionNotice != null) return;
        // While the transport heals the link, its own window decides.
        _silentTicks = 0;
        state = state.copyWith(reconnecting: !up, partnerSilent: false);
      case RemoteMessageReceived(:final message):
        _silentTicks = 0;
        if (state.partnerSilent) state = state.copyWith(partnerSilent: false);
        _onRemote(message);
    }
  }

  /// Both peers ping every second, so silence means the link (or the
  /// partner's app) stopped; the DataChannel itself can take ~30 s to fail.
  void _onHeartbeat() {
    if (state.connectionNotice != null) {
      _heartbeat?.cancel();
      return;
    }
    if (state.reconnecting) return;
    _send('ping', const {});
    _silentTicks++;
    if (_silentTicks >= silenceLimitTicks) {
      _heartbeat?.cancel();
      _onRemote(
        const GameMessage(
          session: '',
          type: 'ended',
          revision: 0,
          payload: {'reason': 'connection_lost'},
        ),
      );
    } else if (_silentTicks >= silenceWarningTicks && !state.partnerSilent) {
      state = state.copyWith(partnerSilent: true);
    }
  }

  void _onEngineState(BombEngineState next) {
    state = reduceEngineState(state, next);
    if (_transport == null || state.connectionNotice != null) return;
    final last = _lastPublished;
    // The timer is published once per second; score changes immediately.
    if (last != null &&
        next.status == BombEngineStatus.running &&
        last.timeLeft.inSeconds == next.timeLeft.inSeconds &&
        !scoreChanged(last, next)) {
      return;
    }
    _lastPublished = next;
    _send('snapshot', encodeSnapshot(state, next));
  }

  void _onRemote(GameMessage message) {
    switch (message.type) {
      case 'ping':
        return;
      case 'drawing':
        final strokes = applyDrawingPayload(liveDrawing.value, message.payload);
        if (strokes != null) liveDrawing.value = strokes;
      case 'snapshot':
        if (message.revision <= _lastRemoteRevision) return;
        final next = reduceSnapshot(state, message.payload);
        if (identical(next, state)) return;
        _lastRemoteRevision = message.revision;
        state = next;
      case 'ended':
        final next = reduceEnded(
          state,
          message.payload,
          hasEngine: _engine != null,
        );
        if (identical(next, state)) return;
        state = next;
        if (message.payload['reason'] != 'game_finished') {
          // The partner is gone: stop sending, and end on the engine's terms.
          _cancelDrawing();
          _engine?.abandon();
        }
      default:
        state = reducePeerCommand(state, message.type, message.payload);
    }
  }

  void _focus(int? index, {required String source}) => _send('command', {
    'command': 'module_focus',
    'moduleIndex': index,
    'source': source,
  });

  /// Sends the operator's drawing at most every 100 ms. Drawing is
  /// presentation input, so it is not part of the authoritative bomb state.
  void _throttleDrawing(List<Stroke> strokes) {
    _pendingDrawing = strokes;
    _drawingTimer ??= Timer(const Duration(milliseconds: 100), () {
      _drawingTimer = null;
      final pending = _pendingDrawing;
      _pendingDrawing = null;
      if (pending == null) return;
      _send('drawing', {'mode': 'replace', 'strokes': encodeDrawing(pending)});
    });
  }

  void _cancelDrawing() {
    _drawingTimer?.cancel();
    _drawingTimer = null;
    _pendingDrawing = null;
  }

  /// Fire-and-forget: a peer that already left must not surface as an
  /// uncaught async error; the `ended` flow reports the disconnection.
  void _send(String type, Map<String, dynamic> payload) {
    final transport = _transport;
    if (transport == null) return;
    unawaited(
      transport
          .sendGameMessage(type: type, revision: _revision++, payload: payload)
          .catchError((Object _) {}),
    );
  }
}
