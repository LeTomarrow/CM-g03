import 'dart:convert';

/// Messages exchanged after the lobby has started.
class GameMessage {
  const GameMessage({
    required this.session,
    required this.type,
    required this.revision,
    this.payload = const <String, dynamic>{},
  });

  static const maxBytes = 8192;
  static const types = {'snapshot', 'command', 'ended', 'ping'};

  final String session;
  final String type;
  final int revision;
  final Map<String, dynamic> payload;

  String encode() {
    if (!types.contains(type)) {
      throw const FormatException('Invalid game type');
    }
    final text = jsonEncode({
      'scope': 'game',
      'version': 1,
      'session': session,
      'type': type,
      'revision': revision,
      'payload': payload,
    });
    if (text.length > maxBytes) {
      throw const FormatException('Message too large');
    }
    return text;
  }

  static GameMessage decode(String text, String session) {
    if (text.length > maxBytes) {
      throw const FormatException('Message too large');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['scope'] != 'game' ||
        data['version'] != 1 ||
        data['session'] != session ||
        !types.contains(data['type']) ||
        data['revision'] is! int ||
        data['revision'] < 0 ||
        data['payload'] is! Map) {
      throw const FormatException('Invalid game message');
    }
    return GameMessage(
      session: session,
      type: data['type'] as String,
      revision: data['revision'] as int,
      payload: Map<String, dynamic>.from(data['payload'] as Map),
    );
  }
}
