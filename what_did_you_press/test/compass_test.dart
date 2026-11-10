import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/features/game/modules/compass_module.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/modules/compass_controller.dart';
import 'package:what_did_you_press/services/compass_service.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('hold aligns the pointer and release locks the answer', (
    tester,
  ) async {
    final readings = StreamController<CompassSample>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compassHeadingProvider.overrideWith((ref) => readings.stream),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const CompassModulePage(),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);
    expect(
      tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled,
      isFalse,
    );
    readings.add(const CompassSample(heading: 10, accuracyDegrees: 5));
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
    readings.add(const CompassSample(heading: 45, accuracyDegrees: 5));
    await tester.pump();
    expect(find.text('45°'), findsOneWidget);
    expect(
      tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled,
      isFalse,
    );
    await press.up();
    await tester.pump();
    readings.add(const CompassSample(heading: 180, accuracyDegrees: 5));
    await tester.pump();
    expect(find.text('45°'), findsOneWidget);
    expect(
      tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(readings.close);
  });

  test(
    'heading changes only while aligning and stays locked on release',
    () async {
      final readings = StreamController<CompassSample>();
      final container = ProviderContainer(
        overrides: [
          compassHeadingProvider.overrideWith((ref) => readings.stream),
        ],
      );
      final subscription = container.listen(
        compassAlignmentProvider,
        (_, _) {},
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await readings.close();
      });
      final controller = container.read(compassAlignmentProvider.notifier);
      Future<void> emit(double heading) async {
        readings.add(CompassSample(heading: heading, accuracyDegrees: 5));
        await Future<void>.delayed(Duration.zero);
      }

      await emit(10);
      expect(container.read(compassAlignmentProvider).sample, isNull);
      controller.startAlignment();
      await emit(45);
      expect(container.read(compassAlignmentProvider).sample!.heading, 45);
      controller.lockAlignment();
      await emit(180);
      expect(container.read(compassAlignmentProvider).sample!.heading, 45);
      controller.startAlignment();
      expect(container.read(compassAlignmentProvider).sample!.heading, 180);
      await emit(359);
      controller.lockAlignment();
      expect(container.read(compassAlignmentProvider).sample!.heading, 359);
      expect(container.read(compassAlignmentProvider).isAligning, isFalse);
    },
  );

  test('missing or unreliable readings cannot be submitted', () {
    expect(const CompassSample(heading: null).canConfirm(15), isFalse);
    expect(const CompassSample(heading: double.nan).canConfirm(15), isFalse);
    expect(
      const CompassSample(heading: 45, accuracyDegrees: 16).canConfirm(15),
      isFalse,
    );
    expect(
      const CompassSample(heading: 45, shouldCalibrate: true).canConfirm(15),
      isFalse,
    );
    expect(
      const CompassSample(heading: 45, accuracyDegrees: 15).canConfirm(15),
      isTrue,
    );
    // Some devices supply a heading without an uncertainty estimate.
    expect(const CompassSample(heading: 45).canConfirm(15), isTrue);
  });

  test(
    'a sensor failure while aligning invalidates the captured heading',
    () async {
      var cancelled = false;
      final readings = StreamController<CompassSample>(
        onCancel: () => cancelled = true,
      );
      final container = ProviderContainer(
        overrides: [
          compassHeadingProvider.overrideWith((ref) => readings.stream),
        ],
      );
      final subscription = container.listen(
        compassAlignmentProvider,
        (_, _) {},
      );
      final controller = container.read(compassAlignmentProvider.notifier);
      controller.startAlignment();
      readings.add(const CompassSample(heading: 45, accuracyDegrees: 5));
      await Future<void>.delayed(Duration.zero);
      readings.addError(StateError('Sensor disconnected'));
      await Future<void>.delayed(Duration.zero);
      controller.lockAlignment();
      expect(container.read(compassAlignmentProvider).sample, isNull);
      subscription.close();
      container.dispose();
      await readings.close();
      expect(cancelled, isTrue);
    },
  );
}
