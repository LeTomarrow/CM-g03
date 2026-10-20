import 'dart:async';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/game/modules/compass_module.dart';
import 'package:what_did_you_press/features/game/modules/drawing_module.dart';
import 'package:what_did_you_press/features/game/modules/gyro_module.dart';
import 'package:what_did_you_press/features/game/modules/morse_module.dart';
import 'package:what_did_you_press/features/game/modules/symbols_module.dart';
import 'package:what_did_you_press/features/game/result.dart';

class BombPage extends StatefulWidget {
  const BombPage({super.key, this.onFinished});

  /// Called once with `true` if defused; this page is gone by then.
  final void Function(bool defused)? onFinished;

  @override
  State<BombPage> createState() => _BombPageState();
}

class _BombPageState extends State<BombPage> {
  static const int _maxStrikes = 3;

  final List<BombModule> _modules = ModuleType.values
      .map(BombModule.new)
      .toList();
  Duration _timeLeft = const Duration(minutes: 5);
  int _strikes = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    setState(() => _timeLeft -= const Duration(seconds: 1));
    if (_timeLeft <= Duration.zero) _endGame(false);
  }

  void _endGame(bool defused) {
    _timer?.cancel();
    widget.onFinished?.call(defused);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ResultPage(
          defused: defused,
          timeLeft: _timeLeft,
          strikes: _strikes,
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
    if (leave && mounted) _endGame(false);
  }

  Widget _pageFor(ModuleType type) {
    return switch (type) {
      ModuleType.gyro => const GyroModulePage(),
      ModuleType.compass => const CompassModulePage(),
      ModuleType.morse => const MorseModulePage(),
      ModuleType.symbols => const SymbolsModulePage(),
      ModuleType.drawing => const DrawingModulePage(),
    };
  }

  Future<void> _openModule(BombModule module) async {
    final solved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => _pageFor(module.type)),
    );
    if (!mounted || solved == null) return;

    setState(() {
      if (solved) {
        module.defused = true;
      } else {
        _strikes++;
      }
    });

    if (_modules.every((module) => module.defused)) {
      _endGame(true);
    } else if (_strikes >= _maxStrikes) {
      _endGame(false);
    }
  }

  Widget _buildModuleCard(BombModule module) {
    final color = module.defused ? AppColors.textDim : module.type.color;

    return InkWell(
      onTap: module.defused ? null : () => _openModule(module),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.card,
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: StatusLed(
                color: module.defused ? AppColors.success : AppColors.danger,
              ),
            ),
            Icon(module.type.icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(module.type.label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = _timeLeft.inSeconds < 60;

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
          title: Text('BOMBA'),
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
                    Text(
                      formatTime(_timeLeft),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: isCritical ? AppColors.danger : AppColors.amber,
                      ),
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
                        color: i < _strikes
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
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: _modules.map(_buildModuleCard).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
