import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Widget _buildPlayerSlot(String name, String role, bool isConnected) {
    Color color = isConnected ? AppColors.success : AppColors.amber;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
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
                  _buildPlayerSlot('P1: Bernardo', 'DEFUSER', true),
                  const Divider(color: AppColors.metalGrey, height: 24),
                  _buildPlayerSlot('À espera...', 'MANUAL', false),
                ],
              ),
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
              onPressed: () {},
              color: AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }
}
