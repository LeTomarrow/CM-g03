import 'dart:ui';

import 'package:what_did_you_press/core/drawing.dart';

/// Wire format of the operator's drawing: points in thousandths, bounded so a
/// message stays well under [GameMessage.maxBytes].
const _maxPointsPerStroke = 80;
const _maxPoints = 800;

List<List<List<int>>> encodeDrawing(List<Stroke> strokes) {
  var remaining = _maxPoints;
  final encoded = <List<List<int>>>[];
  for (final stroke in strokes) {
    if (remaining <= 0) break;
    final points = _encodeStroke(stroke).take(remaining).toList();
    encoded.add(points);
    remaining -= points.length;
  }
  return encoded;
}

/// Applies a `drawing` payload to [current]; null if the payload is invalid.
List<Stroke>? applyDrawingPayload(
  List<Stroke> current,
  Map<String, dynamic> payload,
) {
  if (payload['mode'] == 'replace') {
    final rawStrokes = payload['strokes'];
    if (rawStrokes is! List) return null;
    return rawStrokes.whereType<List>().map(_decodeStroke).toList();
  }
  final index = payload['index'];
  final rawPoints = payload['points'];
  if (index is! int || rawPoints is! List || index < 0) return null;
  final strokes = List<Stroke>.of(current);
  while (strokes.length <= index) {
    strokes.add(<Offset>[]);
  }
  strokes[index] = _decodeStroke(rawPoints);
  return strokes;
}

List<List<int>> _encodeStroke(Stroke stroke) {
  List<int> point(Offset p) => [(p.dx * 1000).round(), (p.dy * 1000).round()];
  if (stroke.length <= _maxPointsPerStroke) {
    return [for (final p in stroke) point(p)];
  }
  return [
    for (var i = 0; i < _maxPointsPerStroke; i++)
      point(
        stroke[(i * (stroke.length - 1) / (_maxPointsPerStroke - 1)).round()],
      ),
  ];
}

Stroke _decodeStroke(List<dynamic> rawPoints) => [
  for (final rawPoint in rawPoints.whereType<List>())
    if (rawPoint.length >= 2 && rawPoint[0] is num && rawPoint[1] is num)
      Offset(
        (rawPoint[0] as num).toDouble() / 1000,
        (rawPoint[1] as num).toDouble() / 1000,
      ),
];
