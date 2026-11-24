import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/geo.dart';
import 'package:what_did_you_press/features/world/radar.dart';
import 'package:what_did_you_press/services/bomb_service.dart';

void main() {
  test('geohash de referência (Wikipedia)', () {
    expect(encodeGeohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
  });

  test('células vizinhas incluem a própria e são 9', () {
    final cells = coveringCells(38.7569, -9.1569, 5);
    expect(cells, hasLength(9));
    expect(cells, contains(encodeGeohash(38.7569, -9.1569, 5)));
  });

  test('células vizinhas cobrem o raio de bombas próximas', () {
    final cells = coveringCells(38.7569, -9.1569, 5);
    for (final (dLat, dLng) in [(0.027, 0.0), (0.0, 0.035), (-0.027, -0.035)]) {
      final hash = encodeGeohash(38.7569 + dLat, -9.1569 + dLng, 5);
      expect(cells, contains(hash));
    }
    expect(
      distanceMeters(38.7569, -9.1569, 38.7569, -9.1219),
      greaterThan(nearbyRadiusMeters),
    );
  });

  test('distância Lisboa–Porto ronda 274 km', () {
    final meters = distanceMeters(38.7223, -9.1393, 41.1579, -8.6291);
    expect(meters / 1000, closeTo(274, 2));
  });

  test('offset aponta para norte e este', () {
    final (east, north) = offsetMeters(38.7569, -9.1569, 38.7579, -9.1559);
    expect(north, closeTo(111, 1));
    expect(east, closeTo(87, 1));
  });

  Bomb bomb(String id) => Bomb(
    id: id,
    lat: 0,
    lng: 0,
    plantedBy: 'uid',
    status: 'armed',
    active: true,
    claimedBy: null,
    claimExpiresAt: null,
    expiresAt: DateTime(2099),
  );

  test('bombas do mesmo jogador têm nomes diferentes e estáveis', () {
    final codes = [for (var slot = 0; slot < 3; slot++) bomb('abc_$slot').code];
    expect(codes.toSet(), hasLength(3));
    // Not just one letter apart, so players can tell them apart.
    for (final other in codes.skip(1)) {
      final differing = List.generate(
        4,
        (i) => codes.first[i] != other[i],
      ).where((d) => d).length;
      expect(differing, greaterThan(1));
    }
    expect(bomb('abc_0').code, codes.first);
    expect(codes.first, matches(RegExp(r'^[A-Z2-9]{4}$')));
  });

  test('radar aproxima-se da bomba mais perto', () {
    expect(radarRangeFor(null), 500);
    expect(radarRangeFor(10), 100);
    expect(radarRangeFor(90), 250);
    expect(radarRangeFor(700), 1000);
    expect(radarRangeFor(5000), 3000);
  });
}
