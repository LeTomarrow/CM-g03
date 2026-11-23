import 'package:what_did_you_press/services/game_protocol.dart';

/// What the game needs from the network: a channel of [GameMessage]s.
/// Implemented by RoomService over the WebRTC DataChannel; tests use fakes.
abstract interface class GameTransport {
  Stream<GameMessage> get gameMessages;

  /// Throws if the peer is no longer connected.
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload,
  });
}
