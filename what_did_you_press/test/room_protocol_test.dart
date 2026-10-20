import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/services/room_protocol.dart';

void main() {
  test('host owns roles; guest applies state and cannot swap locally', () {
    final host = RoomProtocol(session: 'abc', isHost: true);
    final guest = RoomProtocol(session: 'abc', isHost: false);
    host.swap();
    host.connected();
    expect(guest.apply(host.message('state')), isTrue);
    expect(guest.hostRole, 'manual');
    expect(() => guest.swap(), throwsStateError);
    expect(host.apply(guest.message('state')), isFalse);
    host.swap();
    guest.apply(host.message('state'));
    expect(guest.hostRole, 'defuser');
    expect(
      guest.apply(const RoomMessage('abc', 'state', 0, 'manual')),
      isFalse,
    );
  });

  test('start requires ready, matching prepare and frozen role/revision', () {
    final host = RoomProtocol(session: 'abc', isHost: true);
    final guest = RoomProtocol(session: 'abc', isHost: false);
    expect(() => host.prepare(), throwsStateError);
    host.connected();
    host.prepare();
    expect(guest.apply(host.message('start')), isFalse);
    guest.apply(host.message('prepare'));
    expect(() => host.swap(), throwsStateError);
    expect(guest.apply(host.message('state')), isFalse);
    expect(
      guest.apply(RoomMessage('abc', 'start', host.revision, 'manual')),
      isFalse,
    );
    expect(guest.apply(host.message('start')), isTrue);
    expect(guest.phase, 'playing');
    expect(guest.apply(host.message('start')), isFalse);
  });

  test('aborted start unlocks roles with a newer host state', () {
    final host = RoomProtocol(session: 'abc', isHost: true)..connected();
    final guest = RoomProtocol(session: 'abc', isHost: false);
    host.prepare();
    guest.apply(host.message('prepare'));
    host.abortStart();
    guest.apply(host.message('state'));
    expect(guest.phase, 'ready');
    host.swap();
    guest.apply(host.message('state'));
    expect(guest.hostRole, host.hostRole);
  });

  test(
    'protocol rejects malformed, wrong-session and unsupported messages',
    () {
      const message = RoomMessage('abc', 'state', 3, 'manual');
      expect(RoomMessage.decode(message.encode(), 'abc').revision, 3);
      expect(
        () => RoomMessage.decode(message.encode(), 'other'),
        throwsFormatException,
      );
      expect(() => RoomMessage.decode('{}', 'abc'), throwsFormatException);
      expect(
        () => RoomMessage.decode('not json', 'abc'),
        throwsFormatException,
      );
      expect(
        () => RoomMessage.decode(
          const RoomMessage('abc', 'hack', 0, 'defuser').encode(),
          'abc',
        ),
        throwsFormatException,
      );
    },
  );

  test('locked roles reach the guest and block host swaps', () {
    final host = RoomProtocol(session: 'abc', isHost: true)..locked = true;
    final guest = RoomProtocol(session: 'abc', isHost: false);
    host.connected();
    expect(() => host.swap(), throwsStateError);
    final wire = RoomMessage.decode(host.message('state').encode(), 'abc');
    expect(guest.apply(wire), isTrue);
    expect(guest.locked, isTrue);
    expect(guest.hostRole, 'defuser');
  });
}
