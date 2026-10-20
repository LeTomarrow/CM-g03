import 'package:flutter_test/flutter_test.dart';
import 'package:what_did_you_press/core/geo.dart';
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
}
