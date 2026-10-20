import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:what_did_you_press/services/anonymous_sign_in.dart';

/// Mirrors roomOpen() in firestore.rules.
const Duration roomJoinWindow = Duration(hours: 1);
const int roomCreateAttempts = 10;

final Random _random = Random.secure();

/// Candidate six-digit code, also the document ID; callers check it is free.
String randomRoomCode() => (100000 + _random.nextInt(900000)).toString();

/// A waiting room as the rules expect it on create.
Map<String, dynamic> newRoomData(
  String code,
  String hostUid, {
  String? bombId,
}) {
  return {
    'code': code,
    'hostUid': hostUid,
    'guestUid': null,
    'status': 'waiting',
    'bombId': bombId,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

enum RoomFailure { notFound, full, expired, codeCollision }

class RoomException implements Exception {
  const RoomException(this.reason);

  final RoomFailure reason;

  @override
  String toString() => 'RoomException(${reason.name})';
}

class RoomConnection {
  const RoomConnection({required this.roomId, required this.code});

  final String roomId;
  final String code;
}

/// Lobby membership; ready means two members, not an open WebRTC connection.
class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.guestUid,
    required this.status,
    required this.expiresAt,
    this.bombId,
  });

  final String id;
  final String code;
  final String hostUid;
  final String? guestUid;
  final String status;
  final DateTime expiresAt;

  /// Set when the room was opened by claiming an open-world bomb.
  final String? bombId;

  factory Room.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    // Null while our own serverTimestamp() write is still pending.
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Room(
      id: snapshot.id,
      code: data['code'] as String,
      hostUid: data['hostUid'] as String,
      guestUid: data['guestUid'] as String?,
      status: data['status'] as String,
      expiresAt: createdAt.add(roomJoinWindow),
      bombId: data['bombId'] as String?,
    );
  }
}

/// Use after Firebase.initializeApp(). Rule violations surface as
/// FirebaseException(permission-denied); expected failures as RoomException.
class RoomService {
  RoomService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  Future<String> _signedInUid() async {
    await ensureSignedIn(_auth);
    return _auth.currentUser!.uid;
  }

  Future<RoomConnection> createRoom() async {
    final uid = await _signedInUid();
    for (var attempt = 0; attempt < roomCreateAttempts; attempt++) {
      final code = randomRoomCode();
      final ref = _rooms.doc(code);
      final created = await _firestore.runTransaction((transaction) async {
        if ((await transaction.get(ref)).exists) return false;
        transaction.set(ref, newRoomData(code, uid));
        return true;
      });
      if (created) return RoomConnection(roomId: code, code: code);
    }
    throw const RoomException(RoomFailure.codeCollision);
  }

  Future<RoomConnection> joinRoom(String code) async {
    final normalized = code.trim();
    _validateRoomId(normalized);
    final uid = await _signedInUid();
    final ref = _rooms.doc(normalized);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw const RoomException(RoomFailure.notFound);
      final room = Room.fromSnapshot(snapshot);
      if (!room.expiresAt.isAfter(DateTime.now())) {
        throw const RoomException(RoomFailure.expired);
      }
      // Joining again with the same identity is safe.
      if (room.hostUid == uid || room.guestUid == uid) return;
      if (room.guestUid != null || room.status != 'waiting') {
        throw const RoomException(RoomFailure.full);
      }
      transaction.update(ref, {'guestUid': uid, 'status': 'ready'});
    });
    return RoomConnection(roomId: normalized, code: normalized);
  }

  /// Host only; deleting a missing room is a no-op.
  Future<void> deleteRoom(String roomId) async {
    _validateRoomId(roomId);
    await _signedInUid();
    final ref = _rooms.doc(roomId);
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) transaction.delete(ref);
    });
  }

  /// Subscribe after create/join; cancel when leaving. Null means the room
  /// was deleted.
  Stream<Room?> watchRoom(String roomId) {
    _validateRoomId(roomId);
    return _rooms
        .doc(roomId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists ? Room.fromSnapshot(snapshot) : null,
        );
  }

  void _validateRoomId(String roomId) {
    if (!RegExp(r'^\d{6}$').hasMatch(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Expected six digits');
    }
  }
}
