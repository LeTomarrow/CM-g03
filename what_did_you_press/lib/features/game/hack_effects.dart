import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';

/// Operator side of the "screen flash" attack, read from the game state.
class HackFlash extends ConsumerWidget {
  const HackFlash({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flashing = ref.watch(
      gameControllerProvider.select((game) => game.hack == HackType.flash),
    );
    return HackShield(active: flashing, child: child);
  }
}

/// Locks the screen under a pulsing veil that swallows every touch, so the
/// operator is stuck (with the timer running) until the manual counters it.
/// The pulse stays below one per second and only between two bright levels,
/// never a full on/off flash, for players sensitive to flashing light.
class HackShield extends StatefulWidget {
  const HackShield({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<HackShield> createState() => _HackShieldState();
}

class _HackShieldState extends State<HackShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HackShield oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            // Opaque to hits: nothing underneath can be pressed or scrolled.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onVerticalDragStart: (_) {},
              onHorizontalDragStart: (_) {},
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: Tween(begin: 0.8, end: 0.97).animate(_pulse),
                      child: const ColoredBox(color: AppColors.textPrimary),
                    ),
                  ),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'ECRÃ BLOQUEADO PELOS HACKERS\n'
                        'Pede ao manual para travar o ataque no terminal.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.background,
                          fontSize: 18,
                          height: 1.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Manual side of the "continuous vibration" attack: besides the buzzing,
/// the page jitters and blurs so the rules are hard to read. Only motion and
/// blur, no brightness changes.
class HackShake extends StatefulWidget {
  const HackShake({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<HackShake> createState() => _HackShakeState();
}

class _HackShakeState extends State<HackShake>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 60),
  )..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HackShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !_ticker.isAnimating) {
      _ticker.repeat();
    } else if (!widget.active && _ticker.isAnimating) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same widget structure either way, so the child (and its scroll
    // position) survives the attack starting and ending.
    double jitter() => widget.active ? (_random.nextDouble() - 0.5) * 18 : 0;
    return ImageFiltered(
      enabled: widget.active,
      imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
      child: Transform.translate(
        offset: Offset(jitter(), jitter()),
        child: widget.child,
      ),
    );
  }
}

/// Operator banner: the operator cannot stop an attack, only warn the manual.
class HackWarning extends ConsumerWidget {
  const HackWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hack = ref.watch(gameControllerProvider.select((game) => game.hack));
    if (hack == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      color: AppColors.danger.withValues(alpha: 0.2),
      child: Text(
        'ATAQUE HACKER — ${hack.symptom}. Avisa o manual: só ele o pode '
        'travar no terminal.',
        style: const TextStyle(color: AppColors.danger),
      ),
    );
  }
}
