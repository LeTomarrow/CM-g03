import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/lobby.dart';
import 'package:what_did_you_press/features/world/radar.dart';
import 'package:what_did_you_press/services/bomb_service.dart';
import 'package:what_did_you_press/features/world/world_controller.dart';

/// Open-world mode: plant bombs where you stand, or claim one within
/// [claimRadiusMeters] and host a room as its operator.
///
/// View of [WorldController]: renders [WorldState] and handles navigation.
class WorldPage extends ConsumerWidget {
  const WorldPage({super.key});

  Future<void> _plant(BuildContext context, WidgetRef ref) async {
    final planted = await ref.read(worldControllerProvider.notifier).plant();
    if (!planted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bomba plantada. Dura 24 horas.')),
    );
  }

  Future<void> _claim(BuildContext context, WidgetRef ref, Bomb bomb) async {
    final claimed = await ref
        .read(worldControllerProvider.notifier)
        .claim(bomb);
    if (!claimed || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => LobbyPage(bombId: bomb.id)));
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildBombRow(
    BuildContext context,
    WidgetRef ref,
    WorldState world,
    Bomb bomb,
    Position position,
  ) {
    final distance = bomb.distanceTo(position.latitude, position.longitude);
    final own = bomb.plantedBy == world.uid;
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
      onTap: canClaim && !world.busy ? () => _claim(context, ref, bomb) : null,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final world = ref.watch(worldControllerProvider);
    final position = world.position;
    final nearby = world.nearby;
    final range = radarRangeFor(
      position == null || nearby.isEmpty
          ? null
          : nearby
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
                  world.error ?? 'A procurar sinal de GPS...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else ...[
              BombRadar(
                lat: position.latitude,
                lng: position.longitude,
                bombs: nearby,
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
                      'BOMBAS PERTO (${nearby.length})',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    if (nearby.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Nenhuma bomba num raio de 3 km.',
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ),
                    for (final bomb in nearby)
                      _buildBombRow(context, ref, world, bomb, position),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (world.busy) const LinearProgressIndicator(),
              if (world.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    world.error!,
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              MenuButton(
                label: 'PLANTAR AQUI',
                onPressed: () => _plant(context, ref),
                color: AppColors.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
