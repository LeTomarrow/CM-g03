import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/features/game/hack_effects.dart';

void main() {
  Future<int Function()> pumpShield(WidgetTester tester, bool active) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HackShield(
          active: active,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('CORTAR'),
              ),
            ),
          ),
        ),
      ),
    );
    return () => taps;
  }

  testWidgets('the screen attack swallows every touch', (tester) async {
    final taps = await pumpShield(tester, true);
    await tester.tap(find.text('CORTAR'), warnIfMissed: false);
    await tester.pump();
    expect(taps(), 0);
    expect(find.textContaining('BLOQUEADO'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without an attack the screen is usable', (tester) async {
    final taps = await pumpShield(tester, false);
    await tester.tap(find.text('CORTAR'));
    expect(taps(), 1);
    expect(find.textContaining('BLOQUEADO'), findsNothing);
  });

  testWidgets('the shake keeps the page state when it starts and ends', (
    tester,
  ) async {
    final controller = ScrollController();
    Widget page(bool active) => MaterialApp(
      home: HackShake(
        active: active,
        child: ListView(
          controller: controller,
          children: [for (var i = 0; i < 100; i++) Text('regra $i')],
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    controller.jumpTo(500);
    await tester.pumpWidget(page(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, 500);
    await tester.pumpWidget(page(false));
    expect(controller.offset, 500);
  });
}
