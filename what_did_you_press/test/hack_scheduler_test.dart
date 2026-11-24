import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/hack_scheduler.dart';

void main() {
  test('first attack after the first delay, then after each pause', () {
    final scheduler = HackScheduler(
      Random(7),
      firstDelay: (min: 3, max: 3),
      pause: (min: 2, max: 2),
    );
    final launches = [for (var i = 0; i < 7; i++) scheduler.tick()];
    expect(launches.map((hack) => hack != null), [
      false, false, true, // 3 s
      false, true, // 2 s
      false, true, // 2 s
    ]);
  });

  test('default timing stays within the configured ranges', () {
    for (var seed = 0; seed < 50; seed++) {
      final scheduler = HackScheduler(Random(seed));
      var seconds = 1;
      while (scheduler.tick() == null) {
        seconds++;
      }
      expect(seconds, inInclusiveRange(40, 70));
    }
  });

  test('every attack type can be launched', () {
    final scheduler = HackScheduler(
      Random(1),
      firstDelay: (min: 1, max: 1),
      pause: (min: 1, max: 1),
    );
    final seen = <HackType>{for (var i = 0; i < 100; i++) scheduler.tick()!};
    expect(seen, HackType.values.toSet());
  });
}
