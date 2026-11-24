import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:what_did_you_press/services/room/room_models.dart';

/// Firestore `rooms/{code}`: a short-lived rendezvous mailbox for SDP and ICE.
/// It never stores lobby or game decisions; firestore.rules mirrors this shape.
class RoomSignaling {
  RoomSignaling(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String code) =>
      _firestore.collection('rooms').doc(code);

  /// Reserves [code] for a new room, or returns null if it is already taken.
  Future<RoomMailbox?> reserve({
    required String code,
    required String session,
    required String hostUid,
    required DateTime expiresAt,
  }) async {
    final ref = _doc(code);
    final created = await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (snapshot.exists) return false;
      tx.set(ref, {
        'version': 1,
        'session': session,
        'hostUid': hostUid,
        'guestUid': null,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'offer': null,
        'answer': null,
        'hostCandidates': <dynamic>[],
        'guestCandidates': <dynamic>[],
      });
      return true;
    });
    return created ? RoomMailbox._(_firestore, ref) : null;
  }

  /// Re-signaling channel for ICE restarts of [session] during a game.
  ReconnectMailbox reconnect(String session) =>
      ReconnectMailbox(_firestore, session);

  /// Claims the guest slot of [code] for [uid].
  Future<
    ({RoomMailbox mailbox, String session, String hostUid, DateTime expiresAt})
  >
  join(String code, String uid) async {
    final ref = _doc(code);
    final data = await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final data = snapshot.data();
      if (data == null || data['version'] != 1) {
        throw roomError('Sala não encontrada. Confirma o código.');
      }
      if ((data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
        throw roomError('A sala expirou.');
      }
      if (data['hostUid'] == uid) {
        throw roomError('Já és o anfitrião desta sala.');
      }
      if (data['guestUid'] != null && data['guestUid'] != uid) {
        throw roomError('A sala está cheia.');
      }
      // Reusing a previously claimed slot would mix old ICE/SDP with a new peer.
      if (data['answer'] != null) {
        throw roomError('Cria uma nova sala para voltar a ligar.');
      }
      tx.update(ref, {'guestUid': uid});
      return data;
    });
    return (
      mailbox: RoomMailbox._(_firestore, ref),
      session: data['session'] as String,
      hostUid: data['hostUid'] as String,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
    );
  }
}

/// One reserved room document. Each write matches one rule in firestore.rules.
class RoomMailbox {
  RoomMailbox._(this._firestore, this._ref);

  final FirebaseFirestore _firestore;
  final DocumentReference<Map<String, dynamic>> _ref;

  String get code => _ref.id;

  Future<void> writeOffer(Object? offer) => _ref.update({'offer': offer});

  Future<void> writeAnswer(Object? answer) => _ref.update({'answer': answer});

  Future<void> addCandidate(Object? candidate, {required bool fromHost}) =>
      _ref.update({
        fromHost ? 'hostCandidates' : 'guestCandidates': FieldValue.arrayUnion([
          candidate,
        ]),
      });

  /// Document data, or null once the host deleted it.
  ///
  /// A missing document only counts once the server says so: right after
  /// the reservation transaction, the local cache can still report the
  /// room as missing, which used to close a freshly created room.
  Stream<Map<String, dynamic>?> watch() => _ref
      .snapshots()
      .where((snapshot) => snapshot.exists || !snapshot.metadata.isFromCache)
      .map((snapshot) => snapshot.data());

  /// Deletes the mailbox only if it still belongs to [session].
  Future<void> deleteIfSession(String session) async {
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(_ref);
      if (snapshot.data()?['session'] == session) tx.delete(_ref);
    });
  }
}

/// Firestore `reconnects/{session}`: re-signals an ICE restart during a game,
/// after the room mailbox was deleted. The session id is the shared secret
/// that names it; firestore.rules restricts it to the two players.
///
/// Each attempt is a whole new document state written by the host (offer,
/// empty answer and candidate lists, `attempt` + 1); the guest only answers
/// and both only append their own candidates.
class ReconnectMailbox {
  ReconnectMailbox(FirebaseFirestore firestore, String session)
    : _ref = firestore.collection('reconnects').doc(session);

  final DocumentReference<Map<String, dynamic>> _ref;

  Future<void> writeAttempt({
    required int attempt,
    required String hostUid,
    required String guestUid,
    required Object? offer,
  }) => _ref.set({
    'hostUid': hostUid,
    'guestUid': guestUid,
    'attempt': attempt,
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 5)),
    ),
    'offer': offer,
    'answer': null,
    'hostCandidates': <dynamic>[],
    'guestCandidates': <dynamic>[],
  });

  Future<void> writeAnswer(Object? answer) => _ref.update({'answer': answer});

  Future<void> addCandidate(Object? candidate, {required bool fromHost}) =>
      _ref.update({
        fromHost ? 'hostCandidates' : 'guestCandidates': FieldValue.arrayUnion([
          candidate,
        ]),
      });

  /// Document data, or null while no attempt exists.
  Stream<Map<String, dynamic>?> watch() =>
      _ref.snapshots().map((snapshot) => snapshot.data());

  Future<void> delete() => _ref.delete();
}
