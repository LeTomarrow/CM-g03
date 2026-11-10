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
    this.abandoned = false,
    this.notice,
  });

  final bool defused;
  final Duration timeLeft;
  final int strikes;
  final bool abandoned;
  final String? notice;

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
    final color = abandoned
        ? AppColors.amber
        : defused
        ? AppColors.success
        : AppColors.danger;

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
                abandoned
                    ? Icons.link_off
                    : defused
                    ? Icons.verified_user
                    : Icons.local_fire_department,
                size: 96,
                color: color,
              ),
              const SizedBox(height: 24),
              Text(
                abandoned
                    ? 'PARTIDA ABANDONADA'
                    : defused
                    ? 'DESARMADA'
                    : 'BOOM!',
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: abandoned ? 28 : 40),
              ),
              const SizedBox(height: 8),
              Text(
                abandoned
                    ? notice ?? 'A ligação ao teu parceiro terminou.'
                    : defused
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
