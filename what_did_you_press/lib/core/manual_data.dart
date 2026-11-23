import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

// Single source of truth for the manual: the bomb modules generate their
// puzzle from the module's `variant` (a seed) and check answers with the
// `solve*` functions; the manual page renders the rules for the reader.
// Puzzles are generated, not looked up, so they cannot be memorised and the
// variant number tells the manual nothing.

// ── ÂNGULO ──────────────────────────────────────────────────────────────────

const Map<String, int> angleValues = {'▲': 90, '●': 45, '■': 60, '◆': 15};

const List<String> angleRules = [
  'Soma o valor de cada símbolo: ▲ 90° · ● 45° · ■ 60° · ◆ 15°.',
  'Por cada símbolo igual ao que está antes dele, soma mais 100°.',
  'Se o primeiro e o último símbolo forem iguais, subtrai 30°.',
  'Se passar de 360°, tira 360° (ex.: 400° → 40°).',
];

/// Four symbols read from left to right.
List<String> angleSequence(int variant) {
  final random = Random(variant);
  final symbols = angleValues.keys.toList();
  return List.generate(4, (_) => symbols[random.nextInt(symbols.length)]);
}

/// Applies [angleRules]; the result is in [0, 360).
int solveAngle(List<String> sequence) {
  var total = 0;
  for (var i = 0; i < sequence.length; i++) {
    total += angleValues[sequence[i]]!;
    if (i > 0 && sequence[i] == sequence[i - 1]) total += 100;
  }
  if (sequence.first == sequence.last) total -= 30;
  return total % 360;
}

// ── BÚSSOLA ─────────────────────────────────────────────────────────────────

const List<String> cardinalOrder = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];

const Map<String, int> cardinalAngles = {
  'N': 0,
  'NE': 45,
  'E': 90,
  'SE': 135,
  'S': 180,
  'SO': 225,
  'O': 270,
  'NO': 315,
};

const List<String> compassRules = [
  'Soma os quatro números.',
  'Divide por 8 e fica com o resto: '
      '0 N · 1 NE · 2 E · 3 SE · 4 S · 5 SO · 6 O · 7 NO.',
  'Se o último número for maior do que o primeiro, vira para o ponto oposto '
      '(N ↔ S, NE ↔ SO, E ↔ O, SE ↔ NO).',
];

/// Four digits from 1 to 9, read from left to right.
List<int> compassSequence(int variant) {
  final random = Random(variant);
  return List.generate(4, (_) => 1 + random.nextInt(9));
}

/// Applies [compassRules] and returns the cardinal point to face.
String solveCompass(List<int> digits) {
  var index = digits.fold<int>(0, (sum, digit) => sum + digit) % 8;
  if (digits.last > digits.first) index = (index + 4) % 8;
  return cardinalOrder[index];
}

// ── MORSE ───────────────────────────────────────────────────────────────────

/// Decoded word → frequency. Words come in look-alike pairs, so the whole
/// word has to be decoded, not just its first letter.
const Map<String, String> morseFrequencies = {
  'FIO': '3.505 MHz',
  'FIM': '3.512 MHz',
  'LUZ': '3.518 MHz',
  'LUA': '3.522 MHz',
  'TEMPO': '3.528 MHz',
  'TEMA': '3.535 MHz',
  'BOMBA': '3.541 MHz',
  'BOMBO': '3.547 MHz',
};

String morseWord(int variant) {
  final words = morseFrequencies.keys.toList();
  return words[Random(variant).nextInt(words.length)];
}

const Map<String, String> morseCode = {
  'A': '.-',
  'B': '-...',
  'C': '-.-.',
  'D': '-..',
  'E': '.',
  'F': '..-.',
  'G': '--.',
  'H': '....',
  'I': '..',
  'J': '.---',
  'K': '-.-',
  'L': '.-..',
  'M': '--',
  'N': '-.',
  'O': '---',
  'P': '.--.',
  'Q': '--.-',
  'R': '.-.',
  'S': '...',
  'T': '-',
  'U': '..-',
  'V': '...-',
  'W': '.--',
  'X': '-..-',
  'Y': '-.--',
  'Z': '--..',
};

// ── SÍMBOLOS ────────────────────────────────────────────────────────────────

/// SÍMBOLOS: a coloured symbol shown on the module.
class SymbolTile {
  const SymbolTile(this.symbol, this.color);

  final String symbol;
  final Color color;
}

const List<String> symbolPool = ['★', '▲', '●', '■', '◆', '✚'];

const List<Color> symbolColors = [
  AppColors.danger,
  AppColors.neonBlue,
  AppColors.amber,
  AppColors.success,
];

const List<String> symbolRules = [
  'Se existir uma ★ VERMELHA, carrega nela.',
  'Senão, se existirem 3 ou mais símbolos AZUIS, carrega no último azul.',
  'Senão, se não houver nenhum símbolo AMARELO, carrega no último símbolo.',
  'Senão, se houver duas formas iguais, carrega na segunda.',
  'Senão, carrega no primeiro símbolo.',
];

/// Six tiles in reading order (left to right, top to bottom). Half of the
/// boards repeat one shape so the fourth rule can apply.
List<SymbolTile> symbolBoard(int variant) {
  final random = Random(variant);
  final shapes = [...symbolPool]..shuffle(random);
  if (random.nextBool()) {
    final source = random.nextInt(shapes.length);
    final target =
        (source + 1 + random.nextInt(shapes.length - 1)) % shapes.length;
    shapes[target] = shapes[source];
  }
  return [
    for (final shape in shapes)
      SymbolTile(shape, symbolColors[random.nextInt(symbolColors.length)]),
  ];
}

/// Applies [symbolRules] and returns the index of the tile to press.
int solveSymbols(List<SymbolTile> tiles) {
  final redStar = tiles.indexWhere(
    (tile) => tile.symbol == '★' && tile.color == AppColors.danger,
  );
  if (redStar != -1) return redStar;

  final blue = tiles.where((tile) => tile.color == AppColors.neonBlue);
  if (blue.length >= 3) {
    return tiles.lastIndexWhere((tile) => tile.color == AppColors.neonBlue);
  }

  if (!tiles.any((tile) => tile.color == AppColors.amber)) {
    return tiles.length - 1;
  }

  for (var i = 1; i < tiles.length; i++) {
    for (var j = 0; j < i; j++) {
      if (tiles[i].symbol == tiles[j].symbol) return i;
    }
  }

  return 0;
}

// ── DESENHO ─────────────────────────────────────────────────────────────────

/// DESENHO: wires the defuser can cut.
enum WireColor {
  red('VERMELHO', AppColors.danger),
  blue('AZUL', AppColors.neonBlue),
  yellow('AMARELO', AppColors.amber),
  green('VERDE', AppColors.success);

  const WireColor(this.label, this.color);

  final String label;
  final Color color;
}

enum WireRuleKind { color, position, last, after, before }

/// Which wire a glyph asks for. The bomb shows the wires in a random order,
/// so position rules need the operator to describe that order.
class WireRule {
  const WireRule.color(WireColor this.color)
    : kind = WireRuleKind.color,
      position = 0;
  const WireRule.position(this.position)
    : kind = WireRuleKind.position,
      color = null;
  const WireRule.last() : kind = WireRuleKind.last, color = null, position = 0;
  const WireRule.after(WireColor this.color)
    : kind = WireRuleKind.after,
      position = 0;
  const WireRule.before(WireColor this.color)
    : kind = WireRuleKind.before,
      position = 0;

  final WireRuleKind kind;
  final WireColor? color;

  /// 1-based, counted from the left.
  final int position;

  String get label => switch (kind) {
    WireRuleKind.color => 'FIO ${color!.label}',
    WireRuleKind.position => '$position.º A CONTAR DA ESQUERDA',
    WireRuleKind.last => 'ÚLTIMO FIO',
    WireRuleKind.after => 'À DIREITA DO ${color!.label}',
    WireRuleKind.before => 'À ESQUERDA DO ${color!.label}',
  };

  /// Index of the wire to cut in [order] (left to right).
  int solve(List<WireColor> order) => switch (kind) {
    WireRuleKind.color => order.indexOf(color!),
    WireRuleKind.position => position - 1,
    WireRuleKind.last => order.length - 1,
    WireRuleKind.after => (order.indexOf(color!) + 1) % order.length,
    WireRuleKind.before =>
      (order.indexOf(color!) - 1 + order.length) % order.length,
  };
}

const String wireRulesNote =
    'Os fios contam-se da esquerda para a direita. À direita do último fio '
    'está o primeiro; à esquerda do primeiro está o último.';

/// DESENHO: a symbol with no obvious name, drawn as lines in a 0–1 square,
/// and the wire it asks for. Glyphs come in families of three that differ
/// only in a detail, so a rough sketch is not enough.
class Glyph {
  const Glyph(this.lines, this.rule);

  final List<List<Offset>> lines;
  final WireRule rule;
}

const _vee = [Offset(0.2, 0.2), Offset(0.5, 0.8), Offset(0.8, 0.2)];
const _zed = [
  Offset(0.25, 0.2),
  Offset(0.75, 0.2),
  Offset(0.25, 0.8),
  Offset(0.75, 0.8),
];
const _diamond = [
  Offset(0.15, 0.5),
  Offset(0.5, 0.25),
  Offset(0.85, 0.5),
  Offset(0.5, 0.75),
  Offset(0.15, 0.5),
];

const List<Glyph> glyphs = [
  // V with a stem.
  Glyph([
    _vee,
    [Offset(0.5, 0.8), Offset(0.5, 0.3)],
  ], WireRule.color(WireColor.red)),
  Glyph([
    _vee,
    [Offset(0.5, 0.8), Offset(0.5, 0.3)],
    [Offset(0.8, 0.2), Offset(0.9, 0.35)],
  ], WireRule.position(2)),
  Glyph([
    [Offset(0.2, 0.8), Offset(0.5, 0.2), Offset(0.8, 0.8)],
    [Offset(0.5, 0.2), Offset(0.5, 0.7)],
  ], WireRule.after(WireColor.blue)),
  // Z with a tail.
  Glyph([
    _zed,
    [Offset(0.75, 0.8), Offset(0.85, 0.6)],
  ], WireRule.last()),
  Glyph([
    [
      Offset(0.75, 0.2),
      Offset(0.25, 0.2),
      Offset(0.75, 0.8),
      Offset(0.25, 0.8),
    ],
    [Offset(0.25, 0.8), Offset(0.15, 0.6)],
  ], WireRule.color(WireColor.yellow)),
  Glyph([
    _zed,
    [Offset(0.75, 0.8), Offset(0.85, 0.6)],
    [Offset(0.35, 0.5), Offset(0.65, 0.5)],
  ], WireRule.before(WireColor.green)),
  // Diamond with a bar.
  Glyph([
    _diamond,
    [Offset(0.5, 0.4), Offset(0.5, 0.6)],
  ], WireRule.position(3)),
  Glyph([
    _diamond,
    [Offset(0.35, 0.5), Offset(0.65, 0.5)],
  ], WireRule.color(WireColor.green)),
  Glyph([
    _diamond,
    [Offset(0.5, 0.4), Offset(0.5, 0.6)],
    [Offset(0.5, 0.25), Offset(0.5, 0.1)],
  ], WireRule.after(WireColor.red)),
];

/// The glyph shown on the bomb and the order of its wires.
({Glyph glyph, List<WireColor> wires}) drawingPuzzle(int variant) {
  final random = Random(variant);
  final glyph = glyphs[random.nextInt(glyphs.length)];
  return (glyph: glyph, wires: [...WireColor.values]..shuffle(random));
}

// ── INTERRUPTORES ───────────────────────────────────────────────────────────

const int switchCount = 5;

const List<String> switchRules = [
  'Decide os interruptores da esquerda para a direita. "Inicial" é a posição '
      'em que estavam quando o módulo abriu.',
  'VERMELHO: fica para cima.',
  'AZUL: fica ao contrário da posição inicial.',
  'AMARELO: fica como ficou o interruptor à esquerda (o primeiro fica para '
      'baixo).',
  'VERDE: fica para cima se, no início, havia mais interruptores para cima do '
      'que para baixo; senão, para baixo.',
  'Exceção: se um interruptor tiver a mesma cor do que está à sua esquerda, '
      'fica ao contrário desse.',
];

/// Colours (reusing the wire palette) and initial positions (`true` = up),
/// left to right. Never already solved.
({List<WireColor> colors, List<bool> initial}) switchPuzzle(int variant) {
  final random = Random(variant);
  while (true) {
    final colors = List.generate(
      switchCount,
      (_) => WireColor.values[random.nextInt(WireColor.values.length)],
    );
    final initial = List.generate(switchCount, (_) => random.nextBool());
    final target = solveSwitches(colors, initial);
    if (!listEquals(target, initial)) return (colors: colors, initial: initial);
  }
}

/// Applies [switchRules] and returns the final positions (`true` = up).
List<bool> solveSwitches(List<WireColor> colors, List<bool> initial) {
  final upAtStart = initial.where((up) => up).length;
  final greenUp = upAtStart > initial.length - upAtStart;
  final target = <bool>[];
  for (var i = 0; i < colors.length; i++) {
    if (i > 0 && colors[i] == colors[i - 1]) {
      target.add(!target[i - 1]);
      continue;
    }
    target.add(switch (colors[i]) {
      WireColor.red => true,
      WireColor.blue => !initial[i],
      WireColor.yellow => i == 0 ? false : target[i - 1],
      WireColor.green => greenUp,
    });
  }
  return target;
}

// ── HACKERS ─────────────────────────────────────────────────────────────────

/// Prefix of the blackout command; the password comes after it.
const String restoreCommand = 'energia --repor';

/// Hacker attacks: what the players notice and the command that stops it.
enum HackType {
  flash('Ecrã do operador a piscar', 'bloquear --ecra'),
  vibration('Vibração contínua no manual', 'parar --vibracao'),
  lights('Manual às escuras', '$restoreCommand <senha>');

  const HackType(this.symptom, this.command);

  final String symptom;
  final String command;
}

/// Words the hackers use as blackout passwords.
const List<String> blackoutPasswords = [
  'FUSIVEL',
  'PAVIO',
  'DETONADOR',
  'CABO',
  'RELE',
  'CIRCUITO',
];

/// Caesar cipher: moves every letter of [word] by [shift] positions.
/// A negative [shift] decrypts.
String caesarShift(String word, int shift) {
  return String.fromCharCodes(
    word.codeUnits.map((code) => 65 + (code - 65 + shift) % 26),
  );
}
