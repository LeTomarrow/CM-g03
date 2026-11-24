import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/segment_display.dart';
import 'package:what_did_you_press/features/account.dart';
import 'package:what_did_you_press/features/configs.dart';
import 'package:what_did_you_press/features/help.dart';
import 'package:what_did_you_press/features/lobby.dart';
import 'package:what_did_you_press/features/world/world.dart';
import 'package:what_did_you_press/features/update/update_ui.dart';

/// The menu is the bomb's wiring: cut a wire to open that screen.
class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: GamePage(),
    );
  }
}

/// One wire: classic bomb wire colours, and where its tape label sits (0–1).
class _Wire {
  const _Wire(this.label, this.color, this.tagAt, this.tilt, this.open);

  final String label;
  final Color color;
  final double tagAt;
  final double tilt;
  final Widget Function() open;
}

final _wires = [
  _Wire('Jogar', WireColors.red, 0.18, -0.02, () => const LobbyPage()),
  _Wire('Mundo', WireColors.blue, 0.52, 0.015, () => const WorldPage()),
  _Wire('Ajuda', WireColors.yellow, 0.3, -0.01, () => const HelpPage()),
  _Wire('Definições', WireColors.white, 0.44, 0.02, () => const ConfigsPage()),
  _Wire('Perfil', WireColors.black, 0.24, -0.015, () => const AccountPage()),
];

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdateOnStart(context);
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  String get _time =>
      '${_now.hour.toString().padLeft(2, '0')}:'
      '${_now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final title = GoogleFonts.barlowCondensed(
      color: AppColors.textPrimary,
      fontSize: 64,
      fontWeight: FontWeight.w800,
      height: 0.88,
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What did you\npress?!', style: title),
                      const SizedBox(height: 14),
                      Text(
                        'Um desarma a bomba, o outro lê o manual. '
                        'Só falando é que se safam.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // The device: clock and wiring, within thumb reach.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ClockPlate(time: _time, colon: _now.second.isEven),
                      const SizedBox(height: 20),
                      for (final wire in _wires) _CutWire(wire: wire),
                      const SizedBox(height: 12),
                      Text(
                        'Corta um fio para continuar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recessed plate holding the LED clock, screwed to the casing.
class _ClockPlate extends StatelessWidget {
  const _ClockPlate({required this.time, required this.colon});

  final String time;
  final bool colon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E100C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.metalGrey, width: 2),
      ),
      child: SegmentDisplay(
        text: time,
        color: AppColors.led,
        height: 44,
        colonVisible: colon,
      ),
    );
  }
}

class _CutWire extends StatefulWidget {
  const _CutWire({required this.wire});

  final _Wire wire;

  @override
  State<_CutWire> createState() => _CutWireState();
}

class _CutWireState extends State<_CutWire>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cut = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  double _cutAt = 0.75;
  bool _busy = false;

  @override
  void dispose() {
    _cut.dispose();
    super.dispose();
  }

  Future<void> _snip(double at) async {
    if (_busy) return;
    _busy = true;
    // Never cut through the tape label.
    final tag = widget.wire.tagAt;
    _cutAt = (at - tag).abs() < 0.2 ? (tag + 0.35).clamp(0.1, 0.9) : at;
    HapticFeedback.heavyImpact();
    if (!MediaQuery.of(context).disableAnimations) {
      await _cut.forward(from: 0);
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => widget.wire.open()));
    // Back from the screen: the wire has been fixed.
    if (mounted) _cut.value = 0;
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final wire = widget.wire;
    return Semantics(
      button: true,
      label: wire.label,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) =>
              _snip(details.localPosition.dx / constraints.maxWidth),
          child: SizedBox(
            height: 64,
            child: AnimatedBuilder(
              animation: _cut,
              builder: (context, child) => CustomPaint(
                painter: _WirePainter(
                  color: wire.color,
                  cutAt: _cutAt,
                  progress: Curves.easeOutBack.transform(_cut.value),
                ),
                child: child,
              ),
              child: Align(
                alignment: Alignment(wire.tagAt * 2 - 1, 0),
                child: Transform.rotate(
                  angle: wire.tilt,
                  child: _Tape(label: wire.label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strip of label-maker tape wrapped around the wire.
class _Tape extends StatelessWidget {
  const _Tape({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 4),
      decoration: BoxDecoration(
        color: AppColors.tape,
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          color: AppColors.background,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.color,
    required this.cutAt,
    required this.progress,
  });

  final Color color;
  final double cutAt;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final y = size.height / 2;
    final left = Offset(inset, y);
    final right = Offset(size.width - inset, y);
    final thickness = 9.0;

    Path sagging(Offset from, Offset to, double sag) => Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2,
        (from.dy + to.dy) / 2 + sag,
        to.dx,
        to.dy,
      );

    final paths = <Path>[];
    final tips = <Offset>[];
    if (progress == 0) {
      paths.add(sagging(left, right, 6));
    } else {
      // The two loose ends spring apart and drop.
      final cutX = left.dx + (right.dx - left.dx) * cutAt;
      final gap = 10 * progress;
      final drop = 14 * progress;
      final leftEnd = Offset(cutX - gap, y + drop);
      final rightEnd = Offset(cutX + gap, y + drop * 0.8);
      paths
        ..add(sagging(left, leftEnd, 4 + 4 * progress))
        ..add(sagging(rightEnd, right, 4 + 4 * progress));
      tips.addAll([leftEnd, rightEnd]);
    }

    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness + 2
      ..strokeCap = StrokeCap.round;
    final insulation = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final path in paths) {
      canvas.drawPath(path.shift(const Offset(0, 3)), outline);
      canvas.drawPath(path, insulation);
      canvas.drawPath(path.shift(const Offset(0, -2)), shine);
    }

    // Bare copper where the wire was cut.
    final copper = Paint()..color = AppColors.copper;
    for (final tip in tips) {
      canvas.drawCircle(tip, thickness * 0.32 * progress.clamp(0, 1), copper);
    }

    // Screw terminals holding each end.
    for (final post in [left, right]) {
      canvas.drawCircle(post, 9, Paint()..color = AppColors.metalGrey);
      canvas.drawCircle(post, 9, outline..strokeWidth = 1.5);
      final slot = Paint()
        ..color = AppColors.background
        ..strokeWidth = 2;
      const angle = math.pi / 5;
      final d = Offset(math.cos(angle), math.sin(angle)) * 5;
      canvas.drawLine(post - d, post + d, slot);
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.progress != progress || old.cutAt != cutAt || old.color != color;
}
