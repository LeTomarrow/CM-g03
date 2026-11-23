import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/bomb_loadout.dart';

void main() {
  test('formatTime mostra MM:SS', () {
    expect(formatTime(const Duration(minutes: 4, seconds: 7)), '04:07');
  });

  test('angleDistance dá a volta aos 360 graus', () {
    expect(angleDistance(355, 5), 10);
  });

  test('símbolos: estrela vermelha tem prioridade', () {
    const tiles = [
      SymbolTile('●', AppColors.neonBlue),
      SymbolTile('★', AppColors.danger),
    ];
    expect(solveSymbols(tiles), 1);
  });

  test('símbolos: 3 azuis → último azul', () {
    const tiles = [
      SymbolTile('●', AppColors.neonBlue),
      SymbolTile('▲', AppColors.neonBlue),
      SymbolTile('■', AppColors.amber),
      SymbolTile('◆', AppColors.neonBlue),
      SymbolTile('✚', Colors.white),
    ];
    expect(solveSymbols(tiles), 3);
  });

  test('desenho: todos os símbolos cabem na tela de 0 a 1', () {
    for (final glyph in glyphs) {
      for (final point in glyph.lines.expand((line) => line)) {
        expect(point.dx, inInclusiveRange(0, 1));
        expect(point.dy, inInclusiveRange(0, 1));
      }
    }
  });

  test('símbolos: sem amarelos → último; forma repetida → a segunda', () {
    const noAmber = [
      SymbolTile('●', AppColors.success),
      SymbolTile('▲', AppColors.neonBlue),
      SymbolTile('■', AppColors.danger),
    ];
    expect(solveSymbols(noAmber), 2);
    const repeated = [
      SymbolTile('●', AppColors.amber),
      SymbolTile('▲', AppColors.success),
      SymbolTile('●', AppColors.danger),
      SymbolTile('▲', AppColors.amber),
    ];
    expect(solveSymbols(repeated), 2);
    const plain = [
      SymbolTile('●', AppColors.amber),
      SymbolTile('▲', AppColors.success),
    ];
    expect(solveSymbols(plain), 0);
  });

  test('símbolos: os tabuleiros gerados usam todas as regras', () {
    final answers = <String>{};
    for (var variant = 0; variant < 500; variant++) {
      final board = symbolBoard(variant);
      expect(board, hasLength(6));
      final index = solveSymbols(board);
      expect(index, inInclusiveRange(0, 5));
      final tile = board[index];
      answers.add(
        tile.symbol == '★' && tile.color == AppColors.danger
            ? 'star'
            : '${index == 0}-${index == 5}',
      );
    }
    expect(answers.length, greaterThanOrEqualTo(3));
  });

  test('ângulo: soma, pares seguidos, extremos iguais e volta aos 360', () {
    expect(solveAngle(['▲', '●', '■', '◆']), 210);
    // 90 + 90 + 100 + 45 + 90 = 415, primeiro = último → 385 → 25.
    expect(solveAngle(['▲', '▲', '●', '▲']), 25);
    for (var variant = 0; variant < 200; variant++) {
      expect(solveAngle(angleSequence(variant)), inInclusiveRange(0, 359));
    }
  });

  test('bússola: resto da soma por 8 e ponto oposto', () {
    expect(solveCompass([3, 1, 4, 1]), 'NE');
    // 10 % 8 = 2 (E); o último é maior do que o primeiro → O.
    expect(solveCompass([1, 2, 3, 4]), 'O');
    for (var variant = 0; variant < 200; variant++) {
      final digits = compassSequence(variant);
      expect(digits.every((d) => d >= 1 && d <= 9), isTrue);
      expect(cardinalAngles, contains(solveCompass(digits)));
    }
  });

  test('morse: todas as palavras têm frequência e código', () {
    for (var variant = 0; variant < 50; variant++) {
      final word = morseWord(variant);
      expect(morseFrequencies, contains(word));
      expect(word.split('').every(morseCode.containsKey), isTrue);
    }
    expect(morseFrequencies.values.toSet(), hasLength(morseFrequencies.length));
  });

  test('desenho: regras dos fios dependem da ordem', () {
    const order = [
      WireColor.green,
      WireColor.red,
      WireColor.blue,
      WireColor.yellow,
    ];
    expect(const WireRule.color(WireColor.red).solve(order), 1);
    expect(const WireRule.position(2).solve(order), 1);
    expect(const WireRule.last().solve(order), 3);
    expect(const WireRule.after(WireColor.blue).solve(order), 3);
    expect(const WireRule.after(WireColor.yellow).solve(order), 0);
    expect(const WireRule.before(WireColor.green).solve(order), 3);
  });

  test('desenho: símbolos distintos e puzzles determinísticos', () {
    final shapes = glyphs.map((glyph) => glyph.lines.toString()).toSet();
    expect(shapes, hasLength(glyphs.length));
    final seen = <Glyph>{};
    for (var variant = 0; variant < 300; variant++) {
      final puzzle = drawingPuzzle(variant);
      expect(drawingPuzzle(variant).wires, puzzle.wires);
      expect(puzzle.wires.toSet(), hasLength(WireColor.values.length));
      expect(
        puzzle.glyph.rule.solve(puzzle.wires),
        inInclusiveRange(0, puzzle.wires.length - 1),
      );
      seen.add(puzzle.glyph);
    }
    expect(seen, hasLength(glyphs.length));
  });

  test('interruptores: regras por cor e exceção de cores seguidas', () {
    const r = WireColor.red, b = WireColor.blue;
    const y = WireColor.yellow, g = WireColor.green;
    // 3 para cima no início → verdes para cima; o 2.º verde seguido inverte.
    expect(solveSwitches([r, b, y, g, g], [false, false, true, true, true]), [
      true,
      true,
      true,
      true,
      false,
    ]);
    // Amarelo no início fica em baixo; o amarelo seguido inverte-o.
    expect(solveSwitches([y, y, b, r, b], [true, false, true, false, false]), [
      false,
      true,
      false,
      true,
      true,
    ]);
  });

  test('interruptores: os puzzles gerados nunca começam resolvidos', () {
    for (var variant = 0; variant < 500; variant++) {
      final puzzle = switchPuzzle(variant);
      expect(puzzle.colors, hasLength(switchCount));
      expect(
        solveSwitches(puzzle.colors, puzzle.initial),
        isNot(puzzle.initial),
      );
    }
  });

  test('cada bomba: 1 AR, Ângulo ou Bússola, e 3 clássicos', () {
    final seen = <ModuleType>{};
    for (var seed = 0; seed < 200; seed++) {
      final types = BombLoadout.generate(
        seed: seed,
      ).modules.map((module) => module.type).toList();
      expect(types, hasLength(BombLoadout.defaultModuleCount));
      expect(types.toSet(), hasLength(types.length));
      expect(types.where(ModuleType.augmented.contains), hasLength(1));
      expect(types.where(ModuleType.orientation.contains), hasLength(1));
      expect(types.where(ModuleType.classic.contains), hasLength(3));
      seen.addAll(types);
    }
    expect(seen, ModuleType.values.toSet());
  });

  test('cifra de César cifra, dá a volta ao Z e decifra', () {
    expect(caesarShift('PAVIO', 3), 'SDYLR');
    expect(caesarShift('ZEBRA', 2), 'BGDTC');
    expect(caesarShift(caesarShift('FUSIVEL', 4), -4), 'FUSIVEL');
  });

  test('loadout com a mesma seed é determinístico e guarda variantes', () {
    final first = BombLoadout.generate(seed: 42);
    final second = BombLoadout.generate(seed: 42);
    expect(first.toJson(), second.toJson());
    expect(first.modules, hasLength(5));
    expect(first.modules.every((module) => module.variant >= 0), isTrue);
  });
}
