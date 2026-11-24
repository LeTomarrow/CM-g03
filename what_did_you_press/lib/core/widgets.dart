import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.danger,
    this.enabled = true,
  });

  final String label;
  final void Function() onPressed;
  final Color color;

  /// A disabled key sits flat and grey and ignores taps.
  final bool enabled;

  /// A chunky hardware key: its darker lower edge reads as depth.
  @override
  Widget build(BuildContext context) {
    final face = enabled ? color : AppColors.surfaceLight;
    final light =
        ThemeData.estimateBrightnessForColor(face) == Brightness.light;
    final edge = Color.lerp(face, Colors.black, 0.45)!;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: face,
              borderRadius: BorderRadius.circular(4),
              boxShadow: enabled
                  ? [BoxShadow(color: edge, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: !enabled
                    ? AppColors.textSecondary
                    : light
                    ? AppColors.background
                    : AppColors.textPrimary,
              ),
            ),
          ),
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
