import 'dart:convert';

/// Small versioned protocol carried only by a reliable, ordered DataChannel.
/// Only the host publishes state; guests request actions and acknowledge start.
class RoomMessage {
  const RoomMessage(
    this.session,
    this.type,
    this.revision,
    this.hostRole, {
    this.locked = false,
  });

  final String session;
  final String type;
  final int revision;
  final String hostRole;

  /// Host-only roles (e.g. the operator of an open-world bomb). Optional on
  /// the wire, so older peers simply ignore it.
  final bool locked;

  static const types = {
    'hello',
    'state',
    'swap',
    'prepare',
    'ack',
    'start',
    'closed',
  };

  String encode() => jsonEncode({
    'version': 1,
    'session': session,
    'type': type,
    'revision': revision,
    'hostRole': hostRole,
    if (locked) 'locked': true,
  });

  static RoomMessage decode(String text, String session) {
    if (text.length > 2048) throw const FormatException('Message too large');
    final data = jsonDecode(text);
    if (data is! Map ||
        data['version'] != 1 ||
        data['session'] != session ||
        !types.contains(data['type']) ||
        data['revision'] is! int ||
        data['revision'] < 0 ||
        !{'defuser', 'manual'}.contains(data['hostRole'])) {
      throw const FormatException('Invalid room message');
    }
    return RoomMessage(
      session,
      data['type'],
      data['revision'],
      data['hostRole'],
      locked: data['locked'] == true,
    );
  }
}

/// The only mutable lobby state. Firestore never stores these game decisions.
class RoomProtocol {
  RoomProtocol({required this.session, required this.isHost});

  final String session;
  final bool isHost;
  int revision = 0;
  String hostRole = 'defuser';
  String phase = 'waiting';

  /// Set by the host before connecting; guests learn it from host state.
  bool locked = false;

  RoomMessage message(String type) =>
      RoomMessage(session, type, revision, hostRole, locked: locked);

  void connected() {
    if (phase == 'waiting') phase = 'ready';
  }

  void swap() {
    if (!isHost || locked || !{'waiting', 'ready'}.contains(phase)) {
      throw StateError('Roles cannot change now');
    }
    hostRole = hostRole == 'defuser' ? 'manual' : 'defuser';
    revision++;
  }

  void prepare() {
    if (!isHost || phase != 'ready') throw StateError('Room is not ready');
    phase = 'starting';
    revision++;
  }

  void abortStart() {
    if (!isHost || phase != 'starting') return;
    phase = 'ready';
    revision++;
  }

  /// Guests accept only newer host state. A start must match the prepared state.
  bool apply(RoomMessage message) {
    if (isHost || message.session != session) return false;
    if (message.type == 'closed') {
      phase = 'closed';
      return true;
    }
    if (message.type == 'start') {
      if (phase != 'starting' ||
          message.revision != revision ||
          message.hostRole != hostRole) {
        return false;
      }
      phase = 'playing';
      return true;
    }
    if (!{'state', 'prepare'}.contains(message.type) ||
        message.revision < revision ||
        phase == 'playing' ||
        phase == 'closed') {
      return false;
    }
    // Replaying a state must never undo a prepare at the same revision.
    if (phase == 'starting' &&
        message.type == 'state' &&
        message.revision == revision) {
      return false;
    }
    revision = message.revision;
    hostRole = message.hostRole;
    locked = message.locked;
    phase = message.type == 'prepare' ? 'starting' : 'ready';
    return true;
  }
}
