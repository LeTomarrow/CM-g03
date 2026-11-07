import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class SymbolsModulePage extends StatefulWidget {
  const SymbolsModulePage({super.key, this.variant = 0});

  final int variant;

  @override
  State<SymbolsModulePage> createState() => _SymbolsModulePageState();
}

class _SymbolsModulePageState extends State<SymbolsModulePage> {
  late final List<SymbolTile> _tiles =
      symbolVariants[widget.variant % symbolVariants.length];
  int? _selected;

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == solveSymbols(_tiles));
  }

  Widget _buildTile(int index) {
    final tile = _tiles[index];
    final isSelected = index == _selected;

    return InkWell(
      onTap: () => setState(() => _selected = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.textPrimary : AppColors.metalGrey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          tile.symbol,
          style: TextStyle(color: tile.color, fontSize: 40),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.symbols,
      onConfirm: _confirm,
      children: [
        Text(
          'Descreve os símbolos ao teu parceiro e carrega no símbolo certo.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: List.generate(_tiles.length, _buildTile),
        ),
      ],
    );
  }
}
