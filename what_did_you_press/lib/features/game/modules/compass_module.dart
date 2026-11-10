import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/features/game/modules/compass_controller.dart';
import 'package:what_did_you_press/services/compass_service.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class CompassModulePage extends ConsumerWidget {
  const CompassModulePage({super.key, this.variant = 0});

  final int variant;

  static const double _tolerance = 15;

  String get _sequence =>
      compassTable.keys.elementAt(variant % compassTable.length);

  void _confirm(BuildContext context, CompassSample? sample) {
    if (sample == null || !sample.canConfirm(_tolerance)) return;
    final target = cardinalAngles[compassTable[_sequence]]!.toDouble();
    Navigator.of(
      context,
    ).pop(angleDistance(sample.heading!, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(compassHeadingProvider);
    final alignment = ref.watch(compassAlignmentProvider);
    final controller = ref.read(compassAlignmentProvider.notifier);
    final sample = alignment.sample;
    final heading = sample?.heading;
    final ready =
        !alignment.isAligning && (sample?.canConfirm(_tolerance) ?? false);
    final message = reading.when(
      loading: () => 'A aguardar a bússola…',
      error: (error, stack) =>
          'Não foi possível ler a bússola. Reabre o módulo para tentar novamente.',
      data: (sensor) {
        if (!sensor.hasHeading) {
          return 'Bússola indisponível neste dispositivo.';
        }
        if (!sensor.canConfirm(_tolerance)) {
          return 'Afasta o telemóvel de ímanes e metal e move-o em forma de 8 para calibrar a bússola.';
        }
        if (alignment.isAligning) {
          return 'Aponta o topo do telemóvel para a direção indicada e solta para fixar.';
        }
        if (sample == null) {
          return 'Mantém o telemóvel na horizontal e mantém o botão premido para alinhar.';
        }
        if (!sample.canConfirm(_tolerance)) {
          return 'Mantém o botão premido para captar uma direção com melhor precisão.';
        }
        return 'Direção fixada. Confirma a resposta ou mantém o botão premido para ajustar.';
      },
    );
    return ModuleFrame(
      type: ModuleType.compass,
      subtitle: 'Usa a bússola e aponta para o ponto cardeal indicado.',
      onConfirm: () => _confirm(context, sample),
      confirmEnabled: ready,
      children: [
        SequencePanel(sequence: _sequence, color: AppColors.amber),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: glowingCardDecoration(
            glowColor: AppColors.amber.withValues(alpha: 0.18),
            borderColor: AppColors.amber.withValues(alpha: 0.5),
          ),
          child: AimDial(
            angle: heading ?? 0,
            labels: cardinalAngles.keys.toList(),
            color: AppColors.amber,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          heading == null ? '—°' : '${(heading.round() % 360)}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.amber, fontSize: 28),
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
              glowColor: AppColors.amber.withValues(
                alpha: alignment.isAligning ? 0.3 : 0.1,
              ),
              borderColor: AppColors.amber,
            ),
            child: Text(
              alignment.isAligning ? 'SOLTA PARA FIXAR' : 'MANTER PARA ALINHAR',
              style: TextStyle(color: AppColors.amber, fontSize: 18),
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
