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
  Stream<Map<String, dynamic>?> watch() =>
      _ref.snapshots().map((snapshot) => snapshot.data());

  /// Deletes the mailbox only if it still belongs to [session].
  Future<void> deleteIfSession(String session) async {
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(_ref);
      if (snapshot.data()?['session'] == session) tx.delete(_ref);
    });
  }
}
