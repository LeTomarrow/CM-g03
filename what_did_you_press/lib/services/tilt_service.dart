import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Rotation of the phone in the screen plane, independent of plugin types.
class TiltSample {
  const TiltSample({required this.angle});

  /// Clockwise degrees in [0, 360); 0 = upright portrait. Null when the phone
  /// is too flat for gravity to define a rotation.
  final double? angle;

  bool get hasAngle => angle != null && angle!.isFinite;
}

/// Owns hardware access; cancelling the stream releases the sensor listener.
class TiltService {
  /// Minimum in-plane gravity (m/s²) for a trustworthy reading (~30° from flat).
  static const double minPlanarGravity = 5;

  /// Low-pass weight of each new reading; lower is smoother but slower.
  static const double smoothing = 0.2;

  Stream<TiltSample> watchTilt() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return Stream.value(const TiltSample(angle: null));
    }
    double? x;
    double? y;
    return accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).map((event) {
      // Filter the vector, not the angle, so wrap-around at 0/360 is harmless.
      x = x == null ? event.x : x! + smoothing * (event.x - x!);
      y = y == null ? event.y : y! + smoothing * (event.y - y!);
      return tiltFromGravity(x!, y!);
    });
  }
}

/// Clockwise screen rotation from the accelerometer's in-plane components.
TiltSample tiltFromGravity(double x, double y) {
  if (math.sqrt(x * x + y * y) < TiltService.minPlanarGravity) {
    return const TiltSample(angle: null);
  }
  final degrees = math.atan2(-x, y) * 180 / math.pi;
  return TiltSample(angle: (degrees + 360) % 360);
}
