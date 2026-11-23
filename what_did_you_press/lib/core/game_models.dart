import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

enum PlayerRole {
  defuser('OPERADOR'),
  manual('MANUAL');

  const PlayerRole(this.label);

  final String label;

  PlayerRole get partner => this == defuser ? manual : defuser;
}

/// Every minigame the bomb can contain.
enum ModuleType {
  gyro('ÂNGULO', Icons.screen_rotation, AppColors.neonBlue),
  compass('BÚSSOLA', Icons.explore, AppColors.amber),
  morse('MORSE', Icons.vibration, AppColors.success),
  symbols('SÍMBOLOS', Icons.category, AppColors.danger),
  drawing('DESENHO', Icons.draw, AppColors.neonPurple),
  switches('INTERRUPTORES', Icons.toggle_on, AppColors.copper);

  const ModuleType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class BombModule {
  BombModule(this.type);

  final ModuleType type;
  bool defused = false;
}

/// Formats a duration as MM:SS for the bomb timer.
String formatTime(Duration time) {
  final minutes = time.inMinutes.toString().padLeft(2, '0');
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Smallest difference between two angles in degrees (0–180).
double angleDistance(double a, double b) {
  return ((a - b + 540) % 360 - 180).abs();
}
