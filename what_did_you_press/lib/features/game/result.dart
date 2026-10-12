import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/lobby.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    required this.defused,
    required this.timeLeft,
    required this.strikes,
  });

  final bool defused;
  final Duration timeLeft;
  final int strikes;

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
    final color = defused ? AppColors.success : AppColors.danger;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                defused ? Icons.verified_user : Icons.local_fire_department,
                size: 96,
                color: color,
              ),
              const SizedBox(height: 24),
              Text(
                defused ? 'DESARMADA' : 'BOOM!',
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 40),
              ),
              const SizedBox(height: 8),
              Text(
                defused
                    ? 'Bom trabalho de equipa.'
                    : 'O que é que carregaste?!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  _buildStat('TEMPO', formatTime(timeLeft), AppColors.amber),
                  const SizedBox(width: 12),
                  _buildStat('ERROS', '$strikes', AppColors.danger),
                ],
              ),
              const Spacer(),
              MenuButton(
                label: 'JOGAR NOVAMENTE',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LobbyPage()),
                ),
                color: AppColors.neonBlue,
              ),
              const SizedBox(height: 16),
              MenuButton(
                label: 'MENU',
                onPressed: () => Navigator.of(context).pop(),
                color: AppColors.metalGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
