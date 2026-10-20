import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:what_did_you_press/core/geo.dart';
import 'package:what_did_you_press/services/anonymous_sign_in.dart';

/// The rules cannot see GPS, so this distance is only checked on the client.
const double claimRadiusMeters = 50;

/// Durations and slot count mirror firestore.rules.
const Duration bombLifetime = Duration(hours: 24);
const Duration claimLease = Duration(minutes: 10);
const int maxActiveBombs = 3;

/// Geohash precision used for nearby queries (~4.9 km cells); with the
/// neighbouring cells this covers at least [nearbyRadiusMeters] in Portugal.
const int _queryPrecision = 5;
const double nearbyRadiusMeters = 3000;

enum BombOutcome { defused, exploded, abandoned }

enum BombFailure { gone, busy, tooFar, ownBomb, limitReached }

class BombException implements Exception {
  const BombException(this.reason);

  final BombFailure reason;

  @override
  String toString() => 'BombException(${reason.name})';
}

/// An open-world bomb as stored in Firestore `bombs/{id}`.
class Bomb {
  const Bomb({
    required this.id,
    required this.lat,
    required this.lng,
    required this.plantedBy,
    required this.status,
    required this.active,
    required this.claimedBy,
    required this.claimExpiresAt,
    required this.expiresAt,
  });

  final String id;
  final double lat;
  final double lng;
  final String plantedBy;
  final String status;
  final bool active;
  final String? claimedBy;
  final DateTime? claimExpiresAt;
  final DateTime expiresAt;

  bool isLive(DateTime now) => active && expiresAt.isAfter(now);

  bool isLeased(DateTime now) {
    return status == 'claimed' && claimExpiresAt!.isAfter(now);
  }

  /// Armed, or claimed by a pair whose lease ran out.
  bool isClaimable(DateTime now) {
    return isLive(now) && (status == 'armed' || !isLeased(now));
  }

  double distanceTo(double lat, double lng) {
    return distanceMeters(lat, lng, this.lat, this.lng);
  }

  factory Bomb.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    // Timestamps are null while our own serverTimestamp() write is pending.
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final claimedAt = data['status'] == 'claimed'
        ? (data['claimedAt'] as Timestamp?)?.toDate() ?? DateTime.now()
        : null;
    return Bomb(
      id: snapshot.id,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      plantedBy: data['plantedBy'] as String,
      status: data['status'] as String,
      active: data['active'] as bool,
      claimedBy: data['claimedBy'] as String?,
      claimExpiresAt: claimedAt?.add(claimLease),
      expiresAt: createdAt.add(bombLifetime),
    );
  }
}

/// Use after Firebase.initializeApp(). Rule violations surface as
/// FirebaseException(permission-denied); expected failures as BombException.
class BombService {
  BombService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String? get uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _bombs =>
      _firestore.collection('bombs');

  Future<String> _signedInUid() async {
    await ensureSignedIn(_auth);
    return _auth.currentUser!.uid;
  }

  /// Plants in the player's first free slot ({uid}_0..2).
  Future<String> plantBomb(double lat, double lng) async {
    final uid = await _signedInUid();
    return _firestore.runTransaction((transaction) async {
      final now = DateTime.now();
      for (var slot = 0; slot < maxActiveBombs; slot++) {
        final ref = _bombs.doc('${uid}_$slot');
        final snapshot = await transaction.get(ref);
        if (snapshot.exists && Bomb.fromSnapshot(snapshot).isLive(now)) {
          continue;
        }
        transaction.set(ref, {
          'lat': lat,
          'lng': lng,
          'geohash': encodeGeohash(lat, lng),
          'plantedBy': uid,
          'status': 'armed',
          'active': true,
          'claimedBy': null,
          'claimedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return ref.id;
      }
      throw const BombException(BombFailure.limitReached);
    });
  }

  /// Locks the bomb for one game ([claimLease]); the claimer then hosts an
  /// ordinary room as operator. Claiming again with the same identity is safe.
  Future<void> claimBomb(String bombId, double lat, double lng) async {
    final uid = await _signedInUid();
    final ref = _bombs.doc(bombId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw const BombException(BombFailure.gone);
      final bomb = Bomb.fromSnapshot(snapshot);
      final now = DateTime.now();
      if (!bomb.isLive(now)) throw const BombException(BombFailure.gone);
      if (bomb.plantedBy == uid) {
        throw const BombException(BombFailure.ownBomb);
      }
      if (bomb.isLeased(now)) {
        if (bomb.claimedBy == uid) return;
        throw const BombException(BombFailure.busy);
      }
      if (bomb.distanceTo(lat, lng) > claimRadiusMeters) {
        throw const BombException(BombFailure.tooFar);
      }
      transaction.update(ref, {
        'status': 'claimed',
        'claimedBy': uid,
        'claimedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Only the claimer may resolve; abandoning re-arms the bomb.
  Future<void> resolveBomb(String bombId, BombOutcome outcome) async {
    await _signedInUid();
    await _bombs
        .doc(bombId)
        .update(
          outcome == BombOutcome.abandoned
              ? {'status': 'armed', 'claimedBy': null, 'claimedAt': null}
              : {
                  'status': outcome.name,
                  'active': false,
                  'resolvedBy': uid,
                  'resolvedAt': FieldValue.serverTimestamp(),
                },
        );
  }

  /// Live bombs within [nearbyRadiusMeters], closest first. Resubscribe when
  /// the player moves far, since the queried cells are fixed per stream.
  Stream<List<Bomb>> watchNearbyBombs(double lat, double lng) {
    final latest = <String, List<Bomb>>{};
    final subscriptions = <StreamSubscription<Object?>>[];
    var cancelled = false;
    late final StreamController<List<Bomb>> controller;

    void emit() {
      final now = DateTime.now();
      final bombs =
          latest.values
              .expand((cell) => cell)
              .where((bomb) => bomb.isLive(now))
              .where((bomb) => bomb.distanceTo(lat, lng) <= nearbyRadiusMeters)
              .toList()
            ..sort(
              (a, b) =>
                  a.distanceTo(lat, lng).compareTo(b.distanceTo(lat, lng)),
            );
      controller.add(bombs);
    }

    Future<void> subscribe() async {
      await ensureSignedIn(_auth);
      if (cancelled) return;
      for (final cell in coveringCells(lat, lng, _queryPrecision)) {
        final query = _bombs
            .where('active', isEqualTo: true)
            .where('geohash', isGreaterThanOrEqualTo: cell)
            .where('geohash', isLessThan: '$cell~');
        subscriptions.add(
          query.snapshots().listen((snapshot) {
            latest[cell] = snapshot.docs.map(Bomb.fromSnapshot).toList();
            emit();
          }, onError: controller.addError),
        );
      }
    }

    controller = StreamController<List<Bomb>>(
      onListen: () => subscribe().catchError(controller.addError),
      onCancel: () async {
        cancelled = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}
