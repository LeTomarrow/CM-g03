import 'package:flutter/foundation.dart';
import 'package:precise_compass/precise_compass.dart';

/// Sensor data independent of the compass plugin's platform types.
class CompassSample {
  const CompassSample({
    required this.heading,
    this.accuracyDegrees = -1,
    this.shouldCalibrate = false,
  });

  final double? heading;
  final double accuracyDegrees;
  final bool shouldCalibrate;

  bool get hasHeading => heading != null && heading!.isFinite;

  bool canConfirm(double tolerance) =>
      hasHeading &&
      !shouldCalibrate &&
      accuracyDegrees.isFinite &&
      (accuracyDegrees < 0 || accuracyDegrees <= tolerance);
}

/// Owns hardware access; cancelling the stream releases the sensor listener.
class CompassService {
  Stream<CompassSample> watchHeading() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return Stream.value(const CompassSample(heading: null));
    }
    return PreciseCompass.headingStream(
      config: const CompassConfig(reference: HeadingReference.magnetic),
    ).map((reading) {
      final heading = reading.headingMagnetic;
      return CompassSample(
        heading: heading != null && heading.isFinite ? heading % 360 : null,
        accuracyDegrees: reading.accuracyDegrees,
        shouldCalibrate: reading.shouldCalibrate,
      );
    });
  }
}
