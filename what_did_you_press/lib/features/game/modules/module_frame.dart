import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';

/// Shared layout for every bomb module: title, content and confirm button.
/// Module pages pop `true` when solved and `false` on a wrong answer.
class ModuleFrame extends StatelessWidget {
  const ModuleFrame({
    super.key,
    required this.type,
    required this.onConfirm,
    required this.children,
  });

  final ModuleType type;
  final void Function() onConfirm;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                children: children,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: MenuButton(
                label: 'CONFIRMAR',
                onPressed: onConfirm,
                color: type.color,
              ),
            ),
          ],
        ),
      ),
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
          style: GoogleFonts.shareTechMono(
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
