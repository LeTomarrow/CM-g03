import 'dart:math';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/manual_data.dart';

/// Hacker terminal. Pops `true` once the active hack is countered.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.activeHack});

  final HackType? activeHack;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Random _random = Random();
  final List<String> _lines = [
    'SISTEMA WDYP v0.1',
    'Escreve "ajuda" para ver os comandos.',
  ];
  late final String _password =
      blackoutPasswords[_random.nextInt(blackoutPasswords.length)];
  late final int _shift = 1 + _random.nextInt(5);
  bool _countered = false;

  @override
  void initState() {
    super.initState();
    // Under attack the manual is blurred or dark, so the terminal itself
    // explains how to counter it.
    if (widget.activeHack != null) _lines.addAll(_analysis());
  }

  List<String> _analysis() {
    return switch (widget.activeHack) {
      null => ['Sistema limpo.'],
      HackType.lights => [
        'ALERTA: corte de energia.',
        'Senha intercetada: ${caesarShift(_password, _shift)}',
        'Cifra de César, desvio +$_shift: recua cada letra $_shift '
            'posições no alfabeto (ex.: desvio +2, D → B).',
        'Repor: $restoreCommand <senha>',
      ],
      final hack => [
        'ALERTA: ${hack.symptom.toLowerCase()}.',
        'Contramedida: ${hack.command}',
      ],
    };
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _execute(String command) {
    if (command == 'ajuda') {
      return [
        'analisar   procura intrusões e diz como as travar',
        'sair       volta ao manual',
      ];
    }
    if (command == 'analisar') return _analysis();

    // Checked before the generic match so "<senha>" typed literally fails.
    if (command.startsWith(restoreCommand)) {
      if (widget.activeHack != HackType.lights) {
        return ['Contra-ataque falhou.'];
      }
      final attempt = command.substring(restoreCommand.length).trim();
      if (attempt.toUpperCase() != _password) return ['Senha incorreta.'];
      _countered = true;
      return ['Senha aceite. Energia reposta.'];
    }

    final hack = HackType.values
        .where((hack) => hack.command == command)
        .firstOrNull;
    if (hack == null) return ['Comando desconhecido: $command'];
    if (hack != widget.activeHack) return ['Contra-ataque falhou.'];

    _countered = true;
    return ['Contra-ataque bem sucedido. Sistema restaurado.'];
  }

  void _runCommand(String input) {
    final command = input.trim();
    _inputController.clear();
    if (command.isEmpty) return;
    if (command == 'sair') {
      Navigator.of(context).pop(_countered);
      return;
    }

    setState(() => _lines.addAll(['> $command', ..._execute(command)]));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });

    if (_countered) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.success,
        title: Text('TERMINAL'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _lines.length,
                  itemBuilder: (context, index) => Text(
                    _lines[index],
                    style: TextStyle(color: AppColors.success, height: 1.6),
                  ),
                ),
              ),
              TextField(
                controller: _inputController,
                autofocus: true,
                enabled: !_countered,
                style: TextStyle(color: AppColors.success),
                onSubmitted: _runCommand,
                decoration: InputDecoration(
                  prefixText: '> ',
                  prefixStyle: TextStyle(color: AppColors.success),
                  fillColor: Colors.black,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.metalGrey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.success),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
