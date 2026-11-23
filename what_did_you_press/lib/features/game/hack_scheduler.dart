import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/manual_data.dart';

/// Builds one scheduler per game. Overridable so tests can launch attacks
/// within a few seconds.
final hackSchedulerProvider = Provider<HackScheduler Function()>(
  (ref) =>
      () => HackScheduler(Random()),
);

/// Decides when the hackers attack. Only the operator (the authority, like
/// the bomb timer) runs it, once per heartbeat second, and only while no
/// attack is active, so each pause is counted from the last counter-attack.
class HackScheduler {
  HackScheduler(
    this._random, {
    this.firstDelay = (min: 40, max: 70),
    this.pause = (min: 50, max: 90),
  }) : _ticksLeft = 0 {
    _ticksLeft = _draw(firstDelay);
  }

  final Random _random;

  /// Seconds before the first attack and between attacks.
  final ({int min, int max}) firstDelay;
  final ({int min, int max}) pause;
  int _ticksLeft;

  int _draw(({int min, int max}) range) =>
      range.min + _random.nextInt(range.max - range.min + 1);

  /// One quiet second; returns the attack to launch when the pause ends.
  HackType? tick() {
    if (--_ticksLeft > 0) return null;
    _ticksLeft = _draw(pause);
    return HackType.values[_random.nextInt(HackType.values.length)];
  }
}
