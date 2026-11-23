import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where the back camera points: [yaw] in degrees clockwise from magnetic
/// north and [pitch] in degrees above the horizon (negative = looking down).
class ArPose {
  const ArPose({required this.yaw, required this.pitch});

  /// No usable sensors (desktop, web): the view falls back to dragging.
  static const unavailable = ArPose(yaw: double.nan, pitch: double.nan);

  final double yaw;
  final double pitch;

  bool get isAvailable => yaw.isFinite && pitch.isFinite;
}

typedef Vector3 = ({double x, double y, double z});

/// Camera direction from gravity and the magnetic field, both in device
/// coordinates (Android convention: the accelerometer reads "up" at rest).
///
/// Unlike the compass heading (the direction of the phone's top edge), this
/// stays stable with the phone held upright, which is how AR is played: the
/// camera looks along the device's −z axis.
ArPose arPoseFrom(Vector3 accel, Vector3 magnetic) {
  Vector3 cross(Vector3 a, Vector3 b) => (
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  );
  double length(Vector3 v) => math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  Vector3 unit(Vector3 v) {
    final l = length(v);
    return (x: v.x / l, y: v.y / l, z: v.z / l);
  }

  if (length(accel) < 1e-3 || length(magnetic) < 1e-3) {
    return ArPose.unavailable;
  }
  final up = unit(accel);
  final eastRaw = cross(magnetic, up);
  if (length(eastRaw) < 1e-3) return ArPose.unavailable;
  final east = unit(eastRaw);
  final north = cross(up, east);
  // Camera forward is (0, 0, -1), so each dot product is minus a z component.
  final yaw = math.atan2(-east.z, -north.z) * 180 / math.pi;
  final pitch = math.asin((-up.z).clamp(-1.0, 1.0)) * 180 / math.pi;
  return ArPose(yaw: (yaw + 360) % 360, pitch: pitch);
}

/// Owns the sensors; cancelling the stream releases both listeners.
class ArPoseService {
  /// Low-pass weight of each reading; lower is steadier but laggier.
  static const double smoothing = 0.15;

  Stream<ArPose> watchPose() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return Stream.value(ArPose.unavailable);
    }
    late final StreamController<ArPose> controller;
    StreamSubscription<AccelerometerEvent>? accelSub;
    StreamSubscription<MagnetometerEvent>? magSub;
    Vector3? accel;
    Vector3? magnetic;

    Vector3 filter(Vector3? old, double x, double y, double z) => old == null
        ? (x: x, y: y, z: z)
        : (
            x: old.x + smoothing * (x - old.x),
            y: old.y + smoothing * (y - old.y),
            z: old.z + smoothing * (z - old.z),
          );

    void emit() {
      if (accel != null && magnetic != null) {
        controller.add(arPoseFrom(accel!, magnetic!));
      }
    }

    controller = StreamController<ArPose>(
      onListen: () {
        const period = SensorInterval.gameInterval;
        accelSub = accelerometerEventStream(samplingPeriod: period).listen((e) {
          accel = filter(accel, e.x, e.y, e.z);
          emit();
        }, onError: (Object _) => controller.add(ArPose.unavailable));
        magSub = magnetometerEventStream(samplingPeriod: period).listen(
          (e) => magnetic = filter(magnetic, e.x, e.y, e.z),
          onError: (Object _) => controller.add(ArPose.unavailable),
        );
      },
      onCancel: () async {
        await accelSub?.cancel();
        await magSub?.cancel();
      },
    );
    return controller.stream;
  }
}
