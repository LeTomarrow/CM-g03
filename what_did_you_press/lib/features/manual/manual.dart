import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/manual/terminal.dart';
import 'package:what_did_you_press/features/game/game_controller.dart';
import 'package:what_did_you_press/features/game/hack_effects.dart';
import 'package:what_did_you_press/features/game/game_event.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/game/game_state.dart';
import 'package:what_did_you_press/services/game_transport.dart';
import 'package:what_did_you_press/features/app_state.dart';

class ManualPage extends ConsumerStatefulWidget {
  const ManualPage({super.key, this.transport});

  final GameTransport? transport;

  @override
  ConsumerState<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends ConsumerState<ManualPage> {
  Timer? _hackVibration;
  String? _shownConnectionNotice;
  final ScrollController _scrollController = ScrollController();
  late final AppLifecycleListener _lifecycle;
  final Map<ModuleType, GlobalKey> _sectionKeys = {
    for (final type in ModuleType.values) type: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => ref
          .read(gameControllerProvider.notifier)
          .dispatch(const AppLifecycleChanged(foreground: false)),
      onShow: () => ref
          .read(gameControllerProvider.notifier)
          .dispatch(const AppLifecycleChanged(foreground: true)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(gameControllerProvider.notifier)
            .start(
              moduleCount: BombLoadout.defaultModuleCount,
              transport: widget.transport,
              authority: false,
            ),
      );
      final name = ref.read(profileProvider).asData?.value.name;
      if (name != null) {
        ref.read(gameControllerProvider.notifier).dispatch(PlayerNameSet(name));
      }
    });
  }

  @override
  void dispose() {
    _stopHackVibration();
    _lifecycle.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToDefuserModule(GameState next) {
    final index = next.activeModule;
    if (index == null || index < 0 || index >= next.loadout.modules.length) {
      return;
    }
    final key = _sectionKeys[next.loadout.modules[index].type];
    final target = key?.currentContext;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          alignment: 0.12,
        );
      }
    });
  }

  /// The "continuous vibration" attack buzzes this phone until countered.
  void _syncHackVibration(bool active) {
    if (!active) return _stopHackVibration();
    if (_hackVibration != null) return;
    void buzz() => Vibration.vibrate(duration: 600).catchError((Object _) {});
    buzz();
    _hackVibration = Timer.periodic(
      const Duration(milliseconds: 850),
      (_) => buzz(),
    );
  }

  void _stopHackVibration() {
    if (_hackVibration == null) return;
    _hackVibration!.cancel();
    _hackVibration = null;
    Vibration.cancel().catchError((Object _) {});
  }

  Future<void> _openTerminal() async {
    final active = ref.read(gameControllerProvider).hack;
    final countered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => TerminalPage(activeHack: active)),
    );
    if (!mounted || countered != true) return;
    ref.read(gameControllerProvider.notifier).dispatch(const HackCountered());
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmLeaveGame(
      context,
      'O teu parceiro fica sozinho com a bomba.',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  Widget _buildSection(
    String title,
    Color color,
    List<Widget> children, {
    Key? key,
    bool highlighted = false,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? color : AppColors.metalGrey,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 18)]
            : null,
      ),
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
    final color = glyph.rule.color?.color ?? AppColors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: AppColors.background,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: DrawingView(
              strokes: glyph.lines,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              glyph.rule.label,
              style: TextStyle(color: color, fontSize: 13),
            ),
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
              'ATAQUE HACKER — ${hack.symptom}. Abre o terminal: ele diz '
              'como o travar.',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _openTerminal,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              backgroundColor: Colors.white,
            ),
            child: const Text('TERMINAL'),
          ),
        ],
      ),
    );
  }

  Widget _buildBombStatus() {
    final game = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    return _buildSection('BOMBA EM DIRETO', AppColors.danger, [
      if (game.linkWarning != null)
        Text(game.linkWarning!, style: const TextStyle(color: AppColors.amber)),
      if (game.connectionNotice != null)
        Text(
          game.connectionNotice!,
          style: const TextStyle(color: AppColors.danger),
        ),
      if (game.status == BombEngineStatus.defused)
        const Text(
          'BOMBA DESARMADA',
          style: TextStyle(color: AppColors.success),
        ),
      if (game.status == BombEngineStatus.exploded)
        const Text('BOMBA EXPLODIU', style: TextStyle(color: AppColors.danger)),
      _buildRow('TEMPO', formatTime(game.timeLeft)),
      _buildRow('STRIKES', '${game.strikes}/3'),
      for (var index = 0; index < game.loadout.modules.length; index++)
        _buildModuleStatusRow(
          game.loadout.modules[index],
          () => controller.dispatch(ManualFocusRequested(index)),
        ),
    ]);
  }

  Widget _buildModuleStatusRow(BombModuleState module, VoidCallback onFocus) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              module.type.label,
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
          Text(
            module.solved
                ? 'RESOLVIDO'
                : module.failureCount == 0
                ? 'PENDENTE'
                : 'FALHAS: ${module.failureCount}',
            style: TextStyle(color: AppColors.amber),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Focar este módulo no defuser',
            onPressed: module.solved ? null : onFocus,
            icon: const Icon(Icons.visibility, size: 18),
            color: AppColors.neonBlue,
          ),
        ],
      ),
    );
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
            'Os hackers cortaram a energia. Abre o terminal: ele mostra a '
            'senha cifrada e como a decifrar.',
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
    final game = ref.watch(gameControllerProvider);
    final visibleHack = game.hack;
    ref.listen<GameState>(gameControllerProvider, (_, next) {
      _scrollToDefuserModule(next);
      _syncHackVibration(next.hack == HackType.vibration);
      final notice = next.connectionNotice;
      if (notice == null || notice == _shownConnectionNotice || !mounted) {
        return;
      }
      _shownConnectionNotice = notice;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pageNavigator = Navigator.of(context);
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text(
              notice == 'A bomba foi desarmada.' ||
                      notice == 'A bomba explodiu.'
                  ? 'FIM DE JOGO'
                  : 'LIGAÇÃO TERMINADA',
            ),
            content: Text(notice),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  notice == 'A bomba foi desarmada.' ||
                          notice == 'A bomba explodiu.'
                      ? 'VOLTAR AO MENU'
                      : 'VOLTAR AO MENU',
                ),
              ),
            ],
          ),
        ).then((_) {
          if (mounted && pageNavigator.canPop()) pageNavigator.pop();
        });
      });
    });
    final activeType =
        game.activeModule == null ||
            game.activeModule! >= game.loadout.modules.length
        ? null
        : game.loadout.modules[game.activeModule!].type;

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
          title: Text('MANUAL · ${game.partnerName}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: 'Abrir terminal',
              onPressed: _openTerminal,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Outside the shake, so it stays readable during the attack.
              if (visibleHack != null && visibleHack != HackType.lights)
                _buildHackBanner(visibleHack),
              Expanded(
                child: Stack(
                  children: [
                    HackShake(
                      active: visibleHack == HackType.vibration,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(24.0),
                        children: [
                          if (widget.transport != null) _buildBombStatus(),
                          _buildSection(
                            ModuleType.gyro.label,
                            ModuleType.gyro.color,
                            [
                              _buildText(
                                'Com o telemóvel na vertical, roda-o até ao ângulo indicado.',
                              ),
                              _buildText(
                                'Pede ao operador os quatro símbolos, da esquerda '
                                'para a direita, e calcula o ângulo:',
                              ),
                              for (int i = 0; i < angleRules.length; i++)
                                _buildText('${i + 1}. ${angleRules[i]}'),
                            ],
                            key: _sectionKeys[ModuleType.gyro],
                            highlighted: activeType == ModuleType.gyro,
                          ),
                          _buildSection(
                            ModuleType.compass.label,
                            ModuleType.compass.color,
                            [
                              _buildText(
                                'Pede ao operador os quatro números e descobre para '
                                'que ponto cardeal deve virar o telemóvel:',
                              ),
                              for (int i = 0; i < compassRules.length; i++)
                                _buildText('${i + 1}. ${compassRules[i]}'),
                            ],
                            key: _sectionKeys[ModuleType.compass],
                            highlighted: activeType == ModuleType.compass,
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
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            key: _sectionKeys[ModuleType.morse],
                            highlighted: activeType == ModuleType.morse,
                          ),
                          _buildSection(
                            ModuleType.symbols.label,
                            ModuleType.symbols.color,
                            [
                              for (int i = 0; i < symbolRules.length; i++)
                                _buildText('${i + 1}. ${symbolRules[i]}'),
                            ],
                            key: _sectionKeys[ModuleType.symbols],
                            highlighted: activeType == ModuleType.symbols,
                          ),
                          _buildSection(
                            ModuleType.arPanels.label,
                            ModuleType.arPanels.color,
                            [
                              _buildText(
                                'Módulo de realidade aumentada: o operador vê 8 '
                                'painéis à volta dele, através da câmara.',
                              ),
                              for (int i = 0; i < arPanelRules.length; i++)
                                _buildText('${i + 1}. ${arPanelRules[i]}'),
                            ],
                            key: _sectionKeys[ModuleType.arPanels],
                            highlighted: activeType == ModuleType.arPanels,
                          ),
                          _buildSection(
                            ModuleType.arDetector.label,
                            ModuleType.arDetector.color,
                            [
                              _buildText(
                                'Módulo de realidade aumentada: uma peça está '
                                'escondida algures à volta do operador.',
                              ),
                              for (int i = 0; i < arDetectorRules.length; i++)
                                _buildText('${i + 1}. ${arDetectorRules[i]}'),
                            ],
                            key: _sectionKeys[ModuleType.arDetector],
                            highlighted: activeType == ModuleType.arDetector,
                          ),
                          _buildSection(
                            ModuleType.switches.label,
                            ModuleType.switches.color,
                            [
                              _buildText(
                                'Pede ao operador a cor e a posição inicial de cada '
                                'interruptor, da esquerda para a direita.',
                              ),
                              for (int i = 0; i < switchRules.length; i++)
                                _buildText(
                                  i == 0
                                      ? switchRules[i]
                                      : '$i. ${switchRules[i]}',
                                ),
                            ],
                            key: _sectionKeys[ModuleType.switches],
                            highlighted: activeType == ModuleType.switches,
                          ),
                          _buildSection(
                            ModuleType.drawing.label,
                            ModuleType.drawing.color,
                            [
                              _buildText(
                                'O operador desenha o símbolo que vê, mas não vê o '
                                'próprio traço. Encontra-o abaixo — os símbolos de '
                                'cada família só diferem num pormenor — e diz-lhe que '
                                'fio cortar. Os fios dele estão por uma ordem '
                                'aleatória: pede-lha quando a regra depende da posição.',
                              ),
                              _buildText(wireRulesNote),
                              const SizedBox(height: 12),
                              Text(
                                'DESENHO DO OPERADOR (EM DIRETO)',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  border: Border.all(
                                    color: AppColors.metalGrey,
                                  ),
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
                              for (final glyph in glyphs) _buildGlyph(glyph),
                            ],
                            key: _sectionKeys[ModuleType.drawing],
                            highlighted: activeType == ModuleType.drawing,
                          ),
                          _buildSection('HACKERS', AppColors.textPrimary, [
                            for (final type in HackType.values)
                              _buildRow(type.symptom, type.command),
                            const SizedBox(height: 12),
                            _buildText(
                              'Durante um ataque abre o terminal (ícone no topo) e '
                              'escreve "analisar": diz-te o ataque e o comando que '
                              'o trava. No apagão mostra a senha cifrada: recua '
                              'cada letra o número de posições do desvio (ex.: '
                              'desvio +2, D → B).',
                            ),
                          ]),
                        ],
                      ),
                    ),
                    if (visibleHack == HackType.lights)
                      Positioned.fill(child: _buildBlackout()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
