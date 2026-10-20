import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/geo.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/lobby.dart';
import 'package:what_did_you_press/features/world/radar.dart';
import 'package:what_did_you_press/services/bomb_service.dart';

/// Resubscribe to nearby bombs after moving this far from the last query.
const double _requeryDistanceMeters = 500;

/// Open-world mode: plant bombs where you stand, or claim one within
/// [claimRadiusMeters] and host a room as its operator.
class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  late final BombService _bombs = BombService();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<Bomb>>? _bombSubscription;
  Position? _position;
  Position? _queriedAt;
  List<Bomb> _nearby = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _bombSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _error = 'Ativa a localização do telemóvel.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _error = 'Sem acesso à localização, não há mundo.');
      }
      return;
    }
    if (!mounted) return;
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _onPosition,
          onError: (Object error) {
            if (mounted) setState(() => _error = 'Perdemos o sinal de GPS.');
          },
        );
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);
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
            if (mounted) setState(() => _nearby = bombs);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = _errorMessage(error));
          },
        );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _plant() => _run(() async {
    final position = _position;
    if (position == null) return;
    await _bombs.plantBomb(position.latitude, position.longitude);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bomba plantada. Dura 24 horas.')),
    );
  });

  /// The lobby abandons the claim if the player leaves before starting.
  Future<void> _claim(Bomb bomb) => _run(() async {
    final position = _position;
    if (position == null) return;
    await _bombs.claimBomb(bomb.id, position.latitude, position.longitude);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => LobbyPage(bombId: bomb.id)));
  });

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

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildBombRow(Bomb bomb, Position position) {
    final distance = bomb.distanceTo(position.latitude, position.longitude);
    final own = bomb.plantedBy == _bombs.uid;
    final claimable = bomb.isClaimable(DateTime.now());
    final inRange = distance <= claimRadiusMeters;
    final (String label, Color color) = own
        ? ('TUA', AppColors.neonPurple)
        : !claimable
        ? ('OCUPADA', AppColors.amber)
        : inRange
        ? ('DESARMAR', AppColors.success)
        : ('LONGE', AppColors.danger);
    final canClaim = !own && claimable && inRange;

    return InkWell(
      onTap: canClaim ? () => _claim(bomb) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            StatusLed(color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'BOMBA ${bomb.code}',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ),
            Text(
              _formatDistance(distance),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final range = radarRangeFor(
      position == null || _nearby.isEmpty
          ? null
          : _nearby
                .map((b) => b.distanceTo(position.latitude, position.longitude))
                .reduce((a, b) => a < b ? a : b),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.success,
        title: Text('MUNDO'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            if (position == null)
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.card,
                child: Text(
                  _error ?? 'A procurar sinal de GPS...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else ...[
              BombRadar(
                lat: position.latitude,
                lng: position.longitude,
                bombs: _nearby,
                rangeMeters: range,
              ),
              const SizedBox(height: 8),
              Text(
                'Raio de ${_formatDistance(range)} · '
                'precisão ±${position.accuracy.round()} m',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BOMBAS PERTO (${_nearby.length})',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    if (_nearby.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Nenhuma bomba num raio de 3 km.',
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ),
                    for (final bomb in _nearby) _buildBombRow(bomb, position),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              MenuButton(
                label: 'PLANTAR AQUI',
                onPressed: _plant,
                color: AppColors.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
