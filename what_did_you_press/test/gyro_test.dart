import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/features/game/modules/gyro_controller.dart';
import 'package:what_did_you_press/features/game/modules/gyro_module.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:what_did_you_press/services/tilt_service.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('tiltFromGravity', () {
    test('upright portrait is 0°', () {
      expect(tiltFromGravity(0, 9.8).angle, closeTo(0, 0.01));
    });

    test('rotating clockwise increases the angle', () {
      expect(tiltFromGravity(-9.8, 0).angle, closeTo(90, 0.01));
      expect(tiltFromGravity(0, -9.8).angle, closeTo(180, 0.01));
      expect(tiltFromGravity(9.8, 0).angle, closeTo(270, 0.01));
      expect(tiltFromGravity(-6.93, 6.93).angle, closeTo(45, 0.1));
    });

    test('phone lying flat has no angle', () {
      expect(tiltFromGravity(0.5, 1).hasAngle, isFalse);
    });
  });

  testWidgets('hold follows the sensor and release locks the angle', (
    tester,
  ) async {
    final readings = StreamController<TiltSample>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tiltProvider.overrideWith((ref) => readings.stream)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const GyroModulePage(),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);
    bool confirmEnabled() =>
        tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled;
    expect(confirmEnabled(), isFalse);

    readings.add(const TiltSample(angle: 10));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('MANTER PARA ALINHAR'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final press = await tester.startGesture(
      tester.getCenter(find.text('MANTER PARA ALINHAR')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    readings.add(const TiltSample(angle: 45));
    await tester.pump();
    expect(find.text('45°'), findsOneWidget);
    expect(confirmEnabled(), isFalse);

    await press.up();
    await tester.pump();
    readings.add(const TiltSample(angle: 200));
    await tester.pump();
    expect(find.text('45°'), findsOneWidget);
    expect(confirmEnabled(), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(readings.close);
  });
}
