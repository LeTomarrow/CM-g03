import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/features/game/bomb_engine.dart';
import 'package:what_did_you_press/features/lobby_controller.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/services/service_providers.dart';

class _Rooms implements RoomService {
  _Rooms(this.uid);
  final String uid;
  final events = StreamController<Room?>.broadcast();
  int closes = 0;
  int starts = 0;

  Room room(String status, {PlayerRole hostRole = PlayerRole.defuser}) => Room(
    id: '123456',
    code: '123456',
    hostUid: 'host',
    guestUid: 'guest',
    status: status,
    expiresAt: DateTime(2099),
    hostRole: hostRole,
  );

  @override
  bool rolesLocked = false;
  @override
  String get currentUserId => uid;
  @override
  Future<RoomConnection> createRoom() async =>
      const RoomConnection(roomId: '123456', code: '123456');
  @override
  Future<RoomConnection> joinRoom(String code) => createRoom();
  @override
  Stream<Room?> watchRoom(String id) => events.stream;
  @override
  Future<void> startGame(String id) async => starts++;
  @override
  Future<void> close() async => closes++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bombs implements BombService {
  final resolved = <BombOutcome>[];
  @override
  Future<void> resolveBomb(String bombId, BombOutcome outcome) async =>
      resolved.add(outcome);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Rooms rooms;
  late _Bombs bombs;
  late ProviderContainer container;

  ProviderSubscription<LobbyState> listen(String? bombId) =>
      container.listen(lobbyControllerProvider(bombId), (_, _) {});

  setUp(() {
    rooms = _Rooms('host');
    bombs = _Bombs();
    container = ProviderContainer(
      overrides: [
        roomServiceFactoryProvider.overrideWithValue(() => rooms),
        bombServiceProvider.overrideWithValue(bombs),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await rooms.events.close();
  });

  test('a remote closure resets the lobby with a notice', () async {
    final sub = listen(null);
    final controller = container.read(lobbyControllerProvider(null).notifier);
    await controller.connect(create: true);
    rooms.events.add(rooms.room('ready'));
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().isHost, isTrue);
    expect(sub.read().canStart, isTrue);

    rooms.events.add(rooms.room('closed'));
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().connection, isNull);
    expect(sub.read().room, isNull);
    expect(sub.read().closedNotice, contains('O outro jogador saiu'));
  });

  test(
    'starting hands the session to the game instead of closing it',
    () async {
      final sub = listen(null);
      final controller = container.read(lobbyControllerProvider(null).notifier);
      await controller.connect(create: true);
      rooms.events.add(rooms.room('playing', hostRole: PlayerRole.manual));
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().startedRole, PlayerRole.manual);

      final session = controller.handOff();
      expect(session.service, same(rooms));
      final closesBefore = rooms.closes;
      sub.close();
      await container.pump();
      expect(rooms.closes, closesBefore);
    },
  );

  test('leaving a world-bomb lobby before starting re-arms the bomb', () async {
    final sub = listen('bomb_0');
    await Future<void>.delayed(Duration.zero);
    expect(rooms.rolesLocked, isTrue);
    expect(sub.read().connection, isNotNull);
    sub.close();
    await container.pump();
    expect(bombs.resolved, [BombOutcome.abandoned]);
  });

  test('a finished world game resolves the bomb by its result', () async {
    final sub = listen('bomb_0');
    await Future<void>.delayed(Duration.zero);
    rooms.events.add(rooms.room('playing'));
    await Future<void>.delayed(Duration.zero);
    final session = container
        .read(lobbyControllerProvider('bomb_0').notifier)
        .handOff();
    sub.close();
    await container.pump();
    expect(bombs.resolved, isEmpty);
    session.onFinished!(BombEngineStatus.abandoned);
    expect(bombs.resolved, [BombOutcome.abandoned]);
  });
}
