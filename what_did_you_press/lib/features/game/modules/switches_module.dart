import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class SwitchesModulePage extends StatefulWidget {
  const SwitchesModulePage({super.key, this.variant = 0});

  final int variant;

  @override
  State<SwitchesModulePage> createState() => _SwitchesModulePageState();
}

class _SwitchesModulePageState extends State<SwitchesModulePage> {
  late final _puzzle = switchPuzzle(widget.variant);
  late List<bool> _positions = List.of(_puzzle.initial);

  void _confirm() {
    final target = solveSwitches(_puzzle.colors, _puzzle.initial);
    Navigator.of(context).pop(listEquals(_positions, target));
  }

  Widget _buildSwitch(int index) {
    final color = _puzzle.colors[index].color;
    final up = _positions[index];
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _positions[index] = !up),
        child: Column(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              height: 140,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: color, width: 3),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 120),
                alignment: up ? Alignment.topCenter : Alignment.bottomCenter,
                child: Container(height: 56, color: color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              up ? 'CIMA' : 'BAIXO',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.switches,
      subtitle: 'Põe cada interruptor na posição que o manual indicar.',
      onConfirm: _confirm,
      children: [
        Text(
          'Diz ao teu parceiro a cor e a posição inicial de cada interruptor, '
          'da esquerda para a direita. Toca num interruptor para o mudar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: glowingCardDecoration(
            glowColor: AppColors.copper.withValues(alpha: 0.18),
            borderColor: AppColors.copper.withValues(alpha: 0.5),
          ),
          child: Row(
            children: [for (var i = 0; i < switchCount; i++) _buildSwitch(i)],
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () =>
              setState(() => _positions = List.of(_puzzle.initial)),
          icon: const Icon(Icons.undo),
          label: const Text('REPOR POSIÇÃO INICIAL'),
          style: TextButton.styleFrom(foregroundColor: AppColors.copper),
        ),
      ],
    );
  }
}
