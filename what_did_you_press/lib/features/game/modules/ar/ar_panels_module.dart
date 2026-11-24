import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/ar/ar_view.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:what_did_you_press/services/ar_pose_service.dart';

/// AR "control room": eight panels float around the operator, who has to
/// turn around the real room to find the alarm and the panel to activate.
class ArPanelsModulePage extends StatefulWidget {
  const ArPanelsModulePage({super.key, this.variant = 0});

  /// Degrees between neighbouring panels.
  static const double spacing = 360 / arPanelCount;

  /// How far off-centre the crosshair may be and still select a panel.
  static const double aimTolerance = 18;

  final int variant;

  /// The panel under the crosshair for [pose], if any.
  static int? aimAt(ArPose pose) {
    if (pose.pitch.abs() > 20) return null;
    for (var i = 0; i < arPanelCount; i++) {
      if (angleDelta(i * spacing, pose.yaw).abs() <= aimTolerance) return i;
    }
    return null;
  }

  @override
  State<ArPanelsModulePage> createState() => _ArPanelsModulePageState();
}

class _ArPanelsModulePageState extends State<ArPanelsModulePage> {
  late final _puzzle = arPanelPuzzle(widget.variant);
  int? _aimed = ArPanelsModulePage.aimAt(const ArPose(yaw: 0, pitch: 0));

  void _onPose(ArPose pose) {
    final aimed = ArPanelsModulePage.aimAt(pose);
    if (aimed != _aimed) setState(() => _aimed = aimed);
  }

  void _confirm() {
    if (_aimed == null) return;
    Navigator.of(
      context,
    ).pop(_aimed == solveArPanels(_puzzle.panels, _puzzle.alarm));
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.arPanels,
      subtitle:
          'Procura o alarme à tua volta e ativa o painel que o manual '
          'indicar.',
      onConfirm: _confirm,
      confirmEnabled: _aimed != null,
      children: [
        Text(
          'Segura o telemóvel na vertical e roda sobre ti próprio. Descreve o '
          'painel do alarme e os vizinhos ao teu parceiro; aponta a mira ao '
          'painel certo e confirma.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        ArView(
          onPose: _onPose,
          objects: (pose) => [
            for (var i = 0; i < arPanelCount; i++)
              ArObject(
                azimuth: i * ArPanelsModulePage.spacing,
                elevation: 0,
                size: 88,
                child: ArPanelCard(
                  panel: _puzzle.panels[i],
                  alarm: i == _puzzle.alarm,
                  aimed: i == _aimed,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ArPanelCard extends StatefulWidget {
  const ArPanelCard({
    super.key,
    required this.panel,
    required this.alarm,
    required this.aimed,
  });

  final ArPanel panel;
  final bool alarm;
  final bool aimed;

  @override
  State<ArPanelCard> createState() => _ArPanelCardState();
}

class _ArPanelCardState extends State<ArPanelCard>
    with SingleTickerProviderStateMixin {
  // A slow pulse on the alarm's frame only (well under 3 Hz).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.alarm) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.85),
          border: Border.all(
            color: widget.alarm
                ? Color.lerp(
                    AppColors.led,
                    AppColors.textPrimary,
                    _pulse.value,
                  )!
                : widget.aimed
                ? AppColors.textPrimary
                : panel.color.color,
            width: widget.alarm || widget.aimed ? 4 : 2,
          ),
        ),
        child: child,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: panel.lit ? AppColors.amber : AppColors.metalGrey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            panel.symbol,
            style: TextStyle(color: panel.color.color, fontSize: 30),
          ),
          if (widget.alarm)
            const Text(
              'ALARME',
              style: TextStyle(color: AppColors.led, fontSize: 10),
            ),
        ],
      ),
    );
  }
}
