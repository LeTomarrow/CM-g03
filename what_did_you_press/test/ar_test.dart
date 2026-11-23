import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/ar/ar_detector_module.dart';
import 'package:what_did_you_press/features/game/modules/ar/ar_panels_module.dart';
import 'package:what_did_you_press/features/game/modules/ar/ar_view.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';
import 'package:what_did_you_press/services/ar_pose_service.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('arPoseFrom: direction of the back camera', () {
    // Northern-hemisphere field: horizontal component north, plus downward.
    const bh = 20.0, bv = 40.0;

    test('upright, facing north', () {
      // North is the camera axis (−z), down is −y.
      final pose = arPoseFrom((x: 0, y: 9.8, z: 0), (x: 0, y: -bv, z: -bh));
      expect(pose.yaw, closeTo(0, 0.01));
      expect(pose.pitch, closeTo(0, 0.01));
    });

    test('upright, turned right to face east', () {
      // North is now to the device's left (−x).
      final pose = arPoseFrom((x: 0, y: 9.8, z: 0), (x: -bh, y: -bv, z: 0));
      expect(pose.yaw, closeTo(90, 0.01));
    });

    test('tilted back 30° to look up keeps the bearing', () {
      const c = 0.8660254, s = 0.5; // cos/sin 30°
      // Rotating the device about x: camera axis rises by 30°.
      final pose = arPoseFrom(
        (x: 0, y: 9.8 * c, z: -9.8 * s),
        (x: 0, y: -bv * c - bh * s, z: -bh * c + bv * s),
      );
      expect(pose.yaw, closeTo(0, 0.01));
      expect(pose.pitch, closeTo(30, 0.01));
    });

    test('no readings means no pose', () {
      expect(
        arPoseFrom((x: 0, y: 0, z: 0), (x: 1, y: 1, z: 1)).isAvailable,
        isFalse,
      );
    });
  });

  group('arProject', () {
    const size = Size(300, 360);
    const ahead = ArPose(yaw: 350, pitch: 0);

    test('straight ahead is the centre, wrapping around 0°', () {
      final point = arProject(
        azimuth: 350,
        elevation: 0,
        view: ahead,
        size: size,
      )!;
      expect(point, const Offset(150, 180));
      final right = arProject(
        azimuth: 20,
        elevation: 0,
        view: ahead,
        size: size,
      )!;
      expect(right.dx, closeTo(150 + 30 / 60 * 300, 0.01));
    });

    test('higher objects are drawn higher; behind is hidden', () {
      final up = arProject(
        azimuth: 350,
        elevation: 10,
        view: ahead,
        size: size,
      )!;
      expect(up.dy, lessThan(180));
      expect(
        arProject(azimuth: 170, elevation: 0, view: ahead, size: size),
        isNull,
      );
    });
  });

  group('Sala de controlo', () {
    ArPanel panel(WireColor color, String symbol, bool lit) =>
        ArPanel(color, symbol, lit: lit);

    test('lit alarm counts right by its shape', () {
      final panels = List.generate(8, (_) => panel(WireColor.blue, '●', false));
      panels[2] = panel(WireColor.red, '▲', true); // alarm: 2 steps right
      expect(solveArPanels(panels, 2), 4);
    });

    test('unlit counts left, wraps, and skips a same-colour panel', () {
      final panels = List.generate(8, (_) => panel(WireColor.blue, '●', false));
      panels[1] = panel(WireColor.green, '★', false); // 1 step left → 0
      panels[0] = panel(WireColor.green, '■', true); // same colour → skip
      expect(solveArPanels(panels, 1), 7);
    });

    test('generated puzzles always have a valid answer', () {
      for (var variant = 0; variant < 300; variant++) {
        final puzzle = arPanelPuzzle(variant);
        expect(solveArPanels(puzzle.panels, puzzle.alarm), isNot(puzzle.alarm));
      }
    });

    test('the crosshair selects the panel within tolerance', () {
      expect(ArPanelsModulePage.aimAt(const ArPose(yaw: 3, pitch: 5)), 0);
      expect(ArPanelsModulePage.aimAt(const ArPose(yaw: 100, pitch: 0)), 2);
      expect(
        ArPanelsModulePage.aimAt(const ArPose(yaw: 22.5, pitch: 0)),
        isNull,
      );
      expect(ArPanelsModulePage.aimAt(const ArPose(yaw: 0, pitch: 40)), isNull);
    });
  });

  group('Detetor', () {
    test('bearing from the symbol plus tens, height from parity', () {
      final target = solveArDetector('●', 3, 7);
      expect(target.azimuth, 165);
      expect(target.elevation, arDetectorLow);
      final wrapped = solveArDetector('◆', 9, 4);
      expect(wrapped.azimuth, 45); // 315 + 90 = 405 → 45
      expect(wrapped.elevation, arDetectorHigh);
    });

    test('the signal only appears near the part', () {
      const target = (azimuth: 165.0, elevation: 25.0);
      expect(
        ArDetectorModulePage.distance(
          const ArPose(yaw: 165, pitch: 25),
          target,
        ),
        0,
      );
      expect(ArDetectorModulePage.signal(0), 1);
      expect(ArDetectorModulePage.signal(45), 0);
      expect(ArDetectorModulePage.signal(15), closeTo(0.5, 0.01));
    });
  });

  group('widgets', () {
    // A reading lands while the view builds; the module reacts on the next
    // frame (the real app keeps producing frames for the camera).
    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
    }

    Future<StreamController<ArPose>> pumpModule(
      WidgetTester tester,
      Widget page,
    ) async {
      final poses = StreamController<ArPose>();
      // Tall enough for the whole AR view to be on screen and hittable.
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [arPoseProvider.overrideWith((ref) => poses.stream)],
          child: MaterialApp(theme: AppTheme.darkTheme, home: page),
        ),
      );
      addTearDown(poses.close);
      return poses;
    }

    testWidgets('panels follow the sensor, relative to the opening bearing', (
      tester,
    ) async {
      final poses = await pumpModule(tester, const ArPanelsModulePage());
      bool enabled() =>
          tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled;

      // Opening bearing 200° becomes 0°: panel 0 is straight ahead.
      poses.add(const ArPose(yaw: 200, pitch: 0));
      await frames(tester);
      expect(enabled(), isTrue);
      // 22.5° off: between two panels, nothing to confirm.
      poses.add(const ArPose(yaw: 222.5, pitch: 0));
      await frames(tester);
      expect(enabled(), isFalse);
      poses.add(const ArPose(yaw: 290, pitch: 0)); // 90° right → panel 2
      await frames(tester);
      expect(enabled(), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without sensors, dragging looks around', (tester) async {
      final poses = await pumpModule(tester, const ArPanelsModulePage());
      poses.add(ArPose.unavailable);
      await frames(tester);
      expect(find.textContaining('arrasta'), findsOneWidget);
      bool enabled() =>
          tester.widget<ModuleFrame>(find.byType(ModuleFrame)).confirmEnabled;
      expect(enabled(), isTrue);
      // Drag left by 75 px → look 22.5° right: between panels 0 and 1.
      await tester.drag(find.byType(ArView), const Offset(-75, 0));
      await frames(tester);
      expect(enabled(), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the detector part appears only when aimed close to it', (
      tester,
    ) async {
      const variant = 11;
      final puzzle = arDetectorPuzzle(variant);
      final target = solveArDetector(
        puzzle.symbol,
        puzzle.first,
        puzzle.second,
      );
      final poses = await pumpModule(
        tester,
        const ArDetectorModulePage(variant: variant),
      );
      poses.add(const ArPose(yaw: 0, pitch: 0));
      await frames(tester);
      expect(find.byIcon(Icons.memory), findsNothing);
      expect(find.text('BASE'), findsOneWidget);
      expect(
        find.textContaining('${puzzle.first}  ${puzzle.second}'),
        findsOneWidget,
      );

      poses.add(ArPose(yaw: target.azimuth, pitch: target.elevation));
      await frames(tester);
      expect(find.byIcon(Icons.memory), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
