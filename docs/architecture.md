# Arquitetura da aplicação

Este documento descreve a arquitetura atual da aplicação **What Did You Press?**, os padrões utilizados, os fluxos entre jogadores e as decisões que devem orientar a implementação futura.

O objetivo principal é manter uma separação clara entre:

- interface Flutter;
- estado da aplicação;
- regras de domínio;
- transporte entre jogadores;
- infraestrutura externa, como Firebase, WebRTC e sensores.

## 1. Visão geral

A aplicação tem dois modos principais:

1. **Lobby e ligação entre jogadores**
2. **Jogo da bomba**

Os jogadores assumem papéis diferentes:

- **Defuser / Operador**: vê e interage com a bomba.
- **Manual**: consulta o manual e orienta o defuser.

No jogo normal, os papéis podem ser trocados na lobby. No modo de bomba do mundo, o jogador que reclamou a bomba é sempre o defuser e os papéis ficam bloqueados.

## 2. Princípios arquiteturais

### 2.1 Separação de responsabilidades

Cada componente deve ter uma responsabilidade principal:

| Componente | Responsabilidade |
|---|---|
| View / Widget | Renderizar estado e encaminhar ações do utilizador |
| Controller / Notifier | Coordenar eventos, estado e casos de uso |
| Repository | Representar uma fonte de dados da aplicação |
| Service | Encapsular uma API ou recurso externo |
| Protocol | Validar e interpretar mensagens |
| Engine | Executar regras determinísticas do jogo |
| Isolate | Executar o engine fora do isolate da UI |

Os nomes das classes devem refletir a responsabilidade. O nome do padrão não deve ser adicionado artificialmente quando não descreve o comportamento da classe.

### 2.2 Fluxo unidirecional de dados

O estado deve seguir uma direção previsível:

```text
ação do utilizador / rede / isolate
              ↓
           evento
              ↓
       controller / reducer
              ↓
       estado imutável
              ↓
             UI
```

A UI não deve alterar diretamente o estado de uma partida nem tomar decisões sobre o resultado do jogo.

### 2.3 Autoridade única

Cada tipo de estado tem uma autoridade definida:

| Estado | Autoridade |
|---|---|
| Reserva da sala | Firestore, através de transações |
| Papéis e início da lobby | Host da sala |
| Timer, strikes e módulos da bomba | Defuser |
| Estado mostrado ao manual | Snapshot enviado pelo defuser |
| Bombas do mundo | Firestore, com regras de segurança |

O manual nunca deve calcular um segundo timer nem decidir se a bomba foi defusada.

## 3. Camadas da aplicação

```text
┌────────────────────────────────────────────┐
│ Presentation                               │
│ Pages, widgets, navegação, interação        │
├────────────────────────────────────────────┤
│ Application                                │
│ Riverpod Notifiers, controllers, casos      │
│ de uso e coordenação de eventos             │
├────────────────────────────────────────────┤
│ Domain                                     │
│ GameState, Room, GameMessage, regras e      │
│ máquinas de estados                         │
├────────────────────────────────────────────┤
│ Data / Infrastructure                      │
│ Firebase, Firestore, WebRTC, sensores,      │
│ isolate e permissões da plataforma          │
└────────────────────────────────────────────┘
```

### Presentation

Contém as páginas e widgets Flutter:

- `features/lobby.dart`
- `features/game/bomb.dart`
- `features/manual/manual.dart`
- widgets dos módulos da bomba

As Views devem limitar-se a:

- observar estado;
- apresentar estado;
- enviar ações para um controller;
- tratar navegação e confirmação de saída.

### Application

É a camada de coordenação. Atualmente o jogo já possui:

- `GameController`;
- `GameState`;
- `GameEvent`;
- `gameControllerProvider`.

O controller coordena o `BombEngine`, recebe eventos e publica o estado que a UI observa.
As transições de estado vivem em funções puras em `game_reducer.dart`.

Os services chegam às páginas por providers (`services/service_providers.dart`):
`bombServiceProvider` e `roomServiceFactoryProvider`. Como cada `RoomService` é
uma sessão descartável, a lobby recebe uma fábrica e cria um service por sala.
Os testes substituem estes providers por fakes.

A lobby e o mundo têm ViewModels próprios: `LobbyController` (`LobbyState`,
um por página através de `lobbyControllerProvider(bombId)`) e
`WorldController` (`WorldState`). As páginas só observam o estado, chamam
métodos e tratam de UI: campo de texto, diálogos, snackbars e navegação.
Quando o jogo começa, `LobbyController.handOff()` entrega a sessão
(`RoomService`, papel e resolução da bomba do mundo) aos ecrãs de jogo e
deixa de a fechar.

### Domain

Contém conceitos independentes da UI e da infraestrutura:

- `PlayerRole`;
- `ModuleType`;
- `GameState`;
- `Room`;
- `RoomMessage`;
- `GameMessage`;
- estados e regras da partida.

O domínio não deve depender de widgets Flutter, Firestore ou WebRTC quando não for necessário.

### Data e Infrastructure

Contém integrações externas:

- `RoomService`: orquestra uma sessão de lobby e implementa `GameTransport`;
  - `RoomSignaling` / `RoomMailbox`: documento `rooms/{code}` no Firestore (SDP e ICE);
  - `PeerLink`: `RTCPeerConnection` e DataChannel `room-v1`, só transporta texto;
  - `RoomProtocol`: máquina de estados da lobby;
- `GameTransport`: interface mínima de mensagens de jogo usada pelo `GameController`;
- `BombService`: Firestore e bombas do mundo;
- `BombEngine`: timer e regras autoritárias da bomba;
- `flutter_webrtc`: ligação peer-to-peer;
- `geolocator` e `sensors_plus`: dados da plataforma.

## 4. Padrões utilizados

### 4.1 MVVM na aplicação

A app segue MVVM; o jogo é a exceção (ver 4.2):

| Ecrã | ViewModel |
|---|---|
| Perfil, Definições | `ProfileController`, `SettingsController` |
| Lobby | `LobbyController` |
| Mundo | `WorldController` |
| Módulo da bússola | `CompassController` |
| Bomba e Manual | `GameController` (MVI) |

Os minijogos gyro, morse, símbolos e desenho guardam apenas estado local de
interação e devolvem sucesso ou falha; a `BombPage` converte esse resultado
num evento MVI.

Estrutura:

```text
View ───── observa ───── ViewModel / Controller
  │                             │
  │ ações                       │
  └─────────────────────────────┘
                                │
                         Repository / Service
```

Em Flutter, o ViewModel é representado por um `Notifier` Riverpod. A View não conhece os detalhes do Firebase, do WebRTC ou do isolate.

### 4.2 MVI no jogo

O jogo utiliza uma variante de MVI:

```text
View ── GameEvent ──► GameController.dispatch ──► reducer puro ──► GameState ──► View
                              │
                              └── efeitos: BombEngine (comandos), GameTransport (mensagens)
BombEngine ── EngineStateReceived ──┘
GameTransport ── RemoteMessageReceived ──┘
```

Todas as entradas passam por `dispatch(GameEvent)`:

- intents do operador: `ModuleOpened`, `ModuleClosed`, `SolveModuleRequested`,
  `StrikeRequested`, `DrawingChanged`, `DrawingCompleted`, `GameEndAnnounced`;
- intents do manual: `ManualFocusRequested`, `HackLaunched`, `HackCountered`;
- ambos: `PlayerNameSet`;
- sistema: `EngineStateReceived`, `RemoteMessageReceived`.

As Views não chamam métodos de negócio do controller; enviam eventos. Os
reducers (`reduceEngineState`, `reduceSnapshot`, `reduceEnded`,
`reducePeerCommand`) são funções puras e devolvem a mesma instância quando
ignoram a entrada. O controller só executa efeitos. `start()` continua a ser
um método de ciclo de vida, porque cria o isolate e liga o transporte.

O `BombEngine` não é um segundo MVI: é um actor num isolate. Recebe comandos
(`solve`, `strike`, `abandon`) e devolve o estado completo a cada 200 ms.

O desenho remoto continua num `ValueNotifier` global (`liveDrawing`) e não
no `GameState`; é estado de apresentação de alta frequência.

Este modelo é apropriado para o jogo porque facilita:

- testes determinísticos;
- sincronização entre jogadores;
- reconstrução de estado a partir de snapshots;
- controlo explícito da autoridade;
- prevenção de alterações acidentais feitas por widgets.

### 4.3 Repository

Um repository representa dados da aplicação, não uma API específica.

Exemplos de nomes adequados para a evolução:

- `RoomRepository`: estado e operações da sessão;
- `BombRepository`: bombas do mundo;
- `GameRepository`: estado persistido ou sincronizado da partida, se vier a ser necessário.

Os repositories podem usar services, mas não devem expor detalhes de Firestore diretamente à UI.

### 4.4 Service

Services encapsulam recursos externos:

- Firebase Auth;
- Firestore;
- WebRTC;
- sensores;
- GPS.

Um service deve ser substituível em testes e não deve conter regras de apresentação.

### 4.5 State machine

A lobby e o protocolo de jogo são máquinas de estados explícitas.

Estados da sala:

```text
waiting → ready → starting → playing
    └────────────────────────→ closed
```

Transições inválidas, como trocar papéis durante `starting` ou `playing`, devem ser rejeitadas pelo domínio, não apenas desativadas visualmente na UI.

## 5. Estado da aplicação

### 5.1 Estado imutável

O estado apresentado pela UI deve ser imutável. Para criar uma alteração, usa-se `copyWith` ou uma nova instância.

Exemplo conceptual:

```dart
state = state.copyWith(
  strikes: next.strikes,
  timeLeft: next.timeLeft,
);
```

Não se deve alterar diretamente uma coleção que já esteja dentro do estado. Coleções recebidas do engine são convertidas para estruturas imutáveis antes de serem publicadas.

### 5.2 Estado da bomba

O `GameState` atual contém:

- tempo restante;
- número de strikes;
- módulos resolvidos;
- estado da bomba;
- indicação de que o engine foi iniciado.

O estado é criado pelo `GameController`, que coordena o `BombEngine`.

### 5.3 Composição da bomba e estado dos módulos

Uma bomba não é apenas uma lista de tipos. O `BombLoadout` representa a
composição sorteada da partida:

```text
BombLoadout
  ├── seed
  └── modules
       ├── id
       ├── type
       ├── variant
       ├── status
       └── failureCount
```

O `type` identifica a família do módulo e `variant` identifica a variante
concreta que calhou nessa bomba. O `failureCount` pertence ao módulo, enquanto
o número global de strikes pertence ao `GameState`.

O loadout é gerado no defuser e enviado explicitamente no snapshot inicial. O
manual não deve fazer um sorteio local, mesmo que conheça a seed.

### 5.4 Ciclo de vida

O `gameControllerProvider` é `autoDispose` porque o estado da bomba pertence a uma única partida.

Ao sair da página:

1. o provider deixa de ser observado;
2. o controller cancela a subscrição do engine;
3. o isolate é encerrado;
4. uma nova partida começa com estado limpo.

## 6. Fluxo de criação e entrada numa sala

### Criar sala

```text
Jogador
  ↓
RoomService.createRoom()
  ↓
Firebase Auth anónimo
  ↓
Firestore transaction
  ↓
rooms/{codigo}
  ↓
WebRTC offer
  ↓
Lobby pronta para receber convidado
```

O documento de Firestore contém apenas dados necessários para signaling:

- sessão;
- host;
- guest;
- offer e answer;
- candidatos ICE;
- expiração.

Não contém timer, papéis, módulos, strikes ou resultados de jogo.

### Entrar numa sala

```text
Jogador introduz código
  ↓
RoomService.joinRoom(code)
  ↓
Firestore transaction reclama guestUid
  ↓
Guest recebe offer
  ↓
Guest cria answer
  ↓
Troca de candidatos ICE
  ↓
DataChannel aberto
  ↓
Sala ready
```

O Firestore é apenas um mailbox temporário. Depois do início do jogo, a comunicação passa para o DataChannel.

## 7. Fluxo da lobby

O host é a autoridade das decisões da lobby.

```text
Guest                        Host
  │                           │
  │──── hello ───────────────>│
  │<─── state ────────────────│
  │                           │
  │──── swap request ────────>│
  │<─── state atualizado ─────│
  │                           │
  │<─── prepare ──────────────│
  │──── ack ─────────────────>│
  │<─── start ────────────────│
```

O host pode ser o manual numa sala normal. Por isso, a autoridade da lobby não deve ser confundida com a autoridade do jogo.

## 8. Fluxo de início do jogo

```text
Host pressiona COMEÇAR
  ↓
Host entra em starting
  ↓
Host envia prepare
  ↓
Guest valida revisão e papéis
  ↓
Guest envia ack
  ↓
Host remove mailbox de signaling
  ↓
Host envia start
  ↓
Ambos entram na View correspondente ao papel
```

O `start` só é válido se corresponder à revisão e aos papéis preparados. Isto evita começar com papéis diferentes em dispositivos diferentes.

## 9. Fluxo do jogo e autoridade do defuser

### Inicialização

```text
BombPage
  ↓
GameController.start()
  ↓
BombEngine.start()
  ↓
Dart Isolate do defuser
  ↓
EngineStateReceived
  ↓
GameState
  ↓
BombPage
```

O timer não é gerido por `Timer` dentro do widget. O widget apenas apresenta o estado publicado pelo controller.

### Resolver um módulo

```text
Defuser interage com módulo
  ↓
Módulo devolve sucesso/erro
  ↓
BombPage envia SolveModuleRequested ou StrikeRequested
  ↓
GameController.dispatch → BombEngine.solveModule() ou registerStrike()
  ↓
Engine produz novo estado
  ↓
GameController atualiza GameState
  ↓
Snapshot enviado ao Manual
```

### Abandono da partida

A saída do parceiro ou a perda de ligação chega ao `GameController` como uma
mensagem `ended`. No operador, o controller pede `BombEngine.abandon()`; o
engine cancela o timer, passa ao estado terminal `abandoned` e ignora novos
inputs. O estado final regressa pelo fluxo habitual `EngineStateReceived →
GameState → BombPage`. A View apresenta a `ResultPage` com o motivo da saída,
sem decidir o estado do engine. Eventos de ligação repetidos não substituem
um resultado concluído e os snapshots deixam de ser publicados após a saída.

As estatísticas continuam a ser registadas apenas no perfil do operador.
Uma partida abandonada não conta como bomba desarmada ou explodida. No modo
mundo, a bomba é resolvida como `abandoned` e volta a ficar armada para outros
jogadores; só a saída voluntária do operador a faz explodir.
O manual mantém o diálogo de fim de sessão e regresso ao menu.

### Snapshot para o manual

```text
BombEngine
  ↓
GameController do defuser
  ↓
GameTransport / RoomService
  ↓
WebRTC DataChannel
  ↓
GameController do manual
  ↓
ManualPage
```

O manual recebe snapshots através do `GameController` em modo réplica. A
primeira versão já mostra tempo, strikes, módulos, variantes e falhas. Os
comandos específicos dos módulos ainda devem ser adicionados sem permitir que
o manual se torne autoridade do jogo.

O módulo de desenho já usa uma mensagem `drawing` separada: os strokes
normalizados são enviados com limitação de frequência e o manual atualiza o
desenho em direto. O desenho é estado de apresentação, não estado autoritário
da bomba.

## 10. Protocolos de comunicação

### Lobby protocol

As mensagens de lobby usam `RoomMessage` e incluem:

- versão;
- sessão;
- tipo;
- revisão;
- papel do host;
- indicação de papéis bloqueados.

Tipos atuais:

- `hello`;
- `state`;
- `swap`;
- `prepare`;
- `ack`;
- `start`;
- `closed`.

### Game protocol

As mensagens de jogo usam `GameMessage`, com um `scope` separado:

```json
{
  "scope": "game",
  "version": 1,
  "session": "...",
  "type": "snapshot",
  "revision": 12,
  "payload": {
    "timeLeftMs": 120000,
    "strikes": 1,
    "solvedModules": [0, 2],
    "status": "running"
  }
}
```

Regras importantes:

- mensagens de jogo não são aceites como mensagens de lobby;
- a sessão deve coincidir;
- a revisão não pode ser negativa;
- mensagens têm limite de tamanho;
- gameplay não é persistido no Firestore;
- snapshots são produzidos pelo defuser.

## 11. Bombas do mundo

As bombas do mundo são diferentes da bomba de uma partida.

```text
Jogador planta bomba
  ↓
BombService.plantBomb()
  ↓
Firestore bombs/{uid}_{slot}
  ↓
Outro jogador encontra bomba por geohash
  ↓
BombService.claimBomb()
  ↓
Claim lease de 10 minutos
  ↓
Lobby criada automaticamente
  ↓
Planteador/claimer joga como defuser
```

O Firestore impõe as regras de segurança de:

- máximo de três slots ativos por jogador;
- uma reclamação por lease;
- resolução apenas pelo jogador que reclamou;
- transições válidas de estado.

A distância GPS é validada no cliente, porque as Firestore Rules não têm acesso à localização física do dispositivo.

## 12. O que não deve acontecer

Evitar:

- escrever gameplay em `rooms/{code}`;
- usar Firestore como canal de tempo real para módulos;
- criar um timer independente no manual;
- decidir `defused` no widget;
- deixar `BombPage` conhecer detalhes do isolate;
- fazer o `RoomService` conter regras de strikes ou módulos;
- duplicar o estado da partida em vários `StatefulWidget`;
- confiar apenas em botões desativados para impedir transições inválidas;
- reutilizar uma sala antiga depois de uma ligação falhada.

## 13. Estado atual e dívida técnica

Já implementado:

- criação e entrada em salas;
- signaling Firestore;
- DataChannel WebRTC;
- troca de papéis;
- handshake seguro de início;
- protocolo de jogo separado;
- `BombEngine` no isolate do defuser;
- `GameState`, `GameEvent` e `GameController` com Riverpod;
- publicação de snapshots da bomba;
- resolução de bombas do mundo (uma partida abandonada pelo parceiro volta a
  armar a bomba, através de `worldOutcomeFor`);
- `GameTransport` independente do `RoomService`;
- `RoomService` dividido em `RoomSignaling`, `PeerLink` e `RoomProtocol`;
- services injetados por providers Riverpod;
- reducers puros do jogo com testes isolados (`test/game_reducer_test.dart`).

Ainda por implementar:

- comandos de jogo versionados para cada módulo;
- confirmação e deduplicação de comandos;
- testes de integração entre dois peers reais (WebRTC).

A reconexão automática continua deliberadamente fora do protocolo atual. Como
o mailbox de signaling é removido depois do handshake final, uma reconexão
segura exige uma versão própria do protocolo de sessão.

## 14. Próximos passos recomendados

### Fase 1 — completar a vertical do jogo

1. ~~Criar `GameTransport` como abstração sobre o DataChannel.~~ Feito.
2. Expandir o comando `module_focus` para comandos de input específicos de cada módulo.
3. ~~Validar revisões e ignorar snapshots antigos.~~ Feito: o manual ignora
   snapshots com revisão menor ou igual à última aplicada. O timer é publicado
   uma vez por segundo, mas módulos resolvidos, falhas e strikes são
   publicados de imediato.
4. ~~Testar o mesmo cenário em dois controllers independentes.~~ Feito em
   `test/game_two_peers_test.dart`, com um DataChannel em memória que codifica
   e valida cada mensagem.

### Fase 2 — migrar a lobby

Feito, em MVVM (`LobbyState` + `LobbyController`, sem `LobbyEvent`): a
lobby tem poucas ações, todas locais, e não precisa de reducer.

### Fase 3 — separar infraestrutura

1. ~~Extrair signaling Firebase~~ — feito em `RoomSignaling`.
2. ~~Extrair WebRTC~~ — feito em `PeerLink`.
3. Criar `RoomRepository` para compor os dois (hoje o `RoomService` faz esse papel).
4. Manter regras de domínio fora dessas implementações.

### Fase 4 — robustez

1. Adicionar estados de erro e reconexão.
2. ~~Definir comportamento quando o app vai para background.~~ Feito: ao
   esconder a app, o jogador envia `command: presence` (`away: true`) e o
   parceiro vê um aviso. O timer da bomba não para, porque o relógio do
   operador é a autoridade. Se a ausência durar mais do que o limite de
   silêncio, a partida termina como `connection_lost`.
3. ~~Adicionar timeout de snapshots e desconexão visível.~~ Feito: os dois
   peers enviam `ping` a cada segundo (`HeartbeatTick`). Sem mensagens do
   parceiro durante 4 s, `GameState.linkWarning` mostra um aviso nos dois
   ecrãs; aos 15 s, o controller trata a sessão como `connection_lost`, sem
   esperar que o DataChannel falhe (o que pode demorar cerca de 30 s). O
   controller conta ticks em vez de ler o relógio, para ser testável com
   tempo simulado (`test/game_heartbeat_test.dart`).
4. Testar TURN em redes que não suportam ligação direta.
5. Validar lifecycle de isolate, rota e provider em Android, iOS e web.

## 15. Regra prática para novas funcionalidades

Antes de adicionar uma funcionalidade, responder:

1. Quem é a autoridade deste estado?
2. É estado de UI, domínio ou infraestrutura?
3. Deve ser um evento, uma mensagem ou uma chamada local?
4. Quem pode alterar o estado?
5. Como se testa sem renderizar widgets?
6. O que acontece se a mensagem chegar atrasada, duplicada ou fora de ordem?

Se estas respostas estiverem claras, a funcionalidade deve encaixar naturalmente nas camadas existentes sem aumentar a responsabilidade dos widgets.

## Bússola: sensor e alinhamento

O package `precise_compass` 0.2.0 requer Flutter >=3.44.0 e Dart >=3.12.0;
o `pubspec.yaml` declara `sdk: ^3.12.0` para o erro ser explícito.

`CompassService` encapsula o package `precise_compass` e publica amostras
imutáveis com rumo magnético, precisão estimada e indicação de calibração.
Não pede localização para obter norte magnético. Android e iOS são suportados;
web e desktop apresentam o estado de sensor indisponível.

`compassHeadingProvider` gere a subscrição do sensor. `CompassController`
captura o rumo apenas enquanto o jogador mantém **MANTER PARA ALINHAR**
premido; ao soltar ou cancelar o gesto, fixa a amostra. O ponteiro e a resposta
usam essa mesma amostra, mesmo que o telemóvel se mova depois. Os providers
são `autoDispose`, libertando o sensor ao fechar o módulo.

A confirmação exige uma amostra válida e o botão de alinhamento solto.
Se o sensor indicar calibração ou uma incerteza superior à tolerância de 15°,
a confirmação fica desativada até o jogador captar uma leitura melhor.
Dispositivos sem estimativa de precisão podem usar o rumo disponível.
O resultado segue o fluxo existente do módulo para o `GameController` e o
`BombEngine`; não se transmite nem persiste o stream do sensor.

Teste num telemóvel real: abrir BÚSSOLA, manter o botão premido, rodar o
telemóvel na horizontal e soltar. Rodar novamente deve manter o ponteiro
fixo; voltar a premir permite ajustar. A calibração física (movimento em 8,
afastado de ímanes/metal) é distinta de fixar a resposta.

## Ângulo: sensor e alinhamento

`TiltService` encapsula o `sensors_plus` e calcula a rotação do telemóvel no
plano do ecrã a partir da gravidade medida pelo acelerómetro
(`atan2(-x, y)`, sentido horário, 0° = vertical em retrato). Usa-se o
acelerómetro e não a integração do giroscópio porque dá um ângulo absoluto,
sem deriva. O vetor é suavizado com um filtro passa-baixo antes de calcular o
ângulo, para a passagem 0°/360° não causar saltos. Com o telemóvel quase
deitado (gravidade no plano < 5 m/s²) não há leitura válida. Web e desktop
apresentam o estado de sensor indisponível.

`tiltProvider` e `GyroController` seguem o mesmo padrão da bússola: o ângulo
só é captado enquanto **MANTER PARA ALINHAR** está premido e fica fixado ao
soltar. A tolerância é de 10°.

## Morse: vibração

O módulo Morse usa o package `vibration` para vibrar com a duração real de
cada símbolo (ponto = 1 unidade, traço = 3 unidades), em sincronia com o LED,
para que o sinal possa ser lido sem olhar para o ecrã. Se o dispositivo não
suportar vibração, recorre a `HapticFeedback`. A vibração é cancelada ao
fechar o módulo.
