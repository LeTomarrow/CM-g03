# Workshop: implementar os ecrãs do jogo (WDYP?!)

Este guia parte do estado atual da branch `dev` (menu, lobby, ajuda, definições e perfil) e leva-vos até um protótipo navegável com **todos os ecrãs do jogo**: bomba, os quatro minijogos, manual, terminal de contra-hack e ecrã de resultado.

Todo o código deste documento foi compilado e testado (`flutter analyze` sem avisos, testes a passar) sobre o código atual. Se seguirem os passos por ordem, a app compila no fim de cada um.

**O que fica de fora (de propósito):** ligação entre os dois telemóveis (salas reais) e chat de voz por WebRTC. Nesta fase cada ecrã usa dados locais ou simulados, tal como o lobby atual usa `'XK-7742'`. A secção [Próximos passos](#próximos-passos) explica onde é que essas peças vão encaixar.

---

## Índice

0. [Arrumar a casa](#passo-0-arrumar-a-casa)
1. [Modelos do jogo](#passo-1-modelos-do-jogo)
2. [Dados do manual](#passo-2-dados-do-manual)
3. [Moldura comum dos módulos](#passo-3-moldura-comum-dos-módulos)
4. [Módulo ÂNGULO (giroscópio)](#passo-4-módulo-ângulo)
5. [Módulo BÚSSOLA (magnetómetro)](#passo-5-módulo-bússola)
6. [Módulo MORSE (vibração)](#passo-6-módulo-morse)
7. [Módulo SÍMBOLOS (sem sensores)](#passo-7-módulo-símbolos)
   - [7b. Módulo DESENHO (desenho em direto)](#passo-7b-módulo-desenho)
8. [Ecrã de resultado](#passo-8-ecrã-de-resultado)
9. [Ecrã da bomba](#passo-9-ecrã-da-bomba)
10. [Terminal de contra-hack](#passo-10-terminal-de-contra-hack)
11. [Ecrã do manual](#passo-11-ecrã-do-manual)
12. [Ligar tudo no lobby](#passo-12-ligar-tudo-no-lobby)
13. [Testes](#passo-13-testes)
- [Extras: sensores reais](#extras-sensores-reais)
- [Próximos passos](#próximos-passos)

**Divisão sugerida para dois:** depois do passo 2 feito em conjunto, um faz o lado do **sapador** (passos 3 a 9, incluindo o 7b) e o outro o lado do **manual** (passos 10 e 11). O passo 12 junta tudo. Os dois lados só partilham os ficheiros de `lib/core/`, por isso não há conflitos de merge.

---

## Regras da casa

Estas convenções foram tiradas do código que já existe (`lobby.dart`, `account.dart`, `configs.dart`, ...). Todo o código novo segue-as:

| Regra | Exemplo no código atual |
|---|---|
| Um ficheiro por ecrã, classe `XxxPage` | `features/lobby.dart` → `LobbyPage` |
| `Scaffold(backgroundColor: AppColors.background)` | todos os ecrãs |
| `AppBar` transparente, `foregroundColor` com a cor do ecrã, título PT-PT em maiúsculas | `title: Text('PERFIL')` a verde |
| Corpo: `SafeArea` → `ListView(padding: EdgeInsets.all(24.0))` | lobby, perfil, definições |
| Blocos de conteúdo: `Container(padding: 16, color: AppColors.card)` | "CÓDIGO DA SALA" no lobby |
| Pedaços repetidos de UI em métodos privados `_buildXxx(...)` | `_buildPlayerSlot`, `_buildStat` |
| Cores **sempre** de `AppColors`, nunca `Color(0x...)` soltas | — |
| Ações principais com `MenuButton` | "GUARDAR", "COMEÇAR" |
| Estado local com `StatefulWidget` + `setState`; controllers libertados em `dispose()` | `_codeController` |
| Todo o texto que aparece no ecrã em PT-PT | "DEFINIÇÕES", "GUARDAR" |

Quatro convenções novas que vamos introduzir:

1. **Navegação com resultado:** um módulo devolve `true` (resolvido) ou `false` (erro) com `Navigator.pop(context, resultado)`.
2. **Uma única fonte de verdade para o manual:** as tabelas que o manual mostra são as mesmas que os módulos usam para validar respostas (`core/manual_data.dart`).
3. **Comentários de código em inglês**, como já está em `app_theme.dart`. O texto que aparece no ecrã fica em PT-PT.
4. **Um jogo a decorrer nunca fecha sem confirmação:** os ecrãs da bomba e do manual perguntam antes de sair (`PopScope`).

### Mapa da app

```
MENU ──► LOBBY ──┬── (SAPADOR) ──► BOMBA ──► ÂNGULO / BÚSSOLA / MORSE / SÍMBOLOS
                 │                   │             (pop true/false)
                 │                   └──► RESULTADO ──► LOBBY | MENU
                 │
                 └── (MANUAL) ───► MANUAL ──► TERMINAL
```

### Estrutura final

```
lib/
├── main.dart
├── core/
│   ├── app_theme.dart
│   ├── widgets.dart          (novo: MenuButton + StatusLed)
│   ├── game_models.dart      (novo)
│   ├── manual_data.dart      (novo)
│   └── drawing.dart          (novo: tela de desenho partilhada)
└── features/
    ├── menu.dart, lobby.dart, help.dart, configs.dart, account.dart
    ├── game/
    │   ├── bomb.dart
    │   ├── result.dart
    │   └── modules/
    │       ├── module_frame.dart
    │       ├── gyro_module.dart
    │       ├── compass_module.dart
    │       ├── morse_module.dart
    │       ├── symbols_module.dart
    │       └── drawing_module.dart
    └── manual/
        ├── manual.dart
        └── terminal.dart
```

> **Dica para testar um ecrã sozinho:** enquanto o lobby não estiver ligado (passo 12), troquem temporariamente o `home:` do `main.dart` pelo ecrã em que estão a trabalhar, por exemplo `home: const GyroModulePage()`. Com hot reload (`r` no terminal do `flutter run`) veem as mudanças logo.

---

## Passo 0: arrumar a casa

Há cinco problemas pequenos no código atual que convém resolver antes de crescer.

> Os pontos 0.1 a 0.4 já estão feitos no commit `035f1a3` ("bug fixing and cleaning"). Ficam aqui para referência; o 0.5 é novo.

### 0.1 O tema não está a ser aplicado

O `AppTheme.darkTheme` existe mas nunca é passado ao `MaterialApp`. É por isso que as fontes Orbitron e Share Tech Mono não aparecem (o `MenuButton` lê `textTheme.labelLarge`, que neste momento vem do tema por defeito).

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/features/menu.dart';
import 'package:what_did_you_press/core/app_theme.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: AppTheme.darkTheme, home: const MenuPage());
  }
}
```

### 0.2 O tema da AppBar sobrepõe-se às cores de cada ecrã

Depois de aplicarem o tema vão reparar que todos os títulos ficam vermelhos, incluindo "PERFIL" e "DEFINIÇÕES". Isto acontece porque o `AppBar` dá prioridade ao `appBarTheme.titleTextStyle` sobre o `foregroundColor` de cada página. A solução é tirar a cor do tema e definir só o `foregroundColor` por defeito.

Em `lib/core/app_theme.dart`, dentro de `appBarTheme`:

```dart
// ANTES
        centerTitle: true,
        titleTextStyle: _textTheme.titleLarge?.copyWith(
          color: AppColors.danger,
          letterSpacing: 3,
        ),

// DEPOIS
        centerTitle: true,
        foregroundColor: AppColors.danger,
```

Sem `titleTextStyle`, o Flutter usa o `titleLarge` do tema (Share Tech Mono) e pinta-o com o `foregroundColor` de cada página.

### 0.3 Título errado na Ajuda

Em `lib/features/help.dart`, o título diz `'LOBBY'`. Mudem para `'AJUDA'`.

### 0.4 Tirar o `MenuButton` do `menu.dart`

Neste momento `lobby.dart`, `account.dart` e `configs.dart` importam `menu.dart` só para usar o `MenuButton`, e o `menu.dart` importa esses ecrãs. Os ecrãs novos também vão precisar do botão, por isso ele passa para `lib/core/widgets.dart`, junto com:
- um widget novo, o `StatusLed` (a bolinha de estado que o lobby já desenha à mão);
- a função `confirmLeaveGame`, o diálogo "ABANDONAR JOGO?" que a bomba e o manual usam para não se sair de um jogo sem querer (passos 9 e 11). Devolve `true` só se o jogador carregar em "ABANDONAR"; tocar fora do diálogo conta como ficar.

Criem `lib/core/widgets.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.danger,
  });

  final String label;
  final void Function() onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

/// Asks before leaving a running game. Returns `true` if the player confirms.
Future<bool> confirmLeaveGame(BuildContext context, String message) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('ABANDONAR JOGO?', style: TextStyle(color: AppColors.danger)),
      content: Text(message, style: TextStyle(color: AppColors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'CONTINUAR',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('ABANDONAR', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );

  // Tapping outside the dialog returns null: treat it as "stay".
  return leave ?? false;
}

/// Small glowing dot used for player and module status.
class StatusLed extends StatelessWidget {
  const StatusLed({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    );
  }
}
```

Depois:
- apaguem a classe `MenuButton` de `menu.dart` e adicionem lá `import 'package:what_did_you_press/core/widgets.dart';`;
- em `lobby.dart`, `account.dart` e `configs.dart`, troquem `import '.../features/menu.dart';` por `import 'package:what_did_you_press/core/widgets.dart';`.

### 0.5 Tudo em português

O ecrã de Ajuda e o subtítulo do menu estavam em inglês. Traduzam-nos para ficar coerente com o resto.

`lib/features/help.dart`:

```diff
@@ -45,23 +45,23 @@
           padding: const EdgeInsets.all(24.0),
           children: [
             _buildCard(
-              'THE MISSION',
-              'You and your partner are tasked with defusing a highly volatile explosive device. One of you can see the bomb, but cannot read the manual. The other has the manual, but cannot see the bomb.',
+              'A MISSÃO',
+              'Tu e o teu parceiro têm de desarmar um engenho explosivo altamente instável. Um de vocês vê a bomba, mas não consegue ler o manual. O outro tem o manual, mas não vê a bomba.',
               color: AppColors.danger,
             ),
             _buildCard(
-              'THE DEFUSER',
-              'Your screen shows the bomb and its various modules. You must describe what you see to your partner and execute their instructions perfectly. One wrong move, and it\'s game over.',
+              'O SAPADOR',
+              'O teu ecrã mostra a bomba e os seus módulos. Tens de descrever o que vês ao teu parceiro e seguir as instruções à risca. Um passo em falso e acabou.',
               color: AppColors.amber,
             ),
             _buildCard(
-              'THE MANUAL OPERATOR',
-              'You hold the defusal manual. You must quickly navigate its pages to find the correct instructions based on the Defuser\'s descriptions. Communicate clearly and quickly.',
+              'O LEITOR DO MANUAL',
+              'Tens o manual de desarmamento. Procura depressa as instruções certas a partir do que o sapador descreve. Comunica de forma clara e rápida.',
               color: AppColors.neonBlue,
             ),
             _buildCard(
-              'COMMUNICATION',
-              'Talk. Yell. Do whatever it takes to relay information accurately. Time is running out. "What did you press?!" might be the last words you hear.',
+              'COMUNICAÇÃO',
+              'Fala. Grita. Faz o que for preciso para passar a informação certa. O tempo está a acabar. "O que é que carregaste?!" podem ser as últimas palavras que ouves.',
               color: AppColors.success,
             ),
           ],
```

`lib/features/menu.dart`:

```diff
@@ -46,7 +46,7 @@
                     style: TextStyle(color: AppColors.danger, fontSize: 48),
                   ),
                   Text(
-                    'Bomb Defusal Game',
+                    'Desarma a bomba. Juntos.',
                     style: TextStyle(color: AppColors.metalGrey, fontSize: 20),
                   ),
                 ],
@@ -91,4 +91,4 @@
       ),
     );
   }
-}
\ No newline at end of file
+}
```

**Checkpoint:** `flutter analyze` sem erros; a app arranca com as fontes novas, cada AppBar com a sua cor e a Ajuda em português.

---

## Passo 1: modelos do jogo

**Conceito novo: enums com campos** (*enhanced enums*, Dart 2.17+). Em vez de espalhar `switch` para saber o nome, ícone e cor de cada módulo, essa informação fica no próprio enum, e `ModuleType.morse.color` funciona em qualquer lado.

Criem `lib/core/game_models.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

enum PlayerRole {
  defuser('SAPADOR'),
  manual('MANUAL');

  const PlayerRole(this.label);

  final String label;

  PlayerRole get partner => this == defuser ? manual : defuser;
}

/// Every minigame the bomb can contain.
enum ModuleType {
  gyro('ÂNGULO', Icons.screen_rotation, AppColors.neonBlue),
  compass('BÚSSOLA', Icons.explore, AppColors.amber),
  morse('MORSE', Icons.vibration, AppColors.success),
  symbols('SÍMBOLOS', Icons.category, AppColors.danger),
  drawing('DESENHO', Icons.draw, AppColors.neonPurple);

  const ModuleType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class BombModule {
  BombModule(this.type);

  final ModuleType type;
  bool defused = false;
}

/// Formats a duration as MM:SS for the bomb timer.
String formatTime(Duration time) {
  final minutes = time.inMinutes.toString().padLeft(2, '0');
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Smallest difference between two angles in degrees (0–180).
double angleDistance(double a, double b) {
  return ((a - b + 540) % 360 - 180).abs();
}
```

Notas:
- Os papéis aparecem no ecrã como `SAPADOR` e `MANUAL`.
- `PlayerRole.partner` devolve o outro papel, o que dá jeito no lobby ("trocar papéis").
- `angleDistance(355, 5)` dá `10` e não `350`. Sem isto, apontar para 359° quando o alvo é 0° contava como errado.
- `formatTime` fica aqui porque é usado pela bomba e pelo ecrã de resultado.
- O módulo DESENHO usa uma cor nova. Acrescentem-na ao `AppColors` em `app_theme.dart`, junto às outras cores de destaque:
  ```dart
  static const Color neonPurple = Color(0xFFD500F9);
  ```

---

## Passo 2: dados do manual

O sapador e o manual têm de "concordar" nas regras. Se a tabela de ângulos estiver num ficheiro e o texto do manual noutro, mais cedo ou mais tarde vão divergir. Por isso há **um único ficheiro** que os módulos usam para validar respostas e que o manual usa para se desenhar.

Criem `lib/core/manual_data.dart`:

```dart
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
  flash('Ecrã do sapador a piscar', 'bloquear --ecra'),
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
```

Notas:
- `solveSymbols` é a tradução para código de `symbolRules`. Se mudarem uma regra, mudem as duas (o passo 13 tem testes para isto).
- `HackType` mapeia o sintoma que os jogadores notam (definido no documento do projeto: luz a piscar, vibração, luz do manual desligada) para o comando que o manual tem de escrever no terminal. Os comandos não têm acentos, para serem fáceis de escrever no teclado do telemóvel.
- **O apagão (`lights`) não tem comando fixo.** Durante o apagão o manual fica tapado, por isso o jogador não conseguiria ler o comando. Em vez disso, o terminal mostra uma senha cifrada (uma palavra de `blackoutPasswords`, aleatória) e o jogador decifra-a para escrever `energia --repor <senha>`.
- `caesarShift` é a cifra de César: anda com cada letra `shift` posições no alfabeto e dá a volta no Z. Com um `shift` negativo, decifra. O `% 26` funciona com negativos porque em Dart o resultado de `%` com divisor positivo nunca é negativo.
- `WireColor` e `Glyph` são do módulo DESENHO (passo 7b). Um `Glyph` é um símbolo sem nome óbvio, guardado como linhas dentro de um quadrado de 0 a 1, e diz que fio cortar. É um `enum` e não um `Map<Color, String>` porque o Dart não deixa usar `Color` como chave de um mapa `const`.
- Estes valores são de exemplo. Inventem os vossos puzzles, que a estrutura mantém-se.

---

## Passo 3: moldura comum dos módulos

Os quatro minijogos têm a mesma estrutura: título com a cor do módulo, conteúdo a fazer scroll e um botão "CONFIRMAR" fixo em baixo. Em vez de repetir isto quatro vezes, fica num widget `ModuleFrame`.

Neste ficheiro estão também dois widgets partilhados:
- `SequencePanel`: o cartão com a sequência que o sapador tem de ler em voz alta (ÂNGULO e BÚSSOLA).
- `AimDial`: um mostrador circular com ponteiro, desenhado com `CustomPainter` (o mesmo mecanismo do `ScanlineOverlay` que já têm no `app_theme.dart`).

**Conceito novo: `CustomPainter`.** Recebe um `Canvas` e um `Size` e desenha com `drawCircle` e `drawLine`. O `shouldRepaint` só devolve `true` quando o ângulo muda, para não redesenhar sem necessidade. Os ângulos usam 0° = topo e sentido horário, por isso a direção é `Offset(sin(a), -cos(a))` (o eixo Y do ecrã cresce para baixo).

Criem `lib/features/game/modules/module_frame.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';

/// Shared layout for every bomb module: title, content and confirm button.
/// Module pages pop `true` when solved and `false` on a wrong answer.
class ModuleFrame extends StatelessWidget {
  const ModuleFrame({
    super.key,
    required this.type,
    required this.onConfirm,
    required this.children,
  });

  final ModuleType type;
  final void Function() onConfirm;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: type.color,
        title: Text(type.label),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: children,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: MenuButton(
                label: 'CONFIRMAR',
                onPressed: onConfirm,
                color: type.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card with the sequence the defuser must read out loud.
class SequencePanel extends StatelessWidget {
  const SequencePanel({super.key, required this.sequence, required this.color});

  final String sequence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        children: [
          Text('SEQUÊNCIA', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            sequence,
            style: TextStyle(color: color, fontSize: 32, letterSpacing: 4),
          ),
        ],
      ),
    );
  }
}

/// Round dial with a needle at [angle] degrees (0 = top, clockwise).
class AimDial extends StatelessWidget {
  const AimDial({
    super.key,
    required this.angle,
    required this.labels,
    required this.color,
  });

  final double angle;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DialPainter(angle: angle, labels: labels, color: color),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.angle,
    required this.labels,
    required this.color,
  });

  final double angle;
  final List<String> labels;
  final Color color;

  Offset _direction(double radians) => Offset(sin(radians), -cos(radians));

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ring = Paint()
      ..color = AppColors.metalGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius - 2, ring);

    for (int i = 0; i < 36; i++) {
      final tick = _direction(i * pi / 18);
      final length = i % 3 == 0 ? 14.0 : 6.0;
      canvas.drawLine(
        center + tick * (radius - length),
        center + tick * (radius - 2),
        ring,
      );
    }

    for (int i = 0; i < labels.length; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: GoogleFonts.shareTechMono(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final position =
          center + _direction(i * 2 * pi / labels.length) * (radius - 34);
      text.paint(canvas, position - Offset(text.width / 2, text.height / 2));
    }

    final needle = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      center + _direction(angle * pi / 180) * (radius - 56),
      needle,
    );
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
```

---

## Passo 4: módulo ÂNGULO

```
┌──────────── ÂNGULO ────────────┐
│ ┌────────────────────────────┐ │
│ │         SEQUÊNCIA          │ │
│ │         ▲ ● ■ ◆            │ │
│ └────────────────────────────┘ │
│            0                   │
│      315   │    45             │
│   270 ─────●       90          │
│      225        135            │
│           180                  │
│             45°                │
│  ──────────●────────── slider  │
│ [         CONFIRMAR          ] │
└────────────────────────────────┘
```

**Fluxo de jogo:** o sapador lê a sequência, o manual procura-a na tabela e diz o ângulo, e o sapador roda o telemóvel até lá e confirma.

**Nesta fase o sensor é simulado com um `Slider`**, para poderem testar no emulador. O [Extra A](#extra-a-ângulo-com-sensor-real) troca o slider pelo sensor real (são cerca de 15 linhas).

Criem `lib/features/game/modules/gyro_module.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class GyroModulePage extends StatefulWidget {
  const GyroModulePage({super.key});

  @override
  State<GyroModulePage> createState() => _GyroModulePageState();
}

class _GyroModulePageState extends State<GyroModulePage> {
  static const double _tolerance = 10;

  final String _sequence = (angleTable.keys.toList()..shuffle()).first;
  double _angle = 0;

  void _confirm() {
    final target = angleTable[_sequence]!.toDouble();
    Navigator.of(context).pop(angleDistance(_angle, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.gyro,
      onConfirm: _confirm,
      children: [
        SequencePanel(sequence: _sequence, color: AppColors.neonBlue),
        const SizedBox(height: 32),
        AimDial(
          angle: _angle,
          labels: const ['0', '45', '90', '135', '180', '225', '270', '315'],
          color: AppColors.neonBlue,
        ),
        const SizedBox(height: 16),
        Text(
          '${_angle.round()}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.neonBlue, fontSize: 28),
        ),
        // Mockup only: replaced by the sensor stream later.
        Slider(
          value: _angle,
          max: 359,
          activeColor: AppColors.neonBlue,
          inactiveColor: AppColors.metalGrey,
          onChanged: (val) => setState(() => _angle = val),
        ),
      ],
    );
  }
}
```

Notas:
- `(angleTable.keys.toList()..shuffle()).first` escolhe um puzzle aleatório. O `..` (*cascade*) chama `shuffle()` e devolve a própria lista.
- O módulo **não sabe nada da bomba**: só faz `pop(true)` ou `pop(false)`. É a bomba que decide o que fazer com isso (passo 9).

---

## Passo 5: módulo BÚSSOLA

É igual ao anterior, mas com números em vez de símbolos e pontos cardeais em vez de graus. Como o `AimDial` aceita quaisquer `labels`, basta passar-lhe `cardinalAngles.keys`.

Criem `lib/features/game/modules/compass_module.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class CompassModulePage extends StatefulWidget {
  const CompassModulePage({super.key});

  @override
  State<CompassModulePage> createState() => _CompassModulePageState();
}

class _CompassModulePageState extends State<CompassModulePage> {
  static const double _tolerance = 15;

  final String _sequence = (compassTable.keys.toList()..shuffle()).first;
  double _heading = 0;

  void _confirm() {
    final target = cardinalAngles[compassTable[_sequence]]!.toDouble();
    Navigator.of(context).pop(angleDistance(_heading, target) <= _tolerance);
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.compass,
      onConfirm: _confirm,
      children: [
        SequencePanel(sequence: _sequence, color: AppColors.amber),
        const SizedBox(height: 32),
        AimDial(
          angle: _heading,
          labels: cardinalAngles.keys.toList(),
          color: AppColors.amber,
        ),
        const SizedBox(height: 16),
        Text(
          '${_heading.round()}°',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.amber, fontSize: 28),
        ),
        // Mockup only: replaced by the magnetometer stream later.
        Slider(
          value: _heading,
          max: 359,
          activeColor: AppColors.amber,
          inactiveColor: AppColors.metalGrey,
          onChanged: (val) => setState(() => _heading = val),
        ),
      ],
    );
  }
}
```

> **Desafio:** os dois módulos são quase iguais. Se quiserem, extraiam um `AimModulePage` genérico que receba a tabela, as labels e a tolerância. Ficou duplicado aqui de propósito, para cada passo se perceber sozinho.

---

## Passo 6: módulo MORSE

```
┌──────────── MORSE ─────────────┐
│ ┌────────────────────────────┐ │
│ │            (●)  ← LED       │ │
│ │      A TRANSMITIR...        │ │
│ └────────────────────────────┘ │
│ [       RECEBER SINAL        ] │
│ FREQUÊNCIA                     │
│ ┌────────────────────────────┐ │
│ │         3.505 MHz          │ │
│ ├────────────────────────────┤ │
│ │         3.515 MHz   ✓      │ │
│ └────────────────────────────┘ │
│ [         CONFIRMAR          ] │
└────────────────────────────────┘
```

**Fluxo de jogo:** o sapador carrega em "RECEBER SINAL", sente (e, no mockup, vê) os pontos e traços e dita-os. O manual descodifica a palavra com o alfabeto Morse, procura a frequência e diz qual escolher.

**Conceito novo: animação com `async`/`await`.** Para tocar uma sequência com tempos não é preciso `AnimationController`: basta um ciclo com `await Future.delayed(...)`. O cuidado importante é verificar `mounted` depois de cada `await`, porque o jogador pode sair do ecrã a meio, e chamar `setState` num widget que já foi destruído dá erro.

No mockup a vibração usa `HapticFeedback` (vem com o Flutter, mas só dá toques curtos). O [Extra C](#extra-c-morse-com-vibração-real) troca por vibrações com a duração certa.

Criem `lib/features/game/modules/morse_module.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class MorseModulePage extends StatefulWidget {
  const MorseModulePage({super.key});

  @override
  State<MorseModulePage> createState() => _MorseModulePageState();
}

class _MorseModulePageState extends State<MorseModulePage> {
  static const Duration _unit = Duration(milliseconds: 250);

  final String _word = (morseFrequencies.keys.toList()..shuffle()).first;
  bool _playing = false;
  bool _ledOn = false;
  String? _selected;

  /// Plays the word once: dot = 1 unit, dash = 3 units, gap between letters = 3.
  Future<void> _playSignal() async {
    if (_playing) return;
    setState(() => _playing = true);

    for (final letter in _word.split('')) {
      for (final symbol in morseCode[letter]!.split('')) {
        if (!mounted) return;
        setState(() => _ledOn = true);
        HapticFeedback.heavyImpact();
        await Future.delayed(symbol == '.' ? _unit : _unit * 3);
        if (!mounted) return;
        setState(() => _ledOn = false);
        await Future.delayed(_unit);
      }
      await Future.delayed(_unit * 2);
    }

    if (mounted) setState(() => _playing = false);
  }

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == morseFrequencies[_word]);
  }

  Widget _buildFrequency(String frequency) {
    final isSelected = frequency == _selected;

    return InkWell(
      onTap: () => setState(() => _selected = frequency),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.success : AppColors.metalGrey,
          ),
        ),
        child: Text(
          frequency,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? AppColors.success : AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frequencies = morseFrequencies.values.toList()..sort();

    return ModuleFrame(
      type: ModuleType.morse,
      onConfirm: _confirm,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          color: AppColors.card,
          child: Column(
            children: [
              StatusLed(
                color: _ledOn ? AppColors.amber : AppColors.metalGrey,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _playing ? 'A TRANSMITIR...' : 'SINAL EM ESPERA',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MenuButton(
          label: 'RECEBER SINAL',
          onPressed: _playSignal,
          color: _playing ? AppColors.metalGrey : AppColors.success,
        ),
        const SizedBox(height: 32),
        Text(
          'FREQUÊNCIA',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
        ),
        const SizedBox(height: 16),
        for (final frequency in frequencies) ...[
          _buildFrequency(frequency),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
```

> **Design de jogo:** o LED ajuda a testar, mas torna o módulo fácil demais, porque o sapador pode ler o código a olhar. Na versão final ponderem esconder o LED e deixar só a vibração.

---

## Passo 7: módulo SÍMBOLOS

```
┌─────────── SÍMBOLOS ───────────┐
│ Descreve os símbolos ao teu    │
│ parceiro e carrega no certo.   │
│ ┌──────┐ ┌──────┐ ┌──────┐     │
│ │  ★   │ │  ●   │ │  ▲   │     │
│ └──────┘ └──────┘ └──────┘     │
│ ┌──────┐ ┌──────┐ ┌──────┐     │
│ │  ◆   │ │  ■   │ │  ✚   │     │
│ └──────┘ └──────┘ └──────┘     │
│ [         CONFIRMAR          ] │
└────────────────────────────────┘
```

É o único minijogo sem sensores: o sapador descreve o painel ("estrela vermelha, bola azul..."), o manual aplica as regras e diz em qual carregar.

**Conceito novo: `GridView` dentro de `ListView`.** Uma grelha dentro de uma lista que já faz scroll precisa de `shrinkWrap: true` (para ocupar só o que precisa) e de `NeverScrollableScrollPhysics()` (para não competir com o scroll da lista).

Criem `lib/features/game/modules/symbols_module.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class SymbolsModulePage extends StatefulWidget {
  const SymbolsModulePage({super.key});

  @override
  State<SymbolsModulePage> createState() => _SymbolsModulePageState();
}

class _SymbolsModulePageState extends State<SymbolsModulePage> {
  final Random _random = Random();
  late final List<SymbolTile> _tiles = List.generate(
    6,
    (_) => SymbolTile(
      symbolPool[_random.nextInt(symbolPool.length)],
      symbolColors[_random.nextInt(symbolColors.length)],
    ),
  );
  int? _selected;

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == solveSymbols(_tiles));
  }

  Widget _buildTile(int index) {
    final tile = _tiles[index];
    final isSelected = index == _selected;

    return InkWell(
      onTap: () => setState(() => _selected = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.textPrimary : AppColors.metalGrey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          tile.symbol,
          style: TextStyle(color: tile.color, fontSize: 40),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.symbols,
      onConfirm: _confirm,
      children: [
        Text(
          'Descreve os símbolos ao teu parceiro e carrega no símbolo certo.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: List.generate(_tiles.length, _buildTile),
        ),
      ],
    );
  }
}
```

---

## Passo 7b: módulo DESENHO

```
┌─────────── DESENHO ────────────┐
│ Desenha o símbolo para o teu   │
│ parceiro e corta o fio que ...  │
│ ┌────────────────────────────┐ │
│ │          SÍMBOLO           │ │
│ │            ⟟⌇              │ │
│ └────────────────────────────┘ │
│ ┌────────────────────────🗑──┐ │
│ │                            │ │
│ │     (tela de desenho)      │ │
│ │                            │ │
│ └────────────────────────────┘ │
│ FIOS                           │
│ [VERMELHO][ AZUL ][AMARELO][VERDE]
│ [         CONFIRMAR          ] │
└────────────────────────────────┘
```

**Fluxo de jogo:** o sapador vê um símbolo estranho, difícil de descrever por palavras, e desenha-o. O manual vê o desenho **em direto**, procura o símbolo no catálogo e diz que fio cortar.

O módulo tem duas partes: os widgets de desenho, que vão para `core/` porque o manual também os usa, e a página do módulo.

### Widgets de desenho

| Conceito | Para quê |
|---|---|
| Pontos normalizados de 0 a 1 | um desenho feito num ecrã pequeno aparece igual num grande. É também o formato que vai passar pelo canal P2P. |
| `Listener` | recebe os eventos de toque "em bruto" (`onPointerDown` / `onPointerMove`), um a cada movimento do dedo. |
| `RawGestureDetector` + `EagerGestureRecognizer` | a tela está dentro de uma `ListView`. Sem isto, um traço vertical fazia scroll à página em vez de desenhar. O reconhecedor "eager" ganha logo o toque. |
| Botão de limpar **fora** do `RawGestureDetector` | se estivesse lá dentro, o reconhecedor "eager" também ficava com os toques no botão e ele nunca funcionava. |
| `_pointer` | guarda o primeiro dedo e ignora os outros, para um segundo dedo não estragar o traço. |
| `shouldRepaint => true` | os traços crescem dentro da mesma lista, por isso comparar listas diria sempre "não mudou". |
| `liveDrawing` (`ValueNotifier`) | faz de canal P2P enquanto não há rede: o módulo escreve, o manual ouve. |

Criem `lib/core/drawing.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

/// One continuous line. Points are normalised to a 0–1 square so a drawing
/// looks the same on any screen size; this is the format that will travel
/// over the P2P data channel.
typedef Stroke = List<Offset>;

/// Mockup stand-in for the P2P data channel: the bomb writes the defuser's
/// drawing here and the manual listens to it.
final ValueNotifier<List<Stroke>> liveDrawing = ValueNotifier([]);

/// Read-only drawing (glyphs, or the partner's live drawing).
class DrawingView extends StatelessWidget {
  const DrawingView({super.key, required this.strokes, required this.color});

  final List<Stroke> strokes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _StrokePainter(strokes: strokes, color: color),
      ),
    );
  }
}

/// Square canvas the player draws on with one finger.
class DrawingPad extends StatefulWidget {
  const DrawingPad({super.key, required this.onChanged, required this.color});

  final void Function(List<Stroke> strokes) onChanged;
  final Color color;

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  final List<Stroke> _strokes = [];
  int? _pointer;

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(List.of(_strokes));
  }

  Offset _normalise(Offset position, Size size) {
    return Offset(
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          // The clear button sits outside the gesture area, otherwise the
          // eager recognizer would swallow its taps.
          return Stack(
            children: [
              RawGestureDetector(
                // Claims the touch so the page does not scroll while drawing.
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(() => EagerGestureRecognizer(), (_) {}),
                },
                child: Listener(
                  onPointerDown: (event) {
                    if (_pointer != null) return;
                    _pointer = event.pointer;
                    _update(
                      () =>
                          _strokes.add([_normalise(event.localPosition, size)]),
                    );
                  },
                  onPointerMove: (event) {
                    if (event.pointer != _pointer) return;
                    _update(
                      () => _strokes.last.add(
                        _normalise(event.localPosition, size),
                      ),
                    );
                  },
                  onPointerUp: (event) {
                    if (event.pointer == _pointer) _pointer = null;
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _pointer) _pointer = null;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(color: AppColors.metalGrey),
                    ),
                    child: DrawingView(strokes: _strokes, color: widget.color),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.textSecondary,
                  tooltip: 'Limpar',
                  onPressed: () => _update(_strokes.clear),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({required this.strokes, required this.color});

  final List<Stroke> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide / 40
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      // A single tap becomes a dot instead of an invisible zero-length line.
      if (stroke.length == 1) path.relativeLineTo(0.1, 0);
      canvas.drawPath(path, paint);
    }
  }

  // Strokes grow in place while drawing, so the list identity never changes.
  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
```

### Página do módulo

Criem `lib/features/game/modules/drawing_module.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class DrawingModulePage extends StatefulWidget {
  const DrawingModulePage({super.key});

  @override
  State<DrawingModulePage> createState() => _DrawingModulePageState();
}

class _DrawingModulePageState extends State<DrawingModulePage> {
  final Glyph _glyph = glyphs[Random().nextInt(glyphs.length)];
  WireColor? _selected;

  @override
  void initState() {
    super.initState();
    liveDrawing.value = [];
  }

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == _glyph.wire);
  }

  Widget _buildWire(WireColor wire) {
    final isSelected = wire == _selected;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selected = wire),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: wire.color.withValues(alpha: isSelected ? 1 : 0.3),
            border: Border.all(
              color: isSelected ? AppColors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            wire.label,
            style: TextStyle(
              color: isSelected ? AppColors.background : AppColors.textPrimary,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleFrame(
      type: ModuleType.drawing,
      onConfirm: _confirm,
      children: [
        Text(
          'Desenha o símbolo para o teu parceiro e corta o fio que ele indicar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.card,
          child: Column(
            children: [
              Text('SÍMBOLO', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                width: 96,
                child: DrawingView(
                  strokes: _glyph.lines,
                  color: AppColors.neonPurple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DrawingPad(
          color: AppColors.neonPurple,
          onChanged: (strokes) => liveDrawing.value = strokes,
        ),
        const SizedBox(height: 24),
        Text(
          'FIOS',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final wire in WireColor.values) ...[
              _buildWire(wire),
              if (wire != WireColor.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}
```

Notas:
- O `initState` limpa o `liveDrawing`, para o manual não ver o desenho de uma ronda anterior.
- O `DrawingView` serve tanto para o símbolo (só leitura) como para o desenho em direto no manual (passo 11).

**Testar num só telemóvel:** desenhem no módulo, voltem ao lobby, troquem de papéis e abram o manual. Na secção DESENHO aparece o último desenho.

> **Quando houver P2P:** no módulo, o `onChanged: (strokes) => liveDrawing.value = strokes` passa a enviar os traços pelo canal. No manual, o `ValueListenableBuilder` passa a ouvir o que chega. Para poupar rede, enviem os pontos em lotes a cada 30–50 ms, não um a um.

---

## Passo 8: ecrã de resultado

Aparece quando a bomba é desarmada ou explode. O `_buildStat` é o mesmo do `account.dart`, para manter o visual.

Criem `lib/features/game/result.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/lobby.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    required this.defused,
    required this.timeLeft,
    required this.strikes,
  });

  final bool defused;
  final Duration timeLeft;
  final int strikes;

  Widget _buildStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: AppColors.card,
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = defused ? AppColors.success : AppColors.danger;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                defused ? Icons.verified_user : Icons.local_fire_department,
                size: 96,
                color: color,
              ),
              const SizedBox(height: 24),
              Text(
                defused ? 'DESARMADA' : 'BOOM!',
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 40),
              ),
              const SizedBox(height: 8),
              Text(
                defused
                    ? 'Bom trabalho de equipa.'
                    : 'O que é que carregaste?!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  _buildStat('TEMPO', formatTime(timeLeft), AppColors.amber),
                  const SizedBox(width: 12),
                  _buildStat('ERROS', '$strikes', AppColors.danger),
                ],
              ),
              const Spacer(),
              MenuButton(
                label: 'JOGAR NOVAMENTE',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LobbyPage()),
                ),
                color: AppColors.neonBlue,
              ),
              const SizedBox(height: 16),
              MenuButton(
                label: 'MENU',
                onPressed: () => Navigator.of(context).pop(),
                color: AppColors.metalGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

"JOGAR NOVAMENTE" usa `pushReplacement`, que troca o resultado pelo lobby e evita que o "voltar" regresse a um jogo acabado.

---

## Passo 9: ecrã da bomba

```
┌──────────── BOMBA ─────────🎤──┐
│ ╔════════════════════════════╗ │
│ ║       TEMPO RESTANTE       ║ │
│ ║          04:37             ║ │  ← glow âmbar; vermelho < 1 min
│ ╚════════════════════════════╝ │
│ ERROS                  ● ○ ○   │
│ MÓDULOS                        │
│ ┌────────────┐ ┌────────────┐  │
│ │          ● │ │          ● │  │  ← LED: vermelho = por fazer
│ │   ÂNGULO   │ │  BÚSSOLA   │  │          verde = resolvido
│ └────────────┘ └────────────┘  │
│ ┌────────────┐ ┌────────────┐  │
│ │   MORSE    │ │  SÍMBOLOS  │  │
│ └────────────┘ └────────────┘  │
│ ┌────────────┐                 │
│ │  DESENHO   │                 │
│ └────────────┘                 │
└────────────────────────────────┘
```

É o ecrã central do sapador, e o que tem mais conceitos novos:

| Conceito | Para quê |
|---|---|
| `Timer.periodic` + `cancel()` no `dispose` | contagem decrescente. Sem o `cancel`, o timer continua a correr depois de sair do ecrã. |
| `await Navigator.push<bool>(...)` | abre um módulo e **espera** pela resposta (`true`/`false`, ou `null` se o jogador carregar em "voltar"). |
| `pushAndRemoveUntil(..., (route) => route.isFirst)` | vai para o resultado e limpa a pilha toda exceto o menu, mesmo que o tempo acabe com um módulo aberto. |
| `switch` como expressão | escolhe a página de cada `ModuleType`. Se adicionarem um módulo ao enum, o compilador avisa que falta aqui. |
| `glowingCardDecoration` | já existia no `app_theme.dart` e não estava a ser usado. |
| `PopScope(canPop: false, ...)` | interceta o botão voltar, o gesto do Android e a seta da AppBar. Em vez de sair, abre o `confirmLeaveGame`; abandonar conta como explosão (`_endGame(false)`). |

Criem `lib/features/game/bomb.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/game/modules/compass_module.dart';
import 'package:what_did_you_press/features/game/modules/drawing_module.dart';
import 'package:what_did_you_press/features/game/modules/gyro_module.dart';
import 'package:what_did_you_press/features/game/modules/morse_module.dart';
import 'package:what_did_you_press/features/game/modules/symbols_module.dart';
import 'package:what_did_you_press/features/game/result.dart';

class BombPage extends StatefulWidget {
  const BombPage({super.key});

  @override
  State<BombPage> createState() => _BombPageState();
}

class _BombPageState extends State<BombPage> {
  static const int _maxStrikes = 3;

  final List<BombModule> _modules = ModuleType.values
      .map(BombModule.new)
      .toList();
  Duration _timeLeft = const Duration(minutes: 5);
  int _strikes = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    setState(() => _timeLeft -= const Duration(seconds: 1));
    if (_timeLeft <= Duration.zero) _endGame(false);
  }

  void _endGame(bool defused) {
    _timer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ResultPage(
          defused: defused,
          timeLeft: _timeLeft,
          strikes: _strikes,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmLeaveGame(
      context,
      'A bomba explode e o jogo conta como perdido.',
    );
    if (leave && mounted) _endGame(false);
  }

  Widget _pageFor(ModuleType type) {
    return switch (type) {
      ModuleType.gyro => const GyroModulePage(),
      ModuleType.compass => const CompassModulePage(),
      ModuleType.morse => const MorseModulePage(),
      ModuleType.symbols => const SymbolsModulePage(),
      ModuleType.drawing => const DrawingModulePage(),
    };
  }

  Future<void> _openModule(BombModule module) async {
    final solved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => _pageFor(module.type)),
    );
    if (!mounted || solved == null) return;

    setState(() {
      if (solved) {
        module.defused = true;
      } else {
        _strikes++;
      }
    });

    if (_modules.every((module) => module.defused)) {
      _endGame(true);
    } else if (_strikes >= _maxStrikes) {
      _endGame(false);
    }
  }

  Widget _buildModuleCard(BombModule module) {
    final color = module.defused ? AppColors.textDim : module.type.color;

    return InkWell(
      onTap: module.defused ? null : () => _openModule(module),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.card,
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: StatusLed(
                color: module.defused ? AppColors.success : AppColors.danger,
              ),
            ),
            Icon(module.type.icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(module.type.label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = _timeLeft.inSeconds < 60;

    // Back button / gesture asks first instead of silently quitting.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.danger,
          title: Text('BOMBA'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.mic, color: AppColors.success),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: glowingCardDecoration(
                  glowColor: isCritical
                      ? AppColors.dangerGlow
                      : AppColors.amberGlow,
                ),
                child: Column(
                  children: [
                    Text(
                      'TEMPO RESTANTE',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatTime(_timeLeft),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: isCritical ? AppColors.danger : AppColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'ERROS',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  for (int i = 0; i < _maxStrikes; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: StatusLed(
                        color: i < _strikes
                            ? AppColors.danger
                            : AppColors.metalGrey,
                        size: 14,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'MÓDULOS',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: _modules.map(_buildModuleCard).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Checkpoint:** ponham `home: const BombPage()` no `main.dart`. O tempo desce; um módulo resolvido fica com o LED verde e deixa de abrir; três erros ou todos os módulos resolvidos levam ao ecrã de resultado. Carregar em voltar pergunta "ABANDONAR JOGO?" em vez de sair.

> Sair de um **módulo** para a bomba não pede confirmação de propósito: não se perde nada, o módulo só devolve `null` e não conta como erro.

---

## Passo 10: terminal de contra-hack

```
┌─────────── TERMINAL ───────────┐  (fundo preto)
│ SISTEMA WDYP v0.1              │
│ Escreve "ajuda" para ver os ...│
│ ALERTA: corte de energia.      │
│ Senha intercetada: SDYLR       │
│ Cifra de César, desvio +3.     │
│ Repor: energia --repor <senha> │
│ > energia --repor pavio        │
│ Senha aceite. Energia reposta. │
│                                │
│ ┌────────────────────────────┐ │
│ │ > _                        │ │
│ └────────────────────────────┘ │
└────────────────────────────────┘
```

O manual abre o terminal quando os hackers atacam. Comandos: `ajuda`, `analisar` e `sair`.

- **Ataques `flash` e `vibration`:** o `analisar` diz que há uma intrusão mas **não diz qual**. O manual tem de a identificar pelo sintoma (tabela "HACKERS" do manual) e escrever o comando certo.
- **Apagão (`lights`):** o manual está tapado, por isso é o próprio terminal que dá o puzzle logo ao abrir (no `initState`): a senha cifrada, o desvio e o formato do comando. A senha e o desvio são gerados quando o terminal abre, por isso sair e voltar a entrar dá um puzzle novo.

O comando do apagão é verificado **antes** da comparação genérica com `HackType.command`. Se fosse ao contrário, alguém que escrevesse `energia --repor <senha>` literalmente desligava o ataque sem decifrar nada.

Conceitos:
- `TextField.onSubmitted` executa o comando quando se carrega em Enter.
- `ScrollController` + `addPostFrameCallback` faz scroll até ao fim **depois** de a nova linha ser desenhada (antes disso, o `maxScrollExtent` ainda é o antigo).
- `HackType.values.where(...).firstOrNull` procura o comando sem lançar exceção quando não existe.

Criem `lib/features/manual/terminal.dart`:

```dart
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
    // During a blackout the manual is hidden, so the terminal itself
    // hands out the (encrypted) puzzle.
    if (widget.activeHack == HackType.lights) _lines.addAll(_blackoutInfo());
  }

  List<String> _blackoutInfo() {
    return [
      'ALERTA: corte de energia.',
      'Senha intercetada: ${caesarShift(_password, _shift)}',
      'Cifra de César, desvio +$_shift.',
      'Repor: $restoreCommand <senha>',
    ];
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _execute(String command) {
    if (command == 'ajuda') {
      return ['analisar   procura intrusões', 'sair       volta ao manual'];
    }
    if (command == 'analisar') {
      if (widget.activeHack == HackType.lights) return _blackoutInfo();
      return [
        widget.activeHack == null
            ? 'Sistema limpo.'
            : 'ALERTA: intrusão ativa. Consulta o manual.',
      ];
    }

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
```

---

## Passo 11: ecrã do manual

```
┌─────────── MANUAL ──────── 🐞 ⌨ ┐
│ ┌────────────────────────────┐ │
│ │ ⚠ CHAT DE VOZ CAÍDO — ...  │ │  ← só quando há ataque
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ ÂNGULO                     │ │
│ │ Aponta o telemóvel para... │ │
│ │ ▲ ● ■ ◆               45°  │ │
│ │ ● ● ▲ ■              120°  │ │
│ └────────────────────────────┘ │
│ ┌ BÚSSOLA ┐ ┌ MORSE ┐ ...      │
└────────────────────────────────┘
          ataque "lights" ▼
┌────────────────────────────────┐
│              💡                │
│            SEM LUZ             │
│ [          TERMINAL          ] │
└────────────────────────────────┘
```

O manual é gerado a partir de `manual_data.dart`. Mudam uma tabela e o manual e o módulo atualizam-se juntos.

Para simular ataques sem o segundo telemóvel, o botão 🐞 na AppBar escolhe um `HackType` aleatório:
- `flash` / `vibration`: aparece um banner vermelho "CHAT DE VOZ CAÍDO" com o sintoma;
- `lights`: um `Stack` + `Positioned.fill` tapa o manual todo e deixa só o acesso ao terminal, tal como está na definição do projeto. O texto do ecrã preto manda o jogador ao terminal, onde está o puzzle da senha.

A secção DESENHO mostra o desenho do sapador em direto (um `ValueListenableBuilder` sobre o `liveDrawing`) e, por baixo, o catálogo de símbolos com o fio de cada um. O `_buildRow` deixa a coluna da direita quebrar linha (`Flexible`), para não dar overflow com o tamanho de letra aumentado nas definições do telemóvel.

Tal como a bomba, o manual está dentro de um `PopScope`: sair pede confirmação ("O teu parceiro fica sozinho com a bomba.").

Criem `lib/features/manual/manual.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/drawing.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/manual/terminal.dart';

class ManualPage extends StatefulWidget {
  const ManualPage({super.key});

  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  HackType? _activeHack;

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
                        'O sapador desenha o símbolo que vê. Encontra-o abaixo '
                        'e diz-lhe que fio cortar.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'DESENHO DO SAPADOR (EM DIRETO)',
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
```

Repararam no `final hack = _activeHack;` no início do `build`? Copiar o campo para uma variável local deixa o Dart promover `HackType?` para `HackType` dentro do `if (hack != null)`, sem precisarem de `!`.

---

## Passo 12: ligar tudo no lobby

Por fim, o lobby passa a saber o papel do jogador. "TROCAR PAPÉIS" alterna entre sapador e manual, e "COMEÇAR" abre o ecrã certo. Aproveitamos também para usar o `StatusLed` no lugar do `Container` desenhado à mão.

Alterações em `lib/features/lobby.dart` (as linhas com `-` saem e as com `+` entram):

```diff
@@ -1,6 +1,9 @@
 import 'package:flutter/material.dart';
 import 'package:what_did_you_press/core/app_theme.dart';
-import 'package:what_did_you_press/features/menu.dart';
+import 'package:what_did_you_press/core/widgets.dart';
+import 'package:what_did_you_press/core/game_models.dart';
+import 'package:what_did_you_press/features/game/bomb.dart';
+import 'package:what_did_you_press/features/manual/manual.dart';
 
 class LobbyPage extends StatefulWidget {
   const LobbyPage({super.key});
@@ -11,6 +14,7 @@
 
 class _LobbyPageState extends State<LobbyPage> {
   final TextEditingController _codeController = TextEditingController();
+  PlayerRole _role = PlayerRole.defuser;
 
   @override
   void dispose() {
@@ -18,16 +22,19 @@
     super.dispose();
   }
 
+  void _startGame() {
+    final Widget page = _role == PlayerRole.defuser
+        ? const BombPage()
+        : const ManualPage();
+    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
+  }
+
   Widget _buildPlayerSlot(String name, String role, bool isConnected) {
     Color color = isConnected ? AppColors.success : AppColors.amber;
 
     return Row(
       children: [
-        Container(
-          width: 10,
-          height: 10,
-          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
-        ),
+        StatusLed(color: color),
         const SizedBox(width: 12),
         Expanded(
           child: Text(
@@ -87,12 +94,18 @@
                     style: TextStyle(color: AppColors.textSecondary),
                   ),
                   const SizedBox(height: 12),
-                  _buildPlayerSlot('P1: Bernardo', 'DEFUSER', true),
+                  _buildPlayerSlot('P1: Bernardo', _role.label, true),
                   const Divider(color: AppColors.metalGrey, height: 24),
-                  _buildPlayerSlot('À espera...', 'MANUAL', false),
+                  _buildPlayerSlot('À espera...', _role.partner.label, false),
                 ],
               ),
             ),
+            const SizedBox(height: 16),
+            MenuButton(
+              label: 'TROCAR PAPÉIS',
+              onPressed: () => setState(() => _role = _role.partner),
+              color: AppColors.metalGrey,
+            ),
             const SizedBox(height: 24),
             TextField(
               controller: _codeController,
@@ -131,7 +144,7 @@
             const SizedBox(height: 40),
             MenuButton(
               label: 'COMEÇAR',
-              onPressed: () {},
+              onPressed: _startGame,
               color: AppColors.danger,
             ),
           ],
```

**Checkpoint final:** voltem a pôr `home: const MenuPage()` no `main.dart`. O caminho JOGAR → TROCAR PAPÉIS → COMEÇAR deve levar à bomba ou ao manual consoante o papel (o "P1" mostra `SAPADOR` ou `MANUAL`).

---

## Passo 13: testes

As regras do jogo são lógica pura, por isso são fáceis de testar e são onde um bug mais estraga o jogo (o manual diz uma coisa e a bomba aceita outra). Criem `test/game_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';

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
}
```

Corram:

```bash
cd what_did_you_press
flutter analyze
flutter test
```

> Testes de widgets (com `pumpWidget`) também funcionam, mas o `google_fonts` tenta descarregar as fontes durante o teste. Se os quiserem, ponham `GoogleFonts.config.allowRuntimeFetching = false;` no início do `main()` do teste.

---

## Extras: sensores reais

Façam isto **num telemóvel físico**, porque o emulador não tem sensores reais. Instalem os pacotes:

```bash
cd what_did_you_press
flutter pub add sensors_plus vibration
```

- Android: o pacote `vibration` já declara a permissão `VIBRATE` no manifest dele, por isso não precisam de fazer nada.
- iOS: o `sensors_plus` obriga a ter `NSMotionUsageDescription` no `ios/Runner/Info.plist`; sem isso a app vai abaixo ao ler sensores.

O padrão é o mesmo nos três: **subscrever um `Stream` no `initState`, fazer `cancel()` no `dispose`**, e trocar o `Slider` pelo valor do sensor.

### Extra A: ÂNGULO com sensor real

```diff
@@ -1,4 +1,8 @@
+import 'dart:async';
+import 'dart:math';
+
 import 'package:flutter/material.dart';
+import 'package:sensors_plus/sensors_plus.dart';
 import 'package:what_did_you_press/core/app_theme.dart';
 import 'package:what_did_you_press/core/game_models.dart';
 import 'package:what_did_you_press/core/manual_data.dart';
@@ -16,6 +20,26 @@
 
   final String _sequence = (angleTable.keys.toList()..shuffle()).first;
   double _angle = 0;
+  StreamSubscription<AccelerometerEvent>? _subscription;
+
+  @override
+  void initState() {
+    super.initState();
+    _subscription =
+        accelerometerEventStream(
+          samplingPeriod: SensorInterval.uiInterval,
+        ).listen((event) {
+          // Phone held upright: gravity tells how much it is rotated clockwise.
+          final degrees = atan2(-event.x, event.y) * 180 / pi;
+          setState(() => _angle = (degrees + 360) % 360);
+        });
+  }
+
+  @override
+  void dispose() {
+    _subscription?.cancel();
+    super.dispose();
+  }
 
   void _confirm() {
     final target = angleTable[_sequence]!.toDouble();
@@ -41,14 +65,6 @@
           textAlign: TextAlign.center,
           style: TextStyle(color: AppColors.neonBlue, fontSize: 28),
         ),
-        // Mockup only: replaced by the sensor stream later.
-        Slider(
-          value: _angle,
-          max: 359,
-          activeColor: AppColors.neonBlue,
-          inactiveColor: AppColors.metalGrey,
-          onChanged: (val) => setState(() => _angle = val),
-        ),
       ],
     );
   }
```

> **Porquê o acelerómetro e não o giroscópio?** O giroscópio mede **velocidade** de rotação (rad/s), não a posição. Para saber o ângulo era preciso somar as leituras ao longo do tempo, e o erro acumula-se (*drift*): passados uns segundos o ponteiro já está desviado. O acelerómetro mede a gravidade, que dá a inclinação absoluta com o telemóvel na vertical, e `atan2(-x, y)` converte-a em graus. Como a definição do projeto fala em giroscópio, podem justificar no relatório que este minijogo usa o acelerómetro (o campo "Accelerometer" está vazio na definição) e guardar o giroscópio para outro minijogo, por exemplo "rodar o telemóvel N voltas" ou "manter imóvel".

### Extra B: BÚSSOLA com magnetómetro

```diff
@@ -1,4 +1,8 @@
+import 'dart:async';
+import 'dart:math';
+
 import 'package:flutter/material.dart';
+import 'package:sensors_plus/sensors_plus.dart';
 import 'package:what_did_you_press/core/app_theme.dart';
 import 'package:what_did_you_press/core/game_models.dart';
 import 'package:what_did_you_press/core/manual_data.dart';
@@ -16,6 +20,26 @@
 
   final String _sequence = (compassTable.keys.toList()..shuffle()).first;
   double _heading = 0;
+  StreamSubscription<MagnetometerEvent>? _subscription;
+
+  @override
+  void initState() {
+    super.initState();
+    _subscription =
+        magnetometerEventStream(
+          samplingPeriod: SensorInterval.uiInterval,
+        ).listen((event) {
+          // Phone lying flat: the horizontal field points to magnetic north.
+          final degrees = atan2(-event.x, event.y) * 180 / pi;
+          setState(() => _heading = (degrees + 360) % 360);
+        });
+  }
+
+  @override
+  void dispose() {
+    _subscription?.cancel();
+    super.dispose();
+  }
 
   void _confirm() {
     final target = cardinalAngles[compassTable[_sequence]]!.toDouble();
@@ -41,14 +65,6 @@
           textAlign: TextAlign.center,
           style: TextStyle(color: AppColors.amber, fontSize: 28),
         ),
-        // Mockup only: replaced by the magnetometer stream later.
-        Slider(
-          value: _heading,
-          max: 359,
-          activeColor: AppColors.amber,
-          inactiveColor: AppColors.metalGrey,
-          onChanged: (val) => setState(() => _heading = val),
-        ),
       ],
     );
   }
```

Cuidados:
- a fórmula assume o **telemóvel deitado** (ecrã para cima);
- dá o norte **magnético**, o que chega para o jogo;
- se as leituras forem estranhas, calibrem o sensor fazendo um "8" no ar com o telemóvel;
- para um valor mais estável, façam uma média das últimas leituras antes do `setState`.

### Extra C: MORSE com vibração real

```diff
@@ -1,5 +1,5 @@
 import 'package:flutter/material.dart';
-import 'package:flutter/services.dart';
+import 'package:vibration/vibration.dart';
 import 'package:what_did_you_press/core/app_theme.dart';
 import 'package:what_did_you_press/core/game_models.dart';
 import 'package:what_did_you_press/core/manual_data.dart';
@@ -29,9 +29,10 @@
     for (final letter in _word.split('')) {
       for (final symbol in morseCode[letter]!.split('')) {
         if (!mounted) return;
+        final duration = symbol == '.' ? _unit : _unit * 3;
         setState(() => _ledOn = true);
-        HapticFeedback.heavyImpact();
-        await Future.delayed(symbol == '.' ? _unit : _unit * 3);
+        Vibration.vibrate(duration: duration.inMilliseconds);
+        await Future.delayed(duration);
         if (!mounted) return;
         setState(() => _ledOn = false);
         await Future.delayed(_unit);
```

O `Vibration.vibrate(duration: ...)` vibra durante o tempo exato do ponto ou traço. Liguem isto ao interruptor "Vibração" das Definições quando as definições forem persistidas (ver abaixo).

---

## Próximos passos

Por ordem do que mais desbloqueia:

1. **Sincronização entre os dois telemóveis.** É o maior desafio do projeto. O Firebase entra no lobby: junta os dois jogadores, mesmo em redes diferentes, e serve para trocar a sinalização do WebRTC (oferta, resposta e candidatos ICE). Daí para a frente o jogo vai por P2P, num *data channel* na mesma ligação do chat de voz. O sapador é a fonte de verdade (puzzles escolhidos, tempo, erros) e o manual recebe eventos como "ataque X começou" ou os traços do DESENHO, que hoje passam pelo `liveDrawing`.
2. **Chat de voz (WebRTC + microfone).** O ícone 🎤 da bomba e o banner "CHAT DE VOZ CAÍDO" do manual já estão no sítio: basta ligá-los ao estado real da chamada. Os hacks de voz passam a cortar o áudio de verdade até ao contra-ataque.
3. **Sintomas reais dos hacks.** `flash` pode fazer piscar o ecrã do sapador (um `Timer` a alternar a cor de fundo), e `vibration` pode pôr o telemóvel do manual a vibrar em contínuo.
4. **Sensor de luz e orientação do ecrã** (ainda vazios na definição). Uma ideia que encaixa no tema: um módulo que só se resolve com o telemóvel tapado (sensor de luz) ou em landscape.
5. **Persistir definições e perfil** (`shared_preferences`), para que "GUARDAR" deixe de ser só `pop()`.
