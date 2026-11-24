import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/drawing.dart';

void main() {
  testWidgets('ink fades even while the finger never lifts', (tester) async {
    var reported = <Stroke>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: DrawingPad(
              color: Colors.purple,
              inkFade: const Duration(milliseconds: 200),
              onChanged: (strokes) => reported = strokes,
            ),
          ),
        ),
      ),
    );
    List<Stroke> visible() => tester
        .widget<DrawingView>(
          find.descendant(
            of: find.byType(DrawingPad),
            matching: find.byType(DrawingView),
          ),
        )
        .strokes;

    final start = tester.getCenter(find.byType(DrawingPad));
    final finger = await tester.startGesture(start);
    for (var i = 0; i < 5; i++) {
      await finger.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    expect(visible().single, hasLength(6));

    // Real time: the pad ages points with a Stopwatch.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await finger.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(visible().single, hasLength(1), reason: 'only the newest point');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(visible(), isEmpty);
    expect(reported.single, hasLength(7), reason: 'the partner gets it all');

    await finger.up();
    await tester.pump(const Duration(milliseconds: 60));
  });
}
