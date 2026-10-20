import 'package:flutter/material.dart';

/// Seven-segment LED readout, like the clock taped to the bomb. Shows digits,
/// spaces and ':'; unlit segments stay faintly visible as on real hardware.
class SegmentDisplay extends StatelessWidget {
  const SegmentDisplay({
    super.key,
    required this.text,
    required this.color,
    this.height = 56,
    this.colonVisible = true,
  });

  final String text;
  final Color color;
  final double height;
  final bool colonVisible;

  static double _advance(String char, double height) =>
      char == ':' ? height * 0.3 : height * 0.62;

  @override
  Widget build(BuildContext context) {
    final width = text
        .split('')
        .fold<double>(0, (sum, char) => sum + _advance(char, height));
    return Semantics(
      label: text,
      child: CustomPaint(
        size: Size(width, height),
        painter: _SegmentPainter(text, color, colonVisible),
      ),
    );
  }
}

// Segments a–g, clockwise from the top, then the middle bar.
const _digits = {
  '0': 'abcdef',
  '1': 'bc',
  '2': 'abged',
  '3': 'abgcd',
  '4': 'fgbc',
  '5': 'afgcd',
  '6': 'afgedc',
  '7': 'abc',
  '8': 'abcdefg',
  '9': 'abcdfg',
  ' ': '',
};

class _SegmentPainter extends CustomPainter {
  _SegmentPainter(this.text, this.color, this.colonVisible);

  final String text;
  final Color color;
  final bool colonVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final lit = Paint()..color = color;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final unlit = Paint()..color = color.withValues(alpha: 0.07);

    // Real displays lean forward slightly.
    canvas.save();
    canvas.translate(h * 0.08, 0);
    canvas.skew(-0.1, 0);
    var x = 0.0;
    for (final char in text.split('')) {
      if (char == ':') {
        final r = h * 0.05;
        for (final y in [h * 0.32, h * 0.68]) {
          final dot = Offset(x + h * 0.13, y);
          canvas.drawCircle(dot, r, colonVisible ? lit : unlit);
          if (colonVisible) canvas.drawCircle(dot, r, glow);
        }
      } else {
        final on = _digits[char] ?? '';
        for (final segment in 'abcdefg'.split('')) {
          final path = _segment(segment, x, h);
          if (on.contains(segment)) {
            canvas.drawPath(path, glow);
            canvas.drawPath(path, lit);
          } else {
            canvas.drawPath(path, unlit);
          }
        }
      }
      x += SegmentDisplay._advance(char, h);
    }
    canvas.restore();
  }

  /// One bevelled bar inside a digit cell starting at [left].
  Path _segment(String segment, double left, double h) {
    final w = h * 0.48;
    final t = h * 0.1;
    final gap = t * 0.18;
    Path bar(Offset from, Offset to) {
      final horizontal = from.dy == to.dy;
      final half = t / 2;
      final a = from + Offset(horizontal ? gap : 0, horizontal ? 0 : gap);
      final b = to - Offset(horizontal ? gap : 0, horizontal ? 0 : gap);
      return Path()..addPolygon(
        horizontal
            ? [
                a,
                a + Offset(half, -half),
                b + Offset(-half, -half),
                b,
                b + Offset(-half, half),
                a + Offset(half, half),
              ]
            : [
                a,
                a + Offset(half, half),
                b + Offset(half, -half),
                b,
                b + Offset(-half, -half),
                a + Offset(-half, half),
              ],
        true,
      );
    }

    final top = t / 2;
    final mid = h / 2;
    final bottom = h - t / 2;
    final l = left + t / 2;
    final r = left + w - t / 2;
    return switch (segment) {
      'a' => bar(Offset(l, top), Offset(r, top)),
      'b' => bar(Offset(r, top), Offset(r, mid)),
      'c' => bar(Offset(r, mid), Offset(r, bottom)),
      'd' => bar(Offset(l, bottom), Offset(r, bottom)),
      'e' => bar(Offset(l, mid), Offset(l, bottom)),
      'f' => bar(Offset(l, top), Offset(l, mid)),
      _ => bar(Offset(l, mid), Offset(r, mid)),
    };
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.text != text ||
      old.color != color ||
      old.colonVisible != colonVisible;
}
