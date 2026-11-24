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

/// Screen position of a direction for a camera looking at [view], or null
/// when it is outside the field of view.
Offset? arProject({
  required double azimuth,
  required double elevation,
  required ArPose view,
  required Size size,
  double fov = ArView.horizontalFov,
}) {
  final dx = angleDelta(azimuth, view.yaw);
  if (dx.abs() > fov) return null;
  final verticalFov = fov * size.height / size.width;
  return Offset(
    size.width / 2 + dx / fov * size.width,
    size.height / 2 - (elevation - view.pitch) / verticalFov * size.height,
  );
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

  /// Horizontal field of view used to place objects, in degrees.
  static const double horizontalFov = 60;

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
            return GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              onPanUpdate: sensorPose == null ? _drag : null,
              child: Stack(
                children: [
                  const Positioned.fill(child: ArCameraBackground()),
                  Positioned.fill(
                    child: CustomPaint(painter: _HorizonPainter(pose)),
                  ),
                  for (final object in widget.objects(pose))
                    if (arProject(
                          azimuth: object.azimuth,
                          elevation: object.elevation,
                          view: pose,
                          size: size,
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
  _HorizonPainter(this.pose);

  final ArPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    final left = arProject(
      azimuth: pose.yaw - ArView.horizontalFov,
      elevation: 0,
      view: pose,
      size: size,
    );
    if (left == null) return;
    final y = left.dy;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    for (var azimuth = 0; azimuth < 360; azimuth += 15) {
      final point = arProject(
        azimuth: azimuth.toDouble(),
        elevation: 0,
        view: pose,
        size: size,
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
      old.pose.yaw != pose.yaw || old.pose.pitch != pose.pitch;
}

/// The back camera, or a dark backdrop where there is none (desktop, web,
/// tests, permission denied).
class ArCameraBackground extends StatefulWidget {
  const ArCameraBackground({super.key});

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
