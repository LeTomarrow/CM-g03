const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
const EARTH_RADIUS_METERS = 6371000;

export interface Coordinates {
  lat: number;
  lng: number;
}

/**
 * Returns the coordinates in data, or null when they are missing or invalid.
 * @param {unknown} data Callable payload with lat and lng fields.
 * @return {Coordinates | null} Validated coordinates.
 */
export function parseCoordinates(data: unknown): Coordinates | null {
  const {lat, lng} = (data ?? {}) as Record<string, unknown>;
  if (typeof lat !== "number" || typeof lng !== "number") return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return {lat, lng};
}

/**
 * Encodes coordinates as a geohash; shared prefixes mean nearby cells.
 * @param {Coordinates} point Coordinates to encode.
 * @param {number} precision Number of characters.
 * @return {string} Geohash string.
 */
export function encodeGeohash(point: Coordinates, precision = 9): string {
  const lat = [-90, 90];
  const lng = [-180, 180];
  let hash = "";
  let bits = 0;
  let value = 0;
  let evenBit = true;
  while (hash.length < precision) {
    const range = evenBit ? lng : lat;
    const coordinate = evenBit ? point.lng : point.lat;
    const middle = (range[0] + range[1]) / 2;
    value <<= 1;
    if (coordinate >= middle) {
      value |= 1;
      range[0] = middle;
    } else {
      range[1] = middle;
    }
    evenBit = !evenBit;
    if (++bits === 5) {
      hash += BASE32[value];
      bits = 0;
      value = 0;
    }
  }
  return hash;
}

/**
 * Great-circle distance using the haversine formula.
 * @param {Coordinates} a First point.
 * @param {Coordinates} b Second point.
 * @return {number} Distance in meters.
 */
export function distanceMeters(a: Coordinates, b: Coordinates): number {
  const toRadians = (degrees: number) => degrees * Math.PI / 180;
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRadians(a.lat)) *
    Math.cos(toRadians(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(h));
}
