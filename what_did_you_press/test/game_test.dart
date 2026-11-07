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
