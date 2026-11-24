import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:what_did_you_press/core/geo.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/services/service_providers.dart';

/// Resubscribe to nearby bombs after moving this far from the last query.
const double _requeryDistanceMeters = 500;

const _unset = Object();

class WorldState {
  const WorldState({
    this.position,
    this.nearby = const [],
    this.uid,
    this.busy = false,
    this.error,
  });

  final Position? position;

  /// Live bombs nearby, closest first.
  final List<Bomb> nearby;

  /// This player's id, to tell their own bombs apart.
  final String? uid;
  final bool busy;
  final String? error;

  WorldState copyWith({
    Position? position,
    List<Bomb>? nearby,
    String? uid,
    bool? busy,
    Object? error = _unset,
  }) => WorldState(
    position: position ?? this.position,
    nearby: nearby ?? this.nearby,
    uid: uid ?? this.uid,
    busy: busy ?? this.busy,
    error: error == _unset ? this.error : error as String?,
  );
}

final worldControllerProvider =
    NotifierProvider.autoDispose<WorldController, WorldState>(
      WorldController.new,
    );

/// MVVM ViewModel of [WorldPage]: follows the GPS, keeps the nearby bomb query
/// in step with the player, and runs plant/claim actions.
class WorldController extends Notifier<WorldState> {
  late BombService _bombs;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<Bomb>>? _bombSubscription;
  Position? _queriedAt;

  @override
  WorldState build() {
    _bombs = ref.read(bombServiceProvider);
    ref.onDispose(() {
      _positionSubscription?.cancel();
      _bombSubscription?.cancel();
    });
    Future.microtask(_startLocation);
    return const WorldState();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (ref.mounted) {
        state = state.copyWith(error: 'Ativa a localização do telemóvel.');
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!ref.mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      state = state.copyWith(error: 'Sem acesso à localização, não há mundo.');
      return;
    }
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _onPosition,
          onError: (Object error) {
            if (ref.mounted) {
              state = state.copyWith(error: 'Perdemos o sinal de GPS.');
            }
          },
        );
  }

  void _onPosition(Position position) {
    if (!ref.mounted) return;
    state = state.copyWith(position: position);
    final queried = _queriedAt;
    if (queried != null &&
        distanceMeters(
              queried.latitude,
              queried.longitude,
              position.latitude,
              position.longitude,
            ) <
            _requeryDistanceMeters) {
      return;
    }
    _queriedAt = position;
    _bombSubscription?.cancel();
    _bombSubscription = _bombs
        .watchNearbyBombs(position.latitude, position.longitude)
        .listen(
          (bombs) {
            if (ref.mounted) {
              state = state.copyWith(nearby: bombs, uid: _bombs.uid);
            }
          },
          onError: (Object error) {
            if (ref.mounted) {
              state = state.copyWith(error: _errorMessage(error));
            }
          },
        );
  }

  /// Plants a bomb where the player stands; true on success.
  Future<bool> plant() => _run((position) async {
    await _bombs.plantBomb(position.latitude, position.longitude);
  });

  /// Locks [bomb] for this player; true if the lobby can now be opened.
  /// The lobby abandons the claim if the player leaves before starting.
  Future<bool> claim(Bomb bomb) => _run((position) async {
    await _bombs.claimBomb(bomb.id, position.latitude, position.longitude);
  });

  Future<bool> _run(Future<void> Function(Position position) action) async {
    final position = state.position;
    if (state.busy || position == null) return false;
    state = state.copyWith(busy: true, error: null);
    try {
      await action(position);
      return true;
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _errorMessage(error));
      return false;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  String _errorMessage(Object error) {
    if (error is BombException) {
      return switch (error.reason) {
        BombFailure.tooFar => 'Aproxima-te mais da bomba.',
        BombFailure.busy => 'Outra equipa já está nesta bomba.',
        BombFailure.gone => 'Esta bomba já não existe.',
        BombFailure.ownBomb => 'Não podes desarmar a tua própria bomba.',
        BombFailure.limitReached =>
          'Já tens $maxActiveBombs bombas ativas no mapa.',
      };
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        // Usually a client clock far off the server's, or a race we lost.
        'permission-denied' => 'Ação recusada pelo servidor. Tenta novamente.',
        'operation-not-allowed' => 'O início de sessão anónimo não está ativo.',
        'unavailable' || 'network-request-failed' =>
          'Não foi possível ligar. Verifica a ligação à Internet.',
        _ => 'Algo correu mal. Tenta novamente. (${error.code})',
      };
    }
    return 'Algo correu mal. Tenta novamente.';
  }
}
