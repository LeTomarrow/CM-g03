import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/services/service_providers.dart';

/// How a finished game resolves the open-world bomb it was played on.
/// A partner who left does not destroy the bomb: it is re-armed for others.
BombOutcome worldOutcomeFor(BombEngineStatus result) => switch (result) {
  BombEngineStatus.defused => BombOutcome.defused,
  BombEngineStatus.abandoned => BombOutcome.abandoned,
  BombEngineStatus.exploded || BombEngineStatus.running => BombOutcome.exploded,
};

const _unset = Object();

class LobbyState {
  const LobbyState({
    this.connection,
    this.room,
    this.currentUserId,
    this.busy = false,
    this.error,
    this.closedNotice,
    this.startedRole,
  });

  final RoomConnection? connection;
  final Room? room;
  final String? currentUserId;
  final bool busy;
  final String? error;

  /// Set once when the session was closed remotely; the view shows a dialog.
  final String? closedNotice;

  /// Set once when both peers acknowledged the start; the view navigates.
  final PlayerRole? startedRole;

  bool get isHost => room != null && room!.hostUid == currentUserId;
  bool get opening => startedRole != null;
  bool get canStart => !busy && isHost && !opening && room?.status == 'ready';

  LobbyState copyWith({
    Object? connection = _unset,
    Object? room = _unset,
    String? currentUserId,
    bool? busy,
    Object? error = _unset,
    Object? closedNotice = _unset,
    PlayerRole? startedRole,
  }) => LobbyState(
    connection: connection == _unset
        ? this.connection
        : connection as RoomConnection?,
    room: room == _unset ? this.room : room as Room?,
    currentUserId: currentUserId ?? this.currentUserId,
    busy: busy ?? this.busy,
    error: error == _unset ? this.error : error as String?,
    closedNotice: closedNotice == _unset
        ? this.closedNotice
        : closedNotice as String?,
    startedRole: startedRole ?? this.startedRole,
  );
}

/// What the game screens take over once the lobby is left behind.
typedef LobbySession = ({
  RoomService service,
  PlayerRole role,
  void Function(BombEngineStatus result)? onFinished,
});

/// One lobby per page; `bombId` is the open-world bomb claimed by this player,
/// who then hosts as the operator with fixed roles.
final lobbyControllerProvider = NotifierProvider.autoDispose
    .family<LobbyController, LobbyState, String?>(LobbyController.new);

/// MVVM ViewModel of [LobbyPage]: owns the RoomService session, turns its
/// stream and errors into [LobbyState], and hands the session to the game.
class LobbyController extends Notifier<LobbyState> {
  LobbyController(this.bombId);

  final String? bombId;
  late RoomService Function() _roomFactory;
  late RoomService _rooms;
  BombService? _bombs;
  StreamSubscription<Room?>? _subscription;
  bool _closureHandled = false;
  bool _handedOff = false;

  @override
  LobbyState build() {
    _roomFactory = ref.read(roomServiceFactoryProvider);
    _rooms = _newRoomService();
    if (bombId != null) {
      _bombs = ref.read(bombServiceProvider);
      // A bomb room is created as soon as the lobby opens.
      Future.microtask(() => connect(create: true));
    }
    ref.onDispose(() {
      _subscription?.cancel();
      if (_handedOff) return;
      // Leaving before the game starts frees the bomb for other players.
      final id = bombId;
      if (id != null) _bombs?.resolveBomb(id, BombOutcome.abandoned).ignore();
      unawaited(_rooms.close());
    });
    return const LobbyState();
  }

  RoomService _newRoomService() {
    final service = _roomFactory();
    if (bombId != null) service.rolesLocked = true;
    return service;
  }

  bool get rolesFixed {
    final room = state.room;
    return state.busy ||
        room == null ||
        state.opening ||
        bombId != null ||
        room.rolesLocked;
  }

  Future<void> connect({required bool create, String code = ''}) async {
    if (!ref.mounted || state.busy || state.connection != null) return;
    _closureHandled = false;
    state = state.copyWith(busy: true, error: null, closedNotice: null);
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _rooms.close();
      _rooms = _newRoomService();
      final connection = create
          ? await _rooms.createRoom()
          : await _rooms.joinRoom(code);
      if (!ref.mounted) {
        await _rooms.close();
        return;
      }
      state = state.copyWith(
        connection: connection,
        currentUserId: _rooms.currentUserId,
      );
      _subscription = _rooms
          .watchRoom(connection.roomId)
          .listen(_onRoom, onError: _onRoomError);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _errorMessage(error));
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  void _onRoom(Room? room) {
    if (!ref.mounted || _closureHandled) return;
    if (room == null || room.status == 'closed') {
      // Once started, the game screens report the disconnection instead.
      if (state.opening) return;
      final isHost = (room ?? state.room)?.hostUid == _rooms.currentUserId;
      final reason = _rooms.closeReason;
      final next = isHost
          ? 'Cria uma nova sala para continuar.'
          : 'Podes criar ou entrar noutra sala.';
      _closeLocally(
        // Any failure closes the session; say which one it was.
        notice: reason != null
            ? '${_errorMessage(reason)} $next'
            : isHost
            ? 'O outro jogador saiu. $next'
            : 'O anfitrião encerrou a sala. $next',
      );
      return;
    }
    state = state.copyWith(
      room: room,
      error: null,
      currentUserId: _rooms.currentUserId,
    );
    if (room.status == 'playing') _openGame(room);
  }

  void _onRoomError(Object error) {
    if (!ref.mounted || _closureHandled) return;
    state = state.copyWith(
      room: null,
      connection: null,
      error: _errorMessage(error),
    );
  }

  void _openGame(Room room) {
    if (state.opening) return;
    final uid = _rooms.currentUserId;
    if (uid == null || (uid != room.hostUid && uid != room.guestUid)) return;
    state = state.copyWith(startedRole: room.roleFor(uid));
  }

  /// Resets the lobby and closes the session without waiting for it, so the
  /// player sees the result immediately.
  Future<void> _closeLocally({String? notice}) {
    _closureHandled = true;
    final subscription = _subscription;
    final service = _rooms;
    _subscription = null;
    state = LobbyState(
      currentUserId: state.currentUserId,
      closedNotice: notice,
    );
    unawaited(subscription?.cancel());
    return service.close();
  }

  Future<void> leave() async {
    if (state.busy) return;
    await _closeLocally();
  }

  Future<void> startGame() async {
    final room = state.room;
    if (!state.canStart || room == null) return;
    await _run(() => _rooms.startGame(room.id));
  }

  Future<void> switchRoles() async {
    final room = state.room;
    if (state.busy || room == null || room.status == 'playing') return;
    await _run(() => _rooms.switchRoles(room.id));
  }

  /// Transfers the live session to the game; this lobby no longer closes it.
  LobbySession handOff() {
    final role = state.startedRole;
    if (role == null) throw StateError('The game has not started');
    _handedOff = true;
    final id = bombId;
    final bombs = _bombs;
    return (
      service: _rooms,
      role: role,
      // If this fails the claim lease expires and the bomb is re-armed.
      onFinished: id == null || bombs == null
          ? null
          : (result) => bombs
                .resolveBomb(id, worldOutcomeFor(result))
                .catchError((Object error) {
                  debugPrint('resolveBomb failed: $error');
                }),
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    state = state.copyWith(busy: true, error: null);
    try {
      await operation();
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _errorMessage(error));
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  String _errorMessage(Object error) {
    if (error is ArgumentError) return 'Introduz um código de seis dígitos.';
    if (error is FirebaseException) {
      if (error.plugin == 'room' && error.message != null) {
        return error.message!;
      }
      return switch (error.code) {
        'not-found' =>
          'Sala não encontrada. Confirma o código e a configuração.',
        'failed-precondition' => 'A sala não está disponível para esta ação.',
        'permission-denied' => 'A sala foi encerrada ou não tens acesso.',
        'operation-not-allowed' => 'O início de sessão anónimo não está ativo.',
        'unavailable' || 'network-request-failed' =>
          'Não foi possível ligar. Verifica a ligação à Internet.',
        _ =>
          'Não foi possível carregar a sala. Tenta novamente. (${error.code})',
      };
    }
    return 'Não foi possível carregar a sala. Tenta novamente.';
  }
}
