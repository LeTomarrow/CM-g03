import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/manual/terminal.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/services/room_service.dart';

class ManualPage extends ConsumerStatefulWidget {
  const ManualPage({super.key, this.roomService});

  final RoomService? roomService;

  @override
  ConsumerState<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends ConsumerState<ManualPage> {
  HackType? _activeHack;

  @override
  void initState() {
    super.initState();
    ref
        .read(gameControllerProvider.notifier)
        .start(
          moduleCount: ModuleType.values.length,
          roomService: widget.roomService,
          authority: false,
        );
  }

  // Mockup only: in the real game the hack comes from the other device.
  void _simulateHack() {
    final hacks = HackType.values;
    setState(() => _activeHack = hacks[Random().nextInt(hacks.length)]);
  }

  Future<void> _openTerminal() async {
    final countered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TerminalPage(activeHack: _activeHack),
      ),
    );
    if (!mounted || countered != true) return;
    setState(() => _activeHack = null);
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmLeaveGame(
      context,
      'O teu parceiro fica sozinho com a bomba.',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  Widget _buildSection(String title, Color color, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 20)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String left, String right) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(left, style: TextStyle(color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              right,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppColors.amber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlyph(Glyph glyph) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: DrawingView(
              strokes: glyph.lines,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            glyph.wire.label,
            style: TextStyle(color: glyph.wire.color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textPrimary, height: 1.5),
      ),
    );
  }

  Widget _buildHackBanner(HackType hack) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.danger,
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'CHAT DE VOZ CAÍDO — ${hack.symptom}',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBombStatus() {
    final game = ref.watch(gameControllerProvider);
    return _buildSection('BOMBA EM DIRETO', AppColors.danger, [
      _buildRow('TEMPO', formatTime(game.timeLeft)),
      _buildRow('STRIKES', '${game.strikes}/3'),
      for (final module in game.loadout.modules)
        _buildRow(
          '${module.type.label} · V${module.variant + 1}',
          module.solved
              ? 'RESOLVIDO'
              : module.failureCount == 0
              ? 'PENDENTE'
              : 'FALHAS: ${module.failureCount}',
        ),
    ]);
  }

  Widget _buildBlackout() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 64,
            color: AppColors.textDim,
          ),
          const SizedBox(height: 16),
          Text('SEM LUZ', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 8),
          Text(
            'Os hackers cortaram a energia. Usa o terminal para a repor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, height: 1.5),
          ),
          const SizedBox(height: 32),
          MenuButton(
            label: 'TERMINAL',
            onPressed: _openTerminal,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hack = _activeHack;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.neonBlue,
          title: Text('MANUAL'),
          actions: [
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Simular ataque',
              onPressed: _simulateHack,
            ),
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: 'Abrir terminal',
              onPressed: _openTerminal,
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  if (widget.roomService != null) _buildBombStatus(),
                  if (hack != null) ...[
                    _buildHackBanner(hack),
                    const SizedBox(height: 24),
                  ],
                  _buildSection(ModuleType.gyro.label, ModuleType.gyro.color, [
                    _buildText('Aponta o telemóvel para o ângulo indicado.'),
                    for (final entry in angleTable.entries)
                      _buildRow(entry.key, '${entry.value}°'),
                  ]),
                  _buildSection(
                    ModuleType.compass.label,
                    ModuleType.compass.color,
                    [
                      _buildText('Vira o telemóvel para o ponto cardeal.'),
                      for (final entry in compassTable.entries)
                        _buildRow(entry.key, entry.value),
                    ],
                  ),
                  _buildSection(
                    ModuleType.morse.label,
                    ModuleType.morse.color,
                    [
                      _buildText(
                        'Descodifica a palavra e indica a frequência.',
                      ),
                      for (final entry in morseFrequencies.entries)
                        _buildRow(entry.key, entry.value),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          for (final entry in morseCode.entries)
                            Text(
                              '${entry.key} ${entry.value}',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ],
                  ),
                  _buildSection(
                    ModuleType.symbols.label,
                    ModuleType.symbols.color,
                    [
                      for (int i = 0; i < symbolRules.length; i++)
                        _buildText('${i + 1}. ${symbolRules[i]}'),
                    ],
                  ),
                  _buildSection(
                    ModuleType.drawing.label,
                    ModuleType.drawing.color,
                    [
                      _buildText(
                        'O operador desenha o símbolo que vê. Encontra-o abaixo '
                        'e diz-lhe que fio cortar.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'DESENHO DO OPERADOR (EM DIRETO)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: AppColors.metalGrey),
                        ),
                        child: ValueListenableBuilder<List<Stroke>>(
                          valueListenable: liveDrawing,
                          builder: (context, strokes, _) => DrawingView(
                            strokes: strokes,
                            color: AppColors.neonPurple,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.8,
                        children: [
                          for (final glyph in glyphs) _buildGlyph(glyph),
                        ],
                      ),
                    ],
                  ),
                  _buildSection('HACKERS', AppColors.textPrimary, [
                    for (final type in HackType.values)
                      _buildRow(type.symptom, type.command),
                    const SizedBox(height: 12),
                    _buildText(
                      'Às escuras não vais conseguir ler isto: o terminal '
                      'mostra a senha cifrada. Recua cada letra o número de '
                      'posições do desvio (ex.: desvio +2, D → B).',
                    ),
                  ]),
                ],
              ),
              if (hack == HackType.lights)
                Positioned.fill(child: _buildBlackout()),
            ],
          ),
        ),
      ),
    );
  }
}
