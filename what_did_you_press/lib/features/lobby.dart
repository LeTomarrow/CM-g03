import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/features/game/bomb.dart';
import 'package:what_did_you_press/features/manual/manual.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key, this.roomServiceFactory, this.bombId});

  final RoomService Function()? roomServiceFactory;

  /// Open-world bomb claimed by this player, who hosts as the operator.
  final String? bombId;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  final TextEditingController _codeController = TextEditingController();
  late RoomService _rooms = _newRoomService();
  RoomService _newRoomService() {
    final service = widget.roomServiceFactory?.call() ?? RoomService();
    if (widget.bombId != null) service.rolesLocked = true;
    return service;
  }

  late final BombService _bombs = BombService();
  StreamSubscription<Room?>? _roomSubscription;
  RoomConnection? _connection;
  Room? _room;
  bool _busy = false;
  bool _openingGame = false;
  bool _closureHandled = false;

  bool get _isHost => _room != null && _room!.hostUid == _rooms.currentUserId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.bombId != null) _connect(create: true);
  }

  Future<void> _connect({required bool create}) async {
    if (_busy || _connection != null) return;
    setState(() {
      _busy = true;
      _error = null;
      _closureHandled = false;
    });
    try {
      await _roomSubscription?.cancel();
      _roomSubscription = null;
      await _rooms.close();
      _rooms = _newRoomService();
      final connection = create
          ? await _rooms.createRoom()
          : await _rooms.joinRoom(_codeController.text);
      if (!mounted) {
        await _rooms.close();
        return;
      }
      setState(() => _connection = connection);
      _roomSubscription = _rooms
          .watchRoom(connection.roomId)
          .listen(
            (room) {
              if (!mounted || _closureHandled) return;
              if (room == null || room.status == 'closed') {
                final isHost = (room ?? _room)?.hostUid == _rooms.currentUserId;
                _handleRoomClosed(
                  isHost
                      ? 'O outro jogador saiu. Cria uma nova sala para continuar.'
                      : 'O anfitrião encerrou a sala. Podes criar ou entrar noutra sala.',
                );
                return;
              }
              setState(() {
                _room = room;
                _error = null;
              });
              if (room.status == 'playing') _openGame(room);
            },
            onError: (Object error) {
              if (!mounted || _closureHandled) return;
              setState(() {
                _room = null;
                _error = _errorMessage(error);
                _connection = null;
              });
            },
          );
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleRoomClosed(String message) {
    if (!mounted || _closureHandled || _openingGame) return;
    _closureHandled = true;
    final subscription = _roomSubscription;
    final service = _rooms;
    _roomSubscription = null;
    setState(() {
      _room = null;
      _connection = null;
      _busy = false;
      _error = null;
      _codeController.clear();
    });
    // Reset immediately; cleanup must not delay the remote closure notice.
    unawaited(subscription?.cancel());
    unawaited(service.close());
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            'SALA ENCERRADA',
            style: TextStyle(color: AppColors.danger),
          ),
          content: Text(
            message,
            style: TextStyle(color: AppColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'ENTENDIDO',
                style: TextStyle(color: AppColors.amber),
              ),
            ),
          ],
        ),
      ),
    );
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

  @override
  void dispose() {
    _roomSubscription?.cancel();
    // Leaving before the game starts frees the bomb for other players.
    final bombId = widget.bombId;
    if (bombId != null && !_openingGame) {
      _bombs.resolveBomb(bombId, BombOutcome.abandoned).ignore();
    }
    if (!_openingGame) unawaited(_rooms.close());
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _leaveRoom() async {
    if (_busy) return;
    final subscription = _roomSubscription;
    final service = _rooms;
    _roomSubscription = null;
    _closureHandled = true;
    setState(() {
      _connection = null;
      _room = null;
      _busy = false;
      _error = null;
      _codeController.clear();
    });
    // Notify/close the peer immediately, without waiting for UI stream teardown.
    unawaited(subscription?.cancel());
    await service.close();
  }

  Future<void> _startGame() async {
    if (_busy || _openingGame) return;
    if (_room?.status != 'ready') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Espera que outro jogador entre na sala.'),
        ),
      );
      return;
    }
    if (!_isHost) return;
    await _changeRoom(() => _rooms.startGame(_room!.id));
  }

  bool get _rolesFixed =>
      _busy || _room == null || _openingGame || widget.bombId != null;

  Future<void> _switchRoles() async {
    final room = _room;
    if (_busy || room == null || room.status == 'playing') return;
    await _changeRoom(() => _rooms.switchRoles(room.id));
  }

  Future<void> _changeRoom(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openGame(Room room) {
    if (_openingGame) return;
    final uid = _rooms.currentUserId;
    if (uid == null || (uid != room.hostUid && uid != room.guestUid)) return;
    _openingGame = true;
    final role = room.roleFor(uid);
    final bombId = widget.bombId;
    final Widget page = role == PlayerRole.manual
        ? const ManualPage()
        : bombId == null
        ? const BombPage()
        : BombPage(
            // If this fails the claim lease expires and the bomb is re-armed.
            onFinished: (defused) => _bombs
                .resolveBomb(
                  bombId,
                  defused ? BombOutcome.defused : BombOutcome.exploded,
                )
                .catchError((Object error) {
                  debugPrint('resolveBomb failed: $error');
                }),
          );
    // Acknowledged peer start; keep the DataChannel alive while playing.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => _PeerGame(service: _rooms, child: page),
      ),
    );
  }

  Widget _buildPlayerSlot(String name, String role, bool isConnected) {
    Color color = isConnected ? AppColors.success : AppColors.amber;

    return Row(
      children: [
        StatusLed(color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: isConnected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ),
        Text(role, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.danger,
        title: Text('LOBBY'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.card,
              child: Column(
                children: [
                  Text(
                    'CÓDIGO DA SALA',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _connection?.code ?? '------',
                    style: TextStyle(color: AppColors.amber, fontSize: 32),
                  ),
                  if (widget.bombId != null)
                    Text(
                      'BOMBA DO MUNDO · ÉS O OPERADOR',
                      style: TextStyle(color: AppColors.success),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JOGADORES',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  _buildPlayerSlot(
                    _isHost ? 'P1: Anfitrião (tu)' : 'P1: Anfitrião',
                    (_room?.hostRole ?? PlayerRole.defuser).label,
                    _room != null,
                  ),
                  const Divider(color: AppColors.metalGrey, height: 24),
                  _buildPlayerSlot(
                    _room?.guestUid != null
                        ? (_isHost
                              ? 'P2: Jogador ligado'
                              : 'P2: Jogador ligado (tu)')
                        : 'À espera...',
                    (_room?.hostRole ?? PlayerRole.defuser).partner.label,
                    _room?.guestUid != null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: _rolesFixed,
              child: Opacity(
                opacity: _rolesFixed ? 0.5 : 1,
                child: MenuButton(
                  label: 'TROCAR PAPÉIS',
                  onPressed: _switchRoles,
                  color: AppColors.metalGrey,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              enabled: !_busy && _connection == null,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'INTRODUZ O CÓDIGO',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.metalGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.amber),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: TextStyle(color: AppColors.danger)),
              ),
            IgnorePointer(
              ignoring: _busy || _connection != null,
              child: Opacity(
                opacity: _busy || _connection != null ? 0.5 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: MenuButton(
                        label: 'ENTRAR',
                        onPressed: () => _connect(create: false),
                        color: AppColors.neonBlue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: MenuButton(
                        label: 'CRIAR',
                        onPressed: () => _connect(create: true),
                        color: AppColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_room != null) ...[
              const SizedBox(height: 16),
              Text(switch (_room!.status) {
                'ready' => 'LIGAÇÃO ENTRE JOGADORES ESTABELECIDA',
                'starting' => 'A CONFIRMAR O INÍCIO...',
                'closed' => 'LIGAÇÃO ENCERRADA',
                _ =>
                  _room!.guestUid == null
                      ? 'À ESPERA DE OUTRO JOGADOR'
                      : 'A LIGAR AO OUTRO JOGADOR...',
              }, style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: _busy,
                child: Opacity(
                  opacity: _busy ? 0.5 : 1,
                  child: MenuButton(
                    label: _isHost ? 'ENCERRAR SALA' : 'SAIR DA SALA',
                    onPressed: _leaveRoom,
                    color: _isHost ? AppColors.danger : AppColors.metalGrey,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
            IgnorePointer(
              ignoring: _busy || !_isHost || _openingGame,
              child: Opacity(
                opacity: _busy || !_isHost || _openingGame ? 0.5 : 1,
                child: MenuButton(
                  label: _room != null && !_isHost
                      ? 'À ESPERA DO ANFITRIÃO'
                      : 'COMEÇAR',
                  onPressed: _startGame,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Own the peer session after the lobby route is replaced by the game.
class _PeerGame extends StatefulWidget {
  const _PeerGame({required this.service, required this.child});
  final RoomService service;
  final Widget child;

  @override
  State<_PeerGame> createState() => _PeerGameState();
}

class _PeerGameState extends State<_PeerGame> {
  @override
  void dispose() {
    unawaited(widget.service.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
