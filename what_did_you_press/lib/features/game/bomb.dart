import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/segment_display.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/game/modules/compass_module.dart';
import 'package:what_did_you_press/features/game/modules/drawing_module.dart';
import 'package:what_did_you_press/features/game/modules/gyro_module.dart';
import 'package:what_did_you_press/features/game/modules/morse_module.dart';
import 'package:what_did_you_press/features/game/modules/symbols_module.dart';
import 'package:what_did_you_press/features/game/result.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/services/game_transport.dart';
import 'package:what_did_you_press/features/app_state.dart';

class BombPage extends ConsumerStatefulWidget {
  const BombPage({super.key, this.onFinished, this.transport});

  /// Called once with the final result (defused, exploded or abandoned when
  /// the partner left); this page is gone by then.
  final void Function(BombEngineStatus result)? onFinished;
  final GameTransport? transport;

  @override
  ConsumerState<BombPage> createState() => _BombPageState();
}

class _BombPageState extends ConsumerState<BombPage> {
  static const int _maxStrikes = 3;

  bool _ended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(gameControllerProvider.notifier)
            .start(
              moduleCount: ModuleType.values.length,
              transport: widget.transport,
            ),
      );
      final name = ref.read(profileProvider).asData?.value.name;
      if (name != null) {
        ref.read(gameControllerProvider.notifier).dispatch(PlayerNameSet(name));
      }
    });
  }

  Future<void> _endGame(bool defused, {String reason = 'game_finished'}) async {
    if (_ended) return;
    _ended = true;
    final game = ref.read(gameControllerProvider);
    final abandoned = game.status == BombEngineStatus.abandoned;
    if (!abandoned) {
      unawaited(
        ref.read(profileProvider.notifier).recordGame(defused: defused),
      );
    }
    widget.onFinished?.call(
      abandoned
          ? BombEngineStatus.abandoned
          : defused
          ? BombEngineStatus.defused
          : BombEngineStatus.exploded,
    );
    try {
      await ref
          .read(gameControllerProvider.notifier)
          .dispatch(GameEndAnnounced(defused: defused, reason: reason));
    } catch (_) {
      // Local result must still be shown if the peer has already disconnected.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ResultPage(
          defused: defused,
          timeLeft: game.timeLeft,
          strikes: game.strikes,
          abandoned: abandoned,
          notice: abandoned ? game.connectionNotice : null,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmLeaveGame(
      context,
      'A bomba explode e o jogo conta como perdido.',
    );
    if (leave && mounted) unawaited(_endGame(false, reason: 'operator_left'));
  }

  Widget _pageFor(ModuleType type, int variant) {
    final controller = ref.read(gameControllerProvider.notifier);
    return switch (type) {
      ModuleType.gyro => GyroModulePage(variant: variant),
      ModuleType.compass => CompassModulePage(variant: variant),
      ModuleType.morse => MorseModulePage(variant: variant),
      ModuleType.symbols => SymbolsModulePage(variant: variant),
      ModuleType.drawing => DrawingModulePage(
        variant: variant,
        onDrawingChanged: (strokes) =>
            controller.dispatch(DrawingChanged(strokes)),
        onDrawingCompleted: (strokes) =>
            controller.dispatch(DrawingCompleted(strokes)),
      ),
    };
  }

  Future<void> _openModule(int moduleIndex) async {
    final module = ref
        .read(gameControllerProvider)
        .loadout
        .modules[moduleIndex];
    final controller = ref.read(gameControllerProvider.notifier);
    controller.dispatch(ModuleOpened(moduleIndex));
    final solved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _pageFor(module.type, module.variant),
      ),
    );
    controller.dispatch(const ModuleClosed());
    if (!mounted || solved == null) return;
    controller.dispatch(
      solved ? SolveModuleRequested(moduleIndex) : StrikeRequested(moduleIndex),
    );
  }

  Widget _buildModuleCard(int index, BombModuleState module) {
    final color = module.solved ? AppColors.textDim : module.type.color;

    return InkWell(
      onTap: module.solved ? null : () => _openModule(index),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: module.solved ? AppColors.success : module.type.color,
            width: module.solved ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (module.solved ? AppColors.success : module.type.color)
                  .withValues(alpha: 0.12),
              blurRadius: 12,
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: StatusLed(
                  color: module.solved ? AppColors.success : AppColors.danger,
                ),
              ),
              const SizedBox(height: 4),
              Icon(module.type.icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(module.type.label, style: TextStyle(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameControllerProvider);
    ref.listen<GameState>(gameControllerProvider, (previous, next) {
      if (_ended) return;
      if (next.status == BombEngineStatus.defused) {
        unawaited(_endGame(true));
      }
      if (next.status == BombEngineStatus.abandoned) {
        unawaited(_endGame(false, reason: 'opponent_left'));
      }
      if (next.status == BombEngineStatus.exploded) {
        unawaited(_endGame(false));
      }
    });
    final isCritical = game.timeLeft.inSeconds < 60;

    // Back button / gesture asks first instead of silently quitting.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.danger,
          title: Text('BOMBA · ${game.playerName}'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.mic, color: AppColors.success),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: glowingCardDecoration(
                  glowColor: isCritical
                      ? AppColors.dangerGlow
                      : AppColors.amberGlow,
                ),
                child: Column(
                  children: [
                    Text(
                      'TEMPO RESTANTE',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SegmentDisplay(
                      text: formatTime(game.timeLeft),
                      color: isCritical ? AppColors.led : AppColors.amber,
                      height: 64,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'ERROS',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  for (int i = 0; i < _maxStrikes; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: StatusLed(
                        color: i < game.strikes
                            ? AppColors.danger
                            : AppColors.metalGrey,
                        size: 14,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'MÓDULOS',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
              ),
              const SizedBox(height: 16),
              if (game.manualFocus != null) ...[
                Text(
                  'O MANUAL ESTÁ A CONSULTAR: ${game.loadout.modules[game.manualFocus!].type.label}',
                  style: const TextStyle(color: AppColors.neonBlue),
                ),
                const SizedBox(height: 12),
              ],
              if (game.connectionNotice != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  color: AppColors.danger.withValues(alpha: 0.2),
                  child: Text(
                    game.connectionNotice!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  for (var i = 0; i < game.loadout.modules.length; i++)
                    _buildModuleCard(i, game.loadout.modules[i]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
