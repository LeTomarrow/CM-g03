import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/features/game/bomb.dart';
import 'package:what_did_you_press/features/manual/manual.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  final TextEditingController _codeController = TextEditingController();
  late final RoomService _rooms = RoomService();
  StreamSubscription<Room?>? _roomSubscription;
  RoomConnection? _connection;
  Room? _room;
  bool _busy = false;
  bool _openingGame = false;

  bool get _isHost => _room != null && _room!.hostUid == _rooms.currentUserId;
  String? _error;

  Future<void> _connect({required bool create}) async {
    if (_busy || _connection != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _roomSubscription?.cancel();
      _roomSubscription = null;
      final connection = create
          ? await _rooms.createRoom()
          : await _rooms.joinRoom(_codeController.text);
      if (!mounted) return;
      setState(() => _connection = connection);
      _roomSubscription = _rooms
          .watchRoom(connection.roomId)
          .listen(
            (room) {
              if (!mounted) return;
              setState(() {
                _room = room;
                _error = room == null ? 'A sala foi encerrada.' : null;
                if (room == null) _connection = null;
              });
              if (room?.status == 'playing') _openGame(room!);
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _room = null;
                _error = _errorMessage(error);
                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  _connection = null;
                }
              });
            },
          );
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is ArgumentError) return 'Introduz um código de seis dígitos.';
    if (error is FirebaseException) {
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
    _codeController.dispose();
    super.dispose();
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
    final Widget page = role == PlayerRole.defuser
        ? const BombPage()
        : const ManualPage();
    // Both players navigate from the committed room update, never a local tap.
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => page));
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
              ignoring: _busy || _room == null || _openingGame,
              child: Opacity(
                opacity: _busy || _room == null || _openingGame ? 0.5 : 1,
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
