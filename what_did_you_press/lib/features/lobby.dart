import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/features/game/bomb.dart';
import 'package:what_did_you_press/features/lobby_controller.dart';
import 'package:what_did_you_press/features/manual/manual.dart';

class LobbyPage extends ConsumerStatefulWidget {
  const LobbyPage({super.key, this.bombId});

  /// Open-world bomb claimed by this player, who hosts as the operator.
  final String? bombId;

  @override
  ConsumerState<LobbyPage> createState() => _LobbyPageState();
}

/// View of [LobbyController]: renders [LobbyState], forwards taps, and owns
/// only UI concerns (text field, dialogs, snackbars and navigation).
class _LobbyPageState extends ConsumerState<LobbyPage> {
  final TextEditingController _codeController = TextEditingController();

  LobbyController get _controller =>
      ref.read(lobbyControllerProvider(widget.bombId).notifier);

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onStateChanged(LobbyState? previous, LobbyState next) {
    final notice = next.closedNotice;
    if (notice != null && notice != previous?.closedNotice) {
      _codeController.clear();
      _showClosedDialog(notice);
    }
    if (previous?.startedRole == null && next.startedRole != null) {
      _openGame(_controller.handOff());
    }
  }

  void _showClosedDialog(String message) {
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

  void _openGame(LobbySession session) {
    final Widget page = session.role == PlayerRole.manual
        ? ManualPage(transport: session.service)
        : BombPage(transport: session.service, onFinished: session.onFinished);
    // Acknowledged peer start; keep the DataChannel alive while playing.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => _PeerGame(service: session.service, child: page),
      ),
    );
  }

  Future<void> _leaveRoom() async {
    _codeController.clear();
    await _controller.leave();
  }

  Future<void> _startGame(LobbyState lobby) async {
    if (lobby.busy || lobby.opening) return;
    if (lobby.room?.status != 'ready') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Espera que outro jogador entre na sala.'),
        ),
      );
      return;
    }
    await _controller.startGame();
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
    final provider = lobbyControllerProvider(widget.bombId);
    ref.listen(provider, _onStateChanged);
    final lobby = ref.watch(provider);
    final room = lobby.room;
    final isHost = lobby.isHost;
    final busy = lobby.busy;
    final connection = lobby.connection;
    final rolesFixed = _controller.rolesFixed;
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
                    connection?.code ?? '------',
                    style: TextStyle(color: AppColors.amber, fontSize: 32),
                  ),
                  if (widget.bombId != null || room?.rolesLocked == true)
                    Text(
                      widget.bombId != null
                          ? 'BOMBA DO MUNDO · ÉS O OPERADOR'
                          : 'BOMBA DO MUNDO · ÉS O MANUAL',
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
                    isHost ? 'P1: Anfitrião (tu)' : 'P1: Anfitrião',
                    (room?.hostRole ?? PlayerRole.defuser).label,
                    room != null,
                  ),
                  const Divider(color: AppColors.metalGrey, height: 24),
                  _buildPlayerSlot(
                    room?.guestUid != null
                        ? (isHost
                              ? 'P2: Jogador ligado'
                              : 'P2: Jogador ligado (tu)')
                        : 'À espera...',
                    (room?.hostRole ?? PlayerRole.defuser).partner.label,
                    room?.guestUid != null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (connection != null) ...[
              if (room != null) ...[
                MenuButton(
                  label: room.status == 'ready'
                      ? (isHost ? 'COMEÇAR JOGO' : 'À ESPERA DO ANFITRIÃO')
                      : 'A AGUARDAR JOGADOR',
                  onPressed: () => _startGame(lobby),
                  color: AppColors.success,
                  enabled: lobby.canStart,
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: MenuButton(
                      label: 'TROCAR PAPÉIS',
                      onPressed: _controller.switchRoles,
                      color: AppColors.metalGrey,
                      enabled: !rolesFixed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MenuButton(
                      label: isHost ? 'ENCERRAR SALA' : 'SAIR DA SALA',
                      onPressed: _leaveRoom,
                      color: isHost ? AppColors.danger : AppColors.metalGrey,
                      enabled: !busy,
                    ),
                  ),
                ],
              ),
            ] else if (widget.bombId == null) ...[
              // A bomb room is created automatically; joining by code is
              // for ordinary rooms only.
              TextField(
                controller: _codeController,
                enabled: !busy,
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
              Row(
                children: [
                  Expanded(
                    child: MenuButton(
                      label: 'ENTRAR',
                      onPressed: () => _controller.connect(
                        create: false,
                        code: _codeController.text,
                      ),
                      color: AppColors.neonBlue,
                      enabled: !busy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MenuButton(
                      label: 'CRIAR',
                      onPressed: () => _controller.connect(create: true),
                      color: AppColors.amber,
                      enabled: !busy,
                    ),
                  ),
                ],
              ),
            ] else if (!busy)
              MenuButton(
                label: 'CRIAR SALA',
                onPressed: () => _controller.connect(create: true),
                color: AppColors.amber,
              ),
            const SizedBox(height: 16),
            if (busy) const LinearProgressIndicator(),
            if (lobby.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  lobby.error!,
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            if (room != null) ...[
              const SizedBox(height: 16),
              Text(switch (room.status) {
                'ready' => 'LIGAÇÃO ENTRE JOGADORES ESTABELECIDA',
                'starting' => 'A CONFIRMAR O INÍCIO...',
                'closed' => 'LIGAÇÃO ENCERRADA',
                _ =>
                  room.guestUid == null
                      ? 'À ESPERA DE OUTRO JOGADOR'
                      : 'A LIGAR AO OUTRO JOGADOR...',
              }, style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 40),
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
