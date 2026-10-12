import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.danger,
  });

  final String label;
  final void Function() onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

/// Asks before leaving a running game. Returns `true` if the player confirms.
Future<bool> confirmLeaveGame(BuildContext context, String message) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('ABANDONAR JOGO?', style: TextStyle(color: AppColors.danger)),
      content: Text(message, style: TextStyle(color: AppColors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'CONTINUAR',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('ABANDONAR', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );

  // Tapping outside the dialog returns null: treat it as "stay".
  return leave ?? false;
}

/// Small glowing dot used for player and module status.
class StatusLed extends StatelessWidget {
  const StatusLed({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    );
  }
}
