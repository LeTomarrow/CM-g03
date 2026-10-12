import 'package:flutter/material.dart';
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
  PlayerRole _role = PlayerRole.defuser;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _startGame() {
    final Widget page = _role == PlayerRole.defuser
        ? const BombPage()
        : const ManualPage();
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
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
                    'XK-7742',
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
                  _buildPlayerSlot('P1: Bernardo', _role.label, true),
                  const Divider(color: AppColors.metalGrey, height: 24),
                  _buildPlayerSlot('À espera...', _role.partner.label, false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MenuButton(
              label: 'TROCAR PAPÉIS',
              onPressed: () => setState(() => _role = _role.partner),
              color: AppColors.metalGrey,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
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
                    onPressed: () {},
                    color: AppColors.neonBlue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MenuButton(
                    label: 'CRIAR',
                    onPressed: () {},
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            MenuButton(
              label: 'COMEÇAR',
              onPressed: _startGame,
              color: AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }
}
