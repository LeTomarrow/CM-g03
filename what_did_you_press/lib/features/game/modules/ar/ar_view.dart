import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/services/ar_pose_service.dart';

final arPoseServiceProvider = Provider<ArPoseService>((ref) => ArPoseService());

/// Module-scoped sensor state. Riverpod cancels the subscription on disposal.
final arPoseProvider = StreamProvider.autoDispose<ArPose>(
  (ref) => ref.watch(arPoseServiceProvider).watchPose(),
);

/// Signed shortest difference `a - b`, in (-180, 180].
double angleDelta(double a, double b) => ((a - b + 540) % 360) - 180;

/// Something anchored in the room, relative to where the camera pointed when
/// the module opened: [azimuth] degrees to the right, [elevation] degrees up.
class ArObject {
  const ArObject({
    required this.azimuth,
    required this.elevation,
    required this.child,
    this.size = 72,
  });

  final double azimuth;
  final double elevation;
  final Widget child;
  final double size;
}

/// Focal length, in logical pixels, that makes [size] span [fov] degrees
/// horizontally.
double arFocalLength(Size size, {double fov = ArView.horizontalFov}) =>
    size.width / 2 / math.tan(fov / 2 * math.pi / 180);

/// Focal length of the camera feed as [ArCameraBackground] draws it: the
/// landscape [preview] is turned portrait and cover-fitted into [size].
/// Phone previews crop the short side of the sensor, so the long side keeps
/// about [ArView.cameraLongSideFov].
double arCameraFocalLength(Size size, Size? preview) {
  if (preview == null || preview.isEmpty) return arFocalLength(size);
  final long = math.max(preview.width, preview.height);
  final short = math.min(preview.width, preview.height);
  final scale = math.max(size.width / short, size.height / long);
  final focal =
      long / 2 / math.tan(ArView.cameraLongSideFov / 2 * math.pi / 180);
  return focal * scale;
}

/// Screen position of a direction for a pinhole camera looking at [view]
/// with focal length [focal] (default: [ArView.horizontalFov] across), or
/// null when it is behind or far outside the view.
Offset? arProject({
  required double azimuth,
  required double elevation,
  required ArPose view,
  required Size size,
  double? focal,
}) {
  const rad = math.pi / 180;
  final f = focal ?? arFocalLength(size);
  final dAz = angleDelta(azimuth, view.yaw) * rad;
  final el = elevation * rad;
  final pitch = view.pitch * rad;
  // Direction in a frame turned to the camera's bearing: right, ahead, up.
  final right = math.cos(el) * math.sin(dAz);
  final ahead = math.cos(el) * math.cos(dAz);
  final up = math.sin(el);
  // Tilt by the camera's pitch.
  final z = ahead * math.cos(pitch) + up * math.sin(pitch);
  final y = up * math.cos(pitch) - ahead * math.sin(pitch);
  if (z < 0.2) return null;
  return Offset(size.width / 2 + f * right / z, size.height / 2 - f * y / z);
}

/// Camera feed with virtual objects anchored around the player. Without
/// sensors (desktop, web, tests) the player drags to look around instead.
class ArView extends ConsumerStatefulWidget {
  const ArView({
    super.key,
    required this.objects,
    this.hud,
    this.onPose,
    this.height = 420,
  });

  /// Horizontal field of view without a camera feed, in degrees.
  static const double horizontalFov = 60;

  /// Field of view along the long side of a typical phone camera preview.
  static const double cameraLongSideFov = 66;

  final List<ArObject> Function(ArPose pose) objects;
  final Widget Function(ArPose pose)? hud;

  /// The relative pose (yaw 0 = where the module opened), on every change.
  final ValueChanged<ArPose>? onPose;
  final double height;

  @override
  ConsumerState<ArView> createState() => _ArViewState();
}

class _ArViewState extends ConsumerState<ArView> {
  double? _startYaw;
  ArPose _dragPose = const ArPose(yaw: 0, pitch: 0);
  Size? _previewSize;

  ArPose? _relative(ArPose? sensor) {
    if (sensor == null || !sensor.isAvailable) return null;
    _startYaw ??= sensor.yaw;
    return ArPose(
      yaw: (sensor.yaw - _startYaw! + 360) % 360,
      pitch: sensor.pitch,
    );
  }

  /// Riverpod may deliver a reading while this view is building; the parent
  /// usually calls setState in [ArView.onPose], so that waits for the frame
  /// to finish (and asks for the next one).
  void _notify(ArPose pose) {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      widget.onPose?.call(pose);
      return;
    }
    binding.addPostFrameCallback((_) {
      if (mounted) widget.onPose?.call(pose);
    });
    binding.ensureVisualUpdate();
  }

  void _drag(DragUpdateDetails details) {
    setState(() {
      _dragPose = ArPose(
        yaw: (_dragPose.yaw - details.delta.dx * 0.3 + 360) % 360,
        pitch: (_dragPose.pitch + details.delta.dy * 0.3).clamp(-60.0, 60.0),
      );
    });
    widget.onPose?.call(_dragPose);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(arPoseProvider, (_, next) {
      final pose = _relative(next.asData?.value);
      if (pose != null) _notify(pose);
    });
    final sensorPose = _relative(ref.watch(arPoseProvider).asData?.value);
    final pose = sensorPose ?? _dragPose;

    return SizedBox(
      height: widget.height,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final focal = arCameraFocalLength(size, _previewSize);
            return GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              onPanUpdate: sensorPose == null ? _drag : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ArCameraBackground(
                      onPreviewSize: (preview) =>
                          setState(() => _previewSize = preview),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _HorizonPainter(pose, focal)),
                  ),
                  for (final object in widget.objects(pose))
                    if (arProject(
                          azimuth: object.azimuth,
                          elevation: object.elevation,
                          view: pose,
                          size: size,
                          focal: focal,
                        )
                        case final point?)
                      Positioned(
                        left: point.dx - object.size / 2,
                        top: point.dy - object.size / 2,
                        width: object.size,
                        height: object.size,
                        child: object.child,
                      ),
                  const Center(child: _Crosshair()),
                  if (widget.hud != null)
                    Positioned.fill(child: widget.hud!(pose)),
                  if (sensorPose == null)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      child: Text(
                        'Sem sensores: arrasta para olhar à volta.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.textPrimary, width: 2),
        ),
        child: const Center(
          child: SizedBox(
            width: 4,
            height: 4,
            child: ColoredBox(color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Horizon line with a tick every 15° (longer every 45°), unnumbered, so
/// the operator can count turns without reading exact bearings.
class _HorizonPainter extends CustomPainter {
  _HorizonPainter(this.pose, this.focal);

  final ArPose pose;
  final double focal;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    final ahead = arProject(
      azimuth: pose.yaw,
      elevation: 0,
      view: pose,
      size: size,
      focal: focal,
    );
    if (ahead == null) return;
    final y = ahead.dy;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    for (var azimuth = 0; azimuth < 360; azimuth += 15) {
      final point = arProject(
        azimuth: azimuth.toDouble(),
        elevation: 0,
        view: pose,
        size: size,
        focal: focal,
      );
      if (point == null) continue;
      final half = azimuth % 45 == 0 ? 10.0 : 5.0;
      canvas.drawLine(
        Offset(point.dx, y - half),
        Offset(point.dx, y + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HorizonPainter old) =>
      old.pose.yaw != pose.yaw ||
      old.pose.pitch != pose.pitch ||
      old.focal != focal;
}

/// The back camera, or a dark backdrop where there is none (desktop, web,
/// tests, permission denied).
class ArCameraBackground extends StatefulWidget {
  const ArCameraBackground({super.key, this.onPreviewSize});

  /// The feed's (landscape) size once the camera is open, to match the
  /// virtual field of view to it.
  final ValueChanged<Size>? onPreviewSize;

  @override
  State<ArCameraBackground> createState() => _ArCameraBackgroundState();
}

class _ArCameraBackgroundState extends State<ArCameraBackground> {
  CameraController? _controller;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      _open();
    }
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      final back = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      if (back == null || _disposed) return;
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      final preview = controller.value.previewSize;
      if (preview != null) widget.onPreviewSize?.call(preview);
    } catch (_) {
      // No camera or no permission: the backdrop stays.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final preview = controller?.value.previewSize;
    if (controller == null || preview == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceLight, AppColors.background],
          ),
        ),
      );
    }
    // The preview size is landscape; the module is portrait.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: preview.height,
        height: preview.width,
        child: CameraPreview(controller),
      ),
    );
  }
}
