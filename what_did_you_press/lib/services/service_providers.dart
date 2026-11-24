import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/services/room_service.dart';

/// Stateless Firestore access to open-world bombs; override in tests.
final bombServiceProvider = Provider<BombService>((ref) => BombService());

/// A RoomService is one disposable lobby session, so pages get a factory and
/// create a fresh service per room. Override in tests to inject fakes.
final roomServiceFactoryProvider = Provider<RoomService Function()>(
  (ref) => RoomService.new,
);
