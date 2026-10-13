import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

// Single source of truth for the manual: the bomb modules read these
// tables to check answers and the manual page renders them for the reader.

/// ÂNGULO: symbol sequence → angle (degrees) to aim the phone at.
const Map<String, int> angleTable = {
  '▲ ● ■ ◆': 45,
  '● ● ▲ ■': 120,
  '■ ◆ ◆ ▲': 210,
  '◆ ▲ ● ●': 300,
};

/// BÚSSOLA: number sequence → cardinal point to face.
const Map<String, String> compassTable = {
  '3 1 4 1': 'NE',
  '2 7 1 8': 'S',
  '1 6 1 8': 'O',
  '1 4 1 4': 'SE',
};

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

/// MORSE: decoded word → frequency the defuser must select.
const Map<String, String> morseFrequencies = {
  'BOMBA': '3.515 MHz',
  'FIO': '3.522 MHz',
  'TEMPO': '3.532 MHz',
  'LUZ': '3.505 MHz',
};

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
  'Senão, carrega no primeiro símbolo.',
];

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

  return 0;
}

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

/// DESENHO: a symbol with no obvious name, drawn as lines in a 0–1 square,
/// and the wire it tells the defuser to cut.
class Glyph {
  const Glyph(this.lines, this.wire);

  final List<List<Offset>> lines;
  final WireColor wire;
}

const List<Glyph> glyphs = [
  Glyph([
    [Offset(0.2, 0.2), Offset(0.5, 0.8), Offset(0.8, 0.2)],
    [Offset(0.5, 0.8), Offset(0.5, 0.3)],
  ], WireColor.red),
  Glyph([
    [
      Offset(0.25, 0.2),
      Offset(0.75, 0.2),
      Offset(0.25, 0.8),
      Offset(0.75, 0.8),
    ],
    [Offset(0.75, 0.8), Offset(0.85, 0.6)],
  ], WireColor.blue),
  Glyph([
    [
      Offset(0.5, 0.5),
      Offset(0.65, 0.5),
      Offset(0.65, 0.65),
      Offset(0.35, 0.65),
      Offset(0.35, 0.35),
      Offset(0.8, 0.35),
      Offset(0.8, 0.8),
      Offset(0.2, 0.8),
    ],
  ], WireColor.yellow),
  Glyph([
    [Offset(0.6, 0.15), Offset(0.35, 0.5), Offset(0.6, 0.5), Offset(0.4, 0.85)],
    [Offset(0.75, 0.2), Offset(0.8, 0.28)],
  ], WireColor.green),
  Glyph([
    [
      Offset(0.15, 0.5),
      Offset(0.5, 0.25),
      Offset(0.85, 0.5),
      Offset(0.5, 0.75),
      Offset(0.15, 0.5),
    ],
    [Offset(0.5, 0.4), Offset(0.5, 0.6)],
  ], WireColor.red),
  Glyph([
    [
      Offset(0.75, 0.2),
      Offset(0.25, 0.2),
      Offset(0.25, 0.8),
      Offset(0.75, 0.8),
    ],
    [Offset(0.25, 0.5), Offset(0.6, 0.5)],
    [Offset(0.45, 0.2), Offset(0.45, 0.35)],
  ], WireColor.blue),
];

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
