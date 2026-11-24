import 'package:what_did_you_press/services/game_protocol.dart';

/// What the game needs from the network: a channel of [GameMessage]s.
/// Implemented by RoomService over the WebRTC DataChannel; tests use fakes.
abstract interface class GameTransport {
  Stream<GameMessage> get gameMessages;

  /// `false` when the connection drops and is being re-established, `true`
  /// when it recovers. A failed recovery arrives as an `ended` message.
  Stream<bool> get linkStatus;

  /// Throws if the peer is no longer connected.
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload,
  });
}
