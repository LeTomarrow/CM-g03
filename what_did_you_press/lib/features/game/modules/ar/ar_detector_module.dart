import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/ar/ar_view.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:what_did_you_press/services/ar_pose_service.dart';

/// AR "detector": a bomb part hides somewhere around the operator. Only the
/// manual can work out where; the detector just beeps once close.
class ArDetectorModulePage extends StatefulWidget {
  const ArDetectorModulePage({super.key, this.variant = 0});

  /// Signal starts this far (degrees) from the part.
  static const double signalRange = 30;

  /// The part shows up, and can be captured, this close to the crosshair.
  static const double captureRange = 12;

  final int variant;

  /// Angular distance between the crosshair and the part.
  static double distance(
    ArPose pose,
    ({double azimuth, double elevation}) target,
  ) {
    final dAz = angleDelta(target.azimuth, pose.yaw);
    final dEl = target.elevation - pose.pitch;
    return math.sqrt(dAz * dAz + dEl * dEl);
  }

  /// 0 (no signal) to 1 (on target).
  static double signal(double distance) =>
      (1 - distance / signalRange).clamp(0.0, 1.0);

  @override
  State<ArDetectorModulePage> createState() => _ArDetectorModulePageState();
}

class _ArDetectorModulePageState extends State<ArDetectorModulePage> {
  late final _puzzle = arDetectorPuzzle(widget.variant);
  late final _target = solveArDetector(
    _puzzle.symbol,
    _puzzle.first,
    _puzzle.second,
  );
  ArPose _pose = const ArPose(yaw: 0, pitch: 0);
  Timer? _beeper;
  int _sinceBeep = 0;

  double get _distance => ArDetectorModulePage.distance(_pose, _target);

  @override
  void initState() {
    super.initState();
    // Beeps faster the closer the crosshair gets; silent out of range.
    _beeper = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final signal = ArDetectorModulePage.signal(_distance);
      if (signal == 0) return;
      _sinceBeep += 50;
      if (_sinceBeep >= 700 - 600 * signal) {
        _sinceBeep = 0;
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _beeper?.cancel();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(_distance <= ArDetectorModulePage.captureRange);
  }

  Widget _buildVisor() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.background.withValues(alpha: 0.85),
      child: Text(
        'VISOR  ${_puzzle.symbol}  ${_puzzle.first}  ${_puzzle.second}',
        style: const TextStyle(color: AppColors.led, fontSize: 18),
      ),
    );
  }

  Widget _buildSignal(double signal) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: AppColors.background.withValues(alpha: 0.85),
      child: Row(
        children: [
          const Text(
            'SINAL',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: signal,
              minHeight: 8,
              color: AppColors.led,
              backgroundColor: AppColors.metalGrey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.arDetector,
      subtitle: 'Encontra a peça escondida à tua volta, guiado pelo manual.',
      onConfirm: _confirm,
      children: [
        Text(
          'Lê o visor ao teu parceiro. Ele diz-te para onde virar a partir da '
          'BASE. Quando a peça aparecer na mira, confirma para a capturar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        ArView(
          onPose: (pose) => _pose = pose,
          objects: (pose) => [
            const ArObject(
              azimuth: 0,
              elevation: 0,
              size: 64,
              child: _BaseMarker(),
            ),
            if (ArDetectorModulePage.distance(pose, _target) <=
                ArDetectorModulePage.captureRange)
              ArObject(
                azimuth: _target.azimuth,
                elevation: _target.elevation,
                size: 56,
                child: const _Part(),
              ),
          ],
          hud: (pose) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.all(8), child: _buildVisor()),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
                child: _buildSignal(
                  ArDetectorModulePage.signal(
                    ArDetectorModulePage.distance(pose, _target),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BaseMarker extends StatelessWidget {
  const _BaseMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: AppColors.neonBlue,
          child: const Text(
            'BASE',
            style: TextStyle(color: AppColors.background, fontSize: 12),
          ),
        ),
        Container(width: 3, height: 24, color: AppColors.neonBlue),
      ],
    );
  }
}

class _Part extends StatelessWidget {
  const _Part();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.copper,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.led, width: 3),
      ),
      child: const Icon(Icons.memory, color: AppColors.background, size: 30),
    );
  }
}
