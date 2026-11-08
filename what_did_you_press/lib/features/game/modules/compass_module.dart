import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class CompassModulePage extends StatefulWidget {
  const CompassModulePage({super.key, this.variant = 0});

  final int variant;

  @override
  State<CompassModulePage> createState() => _CompassModulePageState();
}

class _CompassModulePageState extends State<CompassModulePage> {
  static const double _tolerance = 15;

  String get _sequence =>
      compassTable.keys.elementAt(widget.variant % compassTable.length);
  double _heading = 0;

  void _confirm() {
    final target = cardinalAngles[compassTable[_sequence]]!.toDouble();
    Navigator.of(context).pop(angleDistance(_heading, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.compass,
      subtitle: 'Usa a bússola e aponta para o ponto cardeal indicado.',
      onConfirm: _confirm,
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
            angle: _heading,
            labels: cardinalAngles.keys.toList(),
            color: AppColors.amber,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${_heading.round()}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.amber, fontSize: 28),
        ),
        // Mockup only: replaced by the magnetometer stream later.
        Slider(
          value: _heading,
          max: 359,
          activeColor: AppColors.amber,
          inactiveColor: AppColors.metalGrey,
          onChanged: (val) => setState(() => _heading = val),
        ),
      ],
    );
  }
}
