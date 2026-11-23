import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/gyro_controller.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:what_did_you_press/services/tilt_service.dart';

class GyroModulePage extends ConsumerWidget {
  const GyroModulePage({super.key, this.variant = 0});

  final int variant;

  static const double _tolerance = 10;

  List<String> get _sequence => angleSequence(variant);

  void _confirm(BuildContext context, TiltSample? sample) {
    if (sample == null || !sample.hasAngle) return;
    final target = solveAngle(_sequence).toDouble();
    Navigator.of(
      context,
    ).pop(angleDistance(sample.angle!, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(tiltProvider);
    final alignment = ref.watch(gyroAlignmentProvider);
    final controller = ref.read(gyroAlignmentProvider.notifier);
    final sample = alignment.sample;
    final angle = sample?.angle;
    final ready = !alignment.isAligning && (sample?.hasAngle ?? false);
    final message = reading.when(
      loading: () => 'A aguardar o sensor…',
      error: (error, stack) =>
          'Não foi possível ler o sensor. Reabre o módulo para tentar novamente.',
      data: (sensor) {
        if (!sensor.hasAngle) {
          return 'Segura o telemóvel na vertical, com o ecrã virado para ti.';
        }
        if (alignment.isAligning) {
          return 'Roda o telemóvel até o indicador marcar o ângulo e solta para fixar.';
        }
        if (sample == null || !sample.hasAngle) {
          return 'Mantém o botão premido e roda o telemóvel para alinhar.';
        }
        return 'Ângulo fixado. Confirma a resposta ou mantém o botão premido para ajustar.';
      },
    );
    return ModuleFrame(
      type: ModuleType.gyro,
      subtitle: 'Roda o telemóvel até ao ângulo pedido pelo manual.',
      onConfirm: () => _confirm(context, sample),
      confirmEnabled: ready,
      children: [
        SequencePanel(sequence: _sequence.join(' '), color: AppColors.neonBlue),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: glowingCardDecoration(
            glowColor: AppColors.neonBlue.withValues(alpha: 0.18),
            borderColor: AppColors.neonBlue.withValues(alpha: 0.5),
          ),
          child: AimDial(
            angle: angle ?? 0,
            labels: const ['0', '45', '90', '135', '180', '225', '270', '315'],
            color: AppColors.neonBlue,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          angle == null ? '—°' : '${angle.round() % 360}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.neonBlue, fontSize: 28),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTapDown: (_) => controller.startAlignment(),
          onTapUp: (_) => controller.lockAlignment(),
          onTapCancel: controller.lockAlignment,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: glowingCardDecoration(
              glowColor: AppColors.neonBlue.withValues(
                alpha: alignment.isAligning ? 0.3 : 0.1,
              ),
              borderColor: AppColors.neonBlue,
            ),
            child: Text(
              alignment.isAligning ? 'SOLTA PARA FIXAR' : 'MANTER PARA ALINHAR',
              style: TextStyle(color: AppColors.neonBlue, fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
      ],
    );
  }
}
