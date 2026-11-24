import 'package:firebase_core/firebase_core.dart';
import 'package:what_did_you_press/core/game_models.dart';

class RoomConnection {
  const RoomConnection({required this.roomId, required this.code});
  final String roomId;
  final String code;
}

/// Local state derived from signaling membership and peer protocol messages.
class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.guestUid,
    required this.status,
    required this.expiresAt,
    required this.hostRole,
    this.rolesLocked = false,
  });
  final String id;
  final String code;
  final String hostUid;
  final String? guestUid;
  final String status;
  final DateTime expiresAt;
  final PlayerRole hostRole;

  /// The host keeps its role, as the operator of an open-world bomb.
  final bool rolesLocked;

  PlayerRole roleFor(String uid) {
    if (uid == hostUid) return hostRole;
    if (uid == guestUid) return hostRole.partner;
    throw StateError('Player is not a room member');
  }
}

/// Expected room failure; the lobby shows its message to the player.
FirebaseException roomError(String message) => FirebaseException(
  plugin: 'room',
  code: 'failed-precondition',
  message: message,
);
