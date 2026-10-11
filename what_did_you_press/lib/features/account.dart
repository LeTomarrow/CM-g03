import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/features/menu.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final TextEditingController _nameController = TextEditingController(
    text: 'Bernardo',
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: AppColors.card,
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.success,
        title: Text('PERFIL'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.metalGrey,
                child: Icon(
                  Icons.person,
                  size: 48,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'NOME',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.metalGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.success),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'ESTATÍSTICAS',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStat('JOGOS', '12', AppColors.neonBlue),
                const SizedBox(width: 12),
                _buildStat('DESARMADAS', '8', AppColors.success),
                const SizedBox(width: 12),
                _buildStat('EXPLODIDAS', '4', AppColors.danger),
              ],
            ),
            const SizedBox(height: 48),
            MenuButton(
              label: 'GUARDAR',
              onPressed: () => Navigator.of(context).pop(),
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}
