import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class GyroModulePage extends StatefulWidget {
  const GyroModulePage({super.key});

  @override
  State<GyroModulePage> createState() => _GyroModulePageState();
}

class _GyroModulePageState extends State<GyroModulePage> {
  static const double _tolerance = 10;

  final String _sequence = (angleTable.keys.toList()..shuffle()).first;
  double _angle = 0;

  void _confirm() {
    final target = angleTable[_sequence]!.toDouble();
    Navigator.of(context).pop(angleDistance(_angle, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.gyro,
      onConfirm: _confirm,
      children: [
        SequencePanel(sequence: _sequence, color: AppColors.neonBlue),
        const SizedBox(height: 32),
        AimDial(
          angle: _angle,
          labels: const ['0', '45', '90', '135', '180', '225', '270', '315'],
          color: AppColors.neonBlue,
        ),
        const SizedBox(height: 16),
        Text(
          '${_angle.round()}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.neonBlue, fontSize: 28),
        ),
        // Mockup only: replaced by the sensor stream later.
        Slider(
          value: _angle,
          max: 359,
          activeColor: AppColors.neonBlue,
          inactiveColor: AppColors.metalGrey,
          onChanged: (val) => setState(() => _angle = val),
        ),
      ],
    );
  }
}
