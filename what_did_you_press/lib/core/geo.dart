import 'dart:math' as math;

const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const double _earthRadiusMeters = 6371000;

/// Same algorithm as functions/src/geo.ts; nearby points share prefixes.
String encodeGeohash(double lat, double lng, [int precision = 9]) {
  var latRange = [-90.0, 90.0];
  var lngRange = [-180.0, 180.0];
  final hash = StringBuffer();
  var bits = 0;
  var value = 0;
  var evenBit = true;
  while (hash.length < precision) {
    final range = evenBit ? lngRange : latRange;
    final coordinate = evenBit ? lng : lat;
    final middle = (range[0] + range[1]) / 2;
    value <<= 1;
    if (coordinate >= middle) {
      value |= 1;
      range[0] = middle;
    } else {
      range[1] = middle;
    }
    evenBit = !evenBit;
    if (++bits == 5) {
      hash.write(_base32[value]);
      bits = 0;
      value = 0;
    }
  }
  return hash.toString();
}

/// The cell containing the point plus its eight neighbours. Querying these
/// covers at least one cell size around the point in every direction.
Set<String> coveringCells(double lat, double lng, int precision) {
  final totalBits = precision * 5;
  final cellLat = 180 / math.pow(2, totalBits ~/ 2);
  final cellLng = 360 / math.pow(2, (totalBits + 1) ~/ 2);
  return {
    for (final dLat in [-cellLat, 0.0, cellLat])
      for (final dLng in [-cellLng, 0.0, cellLng])
        encodeGeohash(
          (lat + dLat).clamp(-90.0, 90.0),
          (lng + dLng + 540) % 360 - 180,
          precision,
        ),
  };
}

/// Great-circle distance using the haversine formula.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  double toRadians(double degrees) => degrees * math.pi / 180;
  final dLat = toRadians(lat2 - lat1);
  final dLng = toRadians(lng2 - lng1);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRadians(lat1)) *
          math.cos(toRadians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.sqrt(h));
}

/// Approximate (east, north) offset in meters; accurate for short distances.
(double, double) offsetMeters(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  const metersPerDegree = _earthRadiusMeters * math.pi / 180;
  final east =
      (toLng - fromLng) * metersPerDegree * math.cos(fromLat * math.pi / 180);
  final north = (toLat - fromLat) * metersPerDegree;
  return (east, north);
}
