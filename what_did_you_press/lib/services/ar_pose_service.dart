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

/// Clockwise turn rate of the camera about the world vertical, in degrees
/// per second, from the gyroscope ([gyro], rad/s, right-handed device axes)
/// and gravity ([accel], device "up").
double yawRateFrom(Vector3 gyro, Vector3 accel) {
  final l = math.sqrt(
    accel.x * accel.x + accel.y * accel.y + accel.z * accel.z,
  );
  if (l < 1e-3) return 0;
  // Counter-clockwise about "up" is positive, so turning right is negative.
  final rate = (gyro.x * accel.x + gyro.y * accel.y + gyro.z * accel.z) / l;
  return -rate * 180 / math.pi;
}

/// Pitch of the camera axis (device −z) above the horizon, from gravity.
double pitchFrom(Vector3 accel) {
  final l = math.sqrt(
    accel.x * accel.x + accel.y * accel.y + accel.z * accel.z,
  );
  if (l < 1e-3) return double.nan;
  return math.asin((-accel.z / l).clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Owns the sensors; cancelling the stream releases every listener.
///
/// The bearing comes from the gyroscope: indoors the magnetometer is bent by
/// walls and appliances, so a real 90° turn can read 60° and virtual objects
/// would drift along with the camera. The magnetometer only seeds the
/// bearing, and stands in when the phone has no gyroscope.
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
    StreamSubscription<GyroscopeEvent>? gyroSub;
    Vector3? accel;
    Vector3? magnetic;
    double? gyroYaw;
    final clock = Stopwatch();

    Vector3 filter(Vector3? old, double x, double y, double z) => old == null
        ? (x: x, y: y, z: z)
        : (
            x: old.x + smoothing * (x - old.x),
            y: old.y + smoothing * (y - old.y),
            z: old.z + smoothing * (z - old.z),
          );

    double? magneticYaw() {
      if (accel == null || magnetic == null) return null;
      final pose = arPoseFrom(accel!, magnetic!);
      return pose.isAvailable ? pose.yaw : null;
    }

    void emit() {
      if (accel == null) return;
      final yaw = gyroYaw ?? magneticYaw();
      if (yaw == null) return;
      controller.add(ArPose(yaw: yaw, pitch: pitchFrom(accel!)));
    }

    void onGyro(GyroscopeEvent e) {
      final up = accel;
      if (up == null) return;
      if (gyroYaw == null) {
        gyroYaw = magneticYaw() ?? 0;
        clock.start();
        return;
      }
      // Clamp the step so a stalled stream cannot jump the view.
      final dt = math.min(clock.elapsedMicroseconds / 1e6, 0.1);
      clock.reset();
      final rate = yawRateFrom((x: e.x, y: e.y, z: e.z), up);
      gyroYaw = (gyroYaw! + rate * dt + 360) % 360;
      emit();
    }

    controller = StreamController<ArPose>(
      onListen: () {
        const period = SensorInterval.gameInterval;
        accelSub = accelerometerEventStream(samplingPeriod: period).listen((e) {
          accel = filter(accel, e.x, e.y, e.z);
          if (gyroYaw == null) emit();
        }, onError: (Object _) => controller.add(ArPose.unavailable));
        magSub = magnetometerEventStream(samplingPeriod: period).listen(
          (e) => magnetic = filter(magnetic, e.x, e.y, e.z),
          onError: (Object _) {},
        );
        gyroSub = gyroscopeEventStream(
          samplingPeriod: period,
        ).listen(onGyro, onError: (Object _) => gyroYaw = null);
      },
      onCancel: () async {
        await accelSub?.cancel();
        await magSub?.cancel();
        await gyroSub?.cancel();
      },
    );
    return controller.stream;
  }
}
