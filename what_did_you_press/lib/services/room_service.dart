import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:what_did_you_press/core/game_models.dart';

class RoomConnection {
  const RoomConnection({required this.roomId, required this.code});

  final String roomId;
  final String code;

  factory RoomConnection.fromMap(Map<String, dynamic> data) {
    return RoomConnection(
      roomId: data['roomId'] as String,
      code: data['code'] as String,
    );
  }
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
    this.hostRole = PlayerRole.defuser,
  });

  final String id;
  final String code;
  final String hostUid;
  final String? guestUid;
  final String status;
  final DateTime expiresAt;
  final PlayerRole hostRole;

  PlayerRole roleFor(String uid) {
    if (uid == hostUid) return hostRole;
    if (uid == guestUid) return hostRole.partner;
    throw StateError("Player is not a room member");
  }

  factory Room.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    return Room(
      id: snapshot.id,
      code: data['code'] as String,
      hostUid: data['hostUid'] as String,
      guestUid: data['guestUid'] as String?,
      status: data['status'] as String,
      hostRole: data['hostRole'] == 'manual'
          ? PlayerRole.manual
          : PlayerRole.defuser,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
    );
  }
}

/// Use after Firebase.initializeApp(). Firebase errors propagate to the UI.
class RoomService {
  RoomService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  Future<void>? _signIn;

  String? get currentUserId => _auth.currentUser?.uid;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    // Concurrent operations must use the same anonymous identity.
    final pending = _signIn ??= _auth.signInAnonymously().then((_) {});
    try {
      await pending;
    } finally {
      if (identical(_signIn, pending)) _signIn = null;
    }
  }

  Future<RoomConnection> createRoom() async {
    await _ensureSignedIn();
    final result = await _functions.httpsCallable('createRoom').call();
    return RoomConnection.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<RoomConnection> joinRoom(String code) async {
    final normalized = code.trim();
    _validateRoomId(normalized);
    await _ensureSignedIn();
    final result = await _functions.httpsCallable('joinRoom').call({
      'code': normalized,
    });
    return RoomConnection.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<void> deleteRoom(String roomId) async {
    _validateRoomId(roomId);
    await _ensureSignedIn();
    await _functions.httpsCallable('deleteRoom').call({'roomId': roomId});
  }

  Future<void> startGame(String roomId) async {
    _validateRoomId(roomId);
    await _ensureSignedIn();
    await _functions.httpsCallable('startGame').call({'roomId': roomId});
  }

  Future<void> switchRoles(String roomId) async {
    _validateRoomId(roomId);
    await _ensureSignedIn();
    await _functions.httpsCallable('switchRoles').call({'roomId': roomId});
  }

  /// Subscribe after create/join; cancel when leaving. Handle null AND
  /// permission-denied errors as closure: deletion removes membership too.
  Stream<Room?> watchRoom(String roomId) {
    _validateRoomId(roomId);
    return _firestore
        .collection('rooms')
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
