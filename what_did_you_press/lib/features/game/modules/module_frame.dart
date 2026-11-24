import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/core/segment_display.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/hack_effects.dart';

/// Shared layout for every bomb module: title, content and confirm button.
/// Module pages pop `true` when solved and `false` on a wrong answer.
class ModuleFrame extends StatelessWidget {
  const ModuleFrame({
    super.key,
    required this.type,
    required this.onConfirm,
    required this.children,
    this.subtitle,
    this.confirmEnabled = true,
    this.action,
  });

  final ModuleType type;
  final void Function() onConfirm;
  final List<Widget> children;
  final String? subtitle;
  final bool confirmEnabled;

  /// Control pinned above the confirm button, always on screen (e.g. the
  /// hold-to-align key), so the player never scrolls to find it.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: type.color,
        title: Text(type.label),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final game = ref.watch(gameControllerProvider);
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: glowingCardDecoration(
                          glowColor: type.color.withValues(alpha: 0.22),
                          borderColor: type.color.withValues(alpha: 0.7),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(type.icon, color: type.color, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'MÓDULO ATIVO',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        type.label,
                                        style: TextStyle(
                                          color: type.color,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'TEMPO',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    SegmentDisplay(
                                      text: formatTime(game.timeLeft),
                                      color: game.timeLeft.inSeconds < 60
                                          ? AppColors.led
                                          : type.color,
                                      height: 24,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.metalGrey)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (action != null) ...[
                      action!,
                      const SizedBox(height: 12),
                    ],
                    IgnorePointer(
                      ignoring: !confirmEnabled,
                      child: Opacity(
                        opacity: confirmEnabled ? 1 : 0.5,
                        child: MenuButton(
                          label: 'CONFIRMAR RESPOSTA',
                          onPressed: onConfirm,
                          color: type.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return HackFlash(child: page);
  }
}

/// Key that aligns while held and locks when released. A raw [Listener], so
/// a finger drifting while the phone turns does not cancel the hold.
class HoldToAlignButton extends StatelessWidget {
  const HoldToAlignButton({
    super.key,
    required this.color,
    required this.aligning,
    required this.onStart,
    required this.onRelease,
    this.reading,
  });

  /// Live value shown above the key, so the player sees it while holding.
  final String? reading;
  final Color color;
  final bool aligning;
  final VoidCallback onStart;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final key = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onStart(),
      onPointerUp: (_) => onRelease(),
      onPointerCancel: (_) => onRelease(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: glowingCardDecoration(
          glowColor: color.withValues(alpha: aligning ? 0.3 : 0.1),
          borderColor: color,
        ),
        child: Text(
          aligning ? 'SOLTA PARA FIXAR' : 'MANTER PARA ALINHAR',
          style: TextStyle(color: color, fontSize: 18),
        ),
      ),
    );
    if (reading == null) return key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          reading!,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 28),
        ),
        const SizedBox(height: 8),
        key,
      ],
    );
  }
}

/// Card with the sequence the defuser must read out loud.
class SequencePanel extends StatelessWidget {
  const SequencePanel({super.key, required this.sequence, required this.color});

  final String sequence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        children: [
          Text('SEQUÊNCIA', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            sequence,
            style: TextStyle(color: color, fontSize: 32, letterSpacing: 4),
          ),
        ],
      ),
    );
  }
}

/// Round dial with a needle at [angle] degrees (0 = top, clockwise).
class AimDial extends StatelessWidget {
  const AimDial({
    super.key,
    required this.angle,
    required this.labels,
    required this.color,
  });

  final double angle;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DialPainter(angle: angle, labels: labels, color: color),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.angle,
    required this.labels,
    required this.color,
  });

  final double angle;
  final List<String> labels;
  final Color color;

  Offset _direction(double radians) => Offset(sin(radians), -cos(radians));

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ring = Paint()
      ..color = AppColors.metalGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius - 2, ring);

    for (int i = 0; i < 36; i++) {
      final tick = _direction(i * pi / 18);
      final length = i % 3 == 0 ? 14.0 : 6.0;
      canvas.drawLine(
        center + tick * (radius - length),
        center + tick * (radius - 2),
        ring,
      );
    }

    for (int i = 0; i < labels.length; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: GoogleFonts.barlowCondensed(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final position =
          center + _direction(i * 2 * pi / labels.length) * (radius - 34);
      text.paint(canvas, position - Offset(text.width / 2, text.height / 2));
    }

    final needle = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      center + _direction(angle * pi / 180) * (radius - 56),
      needle,
    );
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
