import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class DrawingModulePage extends StatefulWidget {
  const DrawingModulePage({
    super.key,
    this.variant = 0,
    this.onDrawingChanged,
    this.onDrawingCompleted,
  });

  final int variant;
  final ValueChanged<List<Stroke>>? onDrawingChanged;
  final ValueChanged<List<Stroke>>? onDrawingCompleted;

  @override
  State<DrawingModulePage> createState() => _DrawingModulePageState();
}

class _DrawingModulePageState extends State<DrawingModulePage> {
  late final Glyph _glyph = glyphs[widget.variant % glyphs.length];
  WireColor? _selected;

  @override
  void initState() {
    super.initState();
    liveDrawing.value = [];
    widget.onDrawingChanged?.call(const []);
  }

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == _glyph.wire);
  }

  Widget _buildWire(WireColor wire) {
    final isSelected = wire == _selected;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selected = wire),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: wire.color.withValues(alpha: isSelected ? 1 : 0.3),
            border: Border.all(
              color: isSelected ? AppColors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            wire.label,
            style: TextStyle(
              color: isSelected ? AppColors.background : AppColors.textPrimary,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.drawing,
      subtitle: 'Desenha o símbolo para o manual e corta o fio indicado.',
      onConfirm: _confirm,
      children: [
        Text(
          'Desenha o símbolo para o teu parceiro e corta o fio que ele indicar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: glowingCardDecoration(
            glowColor: AppColors.neonPurple.withValues(alpha: 0.18),
            borderColor: AppColors.neonPurple.withValues(alpha: 0.5),
          ),
          child: Column(
            children: [
              Text('SÍMBOLO', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                width: 96,
                child: DrawingView(
                  strokes: _glyph.lines,
                  color: AppColors.neonPurple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DrawingPad(
          color: AppColors.neonPurple,
          onChanged: (strokes) {
            liveDrawing.value = strokes;
            widget.onDrawingChanged?.call(strokes);
          },
          onStrokeEnd: widget.onDrawingCompleted,
        ),
        const SizedBox(height: 24),
        Text(
          'FIOS',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final wire in WireColor.values) ...[
              _buildWire(wire),
              if (wire != WireColor.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}
