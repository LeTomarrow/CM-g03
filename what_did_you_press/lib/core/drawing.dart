import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

/// One continuous line. Points are normalised to a 0–1 square so a drawing
/// looks the same on any screen size; this is the format that will travel
/// over the P2P data channel.
typedef Stroke = List<Offset>;

/// Mockup stand-in for the P2P data channel: the bomb writes the defuser's
/// drawing here and the manual listens to it.
final ValueNotifier<List<Stroke>> liveDrawing = ValueNotifier([]);

/// Read-only drawing (glyphs, or the partner's live drawing).
class DrawingView extends StatelessWidget {
  const DrawingView({super.key, required this.strokes, required this.color});

  final List<Stroke> strokes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _StrokePainter(strokes: strokes, color: color),
      ),
    );
  }
}

/// Square canvas the player draws on with one finger.
class DrawingPad extends StatefulWidget {
  const DrawingPad({
    super.key,
    required this.onChanged,
    this.onStrokeEnd,
    required this.color,
    this.inkFade,
  });

  final void Function(List<Stroke> strokes) onChanged;
  final void Function(List<Stroke> strokes)? onStrokeEnd;
  final Color color;

  /// When set, every point disappears from this pad this long after it was
  /// drawn, like a trail behind the finger, even if the finger never lifts.
  /// The full strokes are still reported; the player draws almost blind.
  final Duration? inkFade;

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  final List<Stroke> _strokes = [];

  /// When each point was drawn ([_clock] ms), parallel to [_strokes].
  final List<List<int>> _times = [];
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _fadeTicker;
  int? _pointer;

  @override
  void dispose() {
    _fadeTicker?.cancel();
    super.dispose();
  }

  void _addPoint(Offset point, {required bool newStroke}) {
    final now = _clock.elapsedMilliseconds;
    _update(() {
      if (newStroke) {
        _strokes.add([point]);
        _times.add([now]);
      } else {
        _strokes.last.add(point);
        _times.last.add(now);
      }
    });
    _startFading();
  }

  /// Repaints while ink is fading; stops once nothing is visible.
  void _startFading() {
    if (widget.inkFade == null || _fadeTicker != null) return;
    _fadeTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {});
      if (_visibleStrokes().isEmpty) {
        _fadeTicker?.cancel();
        _fadeTicker = null;
      }
    });
  }

  /// The part of each stroke that is still visible on this pad.
  List<Stroke> _visibleStrokes() {
    final fade = widget.inkFade;
    if (fade == null) return _strokes;
    final cutoff = _clock.elapsedMilliseconds - fade.inMilliseconds;
    return [
      for (var i = 0; i < _strokes.length; i++)
        if (_times[i].last >= cutoff)
          _strokes[i].sublist(_times[i].indexWhere((time) => time >= cutoff)),
    ];
  }

  void _endStroke() {
    _pointer = null;
    widget.onStrokeEnd?.call(List.of(_strokes));
  }

  void _clear() {
    _update(() {
      _strokes.clear();
      _times.clear();
    });
  }

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(List.of(_strokes));
  }

  Offset _normalise(Offset position, Size size) {
    return Offset(
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          // The clear button sits outside the gesture area, otherwise the
          // eager recognizer would swallow its taps.
          return Stack(
            children: [
              RawGestureDetector(
                // Claims the touch so the page does not scroll while drawing.
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(() => EagerGestureRecognizer(), (_) {}),
                },
                child: Listener(
                  onPointerDown: (event) {
                    if (_pointer != null) return;
                    _pointer = event.pointer;
                    _addPoint(
                      _normalise(event.localPosition, size),
                      newStroke: true,
                    );
                  },
                  onPointerMove: (event) {
                    if (event.pointer != _pointer) return;
                    _addPoint(
                      _normalise(event.localPosition, size),
                      newStroke: false,
                    );
                  },
                  onPointerUp: (event) {
                    if (event.pointer == _pointer) _endStroke();
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _pointer) _endStroke();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(color: AppColors.metalGrey),
                    ),
                    child: DrawingView(
                      strokes: _visibleStrokes(),
                      color: widget.color,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.textSecondary,
                  tooltip: 'Limpar',
                  onPressed: _clear,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({required this.strokes, required this.color});

  final List<Stroke> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide / 40
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      // A single tap becomes a dot instead of an invisible zero-length line.
      if (stroke.length == 1) path.relativeLineTo(0.1, 0);
      canvas.drawPath(path, paint);
    }
  }

  // Strokes grow in place while drawing, so the list identity never changes.
  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
