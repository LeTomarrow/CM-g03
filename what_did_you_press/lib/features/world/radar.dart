import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/geo.dart';
import 'package:what_did_you_press/services/bomb_service.dart';

/// Top-down radar centred on the player; north is up.
class BombRadar extends StatelessWidget {
  const BombRadar({
    super.key,
    required this.lat,
    required this.lng,
    required this.bombs,
    this.rangeMeters = 500,
  });

  final double lat;
  final double lng;
  final List<Bomb> bombs;
  final double rangeMeters;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RadarPainter(
          bombs: [
            for (final bomb in bombs)
              (offsetMeters(lat, lng, bomb.lat, bomb.lng), _colorFor(bomb)),
          ],
          rangeMeters: rangeMeters,
        ),
      ),
    );
  }

  Color _colorFor(Bomb bomb) {
    if (!bomb.isClaimable(DateTime.now())) return AppColors.amber;
    if (bomb.distanceTo(lat, lng) <= claimRadiusMeters) {
      return AppColors.success;
    }
    return AppColors.danger;
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.bombs, required this.rangeMeters});

  final List<((double, double), Color)> bombs;
  final double rangeMeters;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ring = Paint()
      ..color = AppColors.success.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, Paint()..color = AppColors.card);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ring);
    }
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      ring,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      ring,
    );
    // Claim radius around the player.
    canvas.drawCircle(
      center,
      radius * claimRadiusMeters / rangeMeters,
      Paint()..color = AppColors.successGlow,
    );

    for (final ((east, north), color) in bombs) {
      final distance = math.sqrt(east * east + north * north);
      // Bombs out of range stick to the edge, dimmed, to show direction.
      final scale = distance > rangeMeters ? rangeMeters / distance : 1.0;
      final point = center.translate(
        east * scale / rangeMeters * radius,
        -north * scale / rangeMeters * radius,
      );
      final dot = color.withValues(alpha: scale < 1 ? 0.4 : 1);
      canvas.drawCircle(point, 8, Paint()..color = dot.withValues(alpha: 0.3));
      canvas.drawCircle(point, 4, Paint()..color = dot);
    }

    canvas.drawCircle(center, 5, Paint()..color = AppColors.neonBlue);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => true;
}
