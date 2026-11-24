import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/lobby.dart';
import 'package:what_did_you_press/services/room_service.dart';
import 'package:what_did_you_press/services/service_providers.dart';

Widget _lobby(FakeRooms rooms) => ProviderScope(
  overrides: [roomServiceFactoryProvider.overrideWithValue(() => rooms)],
  child: MaterialApp(theme: AppTheme.darkTheme, home: const LobbyPage()),
);

class FakeRooms implements RoomService {
  @override
  Object? get closeReason => null;

  FakeRooms(this.uid);
  final String uid;
  final events = StreamController<Room?>.broadcast();
  int closes = 0;

  Room state(String status) => Room(
    id: '123456',
    code: '123456',
    hostUid: 'host',
    guestUid: 'guest',
    status: status,
    expiresAt: DateTime(2099),
    hostRole: PlayerRole.defuser,
  );

  @override
  String get currentUserId => uid;
  @override
  Future<RoomConnection> createRoom() async =>
      const RoomConnection(roomId: '123456', code: '123456');
  @override
  Future<RoomConnection> joinRoom(String code) => createRoom();
  @override
  Stream<Room?> watchRoom(String id) => Stream<Room?>.multi((controller) {
    controller.add(state('ready'));
    final subscription = events.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('remote host closure clears guest lobby and shows one modal', (
    tester,
  ) async {
    final rooms = FakeRooms('guest');
    await tester.pumpWidget(_lobby(rooms));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.ensureVisible(find.text('ENTRAR'));
    await tester.tap(find.text('ENTRAR'));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);

    // The DataChannel emits closed without a separate error. This previously
    // left the guest's room and create/join buttons stuck in the active state.
    rooms.events.add(rooms.state('closed'));
    await tester.pumpAndSettle();
    expect(find.text('SALA ENCERRADA'), findsOneWidget);
    expect(find.textContaining('O anfitrião encerrou'), findsOneWidget);
    expect(find.text('------'), findsOneWidget);
    expect(find.text('123456'), findsNothing);
    expect(rooms.closes, greaterThanOrEqualTo(2));
    await tester.tap(find.text('ENTENDIDO'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('ENTRAR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await rooms.events.close();
  });

  testWidgets('host close uses the shared menu button and resets its lobby', (
    tester,
  ) async {
    final rooms = FakeRooms('host');
    await tester.pumpWidget(_lobby(rooms));
    await tester.ensureVisible(find.text('CRIAR'));
    await tester.tap(find.text('CRIAR'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(MenuButton, 'ENCERRAR SALA');
    expect(button, findsOneWidget);
    expect(tester.widget<MenuButton>(button).color, AppColors.danger);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('------'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await rooms.events.close();
  });
}
